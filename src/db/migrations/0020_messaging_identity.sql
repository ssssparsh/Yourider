-- 0020_messaging_identity.sql
-- Identity for email and calendar, without a sync worker.
--
-- `activities.kind = 'email'` records that an email happened. There is no
-- thread identity, no provider message-id, and no per-user mailbox connection
-- — so two-way sync, deduplication of a message seen twice, and threading are
-- all impossible. Adding this after activity data already exists means
-- backfilling identity that was never captured, which is why it goes in now
-- rather than when a mailbox connector actually gets built.
--
-- WHAT THIS DOES NOT DO: talk to Gmail, Microsoft Graph, or any mail server.
-- That needs OAuth and a live API connection this environment does not have.
-- This is the identity model a sync worker will write into once one exists —
-- the same boundary 0015 drew around the automation worker: this migration
-- owns the data shape, a process outside owns the network call.

BEGIN;

-- ---------------------------------------------------------------------------
-- Connected accounts
-- ---------------------------------------------------------------------------
CREATE TYPE connected_account_provider AS ENUM ('gmail', 'microsoft', 'imap', 'caldav');
CREATE TYPE connected_account_status AS ENUM ('active', 'reauth_required', 'disconnected');

CREATE TABLE connected_accounts (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  user_id           uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  provider          connected_account_provider NOT NULL,
  email_address     citext NOT NULL,

  -- OAuth tokens are secrets and do not belong in a plain column even inside
  -- this database — CLAUDE.md §3's "no secrets in code or prompts" extends to
  -- application data with the same blast radius as a leaked credential. This
  -- table records that a connection exists and its sync state; the tokens
  -- themselves belong in a secrets manager, referenced here by an opaque id a
  -- worker resolves at call time, not stored inline.
  credential_ref    text,

  status            connected_account_status NOT NULL DEFAULT 'active',
  sync_enabled      boolean NOT NULL DEFAULT true,
  last_synced_at    timestamptz,
  sync_cursor       text,   -- provider-specific pagination/delta token

  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz
);

CREATE UNIQUE INDEX connected_accounts_unique
  ON connected_accounts (organization_id, user_id, provider, email_address)
  WHERE deleted_at IS NULL;

CREATE INDEX connected_accounts_org_user_idx
  ON connected_accounts (organization_id, user_id)
  WHERE deleted_at IS NULL;

SELECT app.attach_tenant_triggers('connected_accounts');

CREATE TRIGGER connected_accounts_user_same_org
  BEFORE INSERT OR UPDATE OF user_id ON connected_accounts
  FOR EACH ROW EXECUTE FUNCTION app.notifications_user_same_org();

SELECT app.apply_tenant_rls('connected_accounts');

-- A mailbox connection is personal, the same reasoning as notifications: the
-- default tenant-wide read would let a colleague see which mailbox someone
-- connected and its sync state.
DROP POLICY tenant_select ON connected_accounts;
CREATE POLICY tenant_select ON connected_accounts
  FOR SELECT USING (
    organization_id = app.current_org_id()
    AND (user_id = app.current_user_id()
         OR coalesce(app.current_role_in(organization_id) IN ('owner', 'admin'), false))
  );

SELECT app.attach_audit('connected_accounts');

-- ---------------------------------------------------------------------------
-- Threads and messages
-- ---------------------------------------------------------------------------
CREATE TABLE message_threads (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  -- Provider thread id (Gmail threadId, RFC 2822 References chain root). The
  -- identity a two-way sync actually keys on.
  provider_thread_id text,
  subject           text,

  entity_type       crm_entity,
  entity_id         uuid,

  last_message_at   timestamptz,
  message_count     integer NOT NULL DEFAULT 0 CHECK (message_count >= 0),

  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT message_threads_entity_pair CHECK (
    (entity_type IS NULL) = (entity_id IS NULL)
  )
);

-- Not globally unique: the same provider thread id can recur across distinct
-- mailboxes (two people on the same email chain, each syncing their own copy).
CREATE UNIQUE INDEX message_threads_provider_key
  ON message_threads (organization_id, provider_thread_id)
  WHERE provider_thread_id IS NOT NULL;

CREATE INDEX message_threads_entity_idx
  ON message_threads (organization_id, entity_type, entity_id)
  WHERE entity_id IS NOT NULL;

SELECT app.attach_tenant_triggers('message_threads');

CREATE OR REPLACE FUNCTION app.message_threads_entity_valid()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.entity_type IS NOT NULL THEN
    PERFORM app.assert_entity_in_org(NEW.entity_type, NEW.entity_id, NEW.organization_id);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER message_threads_entity_valid
  BEFORE INSERT OR UPDATE OF entity_type, entity_id ON message_threads
  FOR EACH ROW EXECUTE FUNCTION app.message_threads_entity_valid();

SELECT app.apply_tenant_rls('message_threads');

CREATE TYPE message_direction AS ENUM ('inbound', 'outbound');

CREATE TABLE messages (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  thread_id         uuid NOT NULL REFERENCES message_threads(id) ON DELETE CASCADE,
  connected_account_id uuid REFERENCES connected_accounts(id) ON DELETE SET NULL,

  -- RFC 2822 Message-ID or provider message id. What makes "we already have
  -- this one" answerable, and what a two-way sync is keyed on.
  provider_message_id text NOT NULL,
  in_reply_to       text,

  direction         message_direction NOT NULL,
  from_address      citext NOT NULL,
  to_addresses      citext[] NOT NULL DEFAULT '{}',
  cc_addresses      citext[] NOT NULL DEFAULT '{}',
  subject           text,
  -- The body is content, not metadata, and can be large; if it grows into a
  -- real storage concern later this is exactly the shape 0013's files table
  -- exists for. Kept inline for now — most individual emails are small, and a
  -- second table for every message is premature at this stage.
  body_text         text,
  body_html         text,

  sent_at           timestamptz NOT NULL,

  -- Linked activity for "this email also appears on the deal's timeline" —
  -- optional, since not every synced message is about a CRM record.
  activity_id       uuid,

  created_at        timestamptz NOT NULL DEFAULT now()
);

-- The dedup key. A message seen twice by two sync passes, or by two people's
-- mailboxes both connected, is one row per (organization, provider id) here —
-- worth widening later if the same provider id can legitimately recur per
-- connected account.
CREATE UNIQUE INDEX messages_provider_key
  ON messages (organization_id, provider_message_id);

CREATE INDEX messages_thread_idx
  ON messages (thread_id, sent_at);

CREATE INDEX messages_account_idx
  ON messages (connected_account_id, sent_at DESC)
  WHERE connected_account_id IS NOT NULL;

CREATE TRIGGER messages_thread_same_org
  BEFORE INSERT OR UPDATE OF thread_id ON messages
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('message_threads', 'thread_id');

CREATE TRIGGER messages_account_same_org
  BEFORE INSERT OR UPDATE OF connected_account_id ON messages
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('connected_accounts', 'connected_account_id');

-- Keeps the thread's rollup in step, the same recompute-not-increment shape as
-- files.attachment_count (0013, DECISIONS D15) and for the same reason: a
-- hand-maintained counter drifts the first time a code path forgets it.
CREATE OR REPLACE FUNCTION app.refresh_thread_rollup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_thread_id uuid := coalesce(NEW.thread_id, OLD.thread_id);
BEGIN
  UPDATE message_threads t
     SET message_count  = s.n,
         last_message_at = s.last_sent
    FROM (
      SELECT count(*) AS n, max(sent_at) AS last_sent
        FROM messages WHERE thread_id = v_thread_id
    ) s
   WHERE t.id = v_thread_id;
  RETURN NULL;
END;
$$;

CREATE TRIGGER messages_refresh_thread_rollup
  AFTER INSERT OR DELETE ON messages
  FOR EACH ROW EXECUTE FUNCTION app.refresh_thread_rollup();

SELECT app.apply_tenant_rls('messages');

CREATE TABLE message_participants (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  message_id        uuid NOT NULL REFERENCES messages(id) ON DELETE CASCADE,

  address           citext NOT NULL,
  role              text NOT NULL CHECK (role IN ('from', 'to', 'cc', 'bcc')),
  -- Resolved contact, when the address matches one on file. Nullable: most
  -- participants on a synced mailbox are not CRM contacts.
  contact_id        uuid REFERENCES contacts(id) ON DELETE SET NULL,

  CONSTRAINT message_participants_unique UNIQUE (message_id, address, role)
);

CREATE INDEX message_participants_contact_idx
  ON message_participants (contact_id)
  WHERE contact_id IS NOT NULL;

CREATE TRIGGER message_participants_message_same_org
  BEFORE INSERT OR UPDATE OF message_id ON message_participants
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('messages', 'message_id');

CREATE TRIGGER message_participants_contact_same_org
  BEFORE INSERT OR UPDATE OF contact_id ON message_participants
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('contacts', 'contact_id');

SELECT app.apply_tenant_rls('message_participants');

-- ---------------------------------------------------------------------------
-- Calendar events
-- ---------------------------------------------------------------------------
CREATE TABLE calendar_events (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  connected_account_id uuid REFERENCES connected_accounts(id) ON DELETE SET NULL,

  provider_event_id text NOT NULL,
  title             text,
  location          text,
  starts_at         timestamptz NOT NULL,
  ends_at           timestamptz NOT NULL,
  is_all_day        boolean NOT NULL DEFAULT false,

  entity_type       crm_entity,
  entity_id         uuid,

  attendee_addresses citext[] NOT NULL DEFAULT '{}',
  status            text NOT NULL DEFAULT 'confirmed'
                      CHECK (status IN ('confirmed', 'tentative', 'cancelled')),

  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT calendar_events_window_ordered CHECK (starts_at <= ends_at),
  CONSTRAINT calendar_events_entity_pair CHECK (
    (entity_type IS NULL) = (entity_id IS NULL)
  )
);

CREATE UNIQUE INDEX calendar_events_provider_key
  ON calendar_events (organization_id, provider_event_id);

CREATE INDEX calendar_events_account_window_idx
  ON calendar_events (connected_account_id, starts_at)
  WHERE connected_account_id IS NOT NULL;

CREATE INDEX calendar_events_entity_idx
  ON calendar_events (organization_id, entity_type, entity_id)
  WHERE entity_id IS NOT NULL;

CREATE TRIGGER calendar_events_account_same_org
  BEFORE INSERT OR UPDATE OF connected_account_id ON calendar_events
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('connected_accounts', 'connected_account_id');

CREATE OR REPLACE FUNCTION app.calendar_events_entity_valid()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.entity_type IS NOT NULL THEN
    PERFORM app.assert_entity_in_org(NEW.entity_type, NEW.entity_id, NEW.organization_id);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER calendar_events_entity_valid
  BEFORE INSERT OR UPDATE OF entity_type, entity_id ON calendar_events
  FOR EACH ROW EXECUTE FUNCTION app.calendar_events_entity_valid();

SELECT app.apply_tenant_rls('calendar_events');

COMMIT;
