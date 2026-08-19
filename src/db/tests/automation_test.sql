-- automation_test.sql
-- Exercises the automation engine and, mostly, the approval gate.
--
-- The gate is the part worth testing hardest, because every failure mode is
-- silent: an action that proceeds when it should have paused, a pause that
-- blocks a worker, an unanswered prompt treated as a yes. Each of those has an
-- assertion here, including the one CLAUDE.md §3 states outright — silence is
-- never consent.
--
-- Requires the fixture from functional_test.sql (org-a).
--
--   psql -d yourider -v ON_ERROR_STOP=1 -f src/db/tests/automation_test.sql

\set ON_ERROR_STOP on

DO $$
DECLARE
  v_org        uuid;
  v_user       uuid;
  v_auto       uuid;
  v_auto_ro    uuid;
  v_auto_full  uuid;
  v_auto_bg    uuid;
  v_auto_retry uuid;
  v_run        uuid;
  v_run2       uuid;
  v_claimed    uuid;
  v_ticket     step_ticket;
  v_req        uuid;
  v_job        uuid;
  v_status     automation_run_status;
  v_sstatus    automation_step_status;
  v_decision   approval_decision;
  v_code       text;
  v_text       text;
  v_count      int;
  v_version    int;
  v_class      command_class;
  v_tier       autonomy_tier;
  v_expected   text;
  v_actual     text;
  v_claimed_by text;
  v_next       timestamptz;

  -- write then network: the second action is what the gate has to catch.
  c_actions jsonb := '[
    {"kind": "create_task",  "command_class": "write"},
    {"kind": "send_email",   "command_class": "network"}
  ]'::jsonb;
BEGIN
  SELECT id INTO v_org  FROM organizations WHERE slug = 'org-a';
  SELECT id INTO v_user FROM users WHERE email = 'a@example.com';
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'fixture missing: run functional_test.sql first';
  END IF;

  PERFORM set_config('app.current_org_id', v_org::text, false);
  PERFORM set_config('app.current_user_id', v_user::text, false);

  -- =========================================================================
  RAISE NOTICE '--- 1. the gate matrix (CLAUDE.md §3) ---';
  -- =========================================================================
  FOREACH v_class IN ARRAY ARRAY['read','write','network','install','destructive']::command_class[]
  LOOP
    FOREACH v_tier IN ARRAY ARRAY['read_only','supervised','full']::autonomy_tier[]
    LOOP
      v_expected := CASE
        WHEN v_class = 'read' THEN 'proceed'
        WHEN v_tier = 'read_only' THEN 'blocked'
        WHEN v_class = 'destructive' THEN 'approve'
        WHEN v_tier = 'supervised' THEN
          CASE WHEN v_class = 'write' THEN 'proceed' ELSE 'approve' END
        ELSE 'proceed'
      END;
      v_actual := app.gate_verdict(v_class, v_tier);
      IF v_actual IS DISTINCT FROM v_expected THEN
        RAISE EXCEPTION 'FAIL: % at tier % gave %, expected %',
          v_class, v_tier, v_actual, v_expected;
      END IF;
    END LOOP;
  END LOOP;
  RAISE NOTICE '  ok: all 15 class/tier combinations match the documented matrix';

  -- The two rules most easily lost in a refactor, asserted by name.
  IF app.gate_verdict('destructive', 'full') <> 'approve' THEN
    RAISE EXCEPTION 'FAIL: destructive did not pause at the full tier';
  END IF;
  RAISE NOTICE '  ok: destructive pauses even at the full tier';

  IF app.gate_verdict('write', 'read_only') <> 'blocked' THEN
    RAISE EXCEPTION 'FAIL: read-only tier queued a write for approval';
  END IF;
  RAISE NOTICE '  ok: read-only blocks outright rather than prompting';

  -- =========================================================================
  RAISE NOTICE '--- 2. versions and enqueue ---';
  -- =========================================================================
  INSERT INTO automations (organization_id, name, is_active, autonomy, agent_name)
    VALUES (v_org, 'Notify on negotiation', true, 'supervised', 'sales-agent')
    RETURNING id INTO v_auto;

  BEGIN
    PERFORM app.enqueue_automation_run(v_auto);
    RAISE EXCEPTION 'FAIL: enqueued an automation with no published version';
  EXCEPTION WHEN no_data_found THEN
    RAISE NOTICE '  ok: an automation with no published version cannot run';
  END;

  v_version := app.publish_automation_version(
    v_auto, 'stage_changed', '{"to": "Negotiation"}'::jsonb, '[]'::jsonb, c_actions);
  IF v_version <> 1 THEN
    RAISE EXCEPTION 'FAIL: first version numbered %', v_version;
  END IF;
  RAISE NOTICE '  ok: version 1 published';

  v_run := app.enqueue_automation_run(
    v_auto, 'deal', gen_random_uuid(), '{"reason":"test"}'::jsonb, 'evt-1');

  SELECT count(*) INTO v_count FROM automation_steps WHERE run_id = v_run;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'FAIL: % steps materialised, expected 2', v_count;
  END IF;
  RAISE NOTICE '  ok: steps materialised from the pinned version';

  -- A twice-delivered webhook runs once.
  v_run2 := app.enqueue_automation_run(
    v_auto, 'deal', gen_random_uuid(), '{"reason":"replay"}'::jsonb, 'evt-1');
  IF v_run2 <> v_run THEN
    RAISE EXCEPTION 'FAIL: a replayed event created a second run';
  END IF;
  RAISE NOTICE '  ok: a replayed event is deduplicated to the same run';

  -- An action with no declared class is refused rather than defaulting to
  -- something permissive.
  BEGIN
    PERFORM app.publish_automation_version(
      v_auto, 'manual', '{}'::jsonb, '[]'::jsonb,
      '[{"kind": "mystery"}]'::jsonb);
    PERFORM app.enqueue_automation_run(v_auto, NULL, NULL, '{}'::jsonb, 'evt-classless');
    RAISE EXCEPTION 'FAIL: an action with no command_class was accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: an action must declare its command class';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 3. claiming and the write step ---';
  -- =========================================================================
  v_claimed := app.claim_automation_run('worker-1');
  IF v_claimed IS NULL THEN
    RAISE EXCEPTION 'FAIL: nothing claimable';
  END IF;

  SELECT status, claimed_by INTO v_status, v_claimed_by
    FROM automation_runs WHERE id = v_claimed;
  IF v_status <> 'running' OR v_claimed_by <> 'worker-1' THEN
    RAISE EXCEPTION 'FAIL: claim left status % worker %', v_status, v_claimed_by;
  END IF;
  RAISE NOTICE '  ok: a claimed run is running and leased to its worker';

  v_ticket := app.begin_step(v_claimed);
  IF v_ticket.verdict <> 'proceed' OR v_ticket.command_class <> 'write' THEN
    RAISE EXCEPTION 'FAIL: first step gave % for %', v_ticket.verdict, v_ticket.command_class;
  END IF;
  RAISE NOTICE '  ok: a write proceeds at the supervised tier without prompting';

  PERFORM app.complete_step(v_ticket.step_id, '{"task_id":"abc"}'::jsonb);

  -- =========================================================================
  RAISE NOTICE '--- 4. a network step suspends and RELEASES the worker ---';
  -- =========================================================================
  v_ticket := app.begin_step(v_claimed);
  IF v_ticket.verdict <> 'approve' THEN
    RAISE EXCEPTION 'FAIL: a network action gave verdict %', v_ticket.verdict;
  END IF;
  v_req := v_ticket.approval_id;

  SELECT status, claimed_by INTO v_status, v_claimed_by
    FROM automation_runs WHERE id = v_claimed;
  IF v_status <> 'waiting_approval' THEN
    RAISE EXCEPTION 'FAIL: run status is % after suspending', v_status;
  END IF;

  -- This is the assertion the whole design exists for. A blocking wait would
  -- hold a worker for as long as a person takes to answer.
  IF v_claimed_by IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: the worker is still holding the run (%)', v_claimed_by;
  END IF;
  RAISE NOTICE '  ok: suspending released the worker (claimed_by is null)';

  -- The prompt has to be something a person can decide on.
  SELECT summary INTO v_text FROM approval_requests WHERE id = v_req;
  IF v_text NOT LIKE '%sales-agent%' OR v_text NOT LIKE '%send_email%' THEN
    RAISE EXCEPTION 'FAIL: approval summary is not plain language: %', v_text;
  END IF;
  RAISE NOTICE '  ok: the request reads "%"', v_text;

  BEGIN
    INSERT INTO approval_requests (organization_id, run_id, step_id,
                                   command_class, autonomy, summary, expires_at)
      VALUES (v_org, v_claimed, v_ticket.step_id, 'network', 'supervised',
              'short', now() + interval '1 hour');
    RAISE EXCEPTION 'FAIL: an unreadable approval summary was accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: an approval request must say something a human can read';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 5. approving resumes the run ---';
  -- =========================================================================
  PERFORM app.decide_approval(v_req, 'approved', v_user, 'looks fine');

  SELECT status INTO v_status FROM automation_runs WHERE id = v_claimed;
  IF v_status <> 'queued' THEN
    RAISE EXCEPTION 'FAIL: an approved run is % rather than queued', v_status;
  END IF;
  RAISE NOTICE '  ok: approval re-queues the run for any worker';

  v_claimed := app.claim_automation_run('worker-2');
  v_ticket := app.begin_step(v_claimed);
  IF v_ticket.verdict <> 'proceed' OR v_ticket.command_class <> 'network' THEN
    RAISE EXCEPTION 'FAIL: the approved step gave %', v_ticket.verdict;
  END IF;
  RAISE NOTICE '  ok: the approved step proceeds, on a different worker';

  PERFORM app.complete_step(v_ticket.step_id, '{"sent":true}'::jsonb);
  v_ticket := app.begin_step(v_claimed);
  IF v_ticket.verdict <> 'done' THEN
    RAISE EXCEPTION 'FAIL: run did not finish (%)', v_ticket.verdict;
  END IF;
  SELECT status INTO v_status FROM automation_runs WHERE id = v_claimed;
  IF v_status <> 'succeeded' THEN
    RAISE EXCEPTION 'FAIL: finished run is %', v_status;
  END IF;
  RAISE NOTICE '  ok: with no steps left the run succeeds';

  -- A decision is recorded once.
  BEGIN
    UPDATE approval_requests SET decision = 'rejected' WHERE id = v_req;
    RAISE EXCEPTION 'FAIL: a decided request was re-decided';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: a recorded decision cannot be changed';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 6. silence is not consent ---';
  -- =========================================================================
  v_run := app.enqueue_automation_run(v_auto, NULL, NULL, '{}'::jsonb, 'evt-expire');
  v_claimed := app.claim_automation_run('worker-1');
  v_ticket := app.begin_step(v_claimed);          -- write
  PERFORM app.complete_step(v_ticket.step_id);
  v_ticket := app.begin_step(v_claimed);          -- network → suspends
  v_req := v_ticket.approval_id;

  -- now() is frozen inside this block, so the deadline is moved rather than
  -- waited for.
  UPDATE approval_requests
     SET requested_at = now() - interval '3 days', expires_at = now() - interval '1 day'
   WHERE id = v_req;

  SELECT app.expire_approvals() INTO v_count;
  IF v_count < 1 THEN
    RAISE EXCEPTION 'FAIL: the expiry sweep found nothing';
  END IF;

  SELECT decision INTO v_decision FROM approval_requests WHERE id = v_req;
  IF v_decision <> 'expired' THEN
    RAISE EXCEPTION 'FAIL: an unanswered request is %', v_decision;
  END IF;
  -- 'expired' rather than 'rejected': nobody said no, nobody said anything.
  RAISE NOTICE '  ok: an unanswered request expires, distinctly from rejection';

  SELECT status, error_code INTO v_status, v_code
    FROM automation_runs WHERE id = v_claimed;
  IF v_status <> 'failed' OR v_code <> 'approval_expired' THEN
    RAISE EXCEPTION 'FAIL: expired approval left the run % (%)', v_status, v_code;
  END IF;
  RAISE NOTICE '  ok: the action did not happen — the run failed, it did not proceed';

  BEGIN
    PERFORM app.decide_approval(v_req, 'approved', v_user);
    RAISE EXCEPTION 'FAIL: an expired request was answered';
  EXCEPTION WHEN no_data_found THEN
    RAISE NOTICE '  ok: a stale prompt cannot be answered later';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 7. unattended runs fail loudly ---';
  -- =========================================================================
  INSERT INTO automations (organization_id, name, is_active, autonomy,
                           agent_name, is_unattended)
    VALUES (v_org, 'Nightly enrichment', true, 'supervised', 'enrichment-agent', true)
    RETURNING id INTO v_auto_bg;
  PERFORM app.publish_automation_version(
    v_auto_bg, 'scheduled', '{}'::jsonb, '[]'::jsonb, c_actions);

  v_run := app.enqueue_automation_run(v_auto_bg, NULL, NULL, '{}'::jsonb, 'bg-1');
  v_claimed := app.claim_automation_run('worker-1');
  v_ticket := app.begin_step(v_claimed);          -- write proceeds
  PERFORM app.complete_step(v_ticket.step_id);
  v_ticket := app.begin_step(v_claimed);          -- network, nobody to ask

  IF v_ticket.verdict <> 'blocked' THEN
    RAISE EXCEPTION 'FAIL: unattended run gave verdict %', v_ticket.verdict;
  END IF;

  SELECT count(*) INTO v_count FROM approval_requests WHERE run_id = v_claimed;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: an unattended run raised a prompt nobody will see';
  END IF;

  SELECT status, error_code, error_message INTO v_status, v_code, v_text
    FROM automation_runs WHERE id = v_claimed;
  IF v_status <> 'failed' OR v_code <> 'approval_required_unattended' THEN
    RAISE EXCEPTION 'FAIL: unattended run ended % (%)', v_status, v_code;
  END IF;
  IF v_text IS NULL OR btrim(v_text) = '' THEN
    RAISE EXCEPTION 'FAIL: unattended failure recorded no reason';
  END IF;
  RAISE NOTICE '  ok: it failed loudly and logged why — not skipped, not proceeded';

  -- The write step before it did run, and stays succeeded: failing the run does
  -- not pretend the completed work never happened.
  SELECT status INTO v_sstatus FROM automation_steps
   WHERE run_id = v_claimed AND step_index = 0;
  IF v_sstatus <> 'succeeded' THEN
    RAISE EXCEPTION 'FAIL: the completed step was rewritten to %', v_sstatus;
  END IF;
  RAISE NOTICE '  ok: work already done is not retroactively undone';

  -- =========================================================================
  RAISE NOTICE '--- 8. tiers ---';
  -- =========================================================================
  INSERT INTO automations (organization_id, name, is_active, autonomy)
    VALUES (v_org, 'Report only', true, 'read_only') RETURNING id INTO v_auto_ro;
  PERFORM app.publish_automation_version(
    v_auto_ro, 'manual', '{}'::jsonb, '[]'::jsonb,
    '[{"kind":"create_task","command_class":"write"}]'::jsonb);

  v_run := app.enqueue_automation_run(v_auto_ro, NULL, NULL, '{}'::jsonb, 'ro-1');
  v_claimed := app.claim_automation_run('worker-1');
  v_ticket := app.begin_step(v_claimed);
  IF v_ticket.verdict <> 'blocked' THEN
    RAISE EXCEPTION 'FAIL: read-only tier gave % for a write', v_ticket.verdict;
  END IF;
  SELECT error_code INTO v_code FROM automation_runs WHERE id = v_claimed;
  IF v_code <> 'class_not_permitted' THEN
    RAISE EXCEPTION 'FAIL: blocked run reported %', v_code;
  END IF;
  RAISE NOTICE '  ok: a read-only automation cannot write, and is not prompted';

  -- The full tier is opt-in and has to be attributable to someone.
  BEGIN
    INSERT INTO automations (organization_id, name, autonomy)
      VALUES (v_org, 'Anonymous full', 'full');
    RAISE EXCEPTION 'FAIL: full tier granted with no named agent';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: the full tier must name the agent it was granted to';
  END;

  INSERT INTO automations (organization_id, name, is_active, autonomy, agent_name)
    VALUES (v_org, 'Cleanup', true, 'full', 'ops-agent') RETURNING id INTO v_auto_full;
  PERFORM app.publish_automation_version(
    v_auto_full, 'manual', '{}'::jsonb, '[]'::jsonb,
    '[{"kind":"purge_records","command_class":"destructive"}]'::jsonb);

  v_run := app.enqueue_automation_run(v_auto_full, NULL, NULL, '{}'::jsonb, 'full-1');
  v_claimed := app.claim_automation_run('worker-1');
  v_ticket := app.begin_step(v_claimed);
  IF v_ticket.verdict <> 'approve' THEN
    RAISE EXCEPTION 'FAIL: a destructive action at the full tier gave %', v_ticket.verdict;
  END IF;
  RAISE NOTICE '  ok: nothing is ever fully autonomous for a destructive action';

  PERFORM app.decide_approval(v_ticket.approval_id, 'rejected', v_user, 'not this time');
  SELECT status, error_code INTO v_status, v_code
    FROM automation_runs WHERE id = v_claimed;
  IF v_status <> 'failed' OR v_code <> 'approval_rejected' THEN
    RAISE EXCEPTION 'FAIL: rejection left the run % (%)', v_status, v_code;
  END IF;
  RAISE NOTICE '  ok: rejection stops the run, recorded as a decision';

  -- =========================================================================
  RAISE NOTICE '--- 9. retry is per step, not per run ---';
  -- =========================================================================
  INSERT INTO automations (organization_id, name, is_active, autonomy, agent_name)
    VALUES (v_org, 'Flaky sync', true, 'full', 'sync-agent')
    RETURNING id INTO v_auto_retry;
  PERFORM app.publish_automation_version(
    v_auto_retry, 'manual', '{}'::jsonb, '[]'::jsonb,
    '[{"kind":"push_to_erp","command_class":"network","max_attempts":2}]'::jsonb);

  v_run := app.enqueue_automation_run(v_auto_retry, NULL, NULL, '{}'::jsonb, 'retry-1');
  v_claimed := app.claim_automation_run('worker-1');
  v_ticket := app.begin_step(v_claimed);

  IF app.fail_step(v_ticket.step_id, 'timeout', 'upstream took too long') <> 'retry_scheduled' THEN
    RAISE EXCEPTION 'FAIL: first failure was not retried';
  END IF;
  SELECT status, claimed_by INTO v_status, v_claimed_by
    FROM automation_runs WHERE id = v_claimed;
  IF v_status <> 'waiting_until' OR v_claimed_by IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: backoff left the run % held by %', v_status, v_claimed_by;
  END IF;
  RAISE NOTICE '  ok: a retry suspends on a timer and releases the worker too';

  -- Nothing is claimable until the backoff passes.
  UPDATE automation_runs SET run_after = now() - interval '1 minute'
   WHERE id = v_claimed;
  UPDATE automation_steps SET run_after = now() - interval '1 minute'
   WHERE run_id = v_claimed;
  IF app.release_due_runs() < 1 THEN
    RAISE EXCEPTION 'FAIL: a due run was not released';
  END IF;

  v_claimed := app.claim_automation_run('worker-1');
  v_ticket := app.begin_step(v_claimed);
  IF app.fail_step(v_ticket.step_id, 'timeout', 'again') <> 'failed' THEN
    RAISE EXCEPTION 'FAIL: the attempt budget was not exhausted';
  END IF;
  SELECT status INTO v_status FROM automation_runs WHERE id = v_claimed;
  IF v_status <> 'failed' THEN
    RAISE EXCEPTION 'FAIL: exhausted retries left the run %', v_status;
  END IF;
  RAISE NOTICE '  ok: the attempt budget is finite and then the run fails';

  -- =========================================================================
  RAISE NOTICE '--- 10. a dead worker does not strand its run ---';
  -- =========================================================================
  v_run := app.enqueue_automation_run(v_auto, NULL, NULL, '{}'::jsonb, 'dead-1');
  v_claimed := app.claim_automation_run('worker-doomed');
  PERFORM app.begin_step(v_claimed);
  UPDATE automation_runs SET lease_expires_at = now() - interval '1 minute'
   WHERE id = v_claimed;

  IF app.reclaim_expired_runs() < 1 THEN
    RAISE EXCEPTION 'FAIL: an expired lease was not reclaimed';
  END IF;
  SELECT status, claimed_by INTO v_status, v_claimed_by
    FROM automation_runs WHERE id = v_claimed;
  IF v_status <> 'queued' OR v_claimed_by IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: reclaim left the run % held by %', v_status, v_claimed_by;
  END IF;
  SELECT status INTO v_sstatus FROM automation_steps
   WHERE run_id = v_claimed AND step_index = 0;
  IF v_sstatus <> 'pending' THEN
    RAISE EXCEPTION 'FAIL: the in-flight step was left % rather than retried', v_sstatus;
  END IF;
  RAISE NOTICE '  ok: an expired lease returns the run and its step to the queue';

  -- =========================================================================
  RAISE NOTICE '--- 11. a run is pinned to the version it started under ---';
  -- =========================================================================
  v_run := app.enqueue_automation_run(v_auto_full, NULL, NULL, '{}'::jsonb, 'pin-1');
  SELECT count(*) INTO v_count FROM automation_steps WHERE run_id = v_run;

  PERFORM app.publish_automation_version(
    v_auto_full, 'manual', '{}'::jsonb, '[]'::jsonb,
    '[{"kind":"a","command_class":"read"},
      {"kind":"b","command_class":"read"},
      {"kind":"c","command_class":"read"}]'::jsonb);

  SELECT count(*) INTO v_version FROM automation_steps WHERE run_id = v_run;
  IF v_version <> v_count THEN
    RAISE EXCEPTION 'FAIL: an in-flight run gained steps from a new version';
  END IF;
  RAISE NOTICE '  ok: editing an automation does not change a run already under way';

  -- =========================================================================
  RAISE NOTICE '--- 12. scheduled jobs materialise runs ---';
  -- =========================================================================
  INSERT INTO scheduled_jobs (organization_id, automation_id, name, recurrence,
                              next_run_at)
    VALUES (v_org, v_auto_ro, 'Every 15 minutes', interval '15 minutes',
            now() - interval '1 minute')
    RETURNING id INTO v_job;

  IF app.materialise_scheduled_runs() < 1 THEN
    RAISE EXCEPTION 'FAIL: a due job produced no run';
  END IF;

  SELECT next_run_at INTO v_next FROM scheduled_jobs WHERE id = v_job;
  IF v_next <= now() - interval '1 minute' THEN
    RAISE EXCEPTION 'FAIL: the schedule did not advance (%)', v_next;
  END IF;
  RAISE NOTICE '  ok: a due job produced one run and advanced its schedule';

  -- Two schedulers, or one retrying, must not double-fire a window.
  UPDATE scheduled_jobs SET next_run_at = now() - interval '1 minute'
   WHERE id = v_job;
  SELECT count(*) INTO v_count FROM automation_runs
   WHERE scheduled_job_id = v_job;
  PERFORM app.materialise_scheduled_runs();
  PERFORM app.materialise_scheduled_runs();
  SELECT count(*) INTO v_version FROM automation_runs WHERE scheduled_job_id = v_job;
  IF v_version > v_count + 1 THEN
    RAISE EXCEPTION 'FAIL: a window fired % times', v_version - v_count;
  END IF;
  RAISE NOTICE '  ok: a window fires once however often the scheduler runs';

  RAISE NOTICE '';
  RAISE NOTICE '=== ALL AUTOMATION ASSERTIONS PASSED ===';
END;
$$;
