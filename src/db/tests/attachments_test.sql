-- attachments_test.sql
-- Exercises the file lifecycle and the attachment guards.
--
-- The things that go wrong with file handling are not "does the row insert":
-- they are a client choosing its own storage key, a pending upload that gets
-- attached before the bytes exist, a duplicate that the sweeper can never
-- collect, and a blob deleted while something still points at it. Each of those
-- has an assertion here.
--
-- Requires the fixture from functional_test.sql (org-a, org-b, and a deal).
--
--   psql -d yourider -v ON_ERROR_STOP=1 -f src/db/tests/attachments_test.sql

\set ON_ERROR_STOP on

DO $$
DECLARE
  v_org       uuid;
  v_org_b     uuid;
  v_user      uuid;
  v_deal      uuid;
  v_contact   uuid;
  v_account   uuid;
  v_ticket    file_upload_ticket;
  v_ticket2   file_upload_ticket;
  v_file      uuid;
  v_file2     uuid;
  v_bad       uuid;
  v_dup       uuid;
  v_canonical uuid;
  v_att       uuid;
  v_verdict   download_verdict;
  v_sum_a     bytea := decode(repeat('a1', 32), 'hex');
  v_sum_b     bytea := decode(repeat('b2', 32), 'hex');
  v_sum_c     bytea := decode(repeat('c3', 32), 'hex');
  v_sum_evil  bytea := decode(repeat('ee', 32), 'hex');
  v_count     int;
  v_audit     int;
  v_text      text;
  v_state     file_upload_state;
BEGIN
  SELECT id INTO v_org   FROM organizations WHERE slug = 'org-a';
  SELECT id INTO v_org_b FROM organizations WHERE slug = 'org-b';
  SELECT id INTO v_user  FROM users WHERE email = 'a@example.com';
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'fixture missing: run functional_test.sql first';
  END IF;

  PERFORM set_config('app.current_org_id', v_org::text, false);
  PERFORM set_config('app.current_user_id', v_user::text, false);

  SELECT id INTO v_deal    FROM deals    WHERE organization_id = v_org AND deleted_at IS NULL LIMIT 1;
  SELECT id INTO v_contact FROM contacts WHERE organization_id = v_org AND deleted_at IS NULL LIMIT 1;
  SELECT id INTO v_account FROM accounts WHERE organization_id = v_org AND deleted_at IS NULL LIMIT 1;
  IF v_deal IS NULL OR v_contact IS NULL OR v_account IS NULL THEN
    RAISE EXCEPTION 'fixture missing: expected a deal, contact and account in org-a';
  END IF;

  -- =========================================================================
  RAISE NOTICE '--- 1. two-phase upload ---';
  -- =========================================================================
  v_ticket := app.begin_file_upload(
    v_org, 'yourider-files', 'contract.pdf', 'application/pdf', NULL, v_user);
  v_file := v_ticket.file_id;

  IF v_ticket.already_stored THEN
    RAISE EXCEPTION 'FAIL: a fresh upload reported as already stored';
  END IF;
  RAISE NOTICE '  ok: upload ticket issued (already_stored = false)';

  -- The key must be derived from the row, never chosen by the caller: a
  -- client-supplied key is how one tenant reads another tenant's object.
  IF v_ticket.storage_key <> v_org::text || '/' || v_file::text THEN
    RAISE EXCEPTION 'FAIL: storage key % is not the derived key', v_ticket.storage_key;
  END IF;
  RAISE NOTICE '  ok: storage key is tenant-prefixed and derived from the row';

  BEGIN
    UPDATE files SET storage_key = 'other-org/anything' WHERE id = v_file;
    RAISE EXCEPTION 'FAIL: storage key was writable';
  EXCEPTION WHEN generated_always THEN
    RAISE NOTICE '  ok: storage key cannot be overwritten by the client';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 2. a pending upload is not a file ---';
  -- =========================================================================
  v_verdict := app.can_download(v_file);
  IF v_verdict.allowed OR v_verdict.reason <> 'upload_pending' THEN
    RAISE EXCEPTION 'FAIL: pending upload downloadable (%)', v_verdict.reason;
  END IF;
  RAISE NOTICE '  ok: pending upload refuses download (%)', v_verdict.reason;

  BEGIN
    PERFORM app.attach_file(v_file, 'deal', v_deal);
    RAISE EXCEPTION 'FAIL: pending upload was attachable';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: pending upload cannot be attached';
  END;

  -- 'stored' cannot be claimed without the facts that back it.
  BEGIN
    UPDATE files SET upload_state = 'stored' WHERE id = v_file;
    RAISE EXCEPTION 'FAIL: stored state accepted with no size or checksum';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: "stored" requires size, checksum and uploaded_at';
  END;

  PERFORM app.complete_file_upload(v_file, 20480, v_sum_a);
  SELECT upload_state INTO v_state FROM files WHERE id = v_file;
  IF v_state <> 'stored' THEN
    RAISE EXCEPTION 'FAIL: upload not marked stored (%)', v_state;
  END IF;
  RAISE NOTICE '  ok: completed upload is stored';

  -- =========================================================================
  RAISE NOTICE '--- 3. the scan gate ---';
  -- =========================================================================
  v_verdict := app.can_download(v_file);
  IF v_verdict.allowed OR v_verdict.reason <> 'scan_pending' THEN
    RAISE EXCEPTION 'FAIL: unscanned file downloadable (%)', v_verdict.reason;
  END IF;
  RAISE NOTICE '  ok: unscanned file fails closed (%)', v_verdict.reason;

  PERFORM app.record_scan_result(v_file, 'clean');
  v_verdict := app.can_download(v_file);
  IF NOT v_verdict.allowed THEN
    RAISE EXCEPTION 'FAIL: clean file refused (%)', v_verdict.reason;
  END IF;
  RAISE NOTICE '  ok: clean file is downloadable';

  BEGIN
    PERFORM app.record_scan_result(v_file, 'pending');
    RAISE EXCEPTION 'FAIL: "pending" accepted as a scan result';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: a scan result cannot be "pending"';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 4. infected files ---';
  -- =========================================================================
  v_ticket2 := app.begin_file_upload(
    v_org, 'yourider-files', 'invoice.doc', 'application/msword', NULL, v_user);
  v_bad := v_ticket2.file_id;
  PERFORM app.complete_file_upload(v_bad, 999, v_sum_evil);
  PERFORM app.record_scan_result(v_bad, 'infected', 'EICAR-Test-Signature');

  v_verdict := app.can_download(v_bad);
  IF v_verdict.allowed OR v_verdict.reason <> 'malware_detected' THEN
    RAISE EXCEPTION 'FAIL: infected file downloadable (%)', v_verdict.reason;
  END IF;
  RAISE NOTICE '  ok: infected file refuses download';

  BEGIN
    PERFORM app.attach_file(v_bad, 'deal', v_deal);
    RAISE EXCEPTION 'FAIL: infected file was attachable';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: infected file cannot be attached';
  END;

  -- Content is the identity, so renaming a blocked file changes nothing.
  BEGIN
    PERFORM app.begin_file_upload(
      v_org, 'yourider-files', 'harmless.pdf', 'application/pdf', v_sum_evil, v_user);
    RAISE EXCEPTION 'FAIL: known-malware checksum accepted on re-upload';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: known-malware checksum refused on re-upload';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 5. deduplication ---';
  -- =========================================================================
  -- Checksum known up front: no second upload at all.
  v_ticket2 := app.begin_file_upload(
    v_org, 'yourider-files', 'contract-copy.pdf', 'application/pdf', v_sum_a, v_user);
  IF NOT v_ticket2.already_stored OR v_ticket2.file_id <> v_file THEN
    RAISE EXCEPTION 'FAIL: identical content did not deduplicate';
  END IF;
  RAISE NOTICE '  ok: known checksum returns the existing blob, no re-upload';

  -- Checksum only known after the bytes arrive: the loser is marked superseded
  -- rather than left as a second copy nothing would ever collect.
  v_ticket2 := app.begin_file_upload(
    v_org, 'yourider-files', 'contract-again.pdf', 'application/pdf', NULL, v_user);
  v_dup := v_ticket2.file_id;
  v_canonical := app.complete_file_upload(v_dup, 20480, v_sum_a);

  IF v_canonical <> v_file THEN
    RAISE EXCEPTION 'FAIL: late duplicate did not resolve to the canonical blob';
  END IF;
  SELECT upload_state, superseded_by INTO v_state, v_bad FROM files WHERE id = v_dup;
  IF v_state <> 'failed' OR v_bad <> v_file THEN
    RAISE EXCEPTION 'FAIL: duplicate not marked superseded (state %, by %)', v_state, v_bad;
  END IF;
  RAISE NOTICE '  ok: late duplicate resolves to the canonical blob and is superseded';

  -- Cross-tenant deduplication would be a side channel: an instant upload tells
  -- tenant A that tenant B holds this exact document.
  v_ticket2 := app.begin_file_upload(
    v_org_b, 'yourider-files', 'contract.pdf', 'application/pdf', v_sum_a, NULL);
  IF v_ticket2.already_stored THEN
    RAISE EXCEPTION 'FAIL: deduplicated across tenants';
  END IF;
  RAISE NOTICE '  ok: identical content in another tenant does not deduplicate';

  -- =========================================================================
  RAISE NOTICE '--- 6. attaching ---';
  -- =========================================================================
  v_att := app.attach_file(v_file, 'deal', v_deal, 'attachment', 'Signed contract');

  SELECT attachment_count INTO v_count FROM files WHERE id = v_file;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: attachment_count is % after one attach', v_count;
  END IF;
  RAISE NOTICE '  ok: attachment created and counted';

  SELECT count(*) INTO v_count FROM activities
   WHERE organization_id = v_org AND kind = 'file_attached'
     AND entity_type = 'deal' AND entity_id = v_deal;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: expected 1 file_attached activity, found %', v_count;
  END IF;
  RAISE NOTICE '  ok: attaching wrote a timeline entry';

  -- The same file on the same record in the same role is a double-click.
  BEGIN
    PERFORM app.attach_file(v_file, 'deal', v_deal);
    PERFORM app.attach_file(v_file, 'deal', v_deal);
    RAISE EXCEPTION 'FAIL: duplicate attachment accepted';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE '  ok: the same file cannot be attached twice in one role';
  END;

  -- One blob, several records: the point of splitting files from attachments.
  PERFORM app.attach_file(v_file, 'account', v_account);
  SELECT attachment_count INTO v_count FROM files WHERE id = v_file;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'FAIL: attachment_count is % after two attaches', v_count;
  END IF;
  RAISE NOTICE '  ok: one blob serves several records';

  -- =========================================================================
  RAISE NOTICE '--- 7. polymorphic references are validated ---';
  -- =========================================================================
  BEGIN
    PERFORM app.attach_file(v_file, 'deal', gen_random_uuid());
    RAISE EXCEPTION 'FAIL: attachment to a nonexistent deal accepted';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE '  ok: dangling entity reference refused';
  END;

  -- A user is not organization-scoped, so membership is what belonging means.
  PERFORM app.attach_file(v_file, 'user', v_user, 'avatar');
  RAISE NOTICE '  ok: attaching to a member user is allowed';

  BEGIN
    PERFORM app.attach_file(v_file, 'user', gen_random_uuid(), 'avatar');
    RAISE EXCEPTION 'FAIL: attachment to a non-member user accepted';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE '  ok: non-member user reference refused';
  END;

  -- A file from another tenant must never land on this tenant's record.
  v_file2 := v_ticket2.file_id;   -- the org-b blob from section 5
  PERFORM app.complete_file_upload(v_file2, 20480, v_sum_a);
  BEGIN
    INSERT INTO attachments (organization_id, file_id, entity_type, entity_id)
      VALUES (v_org, v_file2, 'deal', v_deal);
    RAISE EXCEPTION 'FAIL: cross-tenant file attached';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE '  ok: cross-tenant file reference refused';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 8. singleton roles ---';
  -- =========================================================================
  v_ticket2 := app.begin_file_upload(
    v_org, 'yourider-files', 'headshot.png', 'image/png', v_sum_b, v_user);
  v_file2 := v_ticket2.file_id;
  PERFORM app.complete_file_upload(v_file2, 4096, v_sum_b);
  PERFORM app.record_scan_result(v_file2, 'clean');

  PERFORM app.attach_file(v_file2, 'contact', v_contact, 'avatar');
  BEGIN
    PERFORM app.attach_file(v_file, 'contact', v_contact, 'avatar');
    RAISE EXCEPTION 'FAIL: a contact accepted two avatars';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE '  ok: a record has at most one avatar';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 9. detaching and blob protection ---';
  -- =========================================================================
  BEGIN
    DELETE FROM files WHERE id = v_file;
    RAISE EXCEPTION 'FAIL: deleted a blob that attachments still reference';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE '  ok: a referenced blob cannot be deleted';
  END;

  SELECT attachment_count INTO v_count FROM files WHERE id = v_file;
  PERFORM app.detach_file(v_att);
  SELECT attachment_count INTO v_audit FROM files WHERE id = v_file;
  IF v_audit <> v_count - 1 THEN
    RAISE EXCEPTION 'FAIL: detach did not decrement the count (% -> %)', v_count, v_audit;
  END IF;
  RAISE NOTICE '  ok: detach is a soft delete and updates the count';

  IF NOT EXISTS (SELECT 1 FROM attachments WHERE id = v_att AND deleted_at IS NOT NULL) THEN
    RAISE EXCEPTION 'FAIL: detached attachment was hard deleted';
  END IF;
  RAISE NOTICE '  ok: the detached link is still on record';

  -- Detaching frees the role, so the record can get a new one.
  PERFORM app.attach_file(v_file, 'deal', v_deal, 'attachment', 'Countersigned');
  RAISE NOTICE '  ok: a detached file can be re-attached';

  -- =========================================================================
  RAISE NOTICE '--- 10. sweeper candidates ---';
  -- =========================================================================
  -- An upload that was reserved and abandoned. now() is frozen inside this
  -- block, so the age is created by backdating rather than by waiting.
  v_ticket2 := app.begin_file_upload(
    v_org, 'yourider-files', 'abandoned.csv', 'text/csv', NULL, v_user);
  UPDATE files SET created_at = now() - interval '3 days'
   WHERE id = v_ticket2.file_id;
  UPDATE files SET created_at = now() - interval '3 days' WHERE id = v_dup;

  SELECT reason INTO v_text FROM app.sweepable_files()
   WHERE file_id = v_ticket2.file_id;
  IF v_text <> 'abandoned_upload' THEN
    RAISE EXCEPTION 'FAIL: abandoned upload reported as % ', coalesce(v_text, 'absent');
  END IF;
  RAISE NOTICE '  ok: abandoned upload is sweepable (%)', v_text;

  SELECT reason INTO v_text FROM app.sweepable_files() WHERE file_id = v_dup;
  IF v_text <> 'superseded_duplicate' THEN
    RAISE EXCEPTION 'FAIL: superseded duplicate reported as %', coalesce(v_text, 'absent');
  END IF;
  RAISE NOTICE '  ok: superseded duplicate is sweepable (%)', v_text;

  IF EXISTS (SELECT 1 FROM app.sweepable_files() WHERE file_id = v_file) THEN
    RAISE EXCEPTION 'FAIL: an attached blob was reported as sweepable';
  END IF;
  RAISE NOTICE '  ok: an attached blob is never sweepable';

  -- The grace period is the whole safety mechanism: without it the sweeper
  -- deletes bytes out from under an upload still in flight.
  IF EXISTS (
    SELECT 1 FROM app.sweepable_files(interval '7 days')
     WHERE file_id = v_ticket2.file_id
  ) THEN
    RAISE EXCEPTION 'FAIL: grace period ignored';
  END IF;
  RAISE NOTICE '  ok: the grace period holds young uploads back';

  -- =========================================================================
  RAISE NOTICE '--- 11. the audit trail records signal, not counter churn ---';
  -- =========================================================================
  SELECT count(*) INTO v_audit FROM audit_log
   WHERE table_name = 'files' AND record_id = v_file2;

  PERFORM app.attach_file(v_file2, 'account', v_account);   -- moves the counter
  SELECT count(*) INTO v_count FROM audit_log
   WHERE table_name = 'files' AND record_id = v_file2;
  IF v_count <> v_audit THEN
    RAISE EXCEPTION 'FAIL: counter churn wrote % audit rows', v_count - v_audit;
  END IF;
  RAISE NOTICE '  ok: attachment_count changes write no audit rows';

  PERFORM app.record_scan_result(v_file2, 'clean', 're-scanned');
  SELECT count(*) INTO v_count FROM audit_log
   WHERE table_name = 'files' AND record_id = v_file2;
  IF v_count <= v_audit THEN
    RAISE EXCEPTION 'FAIL: a scan result wrote no audit row';
  END IF;
  RAISE NOTICE '  ok: a scan verdict is audited';

  SELECT count(*) INTO v_count FROM audit_log
   WHERE table_name = 'attachments' AND organization_id = v_org;
  IF v_count = 0 THEN
    RAISE EXCEPTION 'FAIL: attachments are not audited';
  END IF;
  RAISE NOTICE '  ok: attach and detach are audited (% rows)', v_count;

  -- =========================================================================
  RAISE NOTICE '--- 12. agent attribution ---';
  -- =========================================================================
  PERFORM set_config('app.current_agent', 'enrichment-agent', false);
  v_ticket2 := app.begin_file_upload(
    v_org, 'yourider-files', 'research.md', 'text/markdown', v_sum_c, NULL);
  SELECT count(*) INTO v_count FROM files
   WHERE id = v_ticket2.file_id
     AND uploader_type = 'agent' AND uploader_agent = 'enrichment-agent';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: agent upload not attributed to the agent';
  END IF;
  RAISE NOTICE '  ok: an agent upload names the agent';
  PERFORM set_config('app.current_agent', '', false);

  BEGIN
    INSERT INTO files (organization_id, storage_bucket, original_filename,
                       mime_type, uploader_type)
      VALUES (v_org, 'yourider-files', 'ghost.pdf', 'application/pdf', 'agent');
    RAISE EXCEPTION 'FAIL: unnamed agent upload accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: an agent-attributed file must name the agent';
  END;

  -- A mime type carrying parameters is not an identity, it is a header.
  BEGIN
    INSERT INTO files (organization_id, storage_bucket, original_filename, mime_type)
      VALUES (v_org, 'yourider-files', 'notes.txt', 'text/plain; charset=utf-8');
    RAISE EXCEPTION 'FAIL: parameterised mime type accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: mime type must be a bare type/subtype';
  END;

  RAISE NOTICE '';
  RAISE NOTICE '=== ALL ATTACHMENT ASSERTIONS PASSED ===';
END;
$$;
