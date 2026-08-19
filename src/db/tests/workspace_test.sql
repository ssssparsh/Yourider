-- workspace_test.sql
-- Exercises teams (0016), saved views (0017), and field/row permissions
-- (0018) — the workspace-configuration layer sitting on top of the tenant
-- boundary.
--
-- Requires the fixture from functional_test.sql (org-a, org-b, users a/b/v).

\set ON_ERROR_STOP on

DO $$
DECLARE
  v_org      uuid;
  v_org_b    uuid;
  v_user_a   uuid;
  v_user_b   uuid;
  v_viewer   uuid;
  v_team_root uuid;
  v_team_east uuid;
  v_team_ne   uuid;
  v_deal      uuid;
  v_view      uuid;
  v_share     uuid;
  v_count     int;
  v_text      text;
  v_redacted  jsonb;
BEGIN
  SELECT id INTO v_org    FROM organizations WHERE slug = 'org-a';
  SELECT id INTO v_org_b  FROM organizations WHERE slug = 'org-b';
  SELECT id INTO v_user_a FROM users WHERE email = 'a@example.com';
  SELECT id INTO v_user_b FROM users WHERE email = 'b@example.com';
  SELECT id INTO v_viewer FROM users WHERE email = 'v@example.com';
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'fixture missing: run functional_test.sql first';
  END IF;

  PERFORM set_config('app.current_org_id', v_org::text, false);
  PERFORM set_config('app.current_user_id', v_user_a::text, false);

  -- =========================================================================
  RAISE NOTICE '--- 1. teams and the hierarchy guard ---';
  -- =========================================================================
  INSERT INTO teams (organization_id, name) VALUES (v_org, 'Sales')
    RETURNING id INTO v_team_root;
  INSERT INTO teams (organization_id, name, parent_team_id)
    VALUES (v_org, 'East', v_team_root) RETURNING id INTO v_team_east;
  INSERT INTO teams (organization_id, name, parent_team_id)
    VALUES (v_org, 'North-East', v_team_east) RETURNING id INTO v_team_ne;

  BEGIN
    UPDATE teams SET parent_team_id = v_team_ne WHERE id = v_team_root;
    RAISE EXCEPTION 'FAIL: a 3-level cycle was accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: a deep cycle (root -> east -> ne -> root) is refused';
  END;

  BEGIN
    UPDATE teams SET parent_team_id = v_team_root WHERE id = v_team_root;
    RAISE EXCEPTION 'FAIL: self-parenting was accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: a team cannot be its own parent';
  END;

  SELECT count(*) INTO v_count FROM app.team_and_descendants(v_team_root);
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'FAIL: root+descendants counted %, expected 3', v_count;
  END IF;
  RAISE NOTICE '  ok: team_and_descendants walks the whole subtree';

  -- =========================================================================
  RAISE NOTICE '--- 2. manager-scoped visibility ---';
  -- =========================================================================
  UPDATE memberships SET team_id = v_team_east, role = 'manager'
   WHERE organization_id = v_org AND user_id = v_user_a;
  UPDATE memberships SET team_id = v_team_ne, role = 'member'
   WHERE organization_id = v_org AND user_id = v_viewer;

  SELECT count(*) INTO v_count FROM app.visible_team_ids(v_org);
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'FAIL: manager of East sees % teams, expected 2 (east+ne)', v_count;
  END IF;
  RAISE NOTICE '  ok: a manager sees their team and its descendants, not the whole org';

  UPDATE memberships SET role = 'admin' WHERE organization_id = v_org AND user_id = v_user_a;
  SELECT count(*) INTO v_count FROM app.visible_team_ids(v_org);
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'FAIL: admin sees % teams, expected all 3', v_count;
  END IF;
  RAISE NOTICE '  ok: admin/owner reach every team';

  -- Restore both memberships exactly as functional_test.sql created them.
  -- This suite runs before platform_test.sql and rls_test.sql in run_tests.sh,
  -- and both depend on v_user_a being 'owner' and v_viewer being an
  -- unaffiliated 'viewer' — a role/team_id change here that outlives this
  -- suite is fixture pollution across suites, not a local mutation. (Caught by
  -- rls_test.sql failing "viewer insert blocked" once the viewer had quietly
  -- become a 'member' with write access.)
  UPDATE memberships SET role = 'owner', team_id = NULL
   WHERE organization_id = v_org AND user_id = v_user_a;
  UPDATE memberships SET role = 'viewer', team_id = NULL
   WHERE organization_id = v_org AND user_id = v_viewer;

  -- =========================================================================
  RAISE NOTICE '--- 3. saved views ---';
  -- =========================================================================
  -- Visibility (private/team/organization) is enforced by RLS policy, which a
  -- superuser connection bypasses entirely (the same trap rls_test.sql exists
  -- to avoid — see its header comment). Those assertions live in rls_test.sql
  -- §11 under the unprivileged role; this section covers what a CHECK/unique
  -- index enforces, which fires regardless of role.
  SELECT id INTO v_deal FROM deals WHERE organization_id = v_org LIMIT 1;

  INSERT INTO saved_views (organization_id, entity_type, name, owner_id, visibility)
    VALUES (v_org, 'deal', 'My private pipeline', v_user_a, 'private')
    RETURNING id INTO v_view;

  BEGIN
    INSERT INTO saved_views (organization_id, entity_type, name, owner_id, is_default)
      VALUES (v_org, 'deal', 'Second default', v_user_a, true);
    INSERT INTO saved_views (organization_id, entity_type, name, owner_id, is_default)
      VALUES (v_org, 'deal', 'Second default 2', v_user_a, true);
    RAISE EXCEPTION 'FAIL: two default views accepted for one owner';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE '  ok: only one default view per (owner, entity_type)';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 4. field redaction ---';
  -- =========================================================================
  INSERT INTO field_permissions (organization_id, entity_type, field_key, hidden_from_roles)
    VALUES (v_org, 'contact', 'ssn', ARRAY['member','viewer']::membership_role[]);

  v_redacted := app.redact_fields('contact', v_org, 'member',
    '{"ssn":"123-45-6789","phone":"555-0100"}'::jsonb);
  IF v_redacted ? 'ssn' THEN
    RAISE EXCEPTION 'FAIL: ssn survived redaction for member';
  END IF;
  IF NOT (v_redacted ? 'phone') THEN
    RAISE EXCEPTION 'FAIL: redaction removed a field nobody hid';
  END IF;
  RAISE NOTICE '  ok: a hidden field is stripped, everything else passes through';

  v_redacted := app.redact_fields('contact', v_org, 'admin',
    '{"ssn":"123-45-6789"}'::jsonb);
  IF NOT (v_redacted ? 'ssn') THEN
    RAISE EXCEPTION 'FAIL: admin was redacted from data they administer';
  END IF;
  RAISE NOTICE '  ok: admin and owner are never redacted';

  -- =========================================================================
  RAISE NOTICE '--- 5. record shares: validation ---';
  -- =========================================================================
  -- Who can SEE a share row is an RLS question — asserted in rls_test.sql §11.
  -- This covers what the triggers and indexes enforce regardless of role.
  INSERT INTO record_shares (organization_id, entity_type, entity_id,
                             shared_with_user_id, permission, granted_by)
    VALUES (v_org, 'deal', v_deal, v_viewer, 'view', v_user_a)
    RETURNING id INTO v_share;

  BEGIN
    INSERT INTO record_shares (organization_id, entity_type, entity_id,
                               shared_with_user_id, permission, granted_by)
      VALUES (v_org, 'deal', v_deal, v_viewer, 'edit', v_user_a);
    RAISE EXCEPTION 'FAIL: a second live share to the same person was accepted';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE '  ok: one live share per (record, recipient)';
  END;

  BEGIN
    INSERT INTO record_shares (organization_id, entity_type, entity_id,
                               shared_with_user_id, shared_with_team_id, granted_by)
      VALUES (v_org, 'deal', v_deal, v_viewer, v_team_east, v_user_a);
    RAISE EXCEPTION 'FAIL: a share to both a user and a team was accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: a share targets exactly one of user or team';
  END;

  BEGIN
    INSERT INTO record_shares (organization_id, entity_type, entity_id,
                               shared_with_user_id, granted_by)
      VALUES (v_org, 'deal', gen_random_uuid(), v_viewer, v_user_a);
    RAISE EXCEPTION 'FAIL: a share to a nonexistent deal was accepted';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE '  ok: the shared record must actually exist';
  END;

  PERFORM app.revoke_share(v_share, v_user_a);
  SELECT count(*) INTO v_count FROM record_shares WHERE id = v_share AND revoked_at IS NOT NULL;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: revoke did not stamp the share';
  END IF;
  RAISE NOTICE '  ok: revoking a share is recorded, not deleted';

  RAISE NOTICE '';
  RAISE NOTICE '=== ALL WORKSPACE ASSERTIONS PASSED ===';
END;
$$;
