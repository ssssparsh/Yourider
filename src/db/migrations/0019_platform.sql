-- 0019_platform.sql
-- Six independent primitives batched into one migration because open-gaps.md
-- §9 already grouped them as "smaller items" — each is small enough on its own
-- that a dedicated migration per item would be mostly boilerplate repeated six
-- times. Each section is self-contained and independently reviewable.
--
-- API keys and webhook SUBSCRIPTIONS are schema; webhook DELIVERY (the actual
-- outbound HTTP call) is not built here, for the same reason the automation
-- worker (0015) and the email/calendar sync (0020) are not: this migration
-- owns state and authorisation, a process outside makes the network call.

BEGIN;

-- =============================================================================
-- A. API keys and webhook subscriptions
-- =============================================================================

CREATE TABLE api_keys (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  name              text NOT NULL CHECK (btrim(name) <> ''),
  -- The raw key is shown to the user exactly once, at creation, by the
  -- application. Only its hash is ever stored — this table cannot leak a
  -- usable credential even if read in full. sha256 rather than a slow
  -- password hash (bcrypt/argon2) because the key itself is the secret,
  -- generated with real entropy; unlike a password, brute-forcing the hash
  -- is not the threat, a dump of this table is.
  key_hash          bytea NOT NULL CHECK (octet_length(key_hash) = 32),
  -- First few characters, unhashed, so a key can be recognised in a UI list
  -- without ever displaying enough of it to be usable.
  key_prefix        text NOT NULL CHECK (length(key_prefix) BETWEEN 6 AND 12),

  scopes            text[] NOT NULL DEFAULT '{}',

  created_by        uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  last_used_at      timestamptz,
  expires_at        timestamptz,
  revoked_at        timestamptz,
  revoked_by        uuid REFERENCES users(id) ON DELETE SET NULL,

  updated_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT api_keys_revoked_is_attributed CHECK (
    revoked_at IS NULL OR revoked_by IS NOT NULL
  )
);

CREATE UNIQUE INDEX api_keys_hash_key ON api_keys (key_hash);

CREATE INDEX api_keys_org_active_idx
  ON api_keys (organization_id)
  WHERE revoked_at IS NULL;

SELECT app.attach_tenant_triggers('api_keys');
SELECT app.apply_tenant_rls('api_keys');
SELECT app.attach_audit('api_keys');

-- Issues a key: generates the secret, stores only its hash, returns the secret
-- once. There is no app.get_api_key() — by construction, nothing can retrieve
-- it after this call returns.
CREATE TYPE issued_api_key AS (
  id      uuid,
  secret  text,
  prefix  text
);

CREATE OR REPLACE FUNCTION app.issue_api_key(
  p_name   text,
  p_scopes text[] DEFAULT '{}'
)
RETURNS issued_api_key
LANGUAGE plpgsql
AS $$
DECLARE
  v_org    uuid := app.current_org_id();
  v_secret text := encode(gen_random_bytes(32), 'base64');
  v_prefix text := left(v_secret, 8);
  v_id     uuid;
  v_out    issued_api_key;
BEGIN
  INSERT INTO api_keys (organization_id, name, key_hash, key_prefix, scopes, created_by)
    VALUES (v_org, p_name, digest(v_secret, 'sha256'), v_prefix, p_scopes,
            app.current_user_id())
    RETURNING id INTO v_id;

  v_out := ROW(v_id, v_secret, v_prefix)::issued_api_key;
  RETURN v_out;
END;
$$;

-- Verifies a presented key and reports which organization it belongs to.
-- SECURITY DEFINER: authenticating a request happens before app.current_org_id
-- has anything to return, so this must be able to read api_keys across every
-- tenant to find the matching hash — the one legitimate reason this table's
-- normal RLS should not apply to a caller.
CREATE OR REPLACE FUNCTION app.authenticate_api_key(p_secret text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_org uuid;
BEGIN
  UPDATE api_keys
     SET last_used_at = now()
   WHERE key_hash = digest(p_secret, 'sha256')
     AND revoked_at IS NULL
     AND (expires_at IS NULL OR expires_at > now())
   RETURNING organization_id INTO v_org;

  RETURN v_org;  -- NULL for anything invalid, revoked, or expired
END;
$$;

CREATE TABLE webhook_subscriptions (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  url               text NOT NULL CHECK (url ~ '^https://'),
  -- HMAC signing secret for the receiver to verify the payload came from us.
  -- Generated server-side, never user-supplied — same reasoning as
  -- storage_key in 0013: a value whose entire purpose is proving authenticity
  -- must not be choosable by the party being authenticated.
  signing_secret    bytea NOT NULL DEFAULT gen_random_bytes(32),
  event_types       text[] NOT NULL CHECK (cardinality(event_types) > 0),

  is_active         boolean NOT NULL DEFAULT true,
  created_by        uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz
);

CREATE INDEX webhook_subscriptions_org_active_idx
  ON webhook_subscriptions (organization_id)
  WHERE is_active AND deleted_at IS NULL;

SELECT app.attach_tenant_triggers('webhook_subscriptions');
SELECT app.apply_tenant_rls('webhook_subscriptions');
SELECT app.attach_audit('webhook_subscriptions');

CREATE TYPE webhook_delivery_status AS ENUM ('pending', 'delivered', 'failed');

CREATE TABLE webhook_deliveries (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  subscription_id   uuid NOT NULL REFERENCES webhook_subscriptions(id) ON DELETE CASCADE,

  event_type        text NOT NULL,
  payload           jsonb NOT NULL,

  status            webhook_delivery_status NOT NULL DEFAULT 'pending',
  attempt           integer NOT NULL DEFAULT 0 CHECK (attempt >= 0),
  run_after         timestamptz NOT NULL DEFAULT now(),
  response_code     integer,
  -- Truncated at the application layer before insert; this is not the place
  -- to store an attacker-controlled response body at unbounded length.
  response_body     text,

  created_at        timestamptz NOT NULL DEFAULT now(),
  delivered_at      timestamptz
);

CREATE INDEX webhook_deliveries_pending_idx
  ON webhook_deliveries (run_after)
  WHERE status = 'pending';

CREATE INDEX webhook_deliveries_subscription_idx
  ON webhook_deliveries (subscription_id, created_at DESC);

CREATE TRIGGER webhook_deliveries_subscription_same_org
  BEFORE INSERT OR UPDATE OF subscription_id ON webhook_deliveries
  FOR EACH ROW
  EXECUTE FUNCTION app.assert_same_org('webhook_subscriptions', 'subscription_id');

SELECT app.apply_tenant_rls('webhook_deliveries');

-- =============================================================================
-- B. Notifications
-- =============================================================================

CREATE TYPE notification_kind AS ENUM (
  'assignment',       -- something was assigned to you
  'mention',          -- someone referenced you
  'approval_needed',  -- an approval_requests row needs your decision
  'stage_change',
  'task_due',
  'system'
);

CREATE TABLE notifications (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  user_id           uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  kind              notification_kind NOT NULL,
  title             text NOT NULL CHECK (btrim(title) <> ''),
  body              text,

  entity_type       crm_entity,
  entity_id         uuid,

  is_read           boolean NOT NULL DEFAULT false,
  read_at           timestamptz,

  created_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT notifications_entity_pair CHECK (
    (entity_type IS NULL) = (entity_id IS NULL)
  ),
  CONSTRAINT notifications_read_is_stamped CHECK (
    is_read = (read_at IS NOT NULL)
  )
);

-- The inbox query: a user's unread notifications, newest first. Partial so its
-- size tracks the backlog, not the lifetime total.
CREATE INDEX notifications_unread_idx
  ON notifications (user_id, created_at DESC)
  WHERE NOT is_read;

CREATE INDEX notifications_user_idx
  ON notifications (organization_id, user_id, created_at DESC);

CREATE TRIGGER notifications_freeze_org
  BEFORE UPDATE ON notifications
  FOR EACH ROW EXECUTE FUNCTION app.freeze_organization_id();

CREATE OR REPLACE FUNCTION app.notifications_user_same_org()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM app.assert_entity_in_org('user', NEW.user_id, NEW.organization_id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER notifications_user_same_org
  BEFORE INSERT OR UPDATE OF user_id ON notifications
  FOR EACH ROW EXECUTE FUNCTION app.notifications_user_same_org();

SELECT app.apply_tenant_rls('notifications');

-- A notification is addressed to one person. Everyone-in-tenant read access
-- (apply_tenant_rls's default) would let a colleague read your inbox, which is
-- exactly the kind of per-row confidentiality tenant-only RLS does not give by
-- default (open-gaps.md §8) — this table is the case that needs the narrower
-- policy, so it gets one rather than waiting on the general mechanism.
DROP POLICY tenant_select ON notifications;
CREATE POLICY tenant_select ON notifications
  FOR SELECT USING (
    organization_id = app.current_org_id() AND user_id = app.current_user_id()
  );

DROP POLICY tenant_update ON notifications;
CREATE POLICY tenant_update ON notifications
  FOR UPDATE
  USING (organization_id = app.current_org_id() AND user_id = app.current_user_id())
  WITH CHECK (organization_id = app.current_org_id() AND user_id = app.current_user_id());

-- Insert stays the standard policy: the party notifying you is not you.

CREATE OR REPLACE FUNCTION app.mark_notification_read(p_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE notifications SET is_read = true, read_at = now()
   WHERE id = p_id AND user_id = app.current_user_id() AND NOT is_read;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no unread notification % for the current user', p_id
      USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;

-- =============================================================================
-- C. Merge and dedup
-- =============================================================================
--
-- Scoped to contacts and accounts, the two entities CRMs actually merge in
-- practice. A fully generic "merge any crm_entity" would mean dynamically
-- discovering every FK into every table at execution time — plausible, but a
-- much larger and riskier piece of dynamic SQL than two known, reviewable
-- functions, for entities nothing here actually merges.
--
-- HISTORY IS NOT REWRITTEN. Live relationships (deals, jobs, channels,
-- attachments, tasks) are repointed to the survivor; `activities` and
-- `audit_log` keep the original id, the same choice 0011 made for the consent
-- ledger. A timeline entry that said "call with Dana" stays a call with the
-- contact Dana was at the time — rewriting it would fabricate history that
-- never happened under the survivor's identity. `entity_merges` is what makes
-- the survivor's full timeline reconstructable across both ids.

CREATE TABLE entity_merges (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  entity_type       crm_entity NOT NULL CHECK (entity_type IN ('contact', 'account')),
  survivor_id       uuid NOT NULL,
  merged_id         uuid NOT NULL,
  -- Full snapshot of the losing record at merge time — the undo record and the
  -- audit answer to "what did we lose".
  merged_snapshot   jsonb NOT NULL,

  merged_by         uuid REFERENCES users(id) ON DELETE SET NULL,
  merged_at         timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT entity_merges_distinct CHECK (survivor_id <> merged_id)
);

CREATE INDEX entity_merges_survivor_idx
  ON entity_merges (organization_id, entity_type, survivor_id);

-- So "what was this id before it was merged away" is answerable from either
-- direction.
CREATE INDEX entity_merges_merged_idx
  ON entity_merges (organization_id, entity_type, merged_id);

SELECT app.apply_tenant_rls('entity_merges');

/* Append-only: a merge is a fact, like a consent record. */
DROP POLICY tenant_update ON entity_merges;
DROP POLICY tenant_delete ON entity_merges;

CREATE OR REPLACE FUNCTION app.merge_contacts(p_survivor_id uuid, p_merged_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_org      uuid;
  v_survivor contacts%ROWTYPE;
  v_loser    contacts%ROWTYPE;
BEGIN
  SELECT * INTO v_survivor FROM contacts
   WHERE id = p_survivor_id AND deleted_at IS NULL;
  SELECT * INTO v_loser FROM contacts
   WHERE id = p_merged_id AND deleted_at IS NULL;

  IF v_survivor.id IS NULL OR v_loser.id IS NULL THEN
    RAISE EXCEPTION 'both contacts must exist and be live'
      USING ERRCODE = 'no_data_found';
  END IF;
  IF v_survivor.id = v_loser.id THEN
    RAISE EXCEPTION 'cannot merge a contact into itself'
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_survivor.organization_id <> v_loser.organization_id THEN
    RAISE EXCEPTION 'cannot merge contacts from different organizations'
      USING ERRCODE = 'foreign_key_violation';
  END IF;
  v_org := v_survivor.organization_id;

  -- Repoint every live reference. Order does not matter between these; none
  -- depends on another having run first.
  UPDATE deals SET primary_contact_id = p_survivor_id
   WHERE primary_contact_id = p_merged_id;

  -- deal_contacts is unique on (deal_id, contact_id): if the survivor is
  -- already on a deal the loser was also on, repointing would collide.
  -- Dropping the now-redundant row is correct — the deal already has the
  -- survivor attached, which is what the merge is trying to achieve.
  DELETE FROM deal_contacts dc
   WHERE dc.contact_id = p_merged_id
     AND EXISTS (
       SELECT 1 FROM deal_contacts s
        WHERE s.deal_id = dc.deal_id AND s.contact_id = p_survivor_id
     );
  UPDATE deal_contacts SET contact_id = p_survivor_id WHERE contact_id = p_merged_id;

  UPDATE service_jobs SET contact_id = p_survivor_id WHERE contact_id = p_merged_id;

  -- contact_channels has no such collision risk: a channel is an address, and
  -- the loser's addresses become additional addresses of the survivor.
  UPDATE contact_channels SET contact_id = p_survivor_id WHERE contact_id = p_merged_id;

  UPDATE attachments SET entity_id = p_survivor_id
   WHERE entity_type = 'contact' AND entity_id = p_merged_id;
  UPDATE tasks SET entity_id = p_survivor_id
   WHERE entity_type = 'contact' AND entity_id = p_merged_id;

  INSERT INTO entity_merges (organization_id, entity_type, survivor_id, merged_id,
                             merged_snapshot, merged_by)
    VALUES (v_org, 'contact', p_survivor_id, p_merged_id, to_jsonb(v_loser),
            app.current_user_id());

  UPDATE contacts SET deleted_at = now() WHERE id = p_merged_id;
END;
$$;

CREATE OR REPLACE FUNCTION app.merge_accounts(p_survivor_id uuid, p_merged_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_org      uuid;
  v_survivor accounts%ROWTYPE;
  v_loser    accounts%ROWTYPE;
BEGIN
  SELECT * INTO v_survivor FROM accounts
   WHERE id = p_survivor_id AND deleted_at IS NULL;
  SELECT * INTO v_loser FROM accounts
   WHERE id = p_merged_id AND deleted_at IS NULL;

  IF v_survivor.id IS NULL OR v_loser.id IS NULL THEN
    RAISE EXCEPTION 'both accounts must exist and be live'
      USING ERRCODE = 'no_data_found';
  END IF;
  IF v_survivor.id = v_loser.id THEN
    RAISE EXCEPTION 'cannot merge an account into itself'
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_survivor.organization_id <> v_loser.organization_id THEN
    RAISE EXCEPTION 'cannot merge accounts from different organizations'
      USING ERRCODE = 'foreign_key_violation';
  END IF;
  v_org := v_survivor.organization_id;

  UPDATE contacts SET account_id = p_survivor_id WHERE account_id = p_merged_id;
  UPDATE deals SET account_id = p_survivor_id WHERE account_id = p_merged_id;
  UPDATE service_jobs SET account_id = p_survivor_id WHERE account_id = p_merged_id;
  -- An account cannot become its own parent through the merge.
  UPDATE accounts SET parent_id = p_survivor_id
   WHERE parent_id = p_merged_id AND id <> p_survivor_id;

  UPDATE attachments SET entity_id = p_survivor_id
   WHERE entity_type = 'account' AND entity_id = p_merged_id;
  UPDATE tasks SET entity_id = p_survivor_id
   WHERE entity_type = 'account' AND entity_id = p_merged_id;

  INSERT INTO entity_merges (organization_id, entity_type, survivor_id, merged_id,
                             merged_snapshot, merged_by)
    VALUES (v_org, 'account', p_survivor_id, p_merged_id, to_jsonb(v_loser),
            app.current_user_id());

  UPDATE accounts SET deleted_at = now() WHERE id = p_merged_id;
END;
$$;

-- =============================================================================
-- D. Import batches
-- =============================================================================
--
-- A bulk import currently leaves no trace beyond the rows it created — no way
-- to see what a specific import did, or undo it. `created_by` already exists
-- on every entity table; what is missing is a row to point it at.

CREATE TYPE import_batch_status AS ENUM (
  'processing', 'completed', 'completed_with_errors', 'failed', 'rolled_back'
);

CREATE TABLE import_batches (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  entity_type       crm_entity NOT NULL,
  source_filename   text,
  -- The uploaded file itself, if kept — see 0013.
  source_file_id    uuid REFERENCES files(id) ON DELETE SET NULL,

  status            import_batch_status NOT NULL DEFAULT 'processing',
  total_rows        integer,
  succeeded_rows     integer NOT NULL DEFAULT 0 CHECK (succeeded_rows >= 0),
  failed_rows       integer NOT NULL DEFAULT 0 CHECK (failed_rows >= 0),
  -- Per-row failures: [{row: 14, error: "invalid email"}]. Small enough per
  -- import to live inline rather than warrant its own table.
  errors            jsonb NOT NULL DEFAULT '[]'::jsonb,

  created_by        uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  completed_at      timestamptz,

  CONSTRAINT import_batches_completed_is_stamped CHECK (
    status IN ('processing') OR completed_at IS NOT NULL
  )
);

CREATE INDEX import_batches_org_idx
  ON import_batches (organization_id, created_at DESC);

CREATE TRIGGER import_batches_freeze_org
  BEFORE UPDATE ON import_batches
  FOR EACH ROW EXECUTE FUNCTION app.freeze_organization_id();

SELECT app.apply_tenant_rls('import_batches');
DROP POLICY tenant_delete ON import_batches;   -- a completed import is a record, not scratch

-- Every table an import can land rows in carries this so a batch is
-- traceable and, within the retention of its rows, reversible: "undo this
-- import" is `UPDATE <table> SET deleted_at = now() WHERE import_batch_id = ?`.
ALTER TABLE accounts ADD COLUMN import_batch_id uuid REFERENCES import_batches(id) ON DELETE SET NULL;
ALTER TABLE contacts ADD COLUMN import_batch_id uuid REFERENCES import_batches(id) ON DELETE SET NULL;
ALTER TABLE leads    ADD COLUMN import_batch_id uuid REFERENCES import_batches(id) ON DELETE SET NULL;
ALTER TABLE deals    ADD COLUMN import_batch_id uuid REFERENCES import_batches(id) ON DELETE SET NULL;

CREATE INDEX accounts_import_batch_idx ON accounts (import_batch_id) WHERE import_batch_id IS NOT NULL;
CREATE INDEX contacts_import_batch_idx ON contacts (import_batch_id) WHERE import_batch_id IS NOT NULL;
CREATE INDEX leads_import_batch_idx    ON leads    (import_batch_id) WHERE import_batch_id IS NOT NULL;
CREATE INDEX deals_import_batch_idx    ON deals    (import_batch_id) WHERE import_batch_id IS NOT NULL;

CREATE TRIGGER accounts_import_batch_same_org
  BEFORE INSERT OR UPDATE OF import_batch_id ON accounts
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('import_batches', 'import_batch_id');
CREATE TRIGGER contacts_import_batch_same_org
  BEFORE INSERT OR UPDATE OF import_batch_id ON contacts
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('import_batches', 'import_batch_id');
CREATE TRIGGER leads_import_batch_same_org
  BEFORE INSERT OR UPDATE OF import_batch_id ON leads
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('import_batches', 'import_batch_id');
CREATE TRIGGER deals_import_batch_same_org
  BEFORE INSERT OR UPDATE OF import_batch_id ON deals
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('import_batches', 'import_batch_id');

-- Soft-deletes every row a batch created. A real undo, not a suggestion: it
-- reuses the same deleted_at every other soft delete in this schema respects,
-- so everything downstream (RLS's default exclusion, reporting) already knows
-- how to treat the rows as gone.
CREATE OR REPLACE FUNCTION app.rollback_import_batch(p_batch_id uuid)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_batch import_batches%ROWTYPE;
  v_count integer;
BEGIN
  SELECT * INTO v_batch FROM import_batches WHERE id = p_batch_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such import batch: %', p_batch_id
      USING ERRCODE = 'no_data_found';
  END IF;

  v_count := 0;
  CASE v_batch.entity_type
    WHEN 'account' THEN
      WITH r AS (UPDATE accounts SET deleted_at = now()
                  WHERE import_batch_id = p_batch_id AND deleted_at IS NULL
                 RETURNING 1)
      SELECT count(*) INTO v_count FROM r;
    WHEN 'contact' THEN
      WITH r AS (UPDATE contacts SET deleted_at = now()
                  WHERE import_batch_id = p_batch_id AND deleted_at IS NULL
                 RETURNING 1)
      SELECT count(*) INTO v_count FROM r;
    WHEN 'lead' THEN
      WITH r AS (UPDATE leads SET deleted_at = now()
                  WHERE import_batch_id = p_batch_id AND deleted_at IS NULL
                 RETURNING 1)
      SELECT count(*) INTO v_count FROM r;
    WHEN 'deal' THEN
      WITH r AS (UPDATE deals SET deleted_at = now()
                  WHERE import_batch_id = p_batch_id AND deleted_at IS NULL
                 RETURNING 1)
      SELECT count(*) INTO v_count FROM r;
    ELSE
      RAISE EXCEPTION 'imports of % are not tracked for rollback', v_batch.entity_type
        USING ERRCODE = 'check_violation';
  END CASE;

  UPDATE import_batches SET status = 'rolled_back' WHERE id = p_batch_id;
  RETURN v_count;
END;
$$;

-- =============================================================================
-- E. FX rate provenance
-- =============================================================================
--
-- `deals.fx_rate` (0005) records a number but not where it came from or when —
-- so a historical conversion is unauditable months later. This does not fetch
-- rates (that needs a live rates API, and is out of scope until one is
-- connected); it gives a place to record one once fetched, and traces a deal's
-- rate back to the record it was read from.

CREATE TABLE fx_rates (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  from_currency     char(3) NOT NULL,
  to_currency       char(3) NOT NULL,
  rate              numeric(18,8) NOT NULL CHECK (rate > 0),
  source            text NOT NULL CHECK (btrim(source) <> ''),
  as_of             timestamptz NOT NULL,

  created_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT fx_rates_distinct_currencies CHECK (from_currency <> to_currency)
);

-- Rates are immutable facts about a point in time; a correction is a new row
-- with a later as_of; two rates for the same pair at the same instant is
-- ambiguity a unique index refuses to store.
CREATE UNIQUE INDEX fx_rates_unique
  ON fx_rates (organization_id, from_currency, to_currency, as_of);

CREATE INDEX fx_rates_lookup_idx
  ON fx_rates (organization_id, from_currency, to_currency, as_of DESC);

SELECT app.apply_tenant_rls('fx_rates');
DROP POLICY tenant_update ON fx_rates;
DROP POLICY tenant_delete ON fx_rates;

ALTER TABLE deals ADD COLUMN fx_rate_source_id uuid REFERENCES fx_rates(id) ON DELETE SET NULL;

CREATE TRIGGER deals_fx_rate_source_same_org
  BEFORE INSERT OR UPDATE OF fx_rate_source_id ON deals
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('fx_rates', 'fx_rate_source_id');

-- The most recent rate for a pair as of a given time, so "what rate would this
-- deal have used" is one lookup rather than a hand-written query someone gets
-- the ORDER BY wrong on.
CREATE OR REPLACE FUNCTION app.latest_fx_rate(
  p_from    char(3),
  p_to      char(3),
  p_org     uuid        DEFAULT NULL,
  p_as_of   timestamptz DEFAULT now()
)
RETURNS fx_rates
LANGUAGE sql
STABLE
AS $$
  SELECT * FROM fx_rates
   WHERE organization_id = coalesce(p_org, app.current_org_id())
     AND from_currency = p_from AND to_currency = p_to
     AND as_of <= p_as_of
   ORDER BY as_of DESC
   LIMIT 1;
$$;

-- =============================================================================
-- F. Denormalised label on timeline rows
-- =============================================================================
--
-- A timeline entry today reads sensibly only while the record it points at
-- still exists — `entity_id` resolves to nothing once the record is gone, and
-- the row becomes an orphaned reference with no way to say what it was about.
-- Caching the name at write time, the way an invoice line caches a price
-- (0014), makes deletion non-destructive to history: the entry still reads
-- "call with Dana Kohli" after Dana is gone.

ALTER TABLE activities ADD COLUMN entity_label text;

-- Best-effort and intentionally not authoritative: a partitioned, high-volume
-- table gets a plain lookup, not the FK-validated path 0013 gave attachments —
-- the same volume trade-off DECISIONS.md D15 already made for this table.
CREATE OR REPLACE FUNCTION app.entity_display_name(
  p_entity crm_entity,
  p_id     uuid
)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_table text := app.entity_table(p_entity);
  v_name  text;
BEGIN
  IF v_table IS NULL THEN
    RETURN NULL;
  END IF;

  CASE p_entity
    WHEN 'contact' THEN
      EXECUTE format('SELECT full_name FROM %I WHERE id = $1', v_table)
        INTO v_name USING p_id;
    WHEN 'user' THEN
      EXECUTE format('SELECT full_name FROM %I WHERE id = $1', v_table)
        INTO v_name USING p_id;
    ELSE
      EXECUTE format('SELECT name FROM %I WHERE id = $1', v_table)
        INTO v_name USING p_id;
  END CASE;

  RETURN v_name;
EXCEPTION WHEN undefined_column THEN
  RETURN NULL;
END;
$$;

COMMIT;
