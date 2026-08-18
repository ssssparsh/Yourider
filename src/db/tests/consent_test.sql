-- consent_test.sql
-- Exercises the consent ledger and the outbound gate.
--
-- The precedence rules are where a gate like this goes wrong, so they are
-- tested explicitly rather than assumed:
--
--   suppression  >  legacy opt-out  >  transactional  >  recorded consent
--
-- Requires the fixture from functional_test.sql (org-a and its contacts).
--
--   psql -d yourider -v ON_ERROR_STOP=1 -f src/db/tests/consent_test.sql

\set ON_ERROR_STOP on

DO $$
DECLARE
  v_org        uuid;
  v_user       uuid;
  v_contact    uuid;
  v_ch_email   uuid;
  v_ch_sms     uuid;
  v_p_market   uuid;
  v_p_txn      uuid;
  v_p_doi      uuid;
  v_p_ttl      uuid;
  v_verdict    send_verdict;
  v_rec        uuid;
  v_evt        uuid;
  v_evt2       uuid;
  v_count      int;
  v_state      consent_state_kind;
BEGIN
  SELECT id INTO v_org FROM organizations WHERE slug = 'org-a';
  SELECT id INTO v_user FROM users WHERE email = 'a@example.com';
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'fixture missing: run functional_test.sql first';
  END IF;

  PERFORM set_config('app.current_org_id', v_org::text, false);
  PERFORM set_config('app.current_user_id', v_user::text, false);

  SELECT id INTO v_contact FROM contacts
   WHERE organization_id = v_org AND deleted_at IS NULL LIMIT 1;
  IF v_contact IS NULL THEN
    RAISE EXCEPTION 'fixture missing: expected at least one contact in org-a';
  END IF;

  -- =========================================================================
  RAISE NOTICE '--- 1. channels ---';
  -- =========================================================================
  INSERT INTO contact_channels (organization_id, contact_id, channel_type, address, is_primary)
    VALUES (v_org, v_contact, 'email', 'dana@acme.test', true)
    RETURNING id INTO v_ch_email;

  INSERT INTO contact_channels (organization_id, contact_id, channel_type, address, is_primary)
    VALUES (v_org, v_contact, 'sms', '+15550100', true)
    RETURNING id INTO v_ch_sms;
  RAISE NOTICE '  ok: email and sms channels created';

  -- Malformed addresses must be rejected at the database, not in a form handler.
  BEGIN
    INSERT INTO contact_channels (organization_id, contact_id, channel_type, address)
      VALUES (v_org, v_contact, 'sms', '555-0100');
    RAISE EXCEPTION 'FAIL: non-E.164 phone number accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: non-E.164 phone rejected';
  END;

  BEGIN
    INSERT INTO contact_channels (organization_id, contact_id, channel_type, address)
      VALUES (v_org, v_contact, 'email', 'not-an-address');
    RAISE EXCEPTION 'FAIL: malformed email accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: malformed email rejected';
  END;

  -- Two primaries for one channel type is a data bug, not a preference.
  BEGIN
    INSERT INTO contact_channels (organization_id, contact_id, channel_type, address, is_primary)
      VALUES (v_org, v_contact, 'email', 'second@acme.test', true);
    RAISE EXCEPTION 'FAIL: a second primary email was allowed';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE '  ok: only one primary channel per type';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 2. purposes ---';
  -- =========================================================================
  INSERT INTO consent_purposes (organization_id, key, name, is_transactional)
    VALUES (v_org, 'marketing', 'Marketing email', false) RETURNING id INTO v_p_market;

  INSERT INTO consent_purposes (organization_id, key, name, is_transactional)
    VALUES (v_org, 'booking_confirmation', 'Booking confirmations', true)
    RETURNING id INTO v_p_txn;

  INSERT INTO consent_purposes (organization_id, key, name, requires_double_optin)
    VALUES (v_org, 'newsletter', 'Newsletter', true) RETURNING id INTO v_p_doi;

  INSERT INTO consent_purposes (organization_id, key, name, default_ttl)
    VALUES (v_org, 'research', 'Research invitations', interval '1 second')
    RETURNING id INTO v_p_ttl;
  RAISE NOTICE '  ok: four purposes defined';

  -- A transactional purpose requiring confirmation is contradictory.
  BEGIN
    INSERT INTO consent_purposes (organization_id, key, name, is_transactional, requires_double_optin)
      VALUES (v_org, 'bad', 'Contradictory', true, true);
    RAISE EXCEPTION 'FAIL: transactional + double opt-in accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: transactional purpose cannot require double opt-in';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 3. no consent means no send ---';
  -- =========================================================================
  v_verdict := app.can_send(v_ch_email, v_p_market);
  IF v_verdict.allowed OR v_verdict.reason <> 'no_consent_recorded' THEN
    RAISE EXCEPTION 'FAIL: expected no_consent_recorded, got (%, %)',
      v_verdict.allowed, v_verdict.reason;
  END IF;
  RAISE NOTICE '  ok: unrecorded consent denies (deny by default)';

  -- Transactional does not need consent.
  v_verdict := app.can_send(v_ch_email, v_p_txn);
  IF NOT v_verdict.allowed OR v_verdict.reason <> 'transactional' THEN
    RAISE EXCEPTION 'FAIL: transactional purpose should send, got (%, %)',
      v_verdict.allowed, v_verdict.reason;
  END IF;
  RAISE NOTICE '  ok: transactional purpose sends without consent';

  -- =========================================================================
  RAISE NOTICE '--- 4. grant, withdraw, regrant ---';
  -- =========================================================================
  v_rec := app.record_consent(v_ch_email, v_p_market, 'granted', 'web_form',
             '{"ip":"203.0.113.4","form_url":"https://example.test/signup"}'::jsonb);

  v_verdict := app.can_send(v_ch_email, v_p_market);
  IF NOT v_verdict.allowed THEN
    RAISE EXCEPTION 'FAIL: granted consent should allow, got (%, %)',
      v_verdict.allowed, v_verdict.reason;
  END IF;
  RAISE NOTICE '  ok: granted consent allows sending';

  PERFORM app.record_consent(v_ch_email, v_p_market, 'withdrawn', 'unsubscribe_link');
  v_verdict := app.can_send(v_ch_email, v_p_market);
  IF v_verdict.allowed OR v_verdict.reason <> 'consent_withdrawn' THEN
    RAISE EXCEPTION 'FAIL: withdrawal should deny, got (%, %)',
      v_verdict.allowed, v_verdict.reason;
  END IF;
  RAISE NOTICE '  ok: withdrawal denies sending';

  -- The ledger keeps every step; only the cache moves.
  SELECT count(*) INTO v_count FROM consent_records
   WHERE channel_id = v_ch_email AND purpose_id = v_p_market;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'FAIL: expected 2 ledger rows, found %', v_count;
  END IF;
  RAISE NOTICE '  ok: ledger retains full history (% rows)', v_count;

  PERFORM app.record_consent(v_ch_email, v_p_market, 'granted', 'preference_centre');
  v_verdict := app.can_send(v_ch_email, v_p_market);
  IF NOT v_verdict.allowed THEN
    RAISE EXCEPTION 'FAIL: re-grant should allow again';
  END IF;
  RAISE NOTICE '  ok: consent can be re-granted after withdrawal';

  -- =========================================================================
  RAISE NOTICE '--- 5. backdated records cannot overwrite newer state ---';
  -- =========================================================================
  -- A verbal consent logged three days late must not resurrect permission that
  -- was withdrawn yesterday. Out-of-order arrival is normal, not exceptional.
  PERFORM app.record_consent(v_ch_email, v_p_market, 'withdrawn', 'unsubscribe_link',
            '{}'::jsonb, now());
  PERFORM app.record_consent(v_ch_email, v_p_market, 'granted', 'verbal',
            '{}'::jsonb, now() - interval '3 days');

  SELECT state INTO v_state FROM consent_state
   WHERE channel_id = v_ch_email AND purpose_id = v_p_market;
  IF v_state <> 'withdrawn' THEN
    RAISE EXCEPTION 'FAIL: backdated grant overwrote a newer withdrawal (state=%)', v_state;
  END IF;
  RAISE NOTICE '  ok: backdated record did not overwrite newer state';

  -- =========================================================================
  RAISE NOTICE '--- 6. double opt-in ---';
  -- =========================================================================
  PERFORM app.record_consent(v_ch_email, v_p_doi, 'granted', 'web_form');
  SELECT state INTO v_state FROM consent_state
   WHERE channel_id = v_ch_email AND purpose_id = v_p_doi;
  IF v_state <> 'pending' THEN
    RAISE EXCEPTION 'FAIL: unconfirmed grant should be pending, got %', v_state;
  END IF;

  v_verdict := app.can_send(v_ch_email, v_p_doi);
  IF v_verdict.allowed OR v_verdict.reason <> 'consent_pending' THEN
    RAISE EXCEPTION 'FAIL: pending double opt-in should deny, got (%, %)',
      v_verdict.allowed, v_verdict.reason;
  END IF;
  RAISE NOTICE '  ok: unconfirmed double opt-in downgraded to pending and denied';

  PERFORM app.record_consent(v_ch_email, v_p_doi, 'granted', 'double_optin',
            '{"confirmation_token":"abc123"}'::jsonb);
  v_verdict := app.can_send(v_ch_email, v_p_doi);
  IF NOT v_verdict.allowed THEN
    RAISE EXCEPTION 'FAIL: confirmed double opt-in should allow';
  END IF;
  RAISE NOTICE '  ok: confirmation via double_optin grants';

  -- =========================================================================
  RAISE NOTICE '--- 7. expiring consent ---';
  -- =========================================================================
  -- Expiry is tested with a backdated grant rather than by sleeping. A DO block
  -- is a single transaction and now() returns transaction-start time, so
  -- pg_sleep cannot advance the clock this code reads. Backdating exercises the
  -- same comparison honestly.
  PERFORM app.record_consent(v_ch_email, v_p_ttl, 'granted', 'web_form');
  v_verdict := app.can_send(v_ch_email, v_p_ttl);
  IF NOT v_verdict.allowed THEN
    RAISE EXCEPTION 'FAIL: freshly granted TTL consent should allow, got (%, %)',
      v_verdict.allowed, v_verdict.reason;
  END IF;
  RAISE NOTICE '  ok: fresh TTL consent allows';

  -- Expiry is tested on a DIFFERENT channel, so this is the first record for
  -- that (channel, purpose) pair. Backdating on the pair used above would be
  -- correctly refused by the out-of-order guard proved in §5 — the guard and
  -- this test cannot both use the same pair.
  PERFORM app.record_consent(v_ch_sms, v_p_ttl, 'granted', 'web_form',
            '{}'::jsonb, now() - interval '2 hours');

  SELECT count(*) INTO v_count FROM consent_state
   WHERE channel_id = v_ch_sms AND purpose_id = v_p_ttl
     AND expires_at IS NOT NULL AND expires_at <= now();
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: backdated grant did not produce a past expiry';
  END IF;

  v_verdict := app.can_send(v_ch_sms, v_p_ttl);
  IF v_verdict.allowed OR v_verdict.reason <> 'consent_expired' THEN
    RAISE EXCEPTION 'FAIL: lapsed consent should deny, got (%, %)',
      v_verdict.allowed, v_verdict.reason;
  END IF;
  RAISE NOTICE '  ok: consent expires on its TTL';

  -- =========================================================================
  RAISE NOTICE '--- 8. suppression outranks everything ---';
  -- =========================================================================
  -- Consent is currently granted for the newsletter purpose. Suppress the
  -- address and both that and the transactional purpose must stop.
  INSERT INTO suppressions (organization_id, channel_type, address, reason, source)
    VALUES (v_org, 'email', 'dana@acme.test', 'hard_bounce', 'test');

  v_verdict := app.can_send(v_ch_email, v_p_doi);
  IF v_verdict.allowed OR v_verdict.reason <> 'suppressed:hard_bounce' THEN
    RAISE EXCEPTION 'FAIL: suppression should beat granted consent, got (%, %)',
      v_verdict.allowed, v_verdict.reason;
  END IF;
  RAISE NOTICE '  ok: suppression overrides granted consent';

  v_verdict := app.can_send(v_ch_email, v_p_txn);
  IF v_verdict.allowed THEN
    RAISE EXCEPTION 'FAIL: suppression must also stop transactional sends';
  END IF;
  RAISE NOTICE '  ok: suppression overrides transactional purpose';

  -- A permanent reason must not carry an expiry.
  BEGIN
    INSERT INTO suppressions (organization_id, channel_type, address, reason, expires_at)
      VALUES (v_org, 'email', 'other@acme.test', 'complaint', now() + interval '1 day');
    RAISE EXCEPTION 'FAIL: expiring complaint suppression accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: complaint suppression cannot expire';
  END;

  -- Only one active suppression per address.
  BEGIN
    INSERT INTO suppressions (organization_id, channel_type, address, reason)
      VALUES (v_org, 'email', 'dana@acme.test', 'manual');
    RAISE EXCEPTION 'FAIL: duplicate active suppression accepted';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE '  ok: one active suppression per address';
  END;

  -- Releasing restores deliverability.
  UPDATE suppressions SET released_at = now(), release_reason = 'test release'
   WHERE organization_id = v_org AND channel_type = 'email'
     AND address = 'dana@acme.test' AND released_at IS NULL;

  v_verdict := app.can_send(v_ch_email, v_p_txn);
  IF NOT v_verdict.allowed THEN
    RAISE EXCEPTION 'FAIL: released suppression should restore sending, got (%, %)',
      v_verdict.allowed, v_verdict.reason;
  END IF;
  RAISE NOTICE '  ok: releasing a suppression restores sending';

  -- =========================================================================
  RAISE NOTICE '--- 9. legacy opt-out is still honoured ---';
  -- =========================================================================
  -- The old boolean is retained rather than dropped, so it must not be silently
  -- ignored during the transition.
  UPDATE contacts SET email_opt_out = true WHERE id = v_contact;

  v_verdict := app.can_send(v_ch_email, v_p_doi);
  IF v_verdict.allowed OR v_verdict.reason <> 'legacy_opt_out' THEN
    RAISE EXCEPTION 'FAIL: legacy opt-out ignored, got (%, %)',
      v_verdict.allowed, v_verdict.reason;
  END IF;
  RAISE NOTICE '  ok: legacy email_opt_out still blocks marketing';

  -- ...but it must not block transactional messages.
  v_verdict := app.can_send(v_ch_email, v_p_txn);
  IF NOT v_verdict.allowed THEN
    RAISE EXCEPTION 'FAIL: legacy opt-out should not block transactional';
  END IF;
  RAISE NOTICE '  ok: legacy opt-out does not block transactional';

  UPDATE contacts SET email_opt_out = false WHERE id = v_contact;

  -- =========================================================================
  RAISE NOTICE '--- 10. delivery events ---';
  -- =========================================================================
  v_evt := app.ingest_message_event(v_org, 'email', 'dana@acme.test', 'delivered',
             'postmark', 'evt-0001', NULL, 'campaign-7');
  IF v_evt IS NULL THEN
    RAISE EXCEPTION 'FAIL: first ingest returned NULL';
  END IF;

  -- Replayed webhook must not double-count.
  v_evt2 := app.ingest_message_event(v_org, 'email', 'dana@acme.test', 'delivered',
              'postmark', 'evt-0001', NULL, 'campaign-7');
  IF v_evt2 IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: replayed event was ingested twice';
  END IF;

  SELECT count(*) INTO v_count FROM message_events
   WHERE provider = 'postmark' AND provider_event_id = 'evt-0001';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: expected 1 stored event, found %', v_count;
  END IF;
  RAISE NOTICE '  ok: webhook replay is idempotent';

  -- The event links back to the channel it belongs to.
  SELECT count(*) INTO v_count FROM message_events
   WHERE id = v_evt AND channel_id = v_ch_email;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: event not linked to its channel';
  END IF;
  RAISE NOTICE '  ok: event resolved to its channel';

  -- =========================================================================
  RAISE NOTICE '--- 11. a hard bounce suppresses automatically ---';
  -- =========================================================================
  PERFORM app.ingest_message_event(v_org, 'sms', '+15550100', 'delivered', 'twilio', 'sms-1');
  v_verdict := app.can_send(v_ch_sms, v_p_txn);
  IF NOT v_verdict.allowed THEN
    RAISE EXCEPTION 'FAIL: sms should be sendable before any bounce';
  END IF;

  PERFORM app.ingest_message_event(v_org, 'sms', '+15550100', 'bounced', 'twilio',
            'sms-2', 'hard');

  IF NOT app.is_suppressed(v_org, 'sms', '+15550100') THEN
    RAISE EXCEPTION 'FAIL: hard bounce did not create a suppression';
  END IF;

  v_verdict := app.can_send(v_ch_sms, v_p_txn);
  IF v_verdict.allowed OR v_verdict.reason <> 'suppressed:hard_bounce' THEN
    RAISE EXCEPTION 'FAIL: hard-bounced address still sendable, got (%, %)',
      v_verdict.allowed, v_verdict.reason;
  END IF;
  RAISE NOTICE '  ok: hard bounce auto-suppressed the address in the same transaction';

  -- A complaint is permanent too.
  PERFORM app.ingest_message_event(v_org, 'email', 'complainer@acme.test',
            'complained', 'postmark', 'evt-0002');
  IF NOT app.is_suppressed(v_org, 'email', 'complainer@acme.test') THEN
    RAISE EXCEPTION 'FAIL: complaint did not suppress';
  END IF;
  RAISE NOTICE '  ok: complaint suppressed an address with no contact row';

  -- =========================================================================
  RAISE NOTICE '--- 12. agent attribution ---';
  -- =========================================================================
  PERFORM set_config('app.current_agent', 'support-responder', false);
  v_rec := app.record_consent(v_ch_email, v_p_market, 'granted', 'verbal');

  SELECT count(*) INTO v_count FROM consent_records
   WHERE id = v_rec AND actor_type = 'agent' AND actor_agent = 'support-responder';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: agent-recorded consent not attributed to the agent';
  END IF;
  RAISE NOTICE '  ok: agent-recorded consent names the agent';
  PERFORM set_config('app.current_agent', '', false);

  -- An agent-attributed record with no agent name must be refused.
  BEGIN
    INSERT INTO consent_records (organization_id, channel_id, purpose_id,
                                 state, source, actor_type)
      VALUES (v_org, v_ch_email, v_p_market, 'granted', 'api', 'agent');
    RAISE EXCEPTION 'FAIL: unnamed agent consent record accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: agent consent record must name the agent';
  END;

  RAISE NOTICE '';
  RAISE NOTICE '=== ALL CONSENT ASSERTIONS PASSED ===';
END;
$$;
