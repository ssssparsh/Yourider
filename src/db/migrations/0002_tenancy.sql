-- 0002_tenancy.sql
-- Organizations (the tenant root), users, and membership.
--
-- Every other table in this schema hangs off `organizations`. The tenant
-- boundary is enforced three ways, deliberately overlapping:
--   1. a NOT NULL organization_id column on every tenant table,
--   2. RLS policies comparing it to app.current_org_id() (0009_rls.sql),
--   3. composite indexes led by organization_id, so the planner cannot
--      accidentally choose a plan that scans across tenants.

BEGIN;

-- ---------------------------------------------------------------------------
-- Organizations
-- ---------------------------------------------------------------------------
CREATE TABLE organizations (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name           text NOT NULL CHECK (length(btrim(name)) > 0),
  slug           citext,  -- citext extension created in 0001_foundation.sql
  -- Reporting currency. Deal and job amounts are stored in their own currency
  -- plus a converted base amount, so cross-currency pipeline totals are a plain
  -- SUM rather than a per-row conversion at query time.
  base_currency  char(3) NOT NULL DEFAULT 'USD',
  settings       jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  deleted_at     timestamptz
);

CREATE UNIQUE INDEX organizations_slug_key
  ON organizations (slug)
  WHERE deleted_at IS NULL AND slug IS NOT NULL;

CREATE TRIGGER set_updated_at BEFORE UPDATE ON organizations
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

-- ---------------------------------------------------------------------------
-- Users
--
-- A user is a person who signs in. Users are global, not tenant-scoped: the
-- same person can belong to several organizations, which is why access lives in
-- `memberships` rather than on the user row.
--
-- `auth_user_id` links to the identity provider's user record — Supabase's
-- auth.users when self-hosting that stack. It is nullable and carries no FK so
-- this schema stays runnable on plain Postgres with any auth in front of it.
-- ---------------------------------------------------------------------------
CREATE TABLE users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id  uuid,
  email         citext NOT NULL,
  full_name     text,
  avatar_url    text,
  is_active     boolean NOT NULL DEFAULT true,
  last_seen_at  timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  deleted_at    timestamptz
);

CREATE UNIQUE INDEX users_email_key
  ON users (email)
  WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX users_auth_user_id_key
  ON users (auth_user_id)
  WHERE auth_user_id IS NOT NULL;

CREATE TRIGGER set_updated_at BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

-- ---------------------------------------------------------------------------
-- Membership — which users may act inside which organization, and as what.
-- ---------------------------------------------------------------------------
CREATE TYPE membership_role AS ENUM (
  'owner',    -- full control including billing and deletion
  'admin',    -- manage members, pipelines, custom fields
  'manager',  -- see and reassign everything owned by their team
  'member',   -- normal operator: works their own records
  'viewer'    -- read-only
);

CREATE TABLE memberships (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  user_id          uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role             membership_role NOT NULL DEFAULT 'member',
  -- Optional team grouping, used by manager-scoped visibility rules.
  team             text,
  invited_by       uuid REFERENCES users(id) ON DELETE SET NULL,
  joined_at        timestamptz NOT NULL DEFAULT now(),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  deleted_at       timestamptz,

  CONSTRAINT memberships_org_user_key UNIQUE (organization_id, user_id)
);

CREATE INDEX memberships_org_role_idx
  ON memberships (organization_id, role)
  WHERE deleted_at IS NULL;

CREATE INDEX memberships_user_idx
  ON memberships (user_id)
  WHERE deleted_at IS NULL;

SELECT app.attach_tenant_triggers('memberships');

-- ---------------------------------------------------------------------------
-- Membership helpers used by RLS policies and application code.
-- SECURITY DEFINER so a policy can consult memberships without the caller
-- needing their own read access to that table.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.is_member_of(p_org uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM memberships m
    WHERE m.organization_id = p_org
      AND m.user_id = app.current_user_id()
      AND m.deleted_at IS NULL
  );
$$;

CREATE OR REPLACE FUNCTION app.current_role_in(p_org uuid)
RETURNS membership_role
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT m.role
  FROM memberships m
  WHERE m.organization_id = p_org
    AND m.user_id = app.current_user_id()
    AND m.deleted_at IS NULL
  LIMIT 1;
$$;

-- True when the caller may mutate tenant data (everything except 'viewer').
CREATE OR REPLACE FUNCTION app.can_write_in(p_org uuid)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT coalesce(app.current_role_in(p_org) <> 'viewer', false);
$$;

COMMIT;
