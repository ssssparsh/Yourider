-- 0011_consent.sql
-- Consent, suppression, and delivery events.
--
-- WHY THIS EXISTS
--
-- `contacts.email_opt_out` and `contacts.sms_opt_out` are booleans. A boolean
-- cannot answer any of the questions a system that actually sends things must
-- answer:
--
--   * Consented to WHAT? Agreeing to a service notification is not agreeing to
--     marketing. GDPR and CASL consent attaches to a purpose, not a person.
--   * Consented WHEN, HOW, and from where? A consent claim you cannot evidence
--     is not a defence.
--   * Confirmed, or merely asked? A boolean cannot distinguish "never asked"
--     from "confirmed" from "unsubscribed", so double opt-in is unrepresentable.
--   * What about an address with no contact row? Suppression must be able to
--     outlive the contact — today, deleting a contact forgets they opted out,
--     which is exactly backwards.
--   * What about bounces and complaints? Unhandled, sending reputation degrades
--     until delivery fails silently.
--
-- This matters more here than in a conventional CRM because /src/agents
-- personas draft and send outbound. The approval gate in CLAUDE.md §3 governs
-- whether a send is ATTEMPTED. Consent governs whether it is LAWFUL. Those are
-- different questions and only one of them previously had an answer.
--
-- THE MODEL
--
--   contact_channels   an addressable endpoint (this email, that phone)
--   consent_purposes   tenant-defined reasons for contacting someone
--   consent_records    APPEND-ONLY ledger of every grant, denial, withdrawal
--   consent_state      derived current state, maintained by trigger
--   suppressions       address-level blocks that outlive contacts
--   message_events     delivery/engagement events, idempotent on provider id
--
-- The ledger is the truth; `consent_state` is a cache so the send-time check is
-- an index lookup rather than a scan for the latest record per pair. Consent
-- becomes a query, not a column read.
--
-- SCOPE BOUNDARY
--
-- Yourider owns consent truth and suppression. It does NOT build a campaign
-- sender, SMTP pool, or bounce ingester — those belong to a dedicated service,
-- which mirrors delivery events back into message_events.

BEGIN;

CREATE TYPE channel_type AS ENUM ('email', 'sms', 'phone', 'push', 'postal');

CREATE TYPE consent_state_kind AS ENUM (
  'pending',    -- asked, awaiting confirmation (double opt-in)
  'granted',
  'denied',     -- explicitly refused when asked
  'withdrawn',  -- previously granted, since revoked
  'expired'     -- time-limited consent that has lapsed
);

CREATE TYPE consent_source AS ENUM (
  'web_form',
  'double_optin',   -- confirmed via a clicked confirmation link
  'import',         -- bulk load; weakest evidence, record provenance carefully
  'api',
  'verbal',         -- logged by a human after a call
  'contract',       -- consent implied by a signed agreement
  'preference_centre',
  'unsubscribe_link',
  'admin'           -- set by an operator
);

CREATE TYPE suppression_reason AS ENUM (
  'hard_bounce',
  'soft_bounce_threshold',
  'complaint',        -- spam report; treat as permanent
  'manual',
  'global_unsubscribe',
  'invalid_address',
  'legal_request'     -- erasure / do-not-contact order
);

CREATE TYPE message_event_kind AS ENUM (
  'queued',
  'sent',
  'delivered',
  'opened',
  'clicked',
  'bounced',
  'complained',
  'failed',
  'unsubscribed'
);

-- ---------------------------------------------------------------------------
-- Channels — the things you can actually address.
--
-- Separate from contacts because a person has several, each with its own
-- verification state and its own consent history. Putting the address on the
-- contact row makes "which of their two emails did they consent on" unanswerable.
-- ---------------------------------------------------------------------------
CREATE TABLE contact_channels (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  contact_id       uuid NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,

  channel_type     channel_type NOT NULL,
  /*
   * Normalised address: lowercase for email (citext handles it), E.164 for
   * phone/sms. Normalisation happens in the application layer — Postgres cannot
   * validate a phone number properly — but the CHECK below catches the obvious
   * failure of storing a non-E.164 string.
   */
  address          citext NOT NULL,
  label            text,
  is_primary       boolean NOT NULL DEFAULT false,

  /* Verified means we proved the address reaches this person. Distinct from
   * consent: a verified address may still have no permission to be marketed to. */
  verified_at      timestamptz,

  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  deleted_at       timestamptz,

  CONSTRAINT contact_channels_address_not_blank
    CHECK (length(btrim(address::text)) > 0),
  CONSTRAINT contact_channels_phone_e164 CHECK (
    channel_type NOT IN ('sms', 'phone')
    OR address::text ~ '^\+[1-9][0-9]{6,14}$'
  ),
  CONSTRAINT contact_channels_email_shape CHECK (
    channel_type <> 'email'
    OR address::text ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
  )
);

CREATE UNIQUE INDEX contact_channels_unique
  ON contact_channels (organization_id, contact_id, channel_type, address)
  WHERE deleted_at IS NULL;

CREATE INDEX contact_channels_contact_idx
  ON contact_channels (organization_id, contact_id)
  WHERE deleted_at IS NULL;

/* Reverse lookup: given an inbound address, who is it? Used by bounce and
 * unsubscribe ingestion, which only ever know the address. */
CREATE INDEX contact_channels_address_idx
  ON contact_channels (organization_id, channel_type, address)
  WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX contact_channels_one_primary
  ON contact_channels (organization_id, contact_id, channel_type)
  WHERE is_primary = true AND deleted_at IS NULL;

SELECT app.attach_tenant_triggers('contact_channels');

CREATE TRIGGER contact_channels_contact_same_org
  BEFORE INSERT OR UPDATE OF contact_id ON contact_channels
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('contacts', 'contact_id');

-- ---------------------------------------------------------------------------
-- Purposes — why you are contacting someone.
--
-- Tenant-defined rather than a fixed enum: what counts as a distinct purpose is
-- a business and jurisdictional question, not something this schema can decide.
-- ---------------------------------------------------------------------------
CREATE TABLE consent_purposes (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  key              text NOT NULL CHECK (key ~ '^[a-z][a-z0-9_]{0,62}$'),
  name             text NOT NULL CHECK (length(btrim(name)) > 0),
  description      text,

  /*
   * Transactional messages — a booking confirmation, a password reset, a
   * service appointment reminder — are generally lawful without marketing
   * consent, as performance of a contract. They are NOT exempt from
   * suppression: a hard-bounced address must not be written to regardless.
   */
  is_transactional boolean NOT NULL DEFAULT false,

  /* When true, a grant only counts once confirmed via a clicked link. */
  requires_double_optin boolean NOT NULL DEFAULT false,

  /* Consent that lapses. NULL means it does not expire on its own. */
  default_ttl      interval,

  is_active        boolean NOT NULL DEFAULT true,
  position         integer NOT NULL DEFAULT 0,

  created_by       uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  deleted_at       timestamptz,

  CONSTRAINT consent_purposes_key_unique UNIQUE (organization_id, key),
  /* A transactional purpose requiring double opt-in is a contradiction. */
  CONSTRAINT consent_purposes_transactional_not_doi CHECK (
    NOT (is_transactional AND requires_double_optin)
  )
);

CREATE INDEX consent_purposes_active_idx
  ON consent_purposes (organization_id, is_active, position)
  WHERE deleted_at IS NULL;

SELECT app.attach_tenant_triggers('consent_purposes');

-- ---------------------------------------------------------------------------
-- The ledger. APPEND ONLY.
--
-- Every grant, denial, withdrawal and confirmation is a new row. Nothing is
-- ever updated, because the question asked in a dispute is not "what is their
-- consent" but "what was their consent on the day you sent that, and what is
-- your evidence" — which a mutable column cannot answer.
--
-- 0009's pattern applies: SELECT and INSERT policies only, no UPDATE or DELETE.
-- ---------------------------------------------------------------------------
CREATE TABLE consent_records (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  channel_id       uuid NOT NULL REFERENCES contact_channels(id) ON DELETE CASCADE,
  purpose_id       uuid NOT NULL REFERENCES consent_purposes(id) ON DELETE CASCADE,

  state            consent_state_kind NOT NULL,
  source           consent_source NOT NULL,

  /*
   * Evidence. What was shown to them, where they were, what they clicked.
   * Free-form because the meaningful contents differ per source, but expected
   * keys are: ip, user_agent, form_url, consent_text, confirmation_token.
   */
  evidence         jsonb NOT NULL DEFAULT '{}'::jsonb,

  /* Who recorded it. An agent must name itself, same rule as the audit log. */
  actor_type       actor_kind NOT NULL DEFAULT 'user',
  actor_user_id    uuid REFERENCES users(id) ON DELETE SET NULL,
  actor_agent      text,

  /* When the consent event happened, which is not always when it was recorded. */
  occurred_at      timestamptz NOT NULL DEFAULT now(),
  expires_at       timestamptz,

  created_at       timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT consent_records_agent_named CHECK (
    actor_type <> 'agent' OR actor_agent IS NOT NULL
  ),
  CONSTRAINT consent_records_expiry_after_grant CHECK (
    expires_at IS NULL OR expires_at > occurred_at
  )
);

CREATE INDEX consent_records_channel_purpose_idx
  ON consent_records (organization_id, channel_id, purpose_id, occurred_at DESC);

CREATE INDEX consent_records_purpose_idx
  ON consent_records (organization_id, purpose_id, occurred_at DESC);

CREATE INDEX consent_records_evidence_idx
  ON consent_records USING gin (evidence jsonb_path_ops);

CREATE TRIGGER consent_records_channel_same_org
  BEFORE INSERT ON consent_records
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('contact_channels', 'channel_id');

CREATE TRIGGER consent_records_purpose_same_org
  BEFORE INSERT ON consent_records
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('consent_purposes', 'purpose_id');

-- ---------------------------------------------------------------------------
-- Derived current state.
--
-- A cache over the ledger, so the send-time check is a primary-key lookup
-- instead of a "latest row per (channel, purpose)" scan. The ledger stays
-- authoritative: this table can be rebuilt from it at any time.
-- ---------------------------------------------------------------------------
CREATE TABLE consent_state (
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  channel_id       uuid NOT NULL REFERENCES contact_channels(id) ON DELETE CASCADE,
  purpose_id       uuid NOT NULL REFERENCES consent_purposes(id) ON DELETE CASCADE,

  state            consent_state_kind NOT NULL,
  effective_at     timestamptz NOT NULL,
  expires_at       timestamptz,
  source_record_id uuid NOT NULL REFERENCES consent_records(id) ON DELETE CASCADE,
  updated_at       timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (channel_id, purpose_id)
);

CREATE INDEX consent_state_org_purpose_idx
  ON consent_state (organization_id, purpose_id, state);

/*
 * Advance the cache when a newer ledger entry arrives.
 *
 * Guarded on occurred_at so a backdated record — a verbal consent logged three
 * days late — cannot overwrite a more recent withdrawal. Out-of-order arrival
 * is normal, not exceptional.
 */
CREATE OR REPLACE FUNCTION app.apply_consent_record()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO consent_state AS cs (
    organization_id, channel_id, purpose_id,
    state, effective_at, expires_at, source_record_id, updated_at
  ) VALUES (
    NEW.organization_id, NEW.channel_id, NEW.purpose_id,
    NEW.state, NEW.occurred_at, NEW.expires_at, NEW.id, now()
  )
  ON CONFLICT (channel_id, purpose_id) DO UPDATE
    SET state            = EXCLUDED.state,
        effective_at     = EXCLUDED.effective_at,
        expires_at       = EXCLUDED.expires_at,
        source_record_id = EXCLUDED.source_record_id,
        updated_at       = now()
    WHERE EXCLUDED.effective_at >= cs.effective_at;

  RETURN NEW;
END;
$$;

CREATE TRIGGER consent_records_apply_state
  AFTER INSERT ON consent_records
  FOR EACH ROW EXECUTE FUNCTION app.apply_consent_record();

-- ---------------------------------------------------------------------------
-- Suppressions.
--
-- Address-level, NOT contact-level, and deliberately carrying no foreign key to
-- contacts. Two consequences, both intended:
--   * an address can be suppressed before any contact exists for it;
--   * deleting a contact does not forget that they asked never to be contacted.
-- ---------------------------------------------------------------------------
CREATE TABLE suppressions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  channel_type     channel_type NOT NULL,
  address          citext NOT NULL CHECK (length(btrim(address::text)) > 0),

  reason           suppression_reason NOT NULL,
  detail           text,
  /* Which provider or process reported it, for traceability. */
  source           text,

  /* Soft bounces may lift; hard bounces and complaints must not. */
  expires_at       timestamptz,

  created_by       uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  released_at      timestamptz,
  released_by      uuid REFERENCES users(id) ON DELETE SET NULL,
  release_reason   text,

  CONSTRAINT suppressions_permanent_reasons_do_not_expire CHECK (
    reason NOT IN ('hard_bounce', 'complaint', 'legal_request')
    OR expires_at IS NULL
  )
);

/* One active suppression per address per channel per tenant. */
CREATE UNIQUE INDEX suppressions_active_unique
  ON suppressions (organization_id, channel_type, address)
  WHERE released_at IS NULL;

CREATE INDEX suppressions_lookup_idx
  ON suppressions (organization_id, channel_type, address, released_at);

SELECT app.attach_audit('suppressions');

-- ---------------------------------------------------------------------------
-- Delivery and engagement events.
--
-- Partitioned like activities and audit_log: this grows with send volume, not
-- customer count, and is the first table to reach nine figures.
--
-- `provider_event_id` is unique per provider so replayed webhooks — which every
-- ESP sends — are idempotent rather than double-counted.
-- ---------------------------------------------------------------------------
CREATE TABLE message_events (
  id                uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL,

  /* Nullable: an event may arrive for an address with no channel row. The
   * address is always present, and is what suppression keys on. */
  channel_id        uuid,
  channel_type      channel_type NOT NULL,
  address           citext NOT NULL,

  purpose_id        uuid,
  /* Free-form campaign/message correlation supplied by the sending service. */
  message_ref       text,

  event_kind        message_event_kind NOT NULL,
  /* 'hard' | 'soft' for bounces; NULL otherwise. */
  bounce_kind       text CHECK (bounce_kind IS NULL OR bounce_kind IN ('hard', 'soft')),

  provider          text NOT NULL,
  provider_event_id text,

  occurred_at       timestamptz NOT NULL DEFAULT now(),
  metadata          jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at        timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (id, created_at),
  CONSTRAINT message_events_bounce_kind_only_on_bounce CHECK (
    bounce_kind IS NULL OR event_kind = 'bounced'
  )
) PARTITION BY RANGE (created_at);

/* Idempotency. Partitioned tables require the partition key in a unique index,
 * so uniqueness is scoped per partition — sufficient, because a provider's
 * retries of one event arrive within the same month. */
CREATE UNIQUE INDEX message_events_provider_event_key
  ON message_events (provider, provider_event_id, created_at)
  WHERE provider_event_id IS NOT NULL;

CREATE INDEX message_events_address_idx
  ON message_events (organization_id, channel_type, address, occurred_at DESC);

CREATE INDEX message_events_channel_idx
  ON message_events (organization_id, channel_id, occurred_at DESC)
  WHERE channel_id IS NOT NULL;

CREATE INDEX message_events_kind_idx
  ON message_events (organization_id, event_kind, occurred_at DESC);

CREATE INDEX message_events_ref_idx
  ON message_events (organization_id, message_ref, occurred_at DESC)
  WHERE message_ref IS NOT NULL;

/* Routed through ensure_month_partition so partitions are born with RLS —
 * see 0010 and the trap documented in src/db/README.md. */
SELECT app.ensure_partition_window('message_events', 2, 6);

-- ---------------------------------------------------------------------------
-- THE GATE
--
-- One function that answers "may I send this?". Everything outbound — human or
-- agent — calls this first. It returns a reason as well as a verdict, because
-- "no" without "why" produces support tickets and guesswork.
-- ---------------------------------------------------------------------------
CREATE TYPE send_verdict AS (
  allowed boolean,
  reason  text
);

CREATE OR REPLACE FUNCTION app.can_send(
  p_channel_id uuid,
  p_purpose_id uuid
)
RETURNS send_verdict
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_ch      contact_channels%ROWTYPE;
  v_purpose consent_purposes%ROWTYPE;
  v_state   consent_state%ROWTYPE;
  v_supp    suppressions%ROWTYPE;
  v_legacy  boolean;
  v_out     send_verdict;
BEGIN
  SELECT * INTO v_ch FROM contact_channels
   WHERE id = p_channel_id AND deleted_at IS NULL;
  IF v_ch.id IS NULL THEN
    RETURN ROW(false, 'channel_not_found')::send_verdict;
  END IF;

  SELECT * INTO v_purpose FROM consent_purposes
   WHERE id = p_purpose_id AND deleted_at IS NULL AND is_active = true;
  IF v_purpose.id IS NULL THEN
    RETURN ROW(false, 'purpose_not_found_or_inactive')::send_verdict;
  END IF;

  IF v_ch.organization_id <> v_purpose.organization_id THEN
    RETURN ROW(false, 'cross_tenant_mismatch')::send_verdict;
  END IF;

  /* Suppression outranks everything, including transactional purposes and an
   * explicit grant. A hard-bounced address does not become deliverable because
   * someone consented; writing to it damages sending reputation for everyone
   * else in the tenant. */
  SELECT * INTO v_supp FROM suppressions
   WHERE organization_id = v_ch.organization_id
     AND channel_type = v_ch.channel_type
     AND address = v_ch.address
     AND released_at IS NULL
     AND (expires_at IS NULL OR expires_at > now())
   LIMIT 1;
  IF v_supp.id IS NOT NULL THEN
    RETURN ROW(false, 'suppressed:' || v_supp.reason::text)::send_verdict;
  END IF;

  /*
   * Legacy opt-out booleans on contacts. Retained rather than dropped so this
   * migration is non-destructive, and honoured here as a global withdrawal so
   * existing data is not silently ignored during the transition. Dropping those
   * columns is a follow-up that requires explicit approval.
   */
  IF v_ch.channel_type = 'email' THEN
    SELECT email_opt_out INTO v_legacy FROM contacts WHERE id = v_ch.contact_id;
  ELSIF v_ch.channel_type = 'sms' THEN
    SELECT sms_opt_out INTO v_legacy FROM contacts WHERE id = v_ch.contact_id;
  ELSE
    v_legacy := false;
  END IF;

  IF coalesce(v_legacy, false) AND NOT v_purpose.is_transactional THEN
    RETURN ROW(false, 'legacy_opt_out')::send_verdict;
  END IF;

  /* Transactional messages are lawful without marketing consent — performance
   * of a contract — but only after the suppression check above. */
  IF v_purpose.is_transactional THEN
    RETURN ROW(true, 'transactional')::send_verdict;
  END IF;

  SELECT * INTO v_state FROM consent_state
   WHERE channel_id = p_channel_id AND purpose_id = p_purpose_id;

  IF v_state.channel_id IS NULL THEN
    RETURN ROW(false, 'no_consent_recorded')::send_verdict;
  END IF;

  IF v_state.expires_at IS NOT NULL AND v_state.expires_at <= now() THEN
    RETURN ROW(false, 'consent_expired')::send_verdict;
  END IF;

  IF v_state.state <> 'granted' THEN
    RETURN ROW(false, 'consent_' || v_state.state::text)::send_verdict;
  END IF;

  RETURN ROW(true, 'consent_granted')::send_verdict;
END;
$$;

COMMENT ON FUNCTION app.can_send(uuid, uuid) IS
  'The outbound gate. Call before every send, human or agent. Suppression '
  'outranks consent; transactional purposes bypass consent but never '
  'suppression. Returns (allowed, reason) so a refusal is explainable.';

/* Convenience wrapper for callers that only hold an address. */
CREATE OR REPLACE FUNCTION app.is_suppressed(
  p_org          uuid,
  p_channel_type channel_type,
  p_address      citext
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM suppressions
     WHERE organization_id = p_org
       AND channel_type = p_channel_type
       AND address = p_address
       AND released_at IS NULL
       AND (expires_at IS NULL OR expires_at > now())
  );
$$;

-- ---------------------------------------------------------------------------
-- Recording consent. A helper so callers cannot forget the ledger and write
-- only to the cache.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.record_consent(
  p_channel_id uuid,
  p_purpose_id uuid,
  p_state      consent_state_kind,
  p_source     consent_source,
  p_evidence   jsonb DEFAULT '{}'::jsonb,
  p_occurred_at timestamptz DEFAULT now()
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_org     uuid;
  v_purpose consent_purposes%ROWTYPE;
  v_expires timestamptz;
  v_agent   text := nullif(current_setting('app.current_agent', true), '');
  v_id      uuid;
BEGIN
  SELECT organization_id INTO v_org FROM contact_channels
   WHERE id = p_channel_id AND deleted_at IS NULL;
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'channel % does not exist', p_channel_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  SELECT * INTO v_purpose FROM consent_purposes
   WHERE id = p_purpose_id AND deleted_at IS NULL;
  IF v_purpose.id IS NULL THEN
    RAISE EXCEPTION 'purpose % does not exist', p_purpose_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  /*
   * Double opt-in: a grant that did not come from a confirmation link is only
   * pending. Enforced here rather than left to callers, because the caller that
   * gets this wrong is precisely the one that should not be trusted with it.
   */
  IF p_state = 'granted'
     AND v_purpose.requires_double_optin
     AND p_source <> 'double_optin' THEN
    p_state := 'pending';
  END IF;

  IF p_state = 'granted' AND v_purpose.default_ttl IS NOT NULL THEN
    v_expires := p_occurred_at + v_purpose.default_ttl;
  END IF;

  INSERT INTO consent_records (
    organization_id, channel_id, purpose_id, state, source, evidence,
    actor_type, actor_user_id, actor_agent, occurred_at, expires_at
  ) VALUES (
    v_org, p_channel_id, p_purpose_id, p_state, p_source, p_evidence,
    CASE WHEN v_agent IS NOT NULL THEN 'agent'::actor_kind
         WHEN app.current_user_id() IS NOT NULL THEN 'user'::actor_kind
         ELSE 'system'::actor_kind END,
    app.current_user_id(), v_agent, p_occurred_at, v_expires
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Ingesting a delivery event.
--
-- Idempotent on (provider, provider_event_id), and applies the suppression
-- consequences of hard bounces and complaints in the same transaction — so an
-- ESP webhook cannot record a complaint without the address becoming
-- unsendable.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.ingest_message_event(
  p_org          uuid,
  p_channel_type channel_type,
  p_address      citext,
  p_event_kind   message_event_kind,
  p_provider     text,
  p_provider_event_id text DEFAULT NULL,
  p_bounce_kind  text DEFAULT NULL,
  p_message_ref  text DEFAULT NULL,
  p_metadata     jsonb DEFAULT '{}'::jsonb,
  p_occurred_at  timestamptz DEFAULT now()
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_channel uuid;
  v_id      uuid;
BEGIN
  SELECT id INTO v_channel FROM contact_channels
   WHERE organization_id = p_org
     AND channel_type = p_channel_type
     AND address = p_address
     AND deleted_at IS NULL
   LIMIT 1;

  INSERT INTO message_events (
    organization_id, channel_id, channel_type, address,
    event_kind, bounce_kind, provider, provider_event_id,
    message_ref, metadata, occurred_at
  ) VALUES (
    p_org, v_channel, p_channel_type, p_address,
    p_event_kind, p_bounce_kind, p_provider, p_provider_event_id,
    p_message_ref, p_metadata, p_occurred_at
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RETURN NULL;  -- replayed webhook; already ingested
  END IF;

  /* Consequences. A hard bounce or a complaint suppresses immediately and
   * permanently; an explicit unsubscribe does too. Soft bounces are counted by
   * a separate scheduled job against a tenant threshold, not here. */
  IF (p_event_kind = 'bounced' AND p_bounce_kind = 'hard')
     OR p_event_kind = 'complained'
     OR p_event_kind = 'unsubscribed' THEN
    INSERT INTO suppressions (
      organization_id, channel_type, address, reason, source, detail
    ) VALUES (
      p_org, p_channel_type, p_address,
      CASE WHEN p_event_kind = 'bounced'     THEN 'hard_bounce'::suppression_reason
           WHEN p_event_kind = 'complained'  THEN 'complaint'::suppression_reason
           ELSE 'global_unsubscribe'::suppression_reason END,
      p_provider,
      format('auto-suppressed from %s event %s', p_event_kind, coalesce(p_provider_event_id, '-'))
    )
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
SELECT app.apply_tenant_rls('contact_channels');
SELECT app.apply_tenant_rls('consent_purposes');
SELECT app.apply_tenant_rls('suppressions');

/* consent_records is append-only, exactly like audit_log. */
ALTER TABLE consent_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE consent_records FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_select ON consent_records
  FOR SELECT USING (organization_id = app.current_org_id());

CREATE POLICY tenant_insert ON consent_records
  FOR INSERT WITH CHECK (
    organization_id = app.current_org_id()
    AND app.can_write_in(organization_id)
  );

/* consent_state is a derived cache, written only by trigger. Readable by the
 * tenant; not directly writable, so it cannot drift from the ledger. */
ALTER TABLE consent_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE consent_state FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_select ON consent_state
  FOR SELECT USING (organization_id = app.current_org_id());

/* message_events: append-only, same reasoning as the audit log. */
ALTER TABLE message_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_events FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_select ON message_events
  FOR SELECT USING (organization_id = app.current_org_id());

CREATE POLICY tenant_insert ON message_events
  FOR INSERT WITH CHECK (organization_id = app.current_org_id());

/* Secure the partitions created above — parent policies do not propagate. */
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT c.relname AS child
      FROM pg_inherits i
      JOIN pg_class c ON c.oid = i.inhrelid
      JOIN pg_class p ON p.oid = i.inhparent
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND p.relname = 'message_events'
  LOOP
    PERFORM app.secure_partition(r.child, 'audit_log');  -- append-only shape
  END LOOP;
END;
$$;

SELECT app.attach_audit('contact_channels');
SELECT app.attach_audit('consent_purposes');

COMMIT;
