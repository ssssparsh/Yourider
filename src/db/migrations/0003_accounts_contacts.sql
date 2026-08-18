-- 0003_accounts_contacts.sql
-- Accounts (who you do business with) and contacts (the people at them).
--
-- An account is either a company or an individual. Sales CRMs assume companies;
-- service businesses often bill a person directly. Rather than force one shape,
-- `account_kind` discriminates, and the columns that only make sense for a
-- company (domain, industry, employee_count) are simply NULL for individuals.
-- This is what keeps the same core usable by a B2B sales team and a
-- service/booking operation without a schema fork.

BEGIN;

CREATE TYPE account_kind AS ENUM ('company', 'individual');

CREATE TYPE lifecycle_stage AS ENUM (
  'prospect',   -- not yet a customer
  'customer',   -- actively paying / being served
  'former',     -- churned
  'partner',
  'other'
);

-- ---------------------------------------------------------------------------
-- Accounts
-- ---------------------------------------------------------------------------
CREATE TABLE accounts (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  account_kind     account_kind NOT NULL DEFAULT 'company',
  name             text NOT NULL CHECK (length(btrim(name)) > 0),
  lifecycle        lifecycle_stage NOT NULL DEFAULT 'prospect',

  -- Company-shaped attributes. NULL for account_kind = 'individual'.
  domain           citext,
  industry         text,
  employee_count   integer CHECK (employee_count IS NULL OR employee_count >= 0),
  annual_revenue   numeric(18,2),

  -- Contact details that belong to the account itself rather than a person.
  phone            text,
  website          text,
  billing_address  jsonb NOT NULL DEFAULT '{}'::jsonb,
  service_address  jsonb NOT NULL DEFAULT '{}'::jsonb,

  owner_id         uuid REFERENCES users(id) ON DELETE SET NULL,
  parent_id        uuid REFERENCES accounts(id) ON DELETE SET NULL,

  custom_fields    jsonb NOT NULL DEFAULT '{}'::jsonb,
  tags             text[] NOT NULL DEFAULT '{}',

  created_by       uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  deleted_at       timestamptz,

  -- An account cannot be its own parent. Deeper cycles are prevented in
  -- application code; a CHECK cannot express reachability.
  CONSTRAINT accounts_no_self_parent CHECK (parent_id IS NULL OR parent_id <> id)
);

-- Every list/filter query is tenant-scoped, so every index leads with
-- organization_id. A partial index on deleted_at IS NULL keeps soft-deleted
-- rows out of the hot index entirely.
CREATE INDEX accounts_org_created_idx
  ON accounts (organization_id, created_at DESC, id)
  WHERE deleted_at IS NULL;

CREATE INDEX accounts_org_owner_idx
  ON accounts (organization_id, owner_id)
  WHERE deleted_at IS NULL;

CREATE INDEX accounts_org_lifecycle_idx
  ON accounts (organization_id, lifecycle)
  WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX accounts_org_domain_key
  ON accounts (organization_id, domain)
  WHERE deleted_at IS NULL AND domain IS NOT NULL;

CREATE INDEX accounts_org_name_trgm_idx
  ON accounts USING gin (organization_id, name gin_trgm_ops)
  WHERE deleted_at IS NULL;

CREATE INDEX accounts_custom_fields_idx
  ON accounts USING gin (custom_fields jsonb_path_ops);

CREATE INDEX accounts_tags_idx
  ON accounts USING gin (tags);

SELECT app.attach_tenant_triggers('accounts');

-- ---------------------------------------------------------------------------
-- Contacts
--
-- `account_id` is the primary affiliation and covers the overwhelming majority
-- of real usage. A contact genuinely tied to several accounts (a consultant, a
-- procurement agent) is modelled by creating the relationship rows in
-- deal_contacts / job assignments rather than a general many-to-many here —
-- adding that join table is cheap later, and paying for it now would slow every
-- contact list query for a case most tenants never hit.
-- ---------------------------------------------------------------------------
CREATE TABLE contacts (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  account_id       uuid REFERENCES accounts(id) ON DELETE SET NULL,

  first_name       text,
  last_name        text,
  -- Generated so search and display never depend on the caller concatenating
  -- correctly, and so one index covers "search by any part of the name".
  full_name        text GENERATED ALWAYS AS (
                     btrim(coalesce(first_name, '') || ' ' || coalesce(last_name, ''))
                   ) STORED,

  email            citext,
  phone            text,
  mobile           text,
  job_title        text,
  department       text,

  lifecycle        lifecycle_stage NOT NULL DEFAULT 'prospect',
  is_primary       boolean NOT NULL DEFAULT false,

  -- Opt-out is tracked on the contact, not inferred from activity. Anything
  -- that sends outbound (including agents) must check this first.
  email_opt_out    boolean NOT NULL DEFAULT false,
  sms_opt_out      boolean NOT NULL DEFAULT false,

  address          jsonb NOT NULL DEFAULT '{}'::jsonb,
  social           jsonb NOT NULL DEFAULT '{}'::jsonb,

  owner_id         uuid REFERENCES users(id) ON DELETE SET NULL,
  custom_fields    jsonb NOT NULL DEFAULT '{}'::jsonb,
  tags             text[] NOT NULL DEFAULT '{}',

  created_by       uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  deleted_at       timestamptz,

  -- A contact with no name at all and no email is not a contact.
  CONSTRAINT contacts_identifiable CHECK (
    coalesce(btrim(first_name), '') <> ''
    OR coalesce(btrim(last_name), '') <> ''
    OR email IS NOT NULL
  )
);

CREATE INDEX contacts_org_created_idx
  ON contacts (organization_id, created_at DESC, id)
  WHERE deleted_at IS NULL;

CREATE INDEX contacts_org_account_idx
  ON contacts (organization_id, account_id)
  WHERE deleted_at IS NULL;

CREATE INDEX contacts_org_owner_idx
  ON contacts (organization_id, owner_id)
  WHERE deleted_at IS NULL;

-- Email is unique per tenant when present. Two tenants may legitimately hold
-- the same person; one tenant holding them twice is a data-quality bug.
CREATE UNIQUE INDEX contacts_org_email_key
  ON contacts (organization_id, email)
  WHERE deleted_at IS NULL AND email IS NOT NULL;

CREATE INDEX contacts_org_name_trgm_idx
  ON contacts USING gin (organization_id, full_name gin_trgm_ops)
  WHERE deleted_at IS NULL;

CREATE INDEX contacts_custom_fields_idx
  ON contacts USING gin (custom_fields jsonb_path_ops);

CREATE INDEX contacts_tags_idx
  ON contacts USING gin (tags);

SELECT app.attach_tenant_triggers('contacts');

-- A contact must belong to the same tenant as its account. A plain FK cannot
-- express this, and it is exactly the kind of cross-tenant reference that RLS
-- alone would not catch on write.
CREATE OR REPLACE FUNCTION app.assert_same_org()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_ref_org uuid;
  v_ref_id  uuid;
  v_table   text := TG_ARGV[0];
  v_column  text := TG_ARGV[1];
BEGIN
  EXECUTE format('SELECT ($1).%I', v_column) INTO v_ref_id USING NEW;
  IF v_ref_id IS NULL THEN
    RETURN NEW;
  END IF;

  EXECUTE format('SELECT organization_id FROM %I WHERE id = $1', v_table)
    INTO v_ref_org USING v_ref_id;

  IF v_ref_org IS NULL OR v_ref_org <> NEW.organization_id THEN
    RAISE EXCEPTION
      'cross-tenant reference: %.% -> %(%) belongs to a different organization',
      TG_TABLE_NAME, v_column, v_table, v_ref_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION app.assert_same_org() IS
  'Trigger guard: the referenced row must live in the same organization as the '
  'row being written. Args: (referenced_table, fk_column_on_this_table).';

CREATE TRIGGER contacts_account_same_org
  BEFORE INSERT OR UPDATE OF account_id ON contacts
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('accounts', 'account_id');

CREATE TRIGGER accounts_parent_same_org
  BEFORE INSERT OR UPDATE OF parent_id ON accounts
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('accounts', 'parent_id');

COMMIT;
