-- functional_test.sql
-- Exercises the schema end to end and fails loudly on any broken invariant.
--
-- Run against a database that has had every migration applied:
--   psql -d yourider -v ON_ERROR_STOP=1 -f src/db/tests/functional_test.sql
--
-- Must be run as a NON-superuser role that lacks BYPASSRLS, otherwise the RLS
-- assertions silently pass for the wrong reason. See src/db/README.md.

\set ON_ERROR_STOP on

DO $$
DECLARE
  v_org_a    uuid;
  v_org_b    uuid;
  v_user_a   uuid;
  v_user_b   uuid;
  v_viewer   uuid;
  v_pipeline uuid;
  v_stage_new uuid;
  v_stage_won uuid;
  v_stage_lost uuid;
  v_svc_pipeline uuid;
  v_svc_stage uuid;
  v_lead     uuid;
  v_deal     uuid;
  v_account  uuid;
  v_contact  uuid;
  v_job      uuid;
  v_service  uuid;
  v_count    int;
  v_ok       boolean;
  v_conv     record;
  v_dur      bigint;
BEGIN
  RAISE NOTICE '--- setup: two organizations ---';

  INSERT INTO organizations (name, slug, base_currency)
    VALUES ('Org A', 'org-a', 'USD') RETURNING id INTO v_org_a;
  INSERT INTO organizations (name, slug, base_currency)
    VALUES ('Org B', 'org-b', 'EUR') RETURNING id INTO v_org_b;

  INSERT INTO users (email, full_name) VALUES ('a@example.com', 'Ann A')
    RETURNING id INTO v_user_a;
  INSERT INTO users (email, full_name) VALUES ('b@example.com', 'Ben B')
    RETURNING id INTO v_user_b;
  INSERT INTO users (email, full_name) VALUES ('v@example.com', 'Vic Viewer')
    RETURNING id INTO v_viewer;

  INSERT INTO memberships (organization_id, user_id, role)
    VALUES (v_org_a, v_user_a, 'owner');
  INSERT INTO memberships (organization_id, user_id, role)
    VALUES (v_org_b, v_user_b, 'owner');
  INSERT INTO memberships (organization_id, user_id, role)
    VALUES (v_org_a, v_viewer, 'viewer');

  PERFORM set_config('app.current_org_id', v_org_a::text, false);
  PERFORM set_config('app.current_user_id', v_user_a::text, false);

  -- =========================================================================
  RAISE NOTICE '--- 1. pipelines and stages ---';
  -- =========================================================================
  INSERT INTO pipelines (organization_id, entity_type, name, is_default)
    VALUES (v_org_a, 'deal', 'Standard Sales', true) RETURNING id INTO v_pipeline;

  INSERT INTO pipeline_stages (organization_id, pipeline_id, name, kind, position, probability)
    VALUES (v_org_a, v_pipeline, 'New', 'open', 1, 0.10) RETURNING id INTO v_stage_new;
  INSERT INTO pipeline_stages (organization_id, pipeline_id, name, kind, position, probability)
    VALUES (v_org_a, v_pipeline, 'Won', 'won', 90, 1.00) RETURNING id INTO v_stage_won;
  INSERT INTO pipeline_stages (organization_id, pipeline_id, name, kind, position, probability)
    VALUES (v_org_a, v_pipeline, 'Lost', 'lost', 99, 0.00) RETURNING id INTO v_stage_lost;

  IF NOT app.pipeline_is_reportable(v_pipeline) THEN
    RAISE EXCEPTION 'FAIL: pipeline with open/won/lost stages should be reportable';
  END IF;

  -- Only one default deal pipeline per tenant.
  BEGIN
    INSERT INTO pipelines (organization_id, entity_type, name, is_default)
      VALUES (v_org_a, 'deal', 'Second Default', true);
    RAISE EXCEPTION 'FAIL: a second default deal pipeline was allowed';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE '  ok: duplicate default pipeline rejected';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 2. custom field definition + validation ---';
  -- =========================================================================
  INSERT INTO custom_field_definitions
    (organization_id, entity_type, key, label, field_type, options, is_required)
  VALUES
    (v_org_a, 'lead', 'segment', 'Segment', 'select',
     '[{"value":"smb","label":"SMB"},{"value":"ent","label":"Enterprise"}]'::jsonb, false);

  INSERT INTO custom_field_definitions
    (organization_id, entity_type, key, label, field_type, min_value, max_value)
  VALUES (v_org_a, 'lead', 'headcount', 'Headcount', 'number', 1, 100000);

  -- Unknown key must be rejected.
  BEGIN
    INSERT INTO leads (organization_id, company_name, custom_fields)
      VALUES (v_org_a, 'Bad Co', '{"not_a_field": 1}'::jsonb);
    RAISE EXCEPTION 'FAIL: unknown custom field key was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    RAISE NOTICE '  ok: unknown custom field rejected';
  END;

  -- Value outside the declared options must be rejected.
  BEGIN
    INSERT INTO leads (organization_id, company_name, custom_fields)
      VALUES (v_org_a, 'Bad Co', '{"segment": "enterprise"}'::jsonb);
    RAISE EXCEPTION 'FAIL: out-of-range select value was accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: invalid select option rejected';
  END;

  -- Number outside declared bounds must be rejected.
  BEGIN
    INSERT INTO leads (organization_id, company_name, custom_fields)
      VALUES (v_org_a, 'Bad Co', '{"headcount": 999999}'::jsonb);
    RAISE EXCEPTION 'FAIL: out-of-bounds number was accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: out-of-bounds number rejected';
  END;

  -- Wrong JSON type must be rejected.
  BEGIN
    INSERT INTO leads (organization_id, company_name, custom_fields)
      VALUES (v_org_a, 'Bad Co', '{"headcount": "many"}'::jsonb);
    RAISE EXCEPTION 'FAIL: string in a number field was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    RAISE NOTICE '  ok: wrong type rejected';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 3. lead creation and conversion ---';
  -- =========================================================================
  INSERT INTO leads (
    organization_id, first_name, last_name, company_name, email, phone,
    source, estimated_value, currency, owner_id, custom_fields
  ) VALUES (
    v_org_a, 'Dana', 'Doe', 'Acme Industries', 'dana@acme.test', '+1-555-0100',
    'web_form', 25000, 'USD', v_user_a, '{"segment":"ent","headcount":500}'::jsonb
  ) RETURNING id INTO v_lead;

  SELECT * INTO v_conv FROM app.convert_lead(v_lead, true, NULL, v_pipeline, v_user_a);
  v_account := v_conv.account_id;
  v_contact := v_conv.contact_id;
  v_deal    := v_conv.deal_id;

  IF v_account IS NULL OR v_contact IS NULL OR v_deal IS NULL THEN
    RAISE EXCEPTION 'FAIL: conversion did not produce account/contact/deal (% / % / %)',
      v_account, v_contact, v_deal;
  END IF;
  RAISE NOTICE '  ok: lead converted to account+contact+deal';

  SELECT count(*) INTO v_count FROM leads
   WHERE id = v_lead AND status = 'qualified' AND converted_at IS NOT NULL
     AND converted_deal_id = v_deal;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: lead not marked converted correctly';
  END IF;

  -- Double conversion must be refused.
  BEGIN
    PERFORM app.convert_lead(v_lead, true, NULL, v_pipeline, v_user_a);
    RAISE EXCEPTION 'FAIL: lead converted twice';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE '  ok: double conversion rejected';
  END;

  -- The generated money columns must agree with their inputs.
  UPDATE deals SET amount = 1000, fx_rate = 1.25 WHERE id = v_deal;
  SELECT count(*) INTO v_count FROM deals
   WHERE id = v_deal AND base_amount = 1250.0000;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: base_amount generated column is wrong';
  END IF;
  RAISE NOTICE '  ok: base_amount computed from amount * fx_rate';

  -- =========================================================================
  RAISE NOTICE '--- 4. stage movement and transition history ---';
  -- =========================================================================
  PERFORM app.move_to_stage('deal', v_deal, v_stage_won, v_user_a, NULL, 'signed');

  SELECT count(*) INTO v_count FROM deals
   WHERE id = v_deal AND stage_id = v_stage_won AND closed_at IS NOT NULL
     AND probability = 1.00;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: winning a deal did not stamp closed_at/probability';
  END IF;
  RAISE NOTICE '  ok: terminal stage stamped closed_at and probability';

  -- Exactly one open interval, and the previous one closed.
  SELECT count(*) INTO v_count FROM stage_transitions
   WHERE entity_type = 'deal' AND entity_id = v_deal AND exited_at IS NULL;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: expected exactly 1 open stage interval, found %', v_count;
  END IF;

  SELECT duration_seconds INTO v_dur FROM stage_transitions
   WHERE entity_type = 'deal' AND entity_id = v_deal AND exited_at IS NOT NULL
   ORDER BY entered_at LIMIT 1;
  IF v_dur IS NULL THEN
    RAISE EXCEPTION 'FAIL: closed interval has no computed duration';
  END IF;
  RAISE NOTICE '  ok: transition history closed prior interval, duration computed';

  -- Moving to the stage it is already in is a no-op, not a new row.
  SELECT count(*) INTO v_count FROM stage_transitions
   WHERE entity_type = 'deal' AND entity_id = v_deal;
  PERFORM app.move_to_stage('deal', v_deal, v_stage_won, v_user_a);
  SELECT count(*) - v_count INTO v_count FROM stage_transitions
   WHERE entity_type = 'deal' AND entity_id = v_deal;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: redundant stage move created % extra rows', v_count;
  END IF;
  RAISE NOTICE '  ok: redundant stage move is a no-op';

  -- =========================================================================
  RAISE NOTICE '--- 5. services and jobs ---';
  -- =========================================================================
  INSERT INTO pipelines (organization_id, entity_type, name, is_default)
    VALUES (v_org_a, 'service_job', 'Delivery', true) RETURNING id INTO v_svc_pipeline;
  INSERT INTO pipeline_stages (organization_id, pipeline_id, name, kind, position)
    VALUES (v_org_a, v_svc_pipeline, 'Scheduled', 'open', 1) RETURNING id INTO v_svc_stage;

  INSERT INTO services (organization_id, name, billing_kind, unit_price, currency,
                        default_duration_minutes)
    VALUES (v_org_a, 'Onboarding Session', 'hourly', 150, 'USD', 60)
    RETURNING id INTO v_service;

  INSERT INTO service_jobs (
    organization_id, service_id, account_id, contact_id, deal_id,
    title, pipeline_id, stage_id, scheduled_start, scheduled_end, quoted_amount
  ) VALUES (
    v_org_a, v_service, v_account, v_contact, v_deal,
    'Kickoff', v_svc_pipeline, v_svc_stage,
    now() + interval '1 day', now() + interval '1 day 1 hour', 150
  ) RETURNING id INTO v_job;

  -- Assignment must auto-stamp assigned_at.
  UPDATE service_jobs SET assigned_user_id = v_user_a WHERE id = v_job;
  SELECT count(*) INTO v_count FROM service_jobs
   WHERE id = v_job AND assigned_at IS NOT NULL;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: assignment did not stamp assigned_at';
  END IF;
  RAISE NOTICE '  ok: assignment stamped assigned_at';

  -- Unassigning must clear it again.
  UPDATE service_jobs SET assigned_user_id = NULL WHERE id = v_job;
  SELECT count(*) INTO v_count FROM service_jobs
   WHERE id = v_job AND assigned_at IS NULL;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: unassignment did not clear assigned_at';
  END IF;
  UPDATE service_jobs SET assigned_user_id = v_user_a WHERE id = v_job;

  -- Schedule ordering is enforced.
  BEGIN
    UPDATE service_jobs SET scheduled_end = scheduled_start - interval '1 hour'
     WHERE id = v_job;
    RAISE EXCEPTION 'FAIL: end before start was allowed';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: scheduled_end before scheduled_start rejected';
  END;

  -- Line item money is computed in the database.
  INSERT INTO service_job_items (organization_id, job_id, service_id, description,
                                 quantity, unit_price, tax_rate)
    VALUES (v_org_a, v_job, v_service, 'Onboarding, 2h', 2, 150, 0.20);
  SELECT count(*) INTO v_count FROM service_job_items
   WHERE job_id = v_job AND line_total = 360.0000;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: line_total should be 2 * 150 * 1.20 = 360';
  END IF;
  RAISE NOTICE '  ok: line_total computed correctly';

  -- =========================================================================
  RAISE NOTICE '--- 6. cross-tenant reference guard ---';
  -- =========================================================================
  BEGIN
    INSERT INTO contacts (organization_id, first_name, last_name, account_id)
      VALUES (v_org_b, 'Mallory', 'M', v_account);  -- account belongs to org A
    RAISE EXCEPTION 'FAIL: cross-tenant account reference was accepted';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE '  ok: cross-tenant contact->account reference rejected';
  END;

  BEGIN
    INSERT INTO deals (organization_id, name, pipeline_id, stage_id)
      VALUES (v_org_b, 'Stolen', v_pipeline, v_stage_new);  -- pipeline is org A's
    RAISE EXCEPTION 'FAIL: cross-tenant pipeline reference was accepted';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE '  ok: cross-tenant deal->pipeline reference rejected';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 7. immutable organization_id ---';
  -- =========================================================================
  BEGIN
    UPDATE accounts SET organization_id = v_org_b WHERE id = v_account;
    RAISE EXCEPTION 'FAIL: organization_id was rewritten';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: organization_id is immutable';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 8. audit trail ---';
  -- =========================================================================
  PERFORM set_config('app.audit_reason', 'test: discount applied', false);
  UPDATE deals SET amount = 900 WHERE id = v_deal;

  SELECT count(*) INTO v_count FROM audit_log
   WHERE table_name = 'deals' AND record_id = v_deal
     AND action = 'update' AND 'amount' = ANY(changed_fields);
  IF v_count < 1 THEN
    RAISE EXCEPTION 'FAIL: audit row missing for deal amount change';
  END IF;
  RAISE NOTICE '  ok: field-level change captured in audit_log';

  SELECT count(*) INTO v_count FROM audit_log
   WHERE table_name = 'deals' AND record_id = v_deal
     AND reason = 'test: discount applied';
  IF v_count < 1 THEN
    RAISE EXCEPTION 'FAIL: audit reason not recorded';
  END IF;
  RAISE NOTICE '  ok: audit reason recorded';

  -- updated_at alone must not generate an audit row.
  SELECT count(*) INTO v_count FROM audit_log WHERE record_id = v_deal;
  UPDATE deals SET amount = 900 WHERE id = v_deal;  -- same value, no real change
  SELECT count(*) - v_count INTO v_count FROM audit_log WHERE record_id = v_deal;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: no-op update produced % audit rows', v_count;
  END IF;
  RAISE NOTICE '  ok: no-op update produced no audit noise';

  -- Agent attribution.
  PERFORM set_config('app.current_agent', 'lead-qualifier', false);
  UPDATE deals SET amount = 950 WHERE id = v_deal;
  SELECT count(*) INTO v_count FROM audit_log
   WHERE record_id = v_deal AND actor_type = 'agent' AND actor_agent = 'lead-qualifier';
  IF v_count < 1 THEN
    RAISE EXCEPTION 'FAIL: agent-attributed change not recorded as agent';
  END IF;
  RAISE NOTICE '  ok: agent writes are attributed to the named agent';
  PERFORM set_config('app.current_agent', '', false);

  -- Soft delete is recorded as a delete, not an update.
  UPDATE service_jobs SET deleted_at = now() WHERE id = v_job;
  SELECT count(*) INTO v_count FROM audit_log
   WHERE table_name = 'service_jobs' AND record_id = v_job AND action = 'delete';
  IF v_count < 1 THEN
    RAISE EXCEPTION 'FAIL: soft delete not classified as delete';
  END IF;
  RAISE NOTICE '  ok: soft delete classified correctly';
  UPDATE service_jobs SET deleted_at = NULL WHERE id = v_job;

  -- Agent activity must name the agent.
  BEGIN
    INSERT INTO activities (organization_id, kind, entity_type, entity_id, actor_type)
      VALUES (v_org_a, 'note', 'deal', v_deal, 'agent');
    RAISE EXCEPTION 'FAIL: agent activity without an agent name was accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: agent activity requires a named agent';
  END;

  RAISE NOTICE '';
  RAISE NOTICE '=== ALL FUNCTIONAL ASSERTIONS PASSED ===';
END;
$$;
