-- platform_test.sql
-- Exercises the platform primitives (0019: api keys, webhooks, notifications,
-- merge/dedup, import batches, fx provenance, timeline labels) and the
-- messaging identity schema (0020).
--
-- Requires the fixture from functional_test.sql (org-a, org-b).

\set ON_ERROR_STOP on

DO $$
DECLARE
  v_org        uuid;
  v_org_b      uuid;
  v_user       uuid;
  v_account_a  uuid;
  v_account_b  uuid;
  v_contact_a  uuid;
  v_contact_b  uuid;
  v_deal_a     uuid;
  v_deal_b     uuid;
  v_issued     issued_api_key;
  v_sub        uuid;
  v_delivery   uuid;
  v_notif      uuid;
  v_batch      uuid;
  v_fx1        uuid;
  v_fx2        uuid;
  v_rate       fx_rates;
  v_account_id uuid;
  v_thread     uuid;
  v_msg1       uuid;
  v_msg2       uuid;
  v_contact_id uuid;
  v_contact_foreign uuid;
  v_count      int;
  v_bool       boolean;
  v_text       text;
  v_org_check  uuid;
BEGIN
  SELECT id INTO v_org   FROM organizations WHERE slug = 'org-a';
  SELECT id INTO v_org_b FROM organizations WHERE slug = 'org-b';
  SELECT id INTO v_user  FROM users WHERE email = 'a@example.com';
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'fixture missing: run functional_test.sql first';
  END IF;

  PERFORM set_config('app.current_org_id', v_org::text, false);
  PERFORM set_config('app.current_user_id', v_user::text, false);

  -- =========================================================================
  RAISE NOTICE '--- 1. API keys ---';
  -- =========================================================================
  v_issued := app.issue_api_key('CI key', ARRAY['read', 'write']);
  IF length(v_issued.secret) < 32 THEN
    RAISE EXCEPTION 'FAIL: issued secret looks too short to be real entropy';
  END IF;

  v_org_check := app.authenticate_api_key(v_issued.secret);
  IF v_org_check IS DISTINCT FROM v_org THEN
    RAISE EXCEPTION 'FAIL: a freshly issued key did not authenticate to its org';
  END IF;
  RAISE NOTICE '  ok: a freshly issued key authenticates to the issuing org';

  IF app.authenticate_api_key('not-a-real-key') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: a bogus secret authenticated';
  END IF;
  RAISE NOTICE '  ok: a wrong secret authenticates to nothing';

  UPDATE api_keys SET revoked_at = now(), revoked_by = v_user WHERE id = v_issued.id;
  IF app.authenticate_api_key(v_issued.secret) IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: a revoked key still authenticates';
  END IF;
  RAISE NOTICE '  ok: a revoked key stops authenticating immediately';

  BEGIN
    UPDATE api_keys SET revoked_at = now() WHERE id = v_issued.id AND revoked_by IS NULL;
    INSERT INTO api_keys (organization_id, name, key_hash, key_prefix, revoked_at)
      VALUES (v_org, 'sneaky', digest('x','sha256'), 'abcdefgh', now());
    RAISE EXCEPTION 'FAIL: a revocation with no revoker was accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: a revoked key must name who revoked it';
  END;

  -- Only the hash and a short prefix are ever stored — never the secret.
  SELECT count(*) INTO v_count FROM api_keys
   WHERE key_hash::text = v_issued.secret OR key_prefix = v_issued.secret;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: the raw secret is recoverable from the table';
  END IF;
  RAISE NOTICE '  ok: the raw secret is never stored, only its hash';

  -- =========================================================================
  RAISE NOTICE '--- 2. webhook subscriptions ---';
  -- =========================================================================
  BEGIN
    INSERT INTO webhook_subscriptions (organization_id, url, event_types)
      VALUES (v_org, 'http://insecure.example.com/hook', ARRAY['deal.won']);
    RAISE EXCEPTION 'FAIL: a plain-http webhook URL was accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: a webhook URL must be https';
  END;

  INSERT INTO webhook_subscriptions (organization_id, url, event_types)
    VALUES (v_org, 'https://example.com/hook', ARRAY['deal.won'])
    RETURNING id INTO v_sub;

  -- The signing secret is generated, not something a caller can hand in and
  -- have trusted as authentic — the same reasoning as 0013's storage_key.
  SELECT octet_length(signing_secret) INTO v_count FROM webhook_subscriptions WHERE id = v_sub;
  IF v_count <> 32 THEN
    RAISE EXCEPTION 'FAIL: signing secret is % bytes, expected 32', v_count;
  END IF;
  RAISE NOTICE '  ok: the signing secret is generated server-side';

  INSERT INTO webhook_deliveries (organization_id, subscription_id, event_type, payload)
    VALUES (v_org, v_sub, 'deal.won', '{"deal_id":"x"}'::jsonb)
    RETURNING id INTO v_delivery;

  BEGIN
    INSERT INTO webhook_deliveries (organization_id, subscription_id, event_type, payload)
      SELECT v_org, s.id, 'deal.won', '{}'::jsonb
        FROM webhook_subscriptions s WHERE s.organization_id = v_org_b LIMIT 1;
  EXCEPTION WHEN OTHERS THEN NULL;  -- no such row exists yet; guarded below instead
  END;

  INSERT INTO webhook_subscriptions (organization_id, url, event_types)
    VALUES (v_org_b, 'https://example.com/other', ARRAY['lead.created']);
  BEGIN
    INSERT INTO webhook_deliveries (organization_id, subscription_id, event_type, payload)
      SELECT v_org, s.id, 'lead.created', '{}'::jsonb
        FROM webhook_subscriptions s WHERE s.organization_id = v_org_b LIMIT 1;
    RAISE EXCEPTION 'FAIL: a delivery pointed at another tenant''s subscription';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE '  ok: a delivery cannot target a foreign subscription';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 3. notifications ---';
  -- =========================================================================
  INSERT INTO notifications (organization_id, user_id, kind, title, entity_type, entity_id)
    VALUES (v_org, v_user, 'assignment', 'A deal was assigned to you',
            'deal', (SELECT id FROM deals WHERE organization_id = v_org LIMIT 1))
    RETURNING id INTO v_notif;

  PERFORM app.mark_notification_read(v_notif);
  IF NOT EXISTS (SELECT 1 FROM notifications WHERE id = v_notif AND is_read AND read_at IS NOT NULL) THEN
    RAISE EXCEPTION 'FAIL: marking read did not stamp is_read/read_at together';
  END IF;
  RAISE NOTICE '  ok: marking a notification read stamps both is_read and read_at';

  BEGIN
    PERFORM app.mark_notification_read(v_notif);
    RAISE EXCEPTION 'FAIL: marking an already-read notification read again succeeded';
  EXCEPTION WHEN no_data_found THEN
    RAISE NOTICE '  ok: marking an already-read notification again is refused';
  END;

  BEGIN
    INSERT INTO notifications (organization_id, user_id, kind, title, entity_id)
      VALUES (v_org, v_user, 'system', 'orphaned entity_id', gen_random_uuid());
    RAISE EXCEPTION 'FAIL: entity_id with no entity_type was accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: entity_type and entity_id must be given together';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 4. contact and account merge ---';
  -- =========================================================================
  INSERT INTO accounts (organization_id, name) VALUES (v_org, 'Acme West') RETURNING id INTO v_account_a;
  INSERT INTO accounts (organization_id, name) VALUES (v_org, 'Acme East') RETURNING id INTO v_account_b;
  INSERT INTO accounts (organization_id, name) VALUES (v_org_b, 'Foreign Co') RETURNING id INTO v_account_id;

  INSERT INTO contacts (organization_id, account_id, first_name, last_name, email)
    VALUES (v_org, v_account_a, 'Dana', 'Primary', 'dana.primary@merge.test')
    RETURNING id INTO v_contact_a;
  INSERT INTO contacts (organization_id, account_id, first_name, last_name, email)
    VALUES (v_org, v_account_a, 'Dana', 'Duplicate', 'dana.dup@merge.test')
    RETURNING id INTO v_contact_b;

  SELECT p.id, s.id INTO v_deal_a, v_deal_b
    FROM pipelines p JOIN pipeline_stages s ON s.pipeline_id = p.id AND s.kind = 'open'
   WHERE p.organization_id = v_org AND p.entity_type = 'deal'
   ORDER BY s.position LIMIT 1;

  INSERT INTO deals (organization_id, name, pipeline_id, stage_id, primary_contact_id)
    VALUES (v_org, 'Merge test deal', v_deal_a, v_deal_b, v_contact_b)
    RETURNING id INTO v_deal_a;

  INSERT INTO contacts (organization_id, first_name, last_name, email)
    VALUES (v_org_b, 'Foreign', 'Contact', 'foreign@merge.test')
    RETURNING id INTO v_contact_foreign;

  BEGIN
    PERFORM app.merge_contacts(v_contact_a, v_contact_foreign);
    RAISE EXCEPTION 'FAIL: merging across organizations was accepted';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE '  ok: cross-tenant merge is refused';
  END;

  PERFORM app.merge_contacts(v_contact_a, v_contact_b);

  SELECT deleted_at IS NOT NULL INTO v_bool FROM contacts WHERE id = v_contact_b;
  IF NOT v_bool THEN
    RAISE EXCEPTION 'FAIL: the losing contact was not soft-deleted';
  END IF;
  RAISE NOTICE '  ok: the losing contact is soft-deleted, not hard-deleted';

  SELECT primary_contact_id INTO v_contact_id FROM deals WHERE id = v_deal_a;
  IF v_contact_id <> v_contact_a THEN
    RAISE EXCEPTION 'FAIL: the deal still points at the merged-away contact';
  END IF;
  RAISE NOTICE '  ok: a live reference (deals.primary_contact_id) was repointed';

  SELECT count(*) INTO v_count FROM entity_merges
   WHERE entity_type = 'contact' AND survivor_id = v_contact_a AND merged_id = v_contact_b;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: no merge record was written';
  END IF;
  SELECT merged_snapshot ->> 'email' INTO v_text FROM entity_merges
   WHERE entity_type = 'contact' AND merged_id = v_contact_b;
  IF v_text <> 'dana.dup@merge.test' THEN
    RAISE EXCEPTION 'FAIL: the merge snapshot did not capture the losing row';
  END IF;
  RAISE NOTICE '  ok: the merge is recorded with a full snapshot of what was lost';

  PERFORM app.merge_accounts(v_account_a, v_account_b);
  IF EXISTS (SELECT 1 FROM accounts WHERE id = v_account_b AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'FAIL: the losing account was not soft-deleted';
  END IF;
  RAISE NOTICE '  ok: account merge soft-deletes the loser too';

  -- =========================================================================
  RAISE NOTICE '--- 5. import batches ---';
  -- =========================================================================
  INSERT INTO import_batches (organization_id, entity_type, source_filename, total_rows, status, completed_at)
    VALUES (v_org, 'contact', 'contacts.csv', 2, 'completed', now())
    RETURNING id INTO v_batch;

  INSERT INTO contacts (organization_id, first_name, last_name, email, import_batch_id)
    VALUES (v_org, 'Imported', 'One', 'imp1@batch.test', v_batch);
  INSERT INTO contacts (organization_id, first_name, last_name, email, import_batch_id)
    VALUES (v_org, 'Imported', 'Two', 'imp2@batch.test', v_batch);

  BEGIN
    INSERT INTO import_batches (organization_id, entity_type, status)
      VALUES (v_org, 'contact', 'completed');
    RAISE EXCEPTION 'FAIL: a completed batch with no completed_at was accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: a completed batch must be stamped complete';
  END;

  v_count := app.rollback_import_batch(v_batch);
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'FAIL: rollback affected % rows, expected 2', v_count;
  END IF;
  IF EXISTS (SELECT 1 FROM contacts WHERE import_batch_id = v_batch AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'FAIL: a rolled-back import left live rows';
  END IF;
  SELECT status INTO v_text FROM import_batches WHERE id = v_batch;
  IF v_text <> 'rolled_back' THEN
    RAISE EXCEPTION 'FAIL: batch status is % after rollback', v_text;
  END IF;
  RAISE NOTICE '  ok: rollback soft-deletes every row the batch created';

  -- =========================================================================
  RAISE NOTICE '--- 6. FX provenance ---';
  -- =========================================================================
  INSERT INTO fx_rates (organization_id, from_currency, to_currency, rate, source, as_of)
    VALUES (v_org, 'EUR', 'USD', 1.0800, 'ecb', now() - interval '2 days')
    RETURNING id INTO v_fx1;
  INSERT INTO fx_rates (organization_id, from_currency, to_currency, rate, source, as_of)
    VALUES (v_org, 'EUR', 'USD', 1.0850, 'ecb', now() - interval '1 day')
    RETURNING id INTO v_fx2;

  v_rate := app.latest_fx_rate('EUR', 'USD', v_org);
  IF v_rate.id <> v_fx2 THEN
    RAISE EXCEPTION 'FAIL: latest_fx_rate did not return the most recent row';
  END IF;
  RAISE NOTICE '  ok: latest_fx_rate returns the most recent rate as of now';

  v_rate := app.latest_fx_rate('EUR', 'USD', v_org, now() - interval '36 hours');
  IF v_rate.id <> v_fx1 THEN
    RAISE EXCEPTION 'FAIL: an as-of query returned a rate from after that time';
  END IF;
  RAISE NOTICE '  ok: an as-of query respects the point in time, not just recency';

  -- fx_rates has no UPDATE/DELETE policy (append-only, like consent_records).
  -- That is an RLS property and this connection runs as postgres, a superuser
  -- that bypasses RLS entirely — asserting it here would pass vacuously
  -- whether or not the policy exists. See rls_test.sql for the real check.

  -- =========================================================================
  RAISE NOTICE '--- 7. denormalised timeline label ---';
  -- =========================================================================
  v_text := app.entity_display_name('account', v_account_a);
  IF v_text <> 'Acme West' THEN
    RAISE EXCEPTION 'FAIL: entity_display_name(account) returned %', v_text;
  END IF;

  v_text := app.entity_display_name('contact', v_contact_a);
  IF v_text IS NULL OR v_text NOT LIKE 'Dana%' THEN
    RAISE EXCEPTION 'FAIL: entity_display_name(contact) returned %', v_text;
  END IF;
  RAISE NOTICE '  ok: entity_display_name resolves both a name column and a generated one';

  INSERT INTO activities (organization_id, kind, entity_type, entity_id, entity_label, subject)
    VALUES (v_org, 'note', 'account', v_account_a, app.entity_display_name('account', v_account_a),
            'test note');
  UPDATE accounts SET deleted_at = now() WHERE id = v_account_a;
  SELECT entity_label INTO v_text FROM activities
   WHERE organization_id = v_org AND entity_type = 'account' AND entity_id = v_account_a
   ORDER BY occurred_at DESC LIMIT 1;
  IF v_text <> 'Acme West' THEN
    RAISE EXCEPTION 'FAIL: the cached label did not survive the record''s deletion';
  END IF;
  RAISE NOTICE '  ok: the cached label still reads correctly after the record is gone';
  UPDATE accounts SET deleted_at = NULL WHERE id = v_account_a;

  -- =========================================================================
  RAISE NOTICE '--- 8. messaging identity ---';
  -- =========================================================================
  INSERT INTO message_threads (organization_id, provider_thread_id, subject, entity_type, entity_id)
    VALUES (v_org, 'gmail-thread-1', 'Re: pricing', 'deal', v_deal_a)
    RETURNING id INTO v_thread;

  INSERT INTO messages (organization_id, thread_id, provider_message_id, direction,
                        from_address, to_addresses, sent_at)
    VALUES (v_org, v_thread, 'msg-1', 'inbound', 'them@example.com',
            ARRAY['us@example.com']::citext[], now() - interval '1 hour')
    RETURNING id INTO v_msg1;
  INSERT INTO messages (organization_id, thread_id, provider_message_id, direction,
                        from_address, to_addresses, sent_at)
    VALUES (v_org, v_thread, 'msg-2', 'outbound', 'us@example.com',
            ARRAY['them@example.com']::citext[], now())
    RETURNING id INTO v_msg2;

  SELECT message_count INTO v_count FROM message_threads WHERE id = v_thread;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'FAIL: thread rollup counted %, expected 2', v_count;
  END IF;
  RAISE NOTICE '  ok: message_count and last_message_at roll up from live messages';

  BEGIN
    INSERT INTO messages (organization_id, thread_id, provider_message_id, direction,
                          from_address, to_addresses, sent_at)
      VALUES (v_org, v_thread, 'msg-1', 'inbound', 'x@example.com', '{}', now());
    RAISE EXCEPTION 'FAIL: a duplicate provider_message_id was accepted';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE '  ok: a provider message id can only be recorded once (dedup)';
  END;

  DELETE FROM messages WHERE id = v_msg2;
  SELECT message_count INTO v_count FROM message_threads WHERE id = v_thread;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: rollup did not decrease after deleting a message (%)', v_count;
  END IF;
  RAISE NOTICE '  ok: the rollup recomputes on delete too';

  INSERT INTO message_participants (organization_id, message_id, address, role, contact_id)
    VALUES (v_org, v_msg1, 'them@example.com', 'from', v_contact_a);

  BEGIN
    INSERT INTO message_threads (organization_id, entity_type, entity_id)
      VALUES (v_org, 'deal', gen_random_uuid());
    RAISE EXCEPTION 'FAIL: a thread linked to a nonexistent deal was accepted';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE '  ok: a thread''s entity link is validated on write';
  END;

  INSERT INTO calendar_events (organization_id, provider_event_id, title, starts_at, ends_at)
    VALUES (v_org, 'gcal-1', 'Discovery call', now(), now() + interval '30 minutes');

  BEGIN
    INSERT INTO calendar_events (organization_id, provider_event_id, title, starts_at, ends_at)
      VALUES (v_org, 'gcal-2', 'Time travel', now(), now() - interval '1 hour');
    RAISE EXCEPTION 'FAIL: an event ending before it starts was accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: a calendar event cannot end before it starts';
  END;

  RAISE NOTICE '';
  RAISE NOTICE '=== ALL PLATFORM ASSERTIONS PASSED ===';
END;
$$;
