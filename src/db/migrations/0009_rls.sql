-- 0009_rls.sql
-- Row-level security and audit triggers on every tenant-scoped table.
--
-- Tenant isolation is enforced in the database, not in application code. The
-- reason is simple arithmetic: an application-layer filter has to be correct in
-- every query anyone ever writes, including ad-hoc ones, background jobs, and
-- anything an agent generates. An RLS policy has to be correct once. When the
-- two disagree, the database wins, which is the safe direction.
--
-- This is defence in depth, not a single control:
--   1. app.current_org_id() returns NULL when no tenant context is set, and
--      NULL never equals anything, so an unset context sees zero rows.
--   2. FORCE ROW LEVEL SECURITY applies policies to the table owner too —
--      without it, the migration role bypasses everything silently.
--   3. The assert_same_org() triggers from 0003 already block cross-tenant
--      foreign keys on write, catching what a read policy cannot.
--
-- Escape hatch: a role with BYPASSRLS (Supabase's service_role, or a dedicated
-- migration role) is exempt. That is the intended path for migrations, backups,
-- and cross-tenant admin tooling. It must never be the role an API request runs
-- as. See src/db/README.md.

BEGIN;

-- ---------------------------------------------------------------------------
-- Helper: apply the standard tenant policy set to a table.
--
-- Read is open to any row in the caller's organization. Write additionally
-- requires a non-viewer role. Splitting them means a 'viewer' membership is
-- genuinely read-only at the database level rather than by convention.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.apply_tenant_rls(p_table text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', p_table);
  EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', p_table);

  EXECUTE format($f$
    CREATE POLICY tenant_select ON %I
      FOR SELECT
      USING (organization_id = app.current_org_id())
  $f$, p_table);

  EXECUTE format($f$
    CREATE POLICY tenant_insert ON %I
      FOR INSERT
      WITH CHECK (
        organization_id = app.current_org_id()
        AND app.can_write_in(organization_id)
      )
  $f$, p_table);

  EXECUTE format($f$
    CREATE POLICY tenant_update ON %I
      FOR UPDATE
      USING (
        organization_id = app.current_org_id()
        AND app.can_write_in(organization_id)
      )
      WITH CHECK (organization_id = app.current_org_id())
  $f$, p_table);

  EXECUTE format($f$
    CREATE POLICY tenant_delete ON %I
      FOR DELETE
      USING (
        organization_id = app.current_org_id()
        AND app.can_write_in(organization_id)
      )
  $f$, p_table);
END;
$$;

-- ---------------------------------------------------------------------------
-- Apply to every tenant table.
-- ---------------------------------------------------------------------------
SELECT app.apply_tenant_rls('memberships');
SELECT app.apply_tenant_rls('accounts');
SELECT app.apply_tenant_rls('contacts');
SELECT app.apply_tenant_rls('pipelines');
SELECT app.apply_tenant_rls('pipeline_stages');
SELECT app.apply_tenant_rls('stage_transitions');
SELECT app.apply_tenant_rls('leads');
SELECT app.apply_tenant_rls('deals');
SELECT app.apply_tenant_rls('deal_contacts');
SELECT app.apply_tenant_rls('services');
SELECT app.apply_tenant_rls('service_jobs');
SELECT app.apply_tenant_rls('service_job_items');
SELECT app.apply_tenant_rls('tasks');
SELECT app.apply_tenant_rls('custom_field_definitions');

-- ---------------------------------------------------------------------------
-- Partitioned tables. RLS is declared on the parent and inherited by every
-- partition, including ones created later by ensure_month_partition().
--
-- The audit log is deliberately append-only from the application's point of
-- view: SELECT and INSERT policies exist, UPDATE and DELETE do not. A tamperable
-- audit trail is not an audit trail. Retention is handled by detaching old
-- partitions as a privileged operation, not by row deletes.
-- ---------------------------------------------------------------------------
ALTER TABLE activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE activities FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_select ON activities
  FOR SELECT USING (organization_id = app.current_org_id());

CREATE POLICY tenant_insert ON activities
  FOR INSERT WITH CHECK (
    organization_id = app.current_org_id()
    AND app.can_write_in(organization_id)
  );

-- Correcting a mistyped note is legitimate; deleting history is not.
CREATE POLICY tenant_update ON activities
  FOR UPDATE
  USING (
    organization_id = app.current_org_id()
    AND app.can_write_in(organization_id)
  )
  WITH CHECK (organization_id = app.current_org_id());

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_select ON audit_log
  FOR SELECT USING (organization_id = app.current_org_id());

CREATE POLICY tenant_insert ON audit_log
  FOR INSERT WITH CHECK (organization_id = app.current_org_id());

-- No UPDATE or DELETE policy on audit_log. This is intentional.

-- ---------------------------------------------------------------------------
-- Organizations and users are not organization_id-scoped, so they get their own
-- policies rather than the generic set.
-- ---------------------------------------------------------------------------
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE organizations FORCE ROW LEVEL SECURITY;

CREATE POLICY org_select ON organizations
  FOR SELECT USING (id = app.current_org_id());

CREATE POLICY org_update ON organizations
  FOR UPDATE
  USING (
    id = app.current_org_id()
    AND coalesce(app.current_role_in(id) IN ('owner', 'admin'), false)
  )
  WITH CHECK (id = app.current_org_id());

-- Creating and deleting organizations is a privileged operation performed by
-- the signup/provisioning path running as a BYPASSRLS role, not by tenant
-- traffic. No INSERT or DELETE policy is defined.

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users FORCE ROW LEVEL SECURITY;

-- A user is visible if they share an organization with the caller, or if they
-- are the caller. Visibility of colleagues is required for owner dropdowns and
-- assignment pickers.
CREATE POLICY users_select ON users
  FOR SELECT USING (
    id = app.current_user_id()
    OR EXISTS (
      SELECT 1 FROM memberships m
       WHERE m.user_id = users.id
         AND m.organization_id = app.current_org_id()
         AND m.deleted_at IS NULL
    )
  );

CREATE POLICY users_update_self ON users
  FOR UPDATE
  USING (id = app.current_user_id())
  WITH CHECK (id = app.current_user_id());

-- ---------------------------------------------------------------------------
-- Audit triggers.
--
-- Attached after RLS so the ordering is explicit: policies decide whether a
-- write is allowed, then the audit trigger records the write that happened.
-- app.record_audit() is SECURITY DEFINER so it can insert into audit_log even
-- for a caller whose own policies would not permit it — the trail must be
-- written even when the actor could not write it themselves.
-- ---------------------------------------------------------------------------
SELECT app.attach_audit('accounts');
SELECT app.attach_audit('contacts');
SELECT app.attach_audit('leads');
SELECT app.attach_audit('deals');
SELECT app.attach_audit('services');
SELECT app.attach_audit('service_jobs');
SELECT app.attach_audit('tasks');
SELECT app.attach_audit('pipelines');
SELECT app.attach_audit('pipeline_stages');
SELECT app.attach_audit('memberships');
SELECT app.attach_audit('custom_field_definitions');

COMMIT;
