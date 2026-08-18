-- 0005_leads_deals.sql
-- The sales side: leads, their conversion, and deals.
--
-- Lead and deal are kept as separate tables rather than collapsing a lead into
-- "a deal in an early stage". The distinction is real: a lead is unverified
-- interest that may never correspond to a person or company you keep, while a
-- deal is a tracked commercial opportunity attached to records you own. Merging
-- them means either polluting the account/contact tables with junk leads or
-- losing the qualification step. Conversion is explicit and recorded.

BEGIN;

CREATE TYPE lead_status AS ENUM (
  'new',
  'working',
  'nurturing',
  'qualified',    -- terminal: became a deal
  'unqualified',  -- terminal: rejected
  'recycled'      -- returned to marketing for a later cycle
);

-- ---------------------------------------------------------------------------
-- Leads
-- ---------------------------------------------------------------------------
CREATE TABLE leads (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  -- Denormalised person/company detail. A lead deliberately does NOT reference
  -- contacts/accounts: those records are only created on conversion, so
  -- unqualified leads never pollute the customer database.
  first_name       text,
  last_name        text,
  full_name        text GENERATED ALWAYS AS (
                     btrim(coalesce(first_name, '') || ' ' || coalesce(last_name, ''))
                   ) STORED,
  company_name     text,
  email            citext,
  phone            text,
  job_title        text,
  website          text,

  source           text,          -- 'web_form', 'referral', 'import', 'agent:lead-qualifier', ...
  source_details   jsonb NOT NULL DEFAULT '{}'::jsonb,
  campaign         text,

  status           lead_status NOT NULL DEFAULT 'new',
  pipeline_id      uuid REFERENCES pipelines(id) ON DELETE SET NULL,
  stage_id         uuid REFERENCES pipeline_stages(id) ON DELETE SET NULL,
  -- Fractional so a card can be dropped between two others in a kanban view
  -- without renumbering the column.
  board_position   numeric(20,10) NOT NULL DEFAULT 0,

  -- Qualification scoring. `score` is whatever the tenant's model produces;
  -- `score_reasons` records why, which matters when an agent assigned it — the
  -- lead-qualifier persona is required to cite signals rather than emit a bare
  -- number.
  score            integer CHECK (score IS NULL OR (score >= 0 AND score <= 100)),
  score_reasons    jsonb NOT NULL DEFAULT '[]'::jsonb,
  scored_at        timestamptz,
  scored_by_agent  text,

  estimated_value  numeric(18,4) CHECK (estimated_value IS NULL OR estimated_value >= 0),
  currency         char(3),

  owner_id         uuid REFERENCES users(id) ON DELETE SET NULL,

  -- Conversion outcome. All three are set together, by app.convert_lead().
  converted_at        timestamptz,
  converted_account_id uuid REFERENCES accounts(id) ON DELETE SET NULL,
  converted_contact_id uuid REFERENCES contacts(id) ON DELETE SET NULL,
  converted_deal_id    uuid,  -- FK added after deals exists, below

  disqualified_at     timestamptz,
  disqualified_reason text,

  last_activity_at timestamptz,
  custom_fields    jsonb NOT NULL DEFAULT '{}'::jsonb,
  tags             text[] NOT NULL DEFAULT '{}',

  created_by       uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  deleted_at       timestamptz,

  CONSTRAINT leads_identifiable CHECK (
    coalesce(btrim(first_name), '') <> ''
    OR coalesce(btrim(last_name), '') <> ''
    OR coalesce(btrim(company_name), '') <> ''
    OR email IS NOT NULL
  ),
  -- A converted lead must record what it became.
  CONSTRAINT leads_conversion_complete CHECK (
    converted_at IS NULL
    OR (converted_account_id IS NOT NULL OR converted_contact_id IS NOT NULL)
  ),
  CONSTRAINT leads_not_both_outcomes CHECK (
    converted_at IS NULL OR disqualified_at IS NULL
  )
);

CREATE INDEX leads_org_created_idx
  ON leads (organization_id, created_at DESC, id)
  WHERE deleted_at IS NULL;

-- The working queue: open leads, newest first, per owner.
CREATE INDEX leads_org_status_owner_idx
  ON leads (organization_id, status, owner_id, created_at DESC)
  WHERE deleted_at IS NULL AND converted_at IS NULL AND disqualified_at IS NULL;

CREATE INDEX leads_org_stage_position_idx
  ON leads (organization_id, stage_id, board_position)
  WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX leads_org_email_open_key
  ON leads (organization_id, email)
  WHERE deleted_at IS NULL AND email IS NOT NULL AND converted_at IS NULL
        AND disqualified_at IS NULL;

CREATE INDEX leads_org_name_trgm_idx
  ON leads USING gin (organization_id, full_name gin_trgm_ops)
  WHERE deleted_at IS NULL;

CREATE INDEX leads_custom_fields_idx
  ON leads USING gin (custom_fields jsonb_path_ops);

CREATE INDEX leads_tags_idx ON leads USING gin (tags);

SELECT app.attach_tenant_triggers('leads');

CREATE TRIGGER leads_pipeline_same_org
  BEFORE INSERT OR UPDATE OF pipeline_id ON leads
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('pipelines', 'pipeline_id');

CREATE TRIGGER leads_stage_same_org
  BEFORE INSERT OR UPDATE OF stage_id ON leads
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('pipeline_stages', 'stage_id');

-- ---------------------------------------------------------------------------
-- Deals
-- ---------------------------------------------------------------------------
CREATE TABLE deals (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  name             text NOT NULL CHECK (length(btrim(name)) > 0),
  account_id       uuid REFERENCES accounts(id) ON DELETE SET NULL,
  primary_contact_id uuid REFERENCES contacts(id) ON DELETE SET NULL,

  pipeline_id      uuid NOT NULL REFERENCES pipelines(id) ON DELETE RESTRICT,
  stage_id         uuid NOT NULL REFERENCES pipeline_stages(id) ON DELETE RESTRICT,
  board_position   numeric(20,10) NOT NULL DEFAULT 0,
  stage_entered_at timestamptz NOT NULL DEFAULT now(),

  -- Money. numeric, never float — a float total that is off by a cent is a
  -- support ticket. `amount` is in `currency`; `base_amount` is the same value
  -- in the organization's base_currency at `fx_rate`, so cross-currency
  -- pipeline totals are a plain SUM instead of a per-row conversion.
  amount           numeric(18,4) NOT NULL DEFAULT 0 CHECK (amount >= 0),
  currency         char(3) NOT NULL DEFAULT 'USD',
  fx_rate          numeric(18,8) NOT NULL DEFAULT 1 CHECK (fx_rate > 0),
  base_amount      numeric(18,4) GENERATED ALWAYS AS (amount * fx_rate) STORED,

  -- Snapshot of the stage's probability when the deal entered it, so historical
  -- forecasts stay reproducible after someone edits the stage definition.
  probability      numeric(5,4) CHECK (probability IS NULL OR (probability >= 0 AND probability <= 1)),
  weighted_amount  numeric(18,4) GENERATED ALWAYS AS (
                     amount * fx_rate * coalesce(probability, 0)
                   ) STORED,

  expected_close_date date,
  closed_at        timestamptz,
  close_reason     text,

  owner_id         uuid REFERENCES users(id) ON DELETE SET NULL,
  source_lead_id   uuid REFERENCES leads(id) ON DELETE SET NULL,

  last_activity_at timestamptz,
  custom_fields    jsonb NOT NULL DEFAULT '{}'::jsonb,
  tags             text[] NOT NULL DEFAULT '{}',

  created_by       uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  deleted_at       timestamptz
);

-- Now that deals exists, close the loop from leads.
ALTER TABLE leads
  ADD CONSTRAINT leads_converted_deal_fk
  FOREIGN KEY (converted_deal_id) REFERENCES deals(id) ON DELETE SET NULL;

CREATE INDEX deals_org_created_idx
  ON deals (organization_id, created_at DESC, id)
  WHERE deleted_at IS NULL;

-- Board rendering: one pipeline, ordered within each stage.
CREATE INDEX deals_org_stage_position_idx
  ON deals (organization_id, stage_id, board_position)
  WHERE deleted_at IS NULL AND closed_at IS NULL;

CREATE INDEX deals_org_owner_open_idx
  ON deals (organization_id, owner_id, expected_close_date)
  WHERE deleted_at IS NULL AND closed_at IS NULL;

CREATE INDEX deals_org_account_idx
  ON deals (organization_id, account_id)
  WHERE deleted_at IS NULL;

-- Forecast queries scan open deals by expected close date.
CREATE INDEX deals_org_forecast_idx
  ON deals (organization_id, expected_close_date, stage_id)
  WHERE deleted_at IS NULL AND closed_at IS NULL;

CREATE INDEX deals_org_closed_idx
  ON deals (organization_id, closed_at DESC)
  WHERE deleted_at IS NULL AND closed_at IS NOT NULL;

CREATE INDEX deals_org_name_trgm_idx
  ON deals USING gin (organization_id, name gin_trgm_ops)
  WHERE deleted_at IS NULL;

CREATE INDEX deals_custom_fields_idx
  ON deals USING gin (custom_fields jsonb_path_ops);

CREATE INDEX deals_tags_idx ON deals USING gin (tags);

SELECT app.attach_tenant_triggers('deals');

CREATE TRIGGER deals_account_same_org
  BEFORE INSERT OR UPDATE OF account_id ON deals
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('accounts', 'account_id');

CREATE TRIGGER deals_contact_same_org
  BEFORE INSERT OR UPDATE OF primary_contact_id ON deals
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('contacts', 'primary_contact_id');

CREATE TRIGGER deals_pipeline_same_org
  BEFORE INSERT OR UPDATE OF pipeline_id ON deals
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('pipelines', 'pipeline_id');

CREATE TRIGGER deals_stage_same_org
  BEFORE INSERT OR UPDATE OF stage_id ON deals
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('pipeline_stages', 'stage_id');

-- ---------------------------------------------------------------------------
-- Deal participants. A real deal involves several people in different roles —
-- economic buyer, champion, blocker, technical evaluator. Storing only a single
-- primary_contact_id loses the map of who actually decides.
-- ---------------------------------------------------------------------------
CREATE TABLE deal_contacts (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  deal_id          uuid NOT NULL REFERENCES deals(id) ON DELETE CASCADE,
  contact_id       uuid NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
  role             text,
  influence        smallint CHECK (influence IS NULL OR (influence BETWEEN 1 AND 5)),
  created_at       timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT deal_contacts_key UNIQUE (deal_id, contact_id)
);

CREATE INDEX deal_contacts_contact_idx
  ON deal_contacts (organization_id, contact_id);

CREATE TRIGGER deal_contacts_deal_same_org
  BEFORE INSERT OR UPDATE OF deal_id ON deal_contacts
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('deals', 'deal_id');

CREATE TRIGGER deal_contacts_contact_same_org
  BEFORE INSERT OR UPDATE OF contact_id ON deal_contacts
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('contacts', 'contact_id');

-- ---------------------------------------------------------------------------
-- Stage movement.
--
-- Moving an item between stages touches three things that must agree: the row's
-- stage_id, its stage_entered_at, and the stage_transitions interval. Doing it
-- in one function means callers cannot get two of the three right and leave the
-- history subtly wrong.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.move_to_stage(
  p_entity_type pipeline_entity,
  p_entity_id   uuid,
  p_stage_id    uuid,
  p_actor_user  uuid DEFAULT NULL,
  p_actor_agent text DEFAULT NULL,
  p_note        text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_org       uuid;
  v_from      uuid;
  v_stage_org uuid;
  v_kind      stage_kind;
  v_prob      numeric(5,4);
  v_now       timestamptz := now();
BEGIN
  SELECT organization_id, kind, probability
    INTO v_stage_org, v_kind, v_prob
  FROM pipeline_stages
  WHERE id = p_stage_id AND deleted_at IS NULL;

  IF v_stage_org IS NULL THEN
    RAISE EXCEPTION 'stage % does not exist', p_stage_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF p_entity_type = 'deal' THEN
    SELECT organization_id, stage_id INTO v_org, v_from
      FROM deals WHERE id = p_entity_id AND deleted_at IS NULL
      FOR UPDATE;
  ELSIF p_entity_type = 'lead' THEN
    SELECT organization_id, stage_id INTO v_org, v_from
      FROM leads WHERE id = p_entity_id AND deleted_at IS NULL
      FOR UPDATE;
  ELSE
    SELECT organization_id, stage_id INTO v_org, v_from
      FROM service_jobs WHERE id = p_entity_id AND deleted_at IS NULL
      FOR UPDATE;
  END IF;

  IF v_org IS NULL THEN
    RAISE EXCEPTION '% % does not exist', p_entity_type, p_entity_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF v_org <> v_stage_org THEN
    RAISE EXCEPTION 'stage % belongs to a different organization', p_stage_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF v_from IS NOT DISTINCT FROM p_stage_id THEN
    RETURN;  -- already there; not an error, just nothing to record
  END IF;

  -- Close the open interval, if any.
  UPDATE stage_transitions
     SET exited_at = v_now
   WHERE entity_type = p_entity_type
     AND entity_id = p_entity_id
     AND exited_at IS NULL;

  INSERT INTO stage_transitions (
    organization_id, entity_type, entity_id,
    from_stage_id, to_stage_id, entered_at,
    actor_user_id, actor_agent, note
  ) VALUES (
    v_org, p_entity_type, p_entity_id,
    v_from, p_stage_id, v_now,
    coalesce(p_actor_user, app.current_user_id()), p_actor_agent, p_note
  );

  IF p_entity_type = 'deal' THEN
    UPDATE deals
       SET stage_id = p_stage_id,
           stage_entered_at = v_now,
           probability = v_prob,
           closed_at = CASE WHEN v_kind IN ('won','lost') THEN v_now ELSE NULL END
     WHERE id = p_entity_id;
  ELSIF p_entity_type = 'lead' THEN
    UPDATE leads SET stage_id = p_stage_id WHERE id = p_entity_id;
  ELSE
    UPDATE service_jobs
       SET stage_id = p_stage_id,
           stage_entered_at = v_now
     WHERE id = p_entity_id;
  END IF;
END;
$$;

COMMENT ON FUNCTION app.move_to_stage IS
  'The only supported way to change an entity''s stage. Keeps stage_id, '
  'stage_entered_at and the stage_transitions interval consistent, and stamps '
  'closed_at when entering a terminal stage.';

-- ---------------------------------------------------------------------------
-- Lead conversion: lead -> (account?, contact?, deal?), atomically.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.convert_lead(
  p_lead_id      uuid,
  p_create_deal  boolean DEFAULT true,
  p_deal_name    text DEFAULT NULL,
  p_pipeline_id  uuid DEFAULT NULL,
  p_actor_user   uuid DEFAULT NULL
)
RETURNS TABLE (account_id uuid, contact_id uuid, deal_id uuid)
LANGUAGE plpgsql
AS $$
DECLARE
  v_lead     leads%ROWTYPE;
  v_account  uuid;
  v_contact  uuid;
  v_deal     uuid;
  v_pipeline uuid;
  v_stage    uuid;
  v_actor    uuid := coalesce(p_actor_user, app.current_user_id());
BEGIN
  SELECT * INTO v_lead FROM leads
   WHERE id = p_lead_id AND deleted_at IS NULL
   FOR UPDATE;

  IF v_lead.id IS NULL THEN
    RAISE EXCEPTION 'lead % does not exist', p_lead_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF v_lead.converted_at IS NOT NULL THEN
    RAISE EXCEPTION 'lead % is already converted', p_lead_id
      USING ERRCODE = 'unique_violation';
  END IF;

  -- Account: reuse an existing one matching the company name, else create.
  IF coalesce(btrim(v_lead.company_name), '') <> '' THEN
    SELECT a.id INTO v_account
      FROM accounts a
     WHERE a.organization_id = v_lead.organization_id
       AND a.deleted_at IS NULL
       AND lower(a.name) = lower(btrim(v_lead.company_name))
     LIMIT 1;

    IF v_account IS NULL THEN
      INSERT INTO accounts (
        organization_id, account_kind, name, website, phone,
        lifecycle, owner_id, created_by
      ) VALUES (
        v_lead.organization_id, 'company', btrim(v_lead.company_name),
        v_lead.website, v_lead.phone, 'prospect', v_lead.owner_id, v_actor
      ) RETURNING id INTO v_account;
    END IF;
  END IF;

  -- Contact: reuse by email within the tenant, else create.
  IF v_lead.email IS NOT NULL OR coalesce(btrim(v_lead.full_name), '') <> '' THEN
    IF v_lead.email IS NOT NULL THEN
      SELECT c.id INTO v_contact
        FROM contacts c
       WHERE c.organization_id = v_lead.organization_id
         AND c.deleted_at IS NULL
         AND c.email = v_lead.email
       LIMIT 1;
    END IF;

    IF v_contact IS NULL THEN
      INSERT INTO contacts (
        organization_id, account_id, first_name, last_name, email, phone,
        job_title, lifecycle, owner_id, created_by
      ) VALUES (
        v_lead.organization_id, v_account, v_lead.first_name, v_lead.last_name,
        v_lead.email, v_lead.phone, v_lead.job_title, 'prospect',
        v_lead.owner_id, v_actor
      ) RETURNING id INTO v_contact;
    ELSIF v_account IS NOT NULL THEN
      UPDATE contacts SET account_id = coalesce(account_id, v_account)
       WHERE id = v_contact;
    END IF;
  END IF;

  -- Deal, on the requested pipeline or the tenant's default deal pipeline.
  IF p_create_deal THEN
    v_pipeline := p_pipeline_id;
    IF v_pipeline IS NULL THEN
      SELECT id INTO v_pipeline FROM pipelines
       WHERE organization_id = v_lead.organization_id
         AND entity_type = 'deal' AND is_default = true AND deleted_at IS NULL
       LIMIT 1;
    END IF;

    IF v_pipeline IS NULL THEN
      RAISE EXCEPTION
        'no default deal pipeline for organization %; pass p_pipeline_id',
        v_lead.organization_id
        USING ERRCODE = 'foreign_key_violation';
    END IF;

    SELECT id INTO v_stage FROM pipeline_stages
     WHERE pipeline_id = v_pipeline AND kind = 'open' AND deleted_at IS NULL
     ORDER BY position ASC LIMIT 1;

    IF v_stage IS NULL THEN
      RAISE EXCEPTION 'pipeline % has no open stage', v_pipeline
        USING ERRCODE = 'foreign_key_violation';
    END IF;

    INSERT INTO deals (
      organization_id, name, account_id, primary_contact_id,
      pipeline_id, stage_id, amount, currency, owner_id,
      source_lead_id, created_by
    ) VALUES (
      v_lead.organization_id,
      coalesce(p_deal_name, nullif(btrim(v_lead.company_name), ''),
               nullif(btrim(v_lead.full_name), ''), 'Untitled deal'),
      v_account, v_contact, v_pipeline, v_stage,
      coalesce(v_lead.estimated_value, 0),
      coalesce(v_lead.currency, 'USD'),
      v_lead.owner_id, v_lead.id, v_actor
    ) RETURNING id INTO v_deal;

    INSERT INTO stage_transitions (
      organization_id, entity_type, entity_id, to_stage_id, actor_user_id
    ) VALUES (
      v_lead.organization_id, 'deal', v_deal, v_stage, v_actor
    );
  END IF;

  UPDATE leads
     SET status = 'qualified',
         converted_at = now(),
         converted_account_id = v_account,
         converted_contact_id = v_contact,
         converted_deal_id = v_deal
   WHERE id = p_lead_id;

  RETURN QUERY SELECT v_account, v_contact, v_deal;
END;
$$;

COMMIT;
