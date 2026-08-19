-- 0015_automation.sql
-- The automation engine, and the approval gate as an execution status.
--
-- "When a deal enters Negotiation, create a task for the owner" had nowhere to
-- live. n8n's data model is the reference for the mechanics (its licence
-- forbids embedding it, see DECISIONS.md D10); the approval semantics are
-- specific to this system and come from CLAUDE.md §3.
--
-- THE DESIGN CONSTRAINT THAT SHAPED EVERYTHING ELSE
--
-- A Network-class action must *suspend* the run pending approval, not block a
-- worker waiting for a human. A blocking wait ties up a connection and a
-- process for however long a person takes to answer — minutes, or a weekend —
-- and a hundred pending approvals is a hundred stalled workers. So approval is
-- a run *status*, the worker is released, and a decision re-queues the run.
--
-- That is why this is a step machine with durable state rather than a function
-- that executes a list of actions. Retrofitting suspension into a synchronous
-- executor means rewriting it, which is why it is here in the first design.
--
-- WHAT THIS MIGRATION DOES NOT DO: execute anything. There is no worker here.
-- The database owns the state machine, the authorisation decision, and the
-- audit trail; a worker process outside it does the effects and reports back
-- through these functions. That boundary is deliberate — an executor inside the
-- database would make every outbound call a transaction held open across the
-- network.

BEGIN;

-- ---------------------------------------------------------------------------
-- Command classes and autonomy tiers — CLAUDE.md §3, as data
--
-- These live in the database rather than only in prose so the rule is enforced
-- at the point of execution and is auditable afterwards. A convention that
-- exists only in a document is followed until someone is in a hurry.
-- ---------------------------------------------------------------------------
CREATE TYPE command_class AS ENUM (
  'read',        -- view data, no side effects
  'write',       -- create or modify a record
  'network',     -- outbound call to an external service
  'install',     -- add or change a dependency
  'destructive'  -- delete, drop, bulk mutation
);

CREATE TYPE autonomy_tier AS ENUM (
  'read_only',   -- read proceeds; everything else is blocked outright
  'supervised',  -- read and write proceed; the rest pause for approval
  'full'         -- all proceed EXCEPT destructive, which always pauses
);

CREATE TYPE automation_trigger_kind AS ENUM (
  'record_created',
  'record_updated',
  'field_changed',
  'stage_changed',
  'scheduled',
  'webhook',
  'manual'
);

CREATE TYPE automation_run_status AS ENUM (
  'queued',            -- waiting for a worker to claim it
  'running',           -- claimed, a worker is executing a step
  'waiting_approval',  -- suspended; no worker held. The reason this exists.
  'waiting_until',     -- suspended on a timer (delay, retry backoff)
  'succeeded',
  'failed',
  'cancelled'
);

CREATE TYPE automation_step_status AS ENUM (
  'pending',
  'running',
  'waiting_approval',
  'succeeded',
  'failed',
  'skipped',    -- a condition excluded it
  'blocked',    -- the tier forbids this class outright; never executable
  'cancelled'
);

-- Silence is not consent. 'expired' is a distinct outcome from 'rejected' so
-- the difference between "a human said no" and "nobody answered" survives into
-- the record — they mean different things when someone asks later why an email
-- never went out.
CREATE TYPE approval_decision AS ENUM (
  'pending',
  'approved',
  'rejected',
  'expired'
);

-- ---------------------------------------------------------------------------
-- Automations and their versions
--
-- The definition is versioned and a run pins the version it started under.
-- Editing a rule while runs are in flight must not change what those runs do —
-- otherwise a run that suspended for approval on Friday resumes on Monday
-- executing actions nobody approved.
-- ---------------------------------------------------------------------------
CREATE TABLE automations (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  name              text NOT NULL CHECK (btrim(name) <> ''),
  description       text,
  is_active         boolean NOT NULL DEFAULT false,

  -- The tier this automation runs at. Defaults to the most restrictive tier
  -- that can still do useful work, per CLAUDE.md §3: "Supervised tier (default
  -- for new agents)".
  autonomy          autonomy_tier NOT NULL DEFAULT 'supervised',
  -- Set when an agent persona drives this automation, so its actions are
  -- attributable to a named agent rather than to "the system".
  agent_name        text,

  -- Runs with no human present. Such a run may not pause: anything that would
  -- need an approval fails loudly and says why, rather than silently skipping
  -- the action or silently doing it.
  is_unattended     boolean NOT NULL DEFAULT false,

  current_version   integer NOT NULL DEFAULT 0,

  created_by        uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz,

  -- 'full' is opt-in and must be granted deliberately. Requiring a named agent
  -- means an unattended automation cannot quietly reach the tier where network
  -- calls proceed without anyone having attached their name to it.
  CONSTRAINT automations_full_tier_is_named CHECK (
    autonomy <> 'full' OR coalesce(btrim(agent_name), '') <> ''
  )
);

CREATE INDEX automations_org_active_idx
  ON automations (organization_id, is_active)
  WHERE deleted_at IS NULL;

SELECT app.attach_tenant_triggers('automations');

CREATE TABLE automation_versions (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  automation_id     uuid NOT NULL REFERENCES automations(id) ON DELETE CASCADE,

  version           integer NOT NULL CHECK (version > 0),

  trigger_kind      automation_trigger_kind NOT NULL,
  -- Shape depends on trigger_kind: {entity_type, field, from, to, cron, ...}.
  trigger_config    jsonb NOT NULL DEFAULT '{}'::jsonb,

  -- Evaluated against the trigger payload before any action runs.
  conditions        jsonb NOT NULL DEFAULT '[]'::jsonb,

  -- Ordered array of actions. Each element carries at minimum
  -- {kind, command_class, config}. command_class is declared per action rather
  -- than inferred from kind: the same "call a webhook" action is Network, and
  -- inferring it at execution time would let a new action kind default to
  -- something permissive by omission.
  actions           jsonb NOT NULL DEFAULT '[]'::jsonb
                      CHECK (jsonb_typeof(actions) = 'array'),

  published_at      timestamptz,
  created_by        uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT automation_versions_unique UNIQUE (automation_id, version)
);

CREATE INDEX automation_versions_lookup_idx
  ON automation_versions (automation_id, version DESC);

-- ---------------------------------------------------------------------------
-- Recurrence, separated from concrete runs
--
-- A `scheduled_job` describes *when something should run*. It is not a run, and
-- it is not a queue entry. Concrete runs are materialised from it ahead of
-- time. Collapsing the two means a missed window is indistinguishable from a
-- window that never existed, and catching up after an outage becomes guesswork.
-- ---------------------------------------------------------------------------
CREATE TABLE scheduled_jobs (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  automation_id     uuid NOT NULL REFERENCES automations(id) ON DELETE CASCADE,

  name              text NOT NULL CHECK (btrim(name) <> ''),
  -- Plain interval rather than cron syntax: an interval is a type Postgres
  -- understands and can add, where a cron string is text this schema would have
  -- to parse. A cron expression can be stored in trigger_config when the caller
  -- needs one and materialise runs itself.
  recurrence        interval NOT NULL CHECK (recurrence > interval '0'),

  next_run_at       timestamptz NOT NULL DEFAULT now(),
  last_run_at       timestamptz,
  -- Missed windows older than this are dropped rather than replayed. A job that
  -- was down for a day should not wake up and fire 288 times.
  catchup_limit     integer NOT NULL DEFAULT 1 CHECK (catchup_limit >= 0),

  is_active         boolean NOT NULL DEFAULT true,

  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz
);

CREATE INDEX scheduled_jobs_due_idx
  ON scheduled_jobs (next_run_at)
  WHERE is_active AND deleted_at IS NULL;

SELECT app.attach_tenant_triggers('scheduled_jobs');

CREATE TRIGGER scheduled_jobs_automation_same_org
  BEFORE INSERT OR UPDATE OF automation_id ON scheduled_jobs
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('automations', 'automation_id');

-- ---------------------------------------------------------------------------
-- Runs — hot metadata
--
-- Split from its payload deliberately. This is the table the queue query and
-- every status dashboard reads; the payload is the part that is large and read
-- rarely. Keeping them together means every "what is running right now" scan
-- drags trigger bodies and action outputs through memory, and it is why
-- execution history swamps the table you need to be fast.
-- ---------------------------------------------------------------------------
CREATE TABLE automation_runs (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  automation_id     uuid NOT NULL REFERENCES automations(id) ON DELETE CASCADE,
  automation_version_id uuid NOT NULL REFERENCES automation_versions(id) ON DELETE RESTRICT,
  scheduled_job_id  uuid REFERENCES scheduled_jobs(id) ON DELETE SET NULL,

  status            automation_run_status NOT NULL DEFAULT 'queued',

  -- Snapshots taken at enqueue time. A run must not change behaviour because
  -- someone edited the automation while it was suspended: a run that paused for
  -- approval on Friday would otherwise resume on Monday at a tier nobody
  -- reviewed, executing actions nobody approved.
  autonomy          autonomy_tier NOT NULL,
  is_unattended     boolean NOT NULL DEFAULT false,
  agent_name        text,

  trigger_kind      automation_trigger_kind NOT NULL,
  trigger_entity_type crm_entity,
  trigger_entity_id uuid,

  -- Makes a twice-delivered webhook run once. Null means "no natural key", and
  -- such runs are not deduplicated at all rather than being collapsed together.
  dedup_key         text,

  current_step      integer NOT NULL DEFAULT 0 CHECK (current_step >= 0),

  -- Worker lease. A worker that dies mid-step leaves a lease that expires, and
  -- the run becomes claimable again. Without this a crashed worker strands its
  -- run in 'running' forever.
  claimed_by        text,
  claimed_at        timestamptz,
  lease_expires_at  timestamptz,

  -- When this run may next be picked up: a scheduled start, a delay step, or a
  -- retry backoff. Null means "now".
  run_after         timestamptz,

  started_at        timestamptz,
  finished_at       timestamptz,
  error_code        text,
  error_message     text,

  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT automation_runs_claim_is_complete CHECK (
    (claimed_by IS NULL AND lease_expires_at IS NULL)
    OR (claimed_by IS NOT NULL AND lease_expires_at IS NOT NULL)
  ),
  CONSTRAINT automation_runs_terminal_is_finished CHECK (
    status NOT IN ('succeeded', 'failed', 'cancelled') OR finished_at IS NOT NULL
  )
);

CREATE UNIQUE INDEX automation_runs_dedup_key
  ON automation_runs (automation_id, dedup_key)
  WHERE dedup_key IS NOT NULL;

-- The queue. Partial, so it stays the size of the backlog rather than the size
-- of all history — the index a worker hits every poll must not grow with the
-- number of runs that have already finished.
CREATE INDEX automation_runs_claimable_idx
  ON automation_runs (coalesce(run_after, created_at), created_at)
  WHERE status = 'queued';

-- Reclaiming runs whose worker died.
CREATE INDEX automation_runs_expired_lease_idx
  ON automation_runs (lease_expires_at)
  WHERE status = 'running';

-- Suspended runs waiting on a person, which is the queue a human works from.
CREATE INDEX automation_runs_waiting_idx
  ON automation_runs (organization_id, status, created_at DESC)
  WHERE status IN ('waiting_approval', 'waiting_until');

CREATE INDEX automation_runs_org_automation_idx
  ON automation_runs (organization_id, automation_id, created_at DESC);

CREATE INDEX automation_runs_trigger_entity_idx
  ON automation_runs (organization_id, trigger_entity_type, trigger_entity_id)
  WHERE trigger_entity_id IS NOT NULL;

CREATE TRIGGER automation_runs_set_updated_at
  BEFORE UPDATE ON automation_runs
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER automation_runs_freeze_org
  BEFORE UPDATE ON automation_runs
  FOR EACH ROW EXECUTE FUNCTION app.freeze_organization_id();

-- ---------------------------------------------------------------------------
-- Run payloads — cold storage, 1:1
--
-- Deleting old payloads is the retention story: run metadata stays cheap and
-- queryable for a long time, and the bulky part is pruned on a shorter clock
-- without losing the record that the run happened or what it decided.
-- ---------------------------------------------------------------------------
CREATE TABLE automation_run_payloads (
  run_id            uuid PRIMARY KEY REFERENCES automation_runs(id) ON DELETE CASCADE,
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  -- What fired the run: the record snapshot, the webhook body, the schedule.
  input             jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- Accumulated across steps, so a later action can use an earlier one's result.
  context           jsonb NOT NULL DEFAULT '{}'::jsonb,
  output            jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX automation_run_payloads_org_idx
  ON automation_run_payloads (organization_id, created_at);

CREATE TRIGGER automation_run_payloads_set_updated_at
  BEFORE UPDATE ON automation_run_payloads
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

-- ---------------------------------------------------------------------------
-- Steps — one row per action, with its own retry state
--
-- Retry belongs to the step, not the run. Re-running a whole workflow because
-- its fourth action hit a rate limit repeats the three side effects that already
-- succeeded, which for a Network action means sending the same email twice.
-- ---------------------------------------------------------------------------
CREATE TABLE automation_steps (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  run_id            uuid NOT NULL REFERENCES automation_runs(id) ON DELETE CASCADE,

  step_index        integer NOT NULL CHECK (step_index >= 0),
  action_kind       text NOT NULL CHECK (btrim(action_kind) <> ''),
  -- Declared by the action definition, snapshotted here. This is the value the
  -- gate reads, so it is recorded on the row that was actually authorised
  -- rather than looked up again at decision time.
  command_class     command_class NOT NULL,

  status            automation_step_status NOT NULL DEFAULT 'pending',

  attempt           integer NOT NULL DEFAULT 0 CHECK (attempt >= 0),
  max_attempts      integer NOT NULL DEFAULT 3 CHECK (max_attempts >= 1),
  run_after         timestamptz,

  started_at        timestamptz,
  finished_at       timestamptz,
  error_code        text,
  error_message     text,
  -- Small result summaries only. Anything large belongs in the run payload.
  output            jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT automation_steps_unique UNIQUE (run_id, step_index)
);

CREATE INDEX automation_steps_run_idx
  ON automation_steps (run_id, step_index);

CREATE INDEX automation_steps_pending_idx
  ON automation_steps (run_id, step_index)
  WHERE status = 'pending';

CREATE TRIGGER automation_steps_set_updated_at
  BEFORE UPDATE ON automation_steps
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER automation_steps_freeze_org
  BEFORE UPDATE ON automation_steps
  FOR EACH ROW EXECUTE FUNCTION app.freeze_organization_id();

-- ---------------------------------------------------------------------------
-- Approval requests
--
-- The plain-language pause from CLAUDE.md §3, made durable. The wording matters
-- enough to be a constraint: "Agent X wants to send an email to <address>" is
-- something a person can decide on, and a request that only names an action
-- kind and a config blob is not.
-- ---------------------------------------------------------------------------
CREATE TABLE approval_requests (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  run_id            uuid NOT NULL REFERENCES automation_runs(id) ON DELETE CASCADE,
  step_id           uuid NOT NULL REFERENCES automation_steps(id) ON DELETE CASCADE,

  command_class     command_class NOT NULL,
  autonomy          autonomy_tier NOT NULL,

  -- What a human reads. Not optional, and not a config dump.
  summary           text NOT NULL CHECK (length(btrim(summary)) >= 8),
  detail            jsonb NOT NULL DEFAULT '{}'::jsonb,

  requested_at      timestamptz NOT NULL DEFAULT now(),
  -- Silence is not consent. An unanswered request expires and the action does
  -- not happen; see app.expire_approvals().
  expires_at        timestamptz NOT NULL,

  decision          approval_decision NOT NULL DEFAULT 'pending',
  decided_at        timestamptz,
  decided_by        uuid REFERENCES users(id) ON DELETE SET NULL,
  decision_reason   text,

  created_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT approval_requests_decided_is_stamped CHECK (
    decision = 'pending' OR decided_at IS NOT NULL
  ),
  -- An expiry cannot be attributed to a person: nobody decided it.
  CONSTRAINT approval_requests_expiry_has_no_decider CHECK (
    decision <> 'expired' OR decided_by IS NULL
  ),
  CONSTRAINT approval_requests_window_ordered CHECK (expires_at > requested_at)
);

-- One live request per step. A second pending approval for the same action is a
-- double-prompt, and whichever a human answers first silently decides the other.
CREATE UNIQUE INDEX approval_requests_one_pending_per_step
  ON approval_requests (step_id)
  WHERE decision = 'pending';

CREATE INDEX approval_requests_pending_idx
  ON approval_requests (organization_id, requested_at)
  WHERE decision = 'pending';

-- The expiry sweep's index.
CREATE INDEX approval_requests_expiring_idx
  ON approval_requests (expires_at)
  WHERE decision = 'pending';

CREATE INDEX approval_requests_run_idx
  ON approval_requests (run_id, requested_at);

-- ---------------------------------------------------------------------------
-- The gate — CLAUDE.md §3 as a function
--
-- One place decides what a class may do at a tier. Every caller reads the same
-- answer, and changing the policy is one edit rather than a search for every
-- place the rule was reimplemented.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.gate_verdict(
  p_class command_class,
  p_tier  autonomy_tier
)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    -- Read is always allowed. It has no side effects to approve.
    WHEN p_class = 'read' THEN 'proceed'

    -- Read-only: everything else is blocked outright, not queued for approval.
    -- A read-only agent asking permission to write is a misconfiguration, and
    -- turning it into a prompt trains people to approve things reflexively.
    WHEN p_tier = 'read_only' THEN 'blocked'

    -- Destructive always pauses, at every tier. No automation is ever fully
    -- autonomous for deletion, drop, or bulk mutation.
    WHEN p_class = 'destructive' THEN 'approve'

    WHEN p_tier = 'supervised' THEN
      CASE WHEN p_class = 'write' THEN 'proceed' ELSE 'approve' END

    -- Full: network and install proceed; destructive was already handled above.
    WHEN p_tier = 'full' THEN 'proceed'
  END;
$$;

COMMENT ON FUNCTION app.gate_verdict(command_class, autonomy_tier) IS
  'The approval matrix from CLAUDE.md §3. Returns proceed | approve | blocked. '
  'Destructive returns approve at every tier, including full.';

-- ---------------------------------------------------------------------------
-- Enqueue
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.enqueue_automation_run(
  p_automation_id     uuid,
  p_trigger_entity_type crm_entity  DEFAULT NULL,
  p_trigger_entity_id uuid          DEFAULT NULL,
  p_input             jsonb         DEFAULT '{}'::jsonb,
  p_dedup_key         text          DEFAULT NULL,
  p_run_after         timestamptz   DEFAULT NULL,
  p_scheduled_job_id  uuid          DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_auto    automations%ROWTYPE;
  v_version automation_versions%ROWTYPE;
  v_run_id  uuid;
  v_action  jsonb;
  v_index   integer := 0;
  v_class   command_class;
BEGIN
  SELECT * INTO v_auto FROM automations
   WHERE id = p_automation_id AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such automation: %', p_automation_id
      USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT v_auto.is_active THEN
    RAISE EXCEPTION 'automation % is not active', p_automation_id
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO v_version FROM automation_versions
   WHERE automation_id = p_automation_id AND version = v_auto.current_version;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'automation % has no published version', p_automation_id
      USING ERRCODE = 'no_data_found';
  END IF;

  -- Deduplication. A webhook delivered twice must run once; returning the
  -- existing run rather than raising means the caller's retry is a no-op
  -- instead of an error it has to special-case.
  IF p_dedup_key IS NOT NULL THEN
    SELECT id INTO v_run_id FROM automation_runs
     WHERE automation_id = p_automation_id AND dedup_key = p_dedup_key;
    IF FOUND THEN
      RETURN v_run_id;
    END IF;
  END IF;

  INSERT INTO automation_runs (
    organization_id, automation_id, automation_version_id, scheduled_job_id,
    status, autonomy, is_unattended, agent_name,
    trigger_kind, trigger_entity_type, trigger_entity_id,
    dedup_key, run_after
  ) VALUES (
    v_auto.organization_id, p_automation_id, v_version.id, p_scheduled_job_id,
    'queued', v_auto.autonomy, v_auto.is_unattended, v_auto.agent_name,
    v_version.trigger_kind, p_trigger_entity_type, p_trigger_entity_id,
    p_dedup_key, p_run_after
  )
  RETURNING id INTO v_run_id;

  INSERT INTO automation_run_payloads (run_id, organization_id, input)
    VALUES (v_run_id, v_auto.organization_id, p_input);

  -- Steps are materialised now, from the pinned version. Reading actions out of
  -- the definition at execution time would let an edit mid-run change what is
  -- still to happen — including inserting a step nobody approved.
  FOR v_action IN SELECT * FROM jsonb_array_elements(v_version.actions) LOOP
    BEGIN
      v_class := (v_action ->> 'command_class')::command_class;
    EXCEPTION WHEN invalid_text_representation OR not_null_violation THEN
      RAISE EXCEPTION
        'action % of automation % declares no valid command_class',
        v_index, p_automation_id
        USING ERRCODE = 'check_violation';
    END;

    IF v_class IS NULL THEN
      RAISE EXCEPTION
        'action % of automation % declares no command_class', v_index, p_automation_id
        USING ERRCODE = 'check_violation';
    END IF;

    INSERT INTO automation_steps (
      organization_id, run_id, step_index, action_kind, command_class,
      max_attempts
    ) VALUES (
      v_auto.organization_id, v_run_id, v_index,
      coalesce(v_action ->> 'kind', 'unknown'), v_class,
      coalesce((v_action ->> 'max_attempts')::integer, 3)
    );
    v_index := v_index + 1;
  END LOOP;

  RETURN v_run_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Claiming
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.claim_automation_run(
  p_worker text,
  p_lease  interval DEFAULT interval '5 minutes'
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_id uuid;
BEGIN
  -- SKIP LOCKED is what makes several workers safe against one queue: a row
  -- another worker is already claiming is passed over rather than waited on.
  SELECT id INTO v_id
    FROM automation_runs
   WHERE status = 'queued'
     AND (run_after IS NULL OR run_after <= now())
   ORDER BY coalesce(run_after, created_at), created_at
   FOR UPDATE SKIP LOCKED
   LIMIT 1;

  IF v_id IS NULL THEN
    RETURN NULL;
  END IF;

  UPDATE automation_runs
     SET status           = 'running',
         claimed_by       = p_worker,
         claimed_at       = now(),
         lease_expires_at = now() + p_lease,
         started_at       = coalesce(started_at, now())
   WHERE id = v_id;

  RETURN v_id;
END;
$$;

-- A worker that dies mid-step leaves its run in 'running' with a lease that
-- stops being renewed. Without this the run is stranded forever, which is the
-- most common way a queue quietly stops making progress.
CREATE OR REPLACE FUNCTION app.reclaim_expired_runs()
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_count integer;
BEGIN
  WITH reclaimed AS (
    UPDATE automation_runs
       SET status = 'queued', claimed_by = NULL, claimed_at = NULL,
           lease_expires_at = NULL
     WHERE status = 'running' AND lease_expires_at < now()
     RETURNING 1
  )
  SELECT count(*)::integer INTO v_count FROM reclaimed;

  -- A step left mid-flight goes back to pending so it is retried rather than
  -- silently skipped when the run is picked up again.
  UPDATE automation_steps s
     SET status = 'pending', started_at = NULL
    FROM automation_runs r
   WHERE s.run_id = r.id
     AND s.status = 'running'
     AND r.status = 'queued'
     AND r.claimed_by IS NULL;

  RETURN v_count;
END;
$$;

-- ---------------------------------------------------------------------------
-- The step machine
-- ---------------------------------------------------------------------------
CREATE TYPE step_ticket AS (
  step_id       uuid,
  step_index    integer,
  action_kind   text,
  command_class command_class,
  -- proceed  — execute it now
  -- approve  — suspended; a human has been asked. The worker is released.
  -- blocked  — the tier forbids this class outright. The run has failed.
  -- done     — no steps left; the run has succeeded.
  verdict       text,
  approval_id   uuid,
  message       text
);

-- Asks: what should this worker do next on this run?
--
-- This is where the approval gate actually bites. When a step needs approval
-- the run is suspended and **the lease is released** — the worker goes back to
-- the queue and picks up other work. That release is the entire reason the
-- engine is a durable state machine instead of a function that runs a list: a
-- blocking wait would hold a worker for as long as a person takes to answer,
-- and a hundred pending approvals would be a hundred stalled workers.
CREATE OR REPLACE FUNCTION app.begin_step(
  p_run_id           uuid,
  p_approval_summary text     DEFAULT NULL,
  p_approval_ttl     interval DEFAULT interval '24 hours'
)
RETURNS step_ticket
LANGUAGE plpgsql
AS $$
DECLARE
  v_run      automation_runs%ROWTYPE;
  v_step     automation_steps%ROWTYPE;
  v_auto     automations%ROWTYPE;
  v_verdict  text;
  v_approval uuid;
  v_summary  text;
  v_out      step_ticket;
BEGIN
  SELECT * INTO v_run FROM automation_runs WHERE id = p_run_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such run: %', p_run_id USING ERRCODE = 'no_data_found';
  END IF;
  IF v_run.status <> 'running' THEN
    RAISE EXCEPTION 'run % is %, not running', p_run_id, v_run.status
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO v_step FROM automation_steps
   WHERE run_id = p_run_id AND status = 'pending'
     AND (run_after IS NULL OR run_after <= now())
   ORDER BY step_index
   LIMIT 1;

  IF NOT FOUND THEN
    -- Nothing left to do. A run with a step still pending but not yet due is
    -- not finished, so check for that before declaring success.
    IF EXISTS (SELECT 1 FROM automation_steps
                WHERE run_id = p_run_id AND status IN ('pending', 'waiting_approval')) THEN
      v_out := ROW(NULL, NULL, NULL, NULL, 'wait', NULL,
                   'steps remain but none are due yet')::step_ticket;
      RETURN v_out;
    END IF;

    UPDATE automation_runs
       SET status = 'succeeded', finished_at = now(),
           claimed_by = NULL, lease_expires_at = NULL
     WHERE id = p_run_id;

    RETURN ROW(NULL, NULL, NULL, NULL, 'done', NULL, 'all steps completed')::step_ticket;
  END IF;

  v_verdict := app.gate_verdict(v_step.command_class, v_run.autonomy);

  -- An approval authorises THIS step. Without this check the gate re-evaluates
  -- after the decision, sees the same class at the same tier, and asks again —
  -- a run that can never get past its first Network action no matter how many
  -- times a human says yes.
  --
  -- The authorisation covers the step's retries too: retrying a send that timed
  -- out is the same action a person already approved, and re-prompting on every
  -- attempt trains people to approve reflexively. Whether the retry is safe to
  -- repeat is an idempotency question for the worker making the call, not an
  -- authorisation question for this gate.
  IF v_verdict = 'approve' AND EXISTS (
    SELECT 1 FROM approval_requests
     WHERE step_id = v_step.id AND decision = 'approved'
  ) THEN
    v_verdict := 'proceed';
  END IF;

  -- ---- blocked: the tier forbids this class outright -----------------------
  IF v_verdict = 'blocked' THEN
    UPDATE automation_steps
       SET status = 'blocked', finished_at = now(),
           error_code = 'class_not_permitted',
           error_message = format(
             'a %s-tier automation may not perform a %s action',
             v_run.autonomy, v_step.command_class)
     WHERE id = v_step.id;

    UPDATE automation_runs
       SET status = 'failed', finished_at = now(),
           claimed_by = NULL, lease_expires_at = NULL,
           error_code = 'class_not_permitted',
           error_message = format(
             'step %s (%s) is a %s action, which tier %s does not permit',
             v_step.step_index, v_step.action_kind, v_step.command_class,
             v_run.autonomy)
     WHERE id = p_run_id;

    RETURN ROW(v_step.id, v_step.step_index, v_step.action_kind,
               v_step.command_class, 'blocked', NULL,
               format('tier %s does not permit %s actions',
                      v_run.autonomy, v_step.command_class))::step_ticket;
  END IF;

  -- ---- approve: suspend -----------------------------------------------------
  IF v_verdict = 'approve' THEN
    -- An unattended run has nobody to ask. CLAUDE.md §3 is explicit that such a
    -- run must fail loudly and log why, rather than silently skipping the
    -- action or silently doing it. The run row carries the reason, so "why did
    -- the nightly automation stop" is answerable from the data.
    IF v_run.is_unattended THEN
      UPDATE automation_steps
         SET status = 'blocked', finished_at = now(),
             error_code = 'approval_required_unattended',
             error_message = format(
               'a %s action needs approval and this run has no human present',
               v_step.command_class)
       WHERE id = v_step.id;

      UPDATE automation_runs
         SET status = 'failed', finished_at = now(),
             claimed_by = NULL, lease_expires_at = NULL,
             error_code = 'approval_required_unattended',
             error_message = format(
               'step %s (%s) is a %s action requiring approval, but this run is '
               'unattended — refusing to proceed without a decision',
               v_step.step_index, v_step.action_kind, v_step.command_class)
       WHERE id = p_run_id;

      RETURN ROW(v_step.id, v_step.step_index, v_step.action_kind,
                 v_step.command_class, 'blocked', NULL,
                 'unattended run cannot pause for approval')::step_ticket;
    END IF;

    SELECT * INTO v_auto FROM automations WHERE id = v_run.automation_id;

    v_summary := coalesce(
      nullif(btrim(coalesce(p_approval_summary, '')), ''),
      format('%s wants to perform a %s action (%s) for automation "%s"',
             coalesce(v_run.agent_name, 'An automation'),
             v_step.command_class, v_step.action_kind, v_auto.name));

    INSERT INTO approval_requests (
      organization_id, run_id, step_id, command_class, autonomy,
      summary, expires_at
    ) VALUES (
      v_run.organization_id, p_run_id, v_step.id, v_step.command_class,
      v_run.autonomy, v_summary, now() + p_approval_ttl
    )
    RETURNING id INTO v_approval;

    UPDATE automation_steps SET status = 'waiting_approval' WHERE id = v_step.id;

    -- The lease is released here. This is the point of the whole design.
    UPDATE automation_runs
       SET status = 'waiting_approval',
           claimed_by = NULL, claimed_at = NULL, lease_expires_at = NULL
     WHERE id = p_run_id;

    RETURN ROW(v_step.id, v_step.step_index, v_step.action_kind,
               v_step.command_class, 'approve', v_approval, v_summary)::step_ticket;
  END IF;

  -- ---- proceed --------------------------------------------------------------
  UPDATE automation_steps
     SET status = 'running', started_at = now(), attempt = attempt + 1
   WHERE id = v_step.id;

  UPDATE automation_runs SET current_step = v_step.step_index WHERE id = p_run_id;

  RETURN ROW(v_step.id, v_step.step_index, v_step.action_kind,
             v_step.command_class, 'proceed', NULL, NULL)::step_ticket;
END;
$$;

CREATE OR REPLACE FUNCTION app.complete_step(
  p_step_id uuid,
  p_output  jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_run_id uuid;
BEGIN
  UPDATE automation_steps
     SET status = 'succeeded', finished_at = now(), output = p_output,
         error_code = NULL, error_message = NULL
   WHERE id = p_step_id AND status = 'running'
   RETURNING run_id INTO v_run_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'step % is not running', p_step_id
      USING ERRCODE = 'check_violation';
  END IF;

  -- Results accumulate in the run payload so a later action can use an earlier
  -- one's output. Merged rather than replaced: a step must not be able to erase
  -- what a previous step recorded.
  UPDATE automation_run_payloads
     SET context = context || jsonb_build_object(p_step_id::text, p_output)
   WHERE run_id = v_run_id;
END;
$$;

-- Retries are per step, with exponential backoff, and the run is suspended on a
-- timer rather than held. Re-running the whole workflow instead would repeat
-- every side effect that already succeeded — which for a Network action means
-- sending the same email again.
CREATE OR REPLACE FUNCTION app.fail_step(
  p_step_id   uuid,
  p_code      text,
  p_message   text,
  p_retryable boolean DEFAULT true
)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_step  automation_steps%ROWTYPE;
  v_delay interval;
BEGIN
  SELECT * INTO v_step FROM automation_steps WHERE id = p_step_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such step: %', p_step_id USING ERRCODE = 'no_data_found';
  END IF;

  IF p_retryable AND v_step.attempt < v_step.max_attempts THEN
    -- 30s, 60s, 120s… capped, so a failing integration backs off instead of
    -- hammering a service that is already unwell.
    v_delay := make_interval(
      secs => least(3600, (30 * power(2, greatest(v_step.attempt - 1, 0)))::int));

    UPDATE automation_steps
       SET status = 'pending', run_after = now() + v_delay,
           error_code = p_code, error_message = p_message, started_at = NULL
     WHERE id = p_step_id;

    UPDATE automation_runs
       SET status = 'waiting_until', run_after = now() + v_delay,
           claimed_by = NULL, claimed_at = NULL, lease_expires_at = NULL
     WHERE id = v_step.run_id;

    RETURN 'retry_scheduled';
  END IF;

  UPDATE automation_steps
     SET status = 'failed', finished_at = now(),
         error_code = p_code, error_message = p_message
   WHERE id = p_step_id;

  UPDATE automation_runs
     SET status = 'failed', finished_at = now(),
         claimed_by = NULL, claimed_at = NULL, lease_expires_at = NULL,
         error_code = p_code, error_message = p_message
   WHERE id = v_step.run_id;

  RETURN 'failed';
END;
$$;

-- A run suspended on a timer becomes claimable again once the timer passes.
CREATE OR REPLACE FUNCTION app.release_due_runs()
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_count integer;
BEGIN
  WITH released AS (
    UPDATE automation_runs
       SET status = 'queued'
     WHERE status = 'waiting_until'
       AND (run_after IS NULL OR run_after <= now())
     RETURNING 1
  )
  SELECT count(*)::integer INTO v_count FROM released;
  RETURN v_count;
END;
$$;

-- ---------------------------------------------------------------------------
-- Approval decisions
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.decide_approval(
  p_request_id uuid,
  p_decision   approval_decision,
  p_decided_by uuid DEFAULT NULL,
  p_reason     text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_req approval_requests%ROWTYPE;
BEGIN
  IF p_decision NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION
      'a person decides approved or rejected; % is not a decision they make',
      p_decision
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO v_req FROM approval_requests
   WHERE id = p_request_id AND decision = 'pending'
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no pending approval request with id %', p_request_id
      USING ERRCODE = 'no_data_found';
  END IF;

  -- An expired request is not answerable. Deciding one late would resurrect an
  -- action the expiry already refused, which is exactly the "stale prompt" case
  -- CLAUDE.md §3 warns about.
  IF v_req.expires_at <= now() THEN
    RAISE EXCEPTION 'approval request % expired at %', p_request_id, v_req.expires_at
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE approval_requests
     SET decision = p_decision, decided_at = now(),
         decided_by = p_decided_by, decision_reason = p_reason
   WHERE id = p_request_id;

  IF p_decision = 'approved' THEN
    -- Back to pending, not straight to running: the worker that picks the run
    -- up re-enters begin_step, which re-reads the gate. An approval authorises
    -- one step, not a bypass of the gate for the rest of the run.
    UPDATE automation_steps
       SET status = 'pending', run_after = NULL
     WHERE id = v_req.step_id;

    UPDATE automation_runs
       SET status = 'queued', run_after = NULL
     WHERE id = v_req.run_id;
  ELSE
    UPDATE automation_steps
       SET status = 'cancelled', finished_at = now(),
           error_code = 'approval_rejected', error_message = p_reason
     WHERE id = v_req.step_id;

    UPDATE automation_runs
       SET status = 'failed', finished_at = now(),
           error_code = 'approval_rejected',
           error_message = coalesce(p_reason, 'a human rejected the request')
     WHERE id = v_req.run_id;
  END IF;
END;
$$;

-- Silence is not consent.
--
-- CLAUDE.md §3: "No response within the session means it does not happen —
-- never assume approval from silence or a stale prompt." This is that sentence
-- as a sweep. The outcome is 'expired' rather than 'rejected' because the two
-- mean different things when someone later asks why the email never went out.
CREATE OR REPLACE FUNCTION app.expire_approvals()
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_count integer;
BEGIN
  WITH expired AS (
    UPDATE approval_requests
       SET decision = 'expired', decided_at = now()
     WHERE decision = 'pending' AND expires_at <= now()
     RETURNING id, run_id, step_id
  ),
  steps AS (
    UPDATE automation_steps s
       SET status = 'cancelled', finished_at = now(),
           error_code = 'approval_expired',
           error_message = 'nobody answered before the request expired'
      FROM expired e
     WHERE s.id = e.step_id
     RETURNING s.id
  ),
  runs AS (
    UPDATE automation_runs r
       SET status = 'failed', finished_at = now(),
           error_code = 'approval_expired',
           error_message = 'nobody answered the approval request before it expired'
      FROM expired e
     WHERE r.id = e.run_id
     RETURNING r.id
  )
  SELECT count(*)::integer INTO v_count FROM expired;

  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION app.cancel_run(p_run_id uuid, p_reason text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE automation_runs
     SET status = 'cancelled', finished_at = now(),
         claimed_by = NULL, claimed_at = NULL, lease_expires_at = NULL,
         error_code = 'cancelled', error_message = p_reason
   WHERE id = p_run_id
     AND status IN ('queued', 'running', 'waiting_approval', 'waiting_until');

  IF NOT FOUND THEN
    RAISE EXCEPTION 'run % is not in a cancellable state', p_run_id
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE automation_steps
     SET status = 'cancelled', finished_at = now()
   WHERE run_id = p_run_id AND status IN ('pending', 'running', 'waiting_approval');

  UPDATE approval_requests
     SET decision = 'rejected', decided_at = now(),
         decision_reason = coalesce(p_reason, 'the run was cancelled')
   WHERE run_id = p_run_id AND decision = 'pending';
END;
$$;

-- ---------------------------------------------------------------------------
-- Materialising scheduled runs
--
-- Turns "should run every 15 minutes" into concrete runs. The dedup key is the
-- job and the window it fires for, so calling this twice — two schedulers, or a
-- retry after a timeout — produces one run per window rather than two.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.materialise_scheduled_runs()
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_job    scheduled_jobs%ROWTYPE;
  v_count  integer := 0;
  v_next   timestamptz;
BEGIN
  FOR v_job IN
    SELECT * FROM scheduled_jobs
     WHERE is_active AND deleted_at IS NULL AND next_run_at <= now()
     ORDER BY next_run_at
     FOR UPDATE SKIP LOCKED
  LOOP
    PERFORM app.enqueue_automation_run(
      p_automation_id    => v_job.automation_id,
      p_input            => jsonb_build_object(
                              'scheduled_job_id', v_job.id,
                              'window', v_job.next_run_at),
      p_dedup_key        => v_job.id::text || '@' || v_job.next_run_at::text,
      p_scheduled_job_id => v_job.id
    );

    v_next := v_job.next_run_at + v_job.recurrence;

    -- A job that was down for a day must not wake up and fire every window it
    -- missed. Past the catch-up allowance, skip forward instead of replaying.
    IF v_next < now() - (v_job.recurrence * v_job.catchup_limit) THEN
      v_next := now() + v_job.recurrence;
    END IF;

    UPDATE scheduled_jobs
       SET next_run_at = v_next, last_run_at = now()
     WHERE id = v_job.id;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ---------------------------------------------------------------------------
-- Publishing a version
--
-- Bumping `current_version` and writing the definition have to happen together;
-- a version published without the pointer moving is invisible, and a pointer
-- moved to a version that does not exist stops every run.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.publish_automation_version(
  p_automation_id  uuid,
  p_trigger_kind   automation_trigger_kind,
  p_trigger_config jsonb DEFAULT '{}'::jsonb,
  p_conditions     jsonb DEFAULT '[]'::jsonb,
  p_actions        jsonb DEFAULT '[]'::jsonb
)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_auto    automations%ROWTYPE;
  v_version integer;
BEGIN
  SELECT * INTO v_auto FROM automations
   WHERE id = p_automation_id AND deleted_at IS NULL
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such automation: %', p_automation_id
      USING ERRCODE = 'no_data_found';
  END IF;

  v_version := v_auto.current_version + 1;

  INSERT INTO automation_versions (
    organization_id, automation_id, version,
    trigger_kind, trigger_config, conditions, actions,
    published_at, created_by
  ) VALUES (
    v_auto.organization_id, p_automation_id, v_version,
    p_trigger_kind, p_trigger_config, p_conditions, p_actions,
    now(), app.current_user_id()
  );

  UPDATE automations SET current_version = v_version WHERE id = p_automation_id;

  RETURN v_version;
END;
$$;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
SELECT app.apply_tenant_rls('automations');
SELECT app.apply_tenant_rls('scheduled_jobs');
SELECT app.apply_tenant_rls('automation_runs');
SELECT app.apply_tenant_rls('automation_run_payloads');
SELECT app.apply_tenant_rls('automation_steps');

/* automation_versions is append-only. A published definition is what a run was
 * authorised under; editing it after the fact rewrites the record of what
 * someone approved. */
ALTER TABLE automation_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE automation_versions FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_select ON automation_versions
  FOR SELECT USING (organization_id = app.current_org_id());

CREATE POLICY tenant_insert ON automation_versions
  FOR INSERT WITH CHECK (
    organization_id = app.current_org_id()
    AND app.can_write_in(organization_id)
  );

/* approval_requests: a decision is recorded once and never rewritten. UPDATE is
 * permitted because deciding one IS an update, but there is no DELETE policy —
 * the record that someone was asked, and what they said, is the governance
 * trail this whole subsystem exists to produce. */
ALTER TABLE approval_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE approval_requests FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_select ON approval_requests
  FOR SELECT USING (organization_id = app.current_org_id());

CREATE POLICY tenant_insert ON approval_requests
  FOR INSERT WITH CHECK (organization_id = app.current_org_id());

CREATE POLICY tenant_update ON approval_requests
  FOR UPDATE
  USING (
    organization_id = app.current_org_id()
    AND app.can_write_in(organization_id)
  )
  WITH CHECK (organization_id = app.current_org_id());

-- A decided request cannot be re-decided. Without this, "approved" is a state
-- someone can flip back to pending and re-answer, and the trail stops meaning
-- anything.
CREATE OR REPLACE FUNCTION app.freeze_approval_decision()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.decision <> 'pending' AND NEW.decision IS DISTINCT FROM OLD.decision THEN
    RAISE EXCEPTION
      'approval request % was already %; a decision is recorded once',
      OLD.id, OLD.decision
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER approval_requests_freeze_decision
  BEFORE UPDATE ON approval_requests
  FOR EACH ROW EXECUTE FUNCTION app.freeze_approval_decision();

-- ---------------------------------------------------------------------------
-- Audit
--
-- The governance record, not the execution record. `automation_runs` and
-- `automation_steps` are already a history of themselves and churn through
-- statuses on every poll — auditing them would bury the trail in bookkeeping
-- (DECISIONS.md D16). What is audited is who changed a rule and who approved
-- an action.
-- ---------------------------------------------------------------------------
SELECT app.attach_audit('automations');
SELECT app.attach_audit('approval_requests');

CREATE TRIGGER record_audit
  AFTER INSERT OR DELETE ON automation_versions
  FOR EACH ROW EXECUTE FUNCTION app.record_audit();

COMMIT;
