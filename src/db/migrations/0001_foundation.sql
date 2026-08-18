-- 0001_foundation.sql
-- Extensions, the tenant-context resolver, and shared trigger helpers.
-- Everything downstream depends on this file; run it first.

BEGIN;

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;    -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pg_trgm;     -- trigram fuzzy matching on names/emails
CREATE EXTENSION IF NOT EXISTS btree_gin;   -- composite GIN (organization_id + jsonb/tsvector)
CREATE EXTENSION IF NOT EXISTS citext;      -- case-insensitive emails and slugs

-- ---------------------------------------------------------------------------
-- Internal schema for helpers. Keeping these out of `public` means PostgREST
-- (and anything else auto-exposing `public`) does not publish them as RPC.
-- ---------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS app;

-- ---------------------------------------------------------------------------
-- Tenant context resolution.
--
-- Two sources, checked in order:
--   1. `app.current_org_id` session GUC — set explicitly by server-side workers,
--      background jobs, and agent runs that are not going through PostgREST.
--   2. The request JWT's `organization_id` claim — the PostgREST/Supabase path.
--
-- Returns NULL when neither is present. Every RLS policy compares against this,
-- and NULL never equals anything, so an unset context sees zero rows rather than
-- every row. That failure mode is deliberate: a missing tenant context must be a
-- silent no-results, never a silent cross-tenant leak.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.current_org_id()
RETURNS uuid
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_raw text;
BEGIN
  v_raw := nullif(current_setting('app.current_org_id', true), '');
  IF v_raw IS NOT NULL THEN
    RETURN v_raw::uuid;
  END IF;

  BEGIN
    v_raw := nullif(
      current_setting('request.jwt.claims', true)::jsonb ->> 'organization_id',
      ''
    );
  EXCEPTION WHEN OTHERS THEN
    -- No JWT in scope, or it is not valid JSON. Not an error: this simply means
    -- we are not on the request path.
    v_raw := NULL;
  END;

  IF v_raw IS NOT NULL THEN
    RETURN v_raw::uuid;
  END IF;

  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION app.current_org_id() IS
  'Resolves the acting tenant from the app.current_org_id GUC, falling back to '
  'the request JWT organization_id claim. NULL when unset, which makes RLS '
  'policies deny by default.';

-- Resolves the acting user the same way. Used by audit triggers to attribute
-- changes. NULL is legitimate here (system migrations, seed scripts).
CREATE OR REPLACE FUNCTION app.current_user_id()
RETURNS uuid
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_raw text;
BEGIN
  v_raw := nullif(current_setting('app.current_user_id', true), '');
  IF v_raw IS NOT NULL THEN
    RETURN v_raw::uuid;
  END IF;

  BEGIN
    v_raw := nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '');
  EXCEPTION WHEN OTHERS THEN
    v_raw := NULL;
  END;

  IF v_raw IS NOT NULL THEN
    BEGIN
      RETURN v_raw::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
      -- A non-UUID `sub` claim (some providers use opaque strings). Treat the
      -- actor as unknown rather than failing the write.
      RETURN NULL;
    END;
  END IF;

  RETURN NULL;
END;
$$;

-- ---------------------------------------------------------------------------
-- Shared triggers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- organization_id must never be rewritten after insert. Moving a record between
-- tenants is not an update, it is a migration with its own audit story.
CREATE OR REPLACE FUNCTION app.freeze_organization_id()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
    RAISE EXCEPTION
      'organization_id is immutable (table %, row %)', TG_TABLE_NAME, OLD.id
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

-- Applies both standard triggers to a tenant-scoped table.
CREATE OR REPLACE FUNCTION app.attach_tenant_triggers(p_table regclass)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  EXECUTE format(
    'CREATE TRIGGER set_updated_at BEFORE UPDATE ON %s
       FOR EACH ROW EXECUTE FUNCTION app.set_updated_at()', p_table);
  EXECUTE format(
    'CREATE TRIGGER freeze_organization_id BEFORE UPDATE ON %s
       FOR EACH ROW EXECUTE FUNCTION app.freeze_organization_id()', p_table);
END;
$$;

-- ---------------------------------------------------------------------------
-- Monthly partition maintenance.
--
-- The activity and audit tables are the ones that reach hundreds of millions of
-- rows first — they grow with every interaction, not with customer count. Both
-- are RANGE-partitioned on created_at so old months can be detached and archived
-- without a rewrite, and so queries scoped to a date window skip the rest.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.ensure_month_partition(
  p_parent text,
  p_month  date
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_start date := date_trunc('month', p_month)::date;
  v_end   date := (date_trunc('month', p_month) + interval '1 month')::date;
  v_child text := format('%s_%s', p_parent, to_char(v_start, 'YYYYMM'));
BEGIN
  IF to_regclass(format('public.%I', v_child)) IS NOT NULL THEN
    RETURN;
  END IF;

  EXECUTE format(
    'CREATE TABLE %I PARTITION OF %I FOR VALUES FROM (%L) TO (%L)',
    v_child, p_parent, v_start, v_end
  );
END;
$$;

COMMENT ON FUNCTION app.ensure_month_partition(text, date) IS
  'Idempotently creates the monthly partition covering p_month. Call ahead of '
  'time from a scheduled job; see src/db/README.md for the maintenance window.';

-- Creates partitions for a rolling window. Run this from a monthly cron so
-- partitions always exist before rows need them — an insert with no matching
-- partition fails outright.
CREATE OR REPLACE FUNCTION app.ensure_partition_window(
  p_parent        text,
  p_months_back   int DEFAULT 1,
  p_months_ahead  int DEFAULT 3
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  i int;
BEGIN
  FOR i IN -p_months_back..p_months_ahead LOOP
    PERFORM app.ensure_month_partition(
      p_parent,
      (date_trunc('month', now()) + make_interval(months => i))::date
    );
  END LOOP;
END;
$$;

COMMIT;
