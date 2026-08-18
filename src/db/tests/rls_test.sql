-- rls_test.sql
-- Proves tenant isolation is enforced by the database, not by convention.
--
-- This test MUST run as a role without SUPERUSER and without BYPASSRLS.
-- A superuser silently ignores every policy, so running this as `postgres`
-- would print all-pass while proving nothing. The runner script creates and
-- switches to `yourider_app` for exactly this reason.
--
--   psql -d yourider -v ON_ERROR_STOP=1 -f src/db/tests/rls_test.sql

\set ON_ERROR_STOP on

-- Fail immediately if the caller can bypass the thing we are testing.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_roles
     WHERE rolname = current_user AND (rolsuper OR rolbypassrls)
  ) THEN
    RAISE EXCEPTION
      'rls_test must not run as a SUPERUSER/BYPASSRLS role (current_user=%). '
      'It would pass vacuously.', current_user;
  END IF;
END;
$$;

-- Fixture identifiers are supplied by the runner, which resolves them with a
-- privileged connection. They cannot be looked up from inside this script:
-- with no tenant context set, RLS correctly hides every row — including the
-- rows this test needs to address. That is the policy working, not a bug.
--
-- They are pushed into session settings here rather than referenced directly
-- inside the DO block below, because psql does not interpolate :variables
-- inside dollar-quoted strings.
SELECT set_config('test.org_a',  :'org_a',  false),
       set_config('test.org_b',  :'org_b',  false),
       set_config('test.user_a', :'user_a', false),
       set_config('test.viewer', :'viewer', false)
\gset

DO $$
DECLARE
  v_org_a   uuid := nullif(current_setting('test.org_a',  true), '')::uuid;
  v_org_b   uuid := nullif(current_setting('test.org_b',  true), '')::uuid;
  v_user_a  uuid := nullif(current_setting('test.user_a', true), '')::uuid;
  v_viewer  uuid := nullif(current_setting('test.viewer', true), '')::uuid;
  v_count   int;
BEGIN
  IF v_org_a IS NULL OR v_org_b IS NULL THEN
    RAISE EXCEPTION 'fixture missing: run functional_test.sql first';
  END IF;

  -- =========================================================================
  RAISE NOTICE '--- 1. no tenant context sees nothing ---';
  -- =========================================================================
  PERFORM set_config('app.current_org_id', '', false);
  PERFORM set_config('app.current_user_id', '', false);

  SELECT count(*) INTO v_count FROM accounts;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: % account rows visible with no tenant context', v_count;
  END IF;
  RAISE NOTICE '  ok: unset context sees 0 accounts (deny by default)';

  SELECT count(*) INTO v_count FROM deals;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: % deal rows visible with no tenant context', v_count;
  END IF;
  RAISE NOTICE '  ok: unset context sees 0 deals';

  -- =========================================================================
  RAISE NOTICE '--- 2. tenant A sees only tenant A ---';
  -- =========================================================================
  PERFORM set_config('app.current_org_id', v_org_a::text, false);
  PERFORM set_config('app.current_user_id', v_user_a::text, false);

  SELECT count(*) INTO v_count FROM accounts WHERE organization_id <> v_org_a;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: tenant A can see % foreign account rows', v_count;
  END IF;

  SELECT count(*) INTO v_count FROM accounts;
  IF v_count = 0 THEN
    RAISE EXCEPTION 'FAIL: tenant A sees none of its own accounts (policy too strict)';
  END IF;
  RAISE NOTICE '  ok: tenant A sees % of its own accounts and 0 foreign', v_count;

  -- =========================================================================
  RAISE NOTICE '--- 3. switching context switches the visible world ---';
  -- =========================================================================
  PERFORM set_config('app.current_org_id', v_org_b::text, false);

  SELECT count(*) INTO v_count FROM accounts;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: tenant B sees % accounts but created none', v_count;
  END IF;
  RAISE NOTICE '  ok: tenant B sees 0 of tenant A''s accounts';

  -- Tenant B legitimately has audit rows of its own (its membership was created
  -- during setup). What must be zero is rows belonging to anyone else.
  SELECT count(*) INTO v_count FROM audit_log WHERE organization_id <> v_org_b;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: tenant B can read % foreign audit rows', v_count;
  END IF;

  SELECT count(*) INTO v_count FROM audit_log WHERE organization_id = v_org_a;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: tenant B can read % of tenant A''s audit rows', v_count;
  END IF;
  RAISE NOTICE '  ok: audit log is tenant-isolated';

  -- =========================================================================
  RAISE NOTICE '--- 4. cannot write into another tenant ---';
  -- =========================================================================
  PERFORM set_config('app.current_org_id', v_org_a::text, false);
  BEGIN
    INSERT INTO accounts (organization_id, name) VALUES (v_org_b, 'Smuggled');
    RAISE EXCEPTION 'FAIL: wrote a row into another tenant';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '  ok: insert into foreign tenant blocked by policy';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 5. viewers cannot write ---';
  -- =========================================================================
  PERFORM set_config('app.current_user_id', v_viewer::text, false);

  SELECT count(*) INTO v_count FROM accounts;
  IF v_count = 0 THEN
    RAISE EXCEPTION 'FAIL: viewer cannot read, but should be able to';
  END IF;
  RAISE NOTICE '  ok: viewer can read (% accounts)', v_count;

  BEGIN
    INSERT INTO accounts (organization_id, name) VALUES (v_org_a, 'Viewer Made This');
    RAISE EXCEPTION 'FAIL: viewer inserted a row';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '  ok: viewer insert blocked';
  END;

  BEGIN
    UPDATE accounts SET name = 'Renamed By Viewer'
     WHERE organization_id = v_org_a;
    -- An UPDATE blocked by a USING clause affects 0 rows rather than raising,
    -- so verify nothing actually changed.
    IF EXISTS (SELECT 1 FROM accounts WHERE name = 'Renamed By Viewer') THEN
      RAISE EXCEPTION 'FAIL: viewer updated a row';
    END IF;
    RAISE NOTICE '  ok: viewer update affected no rows';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '  ok: viewer update blocked';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 6. audit log is append-only ---';
  -- =========================================================================
  PERFORM set_config('app.current_user_id', v_user_a::text, false);

  BEGIN
    UPDATE audit_log SET reason = 'tampered'
     WHERE organization_id = v_org_a;
    IF EXISTS (SELECT 1 FROM audit_log WHERE reason = 'tampered') THEN
      RAISE EXCEPTION 'FAIL: audit_log row was modified';
    END IF;
    RAISE NOTICE '  ok: audit_log update affected no rows';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '  ok: audit_log update blocked (no UPDATE policy)';
  END;

  BEGIN
    DELETE FROM audit_log WHERE organization_id = v_org_a;
    IF NOT EXISTS (SELECT 1 FROM audit_log WHERE organization_id = v_org_a) THEN
      RAISE EXCEPTION 'FAIL: audit_log rows were deleted';
    END IF;
    RAISE NOTICE '  ok: audit_log delete affected no rows';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '  ok: audit_log delete blocked (no DELETE policy)';
  END;

  RAISE NOTICE '';
  RAISE NOTICE '=== ALL RLS ASSERTIONS PASSED (as %) ===', current_user;
END;
$$;
