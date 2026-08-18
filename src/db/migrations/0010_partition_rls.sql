-- 0010_partition_rls.sql
-- Closes a tenant-isolation hole in the partitioned tables.
--
-- THE BUG
--
-- `ALTER TABLE activities ENABLE ROW LEVEL SECURITY` in 0009 protects queries
-- that go through the parent. It does NOT protect a query issued directly
-- against a child partition:
--
--   SELECT * FROM audit_log_202608;   -- every tenant's rows, no policy applied
--
-- Postgres does not propagate `relrowsecurity` to partitions, and a partition
-- is an ordinary table that any role holding SELECT on it can address by name.
-- Because 0009 granted table privileges schema-wide, the application role held
-- exactly that privilege. Verified empirically: with tenant B's context set, a
-- direct read of a populated partition returned all 27 rows, 26 of which
-- belonged to tenant A.
--
-- THE FIX, in two independent layers
--
--   1. Every partition — existing and future — gets RLS enabled, forced, and
--      the same policies as its parent.
--   2. `app.ensure_month_partition` now applies that automatically, so a
--      partition created by next month's cron job is born protected. Relying on
--      an operator to remember is not a control.
--
-- Layer 2 is the one that matters long-term: the original hole existed because
-- partition creation and policy application were separate steps, and anything
-- that must be remembered eventually is not.

BEGIN;

-- ---------------------------------------------------------------------------
-- Apply the parent's policy shape to one partition.
--
-- The two partitioned tables differ: activities permits UPDATE (correcting a
-- mistyped note is legitimate), audit_log does not (a tamperable audit trail is
-- not an audit trail). Neither permits DELETE.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.secure_partition(
  p_child  text,
  p_parent text
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', p_child);
  EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', p_child);

  -- Idempotent: re-running this migration, or calling it on a partition that
  -- already has policies, must not error.
  EXECUTE format('DROP POLICY IF EXISTS tenant_select ON %I', p_child);
  EXECUTE format('DROP POLICY IF EXISTS tenant_insert ON %I', p_child);
  EXECUTE format('DROP POLICY IF EXISTS tenant_update ON %I', p_child);

  EXECUTE format($f$
    CREATE POLICY tenant_select ON %I
      FOR SELECT USING (organization_id = app.current_org_id())
  $f$, p_child);

  IF p_parent = 'audit_log' THEN
    -- Append-only. No UPDATE, no DELETE, deliberately.
    EXECUTE format($f$
      CREATE POLICY tenant_insert ON %I
        FOR INSERT WITH CHECK (organization_id = app.current_org_id())
    $f$, p_child);
  ELSE
    EXECUTE format($f$
      CREATE POLICY tenant_insert ON %I
        FOR INSERT WITH CHECK (
          organization_id = app.current_org_id()
          AND app.can_write_in(organization_id)
        )
    $f$, p_child);

    EXECUTE format($f$
      CREATE POLICY tenant_update ON %I
        FOR UPDATE
        USING (
          organization_id = app.current_org_id()
          AND app.can_write_in(organization_id)
        )
        WITH CHECK (organization_id = app.current_org_id())
    $f$, p_child);
  END IF;
END;
$$;

COMMENT ON FUNCTION app.secure_partition(text, text) IS
  'Applies the parent partitioned table''s RLS posture to one child partition. '
  'Required because Postgres does not propagate row security to partitions, so '
  'a direct query against a child would otherwise bypass tenant isolation.';

-- ---------------------------------------------------------------------------
-- Partition creation now secures what it creates.
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
  IF to_regclass(format('public.%I', v_child)) IS NULL THEN
    EXECUTE format(
      'CREATE TABLE %I PARTITION OF %I FOR VALUES FROM (%L) TO (%L)',
      v_child, p_parent, v_start, v_end
    );
  END IF;

  -- Applied unconditionally, not only on creation: a partition that predates
  -- this migration, or one whose policies were dropped by hand, is repaired the
  -- next time the maintenance job runs.
  PERFORM app.secure_partition(v_child, p_parent);
END;
$$;

-- ---------------------------------------------------------------------------
-- Repair every partition that already exists.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT c.relname AS child, p.relname AS parent
      FROM pg_inherits i
      JOIN pg_class c ON c.oid = i.inhrelid
      JOIN pg_class p ON p.oid = i.inhparent
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND p.relname IN ('activities', 'audit_log')
  LOOP
    PERFORM app.secure_partition(r.child, r.parent);
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- Guard: refuse to finish if any partition is still unprotected.
--
-- A migration that silently half-applies a security fix is worse than one that
-- fails, because it leaves you believing the hole is closed.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_unprotected text[];
BEGIN
  SELECT array_agg(c.relname ORDER BY c.relname) INTO v_unprotected
    FROM pg_inherits i
    JOIN pg_class c ON c.oid = i.inhrelid
    JOIN pg_class p ON p.oid = i.inhparent
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
     AND p.relname IN ('activities', 'audit_log')
     AND NOT (c.relrowsecurity AND c.relforcerowsecurity);

  IF v_unprotected IS NOT NULL THEN
    RAISE EXCEPTION
      'partitions still lack forced RLS: %', array_to_string(v_unprotected, ', ');
  END IF;
END;
$$;

COMMIT;
