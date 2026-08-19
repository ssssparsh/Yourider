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
  RAISE NOTICE '--- 3b. partitions are isolated when queried DIRECTLY ---';
  -- =========================================================================
  -- Regression test for a real hole found during development: enabling RLS on
  -- a partitioned parent does NOT protect its children, and a partition is an
  -- ordinary table addressable by name. Reading through the parent looked
  -- correctly isolated while `SELECT * FROM audit_log_202608` returned every
  -- tenant's rows. Fixed in 0010_partition_rls.sql.
  --
  -- Still under tenant B's context here.
  DECLARE
    r         record;
    v_foreign int;
    v_checked int := 0;
  BEGIN
    -- Every partitioned table, discovered rather than listed: a new one added
    -- later is covered automatically instead of quietly escaping this check.
    FOR r IN
      SELECT c.relname AS child
        FROM pg_inherits i
        JOIN pg_class c ON c.oid = i.inhrelid
        JOIN pg_class p ON p.oid = i.inhparent
        JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public'
         AND p.relkind = 'p'
         AND EXISTS (
           SELECT 1 FROM pg_attribute a
            WHERE a.attrelid = c.oid AND a.attname = 'organization_id'
              AND NOT a.attisdropped
         )
    LOOP
      EXECUTE format(
        'SELECT count(*) FROM %I WHERE organization_id <> $1', r.child
      ) INTO v_foreign USING v_org_b;

      IF v_foreign <> 0 THEN
        RAISE EXCEPTION
          'FAIL: direct query on partition % exposed % foreign rows',
          r.child, v_foreign;
      END IF;
      v_checked := v_checked + 1;
    END LOOP;

    IF v_checked = 0 THEN
      RAISE EXCEPTION 'FAIL: no partitions found to check — test is vacuous';
    END IF;
    RAISE NOTICE '  ok: % partitions leak nothing on direct access', v_checked;
  END;

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

  -- =========================================================================
  RAISE NOTICE '--- 7. consent ledger is tenant-isolated and append-only ---';
  -- =========================================================================
  PERFORM set_config('app.current_org_id', v_org_b::text, false);

  SELECT count(*) INTO v_count FROM contact_channels;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: tenant B sees % of tenant A''s channels', v_count;
  END IF;

  SELECT count(*) INTO v_count FROM consent_records;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: tenant B sees % of tenant A''s consent records', v_count;
  END IF;

  SELECT count(*) INTO v_count FROM suppressions;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: tenant B sees % of tenant A''s suppressions', v_count;
  END IF;

  -- A suppression leaking across tenants would be a disclosure of who
  -- complained about whom, so this is not merely a tidiness check.
  SELECT count(*) INTO v_count FROM consent_state;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: tenant B sees % of tenant A''s consent state', v_count;
  END IF;
  RAISE NOTICE '  ok: channels, records, state and suppressions all isolated';

  PERFORM set_config('app.current_org_id', v_org_a::text, false);

  BEGIN
    UPDATE consent_records SET state = 'granted'
     WHERE organization_id = v_org_a;
    IF EXISTS (
      SELECT 1 FROM consent_records
       WHERE organization_id = v_org_a AND state = 'granted'
         AND source = 'unsubscribe_link'
    ) THEN
      RAISE EXCEPTION 'FAIL: a consent record was rewritten';
    END IF;
    RAISE NOTICE '  ok: consent_records update affected no rows';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '  ok: consent_records update blocked (no UPDATE policy)';
  END;

  BEGIN
    DELETE FROM consent_records WHERE organization_id = v_org_a;
    IF NOT EXISTS (SELECT 1 FROM consent_records WHERE organization_id = v_org_a) THEN
      RAISE EXCEPTION 'FAIL: consent history was deleted';
    END IF;
    RAISE NOTICE '  ok: consent_records delete affected no rows';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '  ok: consent_records delete blocked (no DELETE policy)';
  END;

  -- consent_state is a derived cache: writable only by the ledger trigger, so
  -- it cannot be edited into disagreeing with the history it summarises.
  BEGIN
    UPDATE consent_state SET state = 'granted' WHERE organization_id = v_org_a;
    IF EXISTS (
      SELECT 1 FROM consent_state cs
       WHERE cs.organization_id = v_org_a
         AND cs.state = 'granted'
         AND NOT EXISTS (
           SELECT 1 FROM consent_records r
            WHERE r.id = cs.source_record_id AND r.state = 'granted'
         )
    ) THEN
      RAISE EXCEPTION 'FAIL: consent_state was edited out of step with the ledger';
    END IF;
    RAISE NOTICE '  ok: consent_state update affected no rows';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '  ok: consent_state is not directly writable';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 8. files and attachments are tenant-isolated ---';
  -- =========================================================================
  PERFORM set_config('app.current_org_id', v_org_b::text, false);

  SELECT count(*) INTO v_count FROM files WHERE organization_id = v_org_a;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: tenant B sees % of tenant A''s files', v_count;
  END IF;

  SELECT count(*) INTO v_count FROM attachments WHERE organization_id = v_org_a;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: tenant B sees % of tenant A''s attachments', v_count;
  END IF;

  -- A storage key is a direct reference into the object store. Leaking one is
  -- worse than leaking a row: the object can then be fetched without going
  -- through the database at all, so no policy downstream can intervene.
  SELECT count(*) INTO v_count FROM files
   WHERE storage_key LIKE v_org_a::text || '/%';
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: % of tenant A''s storage keys visible to tenant B', v_count;
  END IF;
  RAISE NOTICE '  ok: files, attachments and storage keys all isolated';

  -- Writing an attachment into another tenant must fail at the policy, before
  -- the cross-tenant trigger ever runs.
  BEGIN
    INSERT INTO attachments (organization_id, file_id, entity_type, entity_id)
      SELECT v_org_a, f.id, 'deal', gen_random_uuid()
        FROM files f WHERE f.organization_id = v_org_b LIMIT 1;
    RAISE EXCEPTION 'FAIL: attachment written into a foreign tenant';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE '  ok: cross-tenant attachment insert blocked by policy';
    WHEN foreign_key_violation THEN
      RAISE NOTICE '  ok: cross-tenant attachment insert blocked by guard';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 9. pricing is tenant-isolated ---';
  -- =========================================================================
  -- Price books are commercially sensitive in a way most tables are not: a
  -- competitor's discount structure is exactly what a leak would be worth.
  SELECT count(*) INTO v_count FROM price_books WHERE organization_id = v_org_a;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: tenant B sees % of tenant A''s price books', v_count;
  END IF;

  SELECT count(*) INTO v_count FROM price_book_entries
   WHERE organization_id = v_org_a;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: tenant B sees % of tenant A''s prices', v_count;
  END IF;

  SELECT count(*) INTO v_count FROM deal_line_items
   WHERE organization_id = v_org_a;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: tenant B sees % of tenant A''s line items', v_count;
  END IF;
  RAISE NOTICE '  ok: price books, prices and line items all isolated';

  PERFORM set_config('app.current_org_id', v_org_a::text, false);

  RAISE NOTICE '';
  RAISE NOTICE '=== ALL RLS ASSERTIONS PASSED (as %) ===', current_user;
END;
$$;
