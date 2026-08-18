-- 0007_activity_audit.sql
-- The timeline, the audit trail, and tasks.
--
-- Two separate logs, deliberately:
--
--   `activities` is the business timeline a human reads — calls, emails,
--   meetings, notes. It is what appears on a contact's record.
--
--   `audit_log` is the forensic record — which column on which row changed from
--   what to what, by whom. It is what you produce when someone asks "who
--   discounted this deal" or when a regulator asks for a data-access history.
--
-- Collapsing them into one table makes both worse: the timeline fills with
-- field-level noise, and the audit trail becomes unqueryable because business
-- events and column diffs need different shapes.
--
-- Both are RANGE-partitioned by month. These two tables grow with interaction
-- volume rather than customer count, so they are the first to reach hundreds of
-- millions of rows. Partitioning means an old month is detached and archived in
-- constant time instead of a DELETE that rewrites the table, and date-scoped
-- queries never touch partitions outside their window.

BEGIN;

CREATE TYPE activity_kind AS ENUM (
  'note',
  'call',
  'email',
  'meeting',
  'sms',
  'task_completed',
  'stage_change',
  'assignment',
  'job_scheduled',
  'job_completed',
  'file_attached',
  'system'
);

-- Who caused a change. `agent` is first-class: once /src/agents personas write
-- CRM records, every mutation must be attributable to a named agent, not
-- silently recorded as though a human did it. This is what makes the approval
-- gate in CLAUDE.md §3 auditable after the fact rather than only at the moment
-- of the prompt.
CREATE TYPE actor_kind AS ENUM ('user', 'agent', 'system', 'integration');

-- The entity an activity or audit row is about. Kept as a text-backed enum
-- rather than a real FK because these tables reference several parent tables and
-- a partitioned table cannot carry FKs into them efficiently at this volume.
CREATE TYPE crm_entity AS ENUM (
  'account', 'contact', 'lead', 'deal', 'service_job', 'service', 'task', 'user'
);

-- ---------------------------------------------------------------------------
-- Activities — the human-readable timeline.
-- ---------------------------------------------------------------------------
CREATE TABLE activities (
  id               uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL,

  kind             activity_kind NOT NULL,
  subject          text,
  body             text,

  entity_type      crm_entity NOT NULL,
  entity_id        uuid NOT NULL,
  -- Denormalised secondary links so "show me everything about this account"
  -- does not need a recursive walk through deals and jobs.
  account_id       uuid,
  contact_id       uuid,
  deal_id          uuid,
  job_id           uuid,

  actor_type       actor_kind NOT NULL DEFAULT 'user',
  actor_user_id    uuid,
  actor_agent      text,          -- agent name from /src/agents, when actor_type='agent'

  -- When it happened in the world, which is not always when it was recorded.
  occurred_at      timestamptz NOT NULL DEFAULT now(),
  duration_seconds integer CHECK (duration_seconds IS NULL OR duration_seconds >= 0),

  -- Outbound communication requires a record of consent having been checked.
  -- NULL for activities where it does not apply.
  consent_checked  boolean,

  metadata         jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at       timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (id, created_at),
  CONSTRAINT activities_agent_named CHECK (
    actor_type <> 'agent' OR actor_agent IS NOT NULL
  )
) PARTITION BY RANGE (created_at);

-- The record timeline: one entity, newest first. This is the query that renders
-- every detail page, so it gets a dedicated covering index.
CREATE INDEX activities_entity_idx
  ON activities (organization_id, entity_type, entity_id, occurred_at DESC);

CREATE INDEX activities_account_idx
  ON activities (organization_id, account_id, occurred_at DESC)
  WHERE account_id IS NOT NULL;

CREATE INDEX activities_contact_idx
  ON activities (organization_id, contact_id, occurred_at DESC)
  WHERE contact_id IS NOT NULL;

CREATE INDEX activities_deal_idx
  ON activities (organization_id, deal_id, occurred_at DESC)
  WHERE deal_id IS NOT NULL;

CREATE INDEX activities_job_idx
  ON activities (organization_id, job_id, occurred_at DESC)
  WHERE job_id IS NOT NULL;

-- "What has this agent been doing" — the operator's view of autonomous work.
CREATE INDEX activities_agent_idx
  ON activities (organization_id, actor_agent, occurred_at DESC)
  WHERE actor_agent IS NOT NULL;

CREATE INDEX activities_org_kind_idx
  ON activities (organization_id, kind, occurred_at DESC);

-- ---------------------------------------------------------------------------
-- Audit log — field-level forensics.
-- ---------------------------------------------------------------------------
CREATE TYPE audit_action AS ENUM ('insert', 'update', 'delete', 'restore', 'read');

CREATE TABLE audit_log (
  id               uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL,

  table_name       text NOT NULL,
  record_id        uuid NOT NULL,
  action           audit_action NOT NULL,

  -- Only the columns that actually changed, plus their before/after values.
  -- Storing full row snapshots would multiply storage for no added answer.
  changed_fields   text[] NOT NULL DEFAULT '{}',
  old_values       jsonb NOT NULL DEFAULT '{}'::jsonb,
  new_values       jsonb NOT NULL DEFAULT '{}'::jsonb,

  actor_type       actor_kind NOT NULL DEFAULT 'user',
  actor_user_id    uuid,
  actor_agent      text,
  -- Free text explaining why. Agents are expected to populate this; humans
  -- usually will not, and that asymmetry is fine.
  reason           text,

  -- Request correlation, so a single API call's cascade of writes can be
  -- reassembled.
  request_id       text,
  ip_address       inet,
  user_agent       text,

  created_at       timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (id, created_at),
  CONSTRAINT audit_log_agent_named CHECK (
    actor_type <> 'agent' OR actor_agent IS NOT NULL
  )
) PARTITION BY RANGE (created_at);

-- "Everything that ever happened to this row."
CREATE INDEX audit_log_record_idx
  ON audit_log (organization_id, table_name, record_id, created_at DESC);

CREATE INDEX audit_log_actor_idx
  ON audit_log (organization_id, actor_user_id, created_at DESC)
  WHERE actor_user_id IS NOT NULL;

CREATE INDEX audit_log_agent_idx
  ON audit_log (organization_id, actor_agent, created_at DESC)
  WHERE actor_agent IS NOT NULL;

CREATE INDEX audit_log_request_idx
  ON audit_log (request_id)
  WHERE request_id IS NOT NULL;

CREATE INDEX audit_log_changed_fields_idx
  ON audit_log USING gin (changed_fields);

-- ---------------------------------------------------------------------------
-- Generic audit trigger.
--
-- Attached per-table in 0009. Computes the changed-column diff rather than
-- snapshotting whole rows, and reads actor identity from the session so
-- application code cannot forget to pass it.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.record_audit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_old      jsonb := '{}'::jsonb;
  v_new      jsonb := '{}'::jsonb;
  v_changed  text[] := '{}';
  v_action   audit_action;
  v_org      uuid;
  v_record   uuid;
  v_key      text;
  v_actor_type actor_kind;
  v_agent    text;
BEGIN
  -- Actor: an agent identifies itself by setting app.current_agent. Absent
  -- that, a user id means 'user', and neither means 'system'.
  v_agent := nullif(current_setting('app.current_agent', true), '');
  IF v_agent IS NOT NULL THEN
    v_actor_type := 'agent';
  ELSIF app.current_user_id() IS NOT NULL THEN
    v_actor_type := 'user';
  ELSE
    v_actor_type := 'system';
  END IF;

  IF TG_OP = 'INSERT' THEN
    v_action := 'insert';
    v_new := to_jsonb(NEW);
    v_org := NEW.organization_id;
    v_record := NEW.id;

  ELSIF TG_OP = 'UPDATE' THEN
    v_org := NEW.organization_id;
    v_record := NEW.id;
    -- A soft delete is a delete, and un-setting deleted_at is a restore.
    IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
      v_action := 'delete';
    ELSIF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
      v_action := 'restore';
    ELSE
      v_action := 'update';
    END IF;

    FOR v_key IN SELECT jsonb_object_keys(to_jsonb(NEW)) LOOP
      IF to_jsonb(NEW) -> v_key IS DISTINCT FROM to_jsonb(OLD) -> v_key THEN
        -- updated_at changes on every write and carries no information.
        IF v_key <> 'updated_at' THEN
          v_changed := v_changed || v_key;
          v_old := v_old || jsonb_build_object(v_key, to_jsonb(OLD) -> v_key);
          v_new := v_new || jsonb_build_object(v_key, to_jsonb(NEW) -> v_key);
        END IF;
      END IF;
    END LOOP;

    -- Nothing of substance changed; do not write an empty audit row.
    IF array_length(v_changed, 1) IS NULL THEN
      RETURN NEW;
    END IF;

  ELSE  -- DELETE
    v_action := 'delete';
    v_old := to_jsonb(OLD);
    v_org := OLD.organization_id;
    v_record := OLD.id;
  END IF;

  INSERT INTO audit_log (
    organization_id, table_name, record_id, action,
    changed_fields, old_values, new_values,
    actor_type, actor_user_id, actor_agent, reason, request_id
  ) VALUES (
    v_org, TG_TABLE_NAME, v_record, v_action,
    v_changed, v_old, v_new,
    v_actor_type, app.current_user_id(), v_agent,
    nullif(current_setting('app.audit_reason', true), ''),
    nullif(current_setting('app.request_id', true), '')
  );

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

CREATE OR REPLACE FUNCTION app.attach_audit(p_table regclass)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  EXECUTE format(
    'CREATE TRIGGER record_audit AFTER INSERT OR UPDATE OR DELETE ON %s
       FOR EACH ROW EXECUTE FUNCTION app.record_audit()', p_table);
END;
$$;

-- ---------------------------------------------------------------------------
-- Tasks — follow-ups attached to any record.
-- Not partitioned: tasks are bounded by team size and worked down, unlike
-- activities which accumulate forever.
-- ---------------------------------------------------------------------------
CREATE TABLE tasks (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  title            text NOT NULL CHECK (length(btrim(title)) > 0),
  description      text,
  priority         job_priority NOT NULL DEFAULT 'normal',

  entity_type      crm_entity,
  entity_id        uuid,

  assignee_id      uuid REFERENCES users(id) ON DELETE SET NULL,
  due_at           timestamptz,
  reminder_at      timestamptz,
  completed_at     timestamptz,
  completed_by     uuid REFERENCES users(id) ON DELETE SET NULL,

  -- Set when an agent proposed this task, so the UI can mark it as
  -- agent-originated per DESIGN.md's agent-draft requirement.
  created_by_agent text,

  created_by       uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  deleted_at       timestamptz,

  CONSTRAINT tasks_entity_paired CHECK (
    (entity_type IS NULL) = (entity_id IS NULL)
  )
);

-- The work queue: open tasks for one person, soonest due first.
CREATE INDEX tasks_org_assignee_due_idx
  ON tasks (organization_id, assignee_id, due_at)
  WHERE deleted_at IS NULL AND completed_at IS NULL;

-- Overdue sweep, tenant-wide.
CREATE INDEX tasks_org_due_idx
  ON tasks (organization_id, due_at)
  WHERE deleted_at IS NULL AND completed_at IS NULL;

CREATE INDEX tasks_entity_idx
  ON tasks (organization_id, entity_type, entity_id)
  WHERE deleted_at IS NULL AND entity_id IS NOT NULL;

SELECT app.attach_tenant_triggers('tasks');

-- ---------------------------------------------------------------------------
-- Initial partitions. `ensure_partition_window` is idempotent and is meant to
-- run monthly from cron; see src/db/README.md.
-- ---------------------------------------------------------------------------
SELECT app.ensure_partition_window('activities', 2, 6);
SELECT app.ensure_partition_window('audit_log', 2, 6);

COMMIT;
