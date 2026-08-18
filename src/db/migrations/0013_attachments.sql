-- 0013_attachments.sql
-- Files and attachments.
--
-- Every CRM needs somewhere to put a contract PDF, a site photo, an imported
-- CSV. Two tables rather than one, deliberately:
--
--   `files` is the stored blob — one row per distinct byte sequence, carrying
--   the storage location, size, checksum, and scan verdict.
--
--   `attachments` is the link from a blob to a record. The same signed contract
--   can hang off a deal, an account, and a service job without three copies of
--   the bytes existing.
--
-- Collapsing them into one polymorphic table means re-uploading identical files
-- and losing the ability to answer "where else does this document appear",
-- which is the first question asked when a document turns out to be wrong.
--
-- WHERE THE BYTES LIVE: object storage, not Postgres. A bytea column puts file
-- content into WAL, into every base backup, and onto every replica, and turns a
-- 20 MB upload into 20 MB of replication traffic. Postgres holds the metadata
-- and the authorisation decision; S3 (or MinIO, or Supabase Storage) holds the
-- bytes. This table is the index, not the filesystem.

BEGIN;

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- Upload is two-phase. A row exists before the bytes do, because the storage
-- key has to be known in order to issue a presigned upload URL. The state says
-- whether the bytes actually arrived — without it, the only options are trusting
-- the client's word that the upload succeeded, or writing the row afterwards
-- and having no way to find objects whose row write failed.
CREATE TYPE file_upload_state AS ENUM (
  'pending',    -- row created, bytes not yet confirmed present
  'stored',     -- bytes confirmed, size and checksum recorded
  'failed'      -- abandoned or superseded; the sweeper may delete the object
);

-- Scan verdict. A file arriving from outside (a customer portal, an inbound
-- email, an agent fetching a URL) must not be downloadable before something has
-- looked at it. 'skipped' is for trusted internal generation, and is a
-- deliberate choice a caller has to make rather than a silent default.
CREATE TYPE file_scan_status AS ENUM ('pending', 'clean', 'infected', 'skipped');

-- Why a file is attached, where the reason has structural meaning. Anything
-- that is merely a human category ("contract", "site photo") belongs in `label`
-- rather than here — these are the roles the schema itself enforces.
CREATE TYPE attachment_role AS ENUM (
  'attachment',     -- the ordinary case: a document on a record
  'avatar',         -- at most one per record
  'logo',           -- at most one per record
  'import_source',  -- the CSV a batch of records came from
  'generated'       -- produced by the system or an agent, not uploaded
);

-- ---------------------------------------------------------------------------
-- files — one row per stored blob
-- ---------------------------------------------------------------------------
CREATE TABLE files (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  storage_bucket    text NOT NULL CHECK (btrim(storage_bucket) <> ''),

  -- Generated, never supplied. A client-chosen key is a tenant-isolation hole:
  -- tenant A asks for the key 'org-b/invoices/secret.pdf' and either overwrites
  -- or reads tenant B's object, and no amount of RLS on this table prevents it,
  -- because the breach happens in the object store rather than in Postgres.
  -- Deriving the key from the row makes that unrepresentable.
  storage_key       text GENERATED ALWAYS AS (
                      organization_id::text || '/' || id::text
                    ) STORED,

  original_filename text NOT NULL CHECK (btrim(original_filename) <> ''),

  -- Bare type only, no parameters: 'text/csv', never 'text/csv; charset=utf-8'.
  -- Parameters belong to the response header, not to the file's identity.
  mime_type         text NOT NULL
                      CHECK (mime_type ~ '^[a-z0-9][-a-z0-9.+]*/[a-z0-9][-a-z0-9.+]*$'),

  byte_size         bigint CHECK (byte_size IS NULL OR byte_size >= 0),
  -- Raw 32 bytes rather than 64 hex characters: half the storage, and it makes
  -- a malformed digest a constraint violation instead of a silent mismatch.
  checksum_sha256   bytea CHECK (checksum_sha256 IS NULL
                                 OR octet_length(checksum_sha256) = 32),

  upload_state      file_upload_state NOT NULL DEFAULT 'pending',
  uploaded_at       timestamptz,
  -- Set when this upload lost a dedup race; points at the row that won.
  superseded_by     uuid REFERENCES files(id) ON DELETE SET NULL,

  scan_status       file_scan_status NOT NULL DEFAULT 'pending',
  scanned_at        timestamptz,
  scan_detail       text,

  -- Maintained by trigger from `attachments`. Kept on the row so the sweeper
  -- can find unreferenced blobs with an index scan rather than an anti-join
  -- across the whole attachment table.
  attachment_count  integer NOT NULL DEFAULT 0 CHECK (attachment_count >= 0),

  uploaded_by       uuid REFERENCES users(id) ON DELETE SET NULL,
  uploader_type     actor_kind NOT NULL DEFAULT 'user',
  uploader_agent    text,

  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz,

  -- Same rule as activities and audit_log: an agent-attributed write must name
  -- the agent. See DECISIONS.md D7.
  CONSTRAINT files_agent_named CHECK (
    uploader_type <> 'agent' OR coalesce(btrim(uploader_agent), '') <> ''
  ),

  -- 'stored' is a claim about reality. It may only be made once the facts that
  -- back it are recorded, so a half-completed upload cannot masquerade as a
  -- finished one.
  CONSTRAINT files_stored_is_complete CHECK (
    upload_state <> 'stored'
    OR (byte_size IS NOT NULL AND checksum_sha256 IS NOT NULL
        AND uploaded_at IS NOT NULL)
  ),

  CONSTRAINT files_scan_recorded CHECK (
    scan_status = 'pending' OR scanned_at IS NOT NULL
  )
);

-- Content addressing, scoped to the tenant.
--
-- Deduplicating across tenants would be tempting — one copy of every identical
-- PDF in the whole system — and is a side channel: tenant A learns that tenant B
-- holds a particular document by observing that their own upload was instant.
-- Storage is cheaper than that inference.
CREATE UNIQUE INDEX files_org_checksum_key
  ON files (organization_id, checksum_sha256)
  WHERE upload_state = 'stored' AND deleted_at IS NULL;

CREATE INDEX files_org_created_idx
  ON files (organization_id, created_at DESC, id)
  WHERE deleted_at IS NULL;

CREATE INDEX files_org_uploader_idx
  ON files (organization_id, uploaded_by, created_at DESC)
  WHERE deleted_at IS NULL;

-- The sweeper's index: blobs nothing points at any more.
CREATE INDEX files_unreferenced_idx
  ON files (organization_id, updated_at)
  WHERE attachment_count = 0;

-- Scan queue. Partial, so it stays small no matter how many files exist.
CREATE INDEX files_scan_pending_idx
  ON files (created_at)
  WHERE scan_status = 'pending' AND upload_state = 'stored';

CREATE INDEX files_filename_trgm_idx
  ON files USING gin (original_filename gin_trgm_ops);

SELECT app.attach_tenant_triggers('files');

-- ---------------------------------------------------------------------------
-- attachments — the link from a blob to a record
-- ---------------------------------------------------------------------------
CREATE TABLE attachments (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  -- No ON DELETE CASCADE and no SET NULL: an attachment must never outlive its
  -- blob as a dangling pointer, and a blob must never be removable while
  -- something still references it. RESTRICT is the correct default here.
  file_id           uuid NOT NULL REFERENCES files(id),

  entity_type       crm_entity NOT NULL,
  entity_id         uuid NOT NULL,

  role              attachment_role NOT NULL DEFAULT 'attachment',
  label             text,
  sort_order        numeric NOT NULL DEFAULT 0,

  attached_by       uuid REFERENCES users(id) ON DELETE SET NULL,
  actor_type        actor_kind NOT NULL DEFAULT 'user',
  actor_agent       text,

  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz,

  CONSTRAINT attachments_agent_named CHECK (
    actor_type <> 'agent' OR coalesce(btrim(actor_agent), '') <> ''
  )
);

-- Attaching the same file twice to the same record in the same role is a
-- double-click, not an intention.
CREATE UNIQUE INDEX attachments_unique
  ON attachments (file_id, entity_type, entity_id, role)
  WHERE deleted_at IS NULL;

-- Roles that are singular by definition. A record has one avatar; a second one
-- is an ambiguity the reader has to resolve, so the database resolves it first.
CREATE UNIQUE INDEX attachments_singleton_role
  ON attachments (entity_type, entity_id, role)
  WHERE deleted_at IS NULL AND role IN ('avatar', 'logo');

CREATE INDEX attachments_entity_idx
  ON attachments (organization_id, entity_type, entity_id, sort_order, created_at)
  WHERE deleted_at IS NULL;

CREATE INDEX attachments_file_idx
  ON attachments (file_id)
  WHERE deleted_at IS NULL;

SELECT app.attach_tenant_triggers('attachments');

-- ---------------------------------------------------------------------------
-- Polymorphic reference validation
--
-- `activities` deliberately carries no FK on (entity_type, entity_id): it is
-- partitioned, high-volume, and a lookup per insert would be paid on every
-- interaction ever recorded.
--
-- Attachments are different. They are low-volume, long-lived, and a dangling
-- one is discovered at the worst moment — someone opens a deal that no longer
-- exists to find the contract. The lookup costs an index hit per attach.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.entity_table(p_entity crm_entity)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_entity
           WHEN 'account'     THEN 'accounts'
           WHEN 'contact'     THEN 'contacts'
           WHEN 'lead'        THEN 'leads'
           WHEN 'deal'        THEN 'deals'
           WHEN 'service_job' THEN 'service_jobs'
           WHEN 'service'     THEN 'services'
           WHEN 'task'        THEN 'tasks'
           WHEN 'user'        THEN 'users'
         END;
$$;

COMMENT ON FUNCTION app.entity_table(crm_entity) IS
  'Maps a crm_entity value to its table name. Adding an enum value without '
  'adding a branch here makes this return NULL, which callers must treat as an '
  'error rather than skipping validation.';

-- Raises unless the referenced record exists, lives in p_org, and is not
-- soft-deleted. `users` is special-cased: it is not organization-scoped, so
-- membership is what "belongs to this org" means for a user.
CREATE OR REPLACE FUNCTION app.assert_entity_in_org(
  p_entity crm_entity,
  p_id     uuid,
  p_org    uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_table text := app.entity_table(p_entity);
  v_row   jsonb;
BEGIN
  IF v_table IS NULL THEN
    RAISE EXCEPTION
      'no table mapping for entity type % — app.entity_table is out of date',
      p_entity
      USING ERRCODE = 'internal_error';
  END IF;

  IF p_entity = 'user' THEN
    IF NOT EXISTS (
      SELECT 1 FROM memberships m
       WHERE m.user_id = p_id
         AND m.organization_id = p_org
         AND m.deleted_at IS NULL
    ) THEN
      RAISE EXCEPTION
        'cross-tenant reference: user % is not a member of organization %',
        p_id, p_org
        USING ERRCODE = 'foreign_key_violation';
    END IF;
    RETURN;
  END IF;

  -- Read through jsonb so a table without `deleted_at` yields NULL rather than
  -- raising. Same lesson as DECISIONS.md D14: a function that spans tables
  -- cannot assume any one table's shape.
  EXECUTE format('SELECT to_jsonb(t) FROM %I t WHERE t.id = $1', v_table)
    INTO v_row USING p_id;

  IF v_row IS NULL THEN
    RAISE EXCEPTION 'no such %: %', p_entity, p_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF (v_row ->> 'organization_id')::uuid IS DISTINCT FROM p_org THEN
    RAISE EXCEPTION
      'cross-tenant reference: %(%) belongs to a different organization',
      p_entity, p_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF (v_row ->> 'deleted_at') IS NOT NULL THEN
    RAISE EXCEPTION 'cannot reference deleted %: %', p_entity, p_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Attachment guards
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.enforce_attachment_target()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_file files%ROWTYPE;
BEGIN
  SELECT * INTO v_file FROM files WHERE id = NEW.file_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such file: %', NEW.file_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF v_file.organization_id <> NEW.organization_id THEN
    RAISE EXCEPTION
      'cross-tenant reference: attachments.file_id -> files(%) belongs to a '
      'different organization', NEW.file_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF v_file.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'cannot attach a deleted file: %', NEW.file_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  -- A pending upload has no confirmed bytes behind it. Attaching one produces a
  -- record that shows a document which may never have arrived.
  IF v_file.upload_state <> 'stored' THEN
    RAISE EXCEPTION
      'cannot attach file % in upload state %', NEW.file_id, v_file.upload_state
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_file.scan_status = 'infected' THEN
    RAISE EXCEPTION 'cannot attach file %: malware detected', NEW.file_id
      USING ERRCODE = 'check_violation';
  END IF;

  PERFORM app.assert_entity_in_org(NEW.entity_type, NEW.entity_id,
                                   NEW.organization_id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER attachments_enforce_target
  BEFORE INSERT OR UPDATE OF file_id, entity_type, entity_id ON attachments
  FOR EACH ROW EXECUTE FUNCTION app.enforce_attachment_target();

-- Keeps files.attachment_count in step with the live attachment rows.
--
-- Recomputed rather than incremented. An increment/decrement pair has to be
-- right for every path that changes a row — insert, hard delete, soft delete,
-- restore, and a file_id moved from one blob to another — and a single missed
-- path leaves a blob that the sweeper either deletes while it is still in use or
-- never deletes at all. Recomputing is a small indexed count and cannot drift.
CREATE OR REPLACE FUNCTION app.refresh_attachment_count()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_ids uuid[] := '{}';
  v_id  uuid;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    v_ids := v_ids || OLD.file_id;
  END IF;
  IF TG_OP <> 'DELETE' THEN
    v_ids := v_ids || NEW.file_id;
  END IF;

  FOREACH v_id IN ARRAY v_ids LOOP
    UPDATE files f
       SET attachment_count = (
             SELECT count(*) FROM attachments a
              WHERE a.file_id = f.id AND a.deleted_at IS NULL
           )
     WHERE f.id = v_id;
  END LOOP;

  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION app.refresh_attachment_count() IS
  'SECURITY DEFINER because the counter must stay accurate even when the '
  'caller cannot write to files directly; it only ever writes a count derived '
  'from rows the caller was already permitted to change.';

CREATE TRIGGER attachments_refresh_count
  AFTER INSERT OR UPDATE OF file_id, deleted_at OR DELETE ON attachments
  FOR EACH ROW EXECUTE FUNCTION app.refresh_attachment_count();

-- ---------------------------------------------------------------------------
-- Timeline helper
--
-- `activity_kind` has carried a 'file_attached' value since 0007 with nothing
-- emitting it. This is that emitter, written as a general helper rather than
-- inline: the other mutating helpers (app.move_to_stage, app.convert_lead,
-- app.stamp_assignment) currently write no timeline rows at all, and routing
-- them through one function later is a small change, whereas four hand-rolled
-- INSERTs that drifted apart is not.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.log_activity(
  p_org         uuid,
  p_kind        activity_kind,
  p_entity_type crm_entity,
  p_entity_id   uuid,
  p_subject     text DEFAULT NULL,
  p_body        text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_id     uuid;
  v_agent  text := nullif(current_setting('app.current_agent', true), '');
  v_actor  actor_kind;
  v_user   uuid := app.current_user_id();
BEGIN
  IF v_agent IS NOT NULL THEN
    v_actor := 'agent';
  ELSIF v_user IS NOT NULL THEN
    v_actor := 'user';
  ELSE
    v_actor := 'system';
  END IF;

  INSERT INTO activities (
    organization_id, kind, subject, body,
    entity_type, entity_id,
    account_id, contact_id, deal_id, job_id,
    actor_type, actor_user_id, actor_agent
  ) VALUES (
    p_org, p_kind, p_subject, p_body,
    p_entity_type, p_entity_id,
    CASE WHEN p_entity_type = 'account'     THEN p_entity_id END,
    CASE WHEN p_entity_type = 'contact'     THEN p_entity_id END,
    CASE WHEN p_entity_type = 'deal'        THEN p_entity_id END,
    CASE WHEN p_entity_type = 'service_job' THEN p_entity_id END,
    v_actor, v_user, v_agent
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Upload lifecycle
-- ---------------------------------------------------------------------------
CREATE TYPE file_upload_ticket AS (
  file_id        uuid,
  storage_bucket text,
  storage_key    text,
  already_stored boolean
);

-- Reserves a row and returns where to put the bytes.
--
-- Pass p_checksum when the client has hashed the file before uploading: if that
-- content already exists in this organization, the upload is skipped entirely
-- and the existing blob is returned with already_stored = true.
CREATE OR REPLACE FUNCTION app.begin_file_upload(
  p_org         uuid,
  p_bucket      text,
  p_filename    text,
  p_mime_type   text,
  p_checksum    bytea DEFAULT NULL,
  p_uploaded_by uuid  DEFAULT NULL
)
RETURNS file_upload_ticket
LANGUAGE plpgsql
AS $$
DECLARE
  v_existing files%ROWTYPE;
  v_ticket   file_upload_ticket;
  v_agent    text := nullif(current_setting('app.current_agent', true), '');
  v_id       uuid;
BEGIN
  IF p_checksum IS NOT NULL THEN
    -- A checksum that already came back infected is a known-bad file. Refusing
    -- it here means a blocked upload cannot be laundered by retrying it: the
    -- content is the identity, so renaming it changes nothing.
    IF EXISTS (
      SELECT 1 FROM files
       WHERE organization_id = p_org
         AND checksum_sha256 = p_checksum
         AND scan_status = 'infected'
    ) THEN
      RAISE EXCEPTION
        'upload refused: this content was previously found to contain malware'
        USING ERRCODE = 'check_violation';
    END IF;

    SELECT * INTO v_existing
      FROM files
     WHERE organization_id = p_org
       AND checksum_sha256 = p_checksum
       AND upload_state = 'stored'
       AND deleted_at IS NULL
     LIMIT 1;

    IF FOUND THEN
      v_ticket.file_id        := v_existing.id;
      v_ticket.storage_bucket := v_existing.storage_bucket;
      v_ticket.storage_key    := v_existing.storage_key;
      v_ticket.already_stored := true;
      RETURN v_ticket;
    END IF;
  END IF;

  INSERT INTO files (
    organization_id, storage_bucket, original_filename, mime_type,
    checksum_sha256, uploaded_by,
    uploader_type, uploader_agent
  ) VALUES (
    p_org, p_bucket, p_filename, lower(p_mime_type),
    p_checksum, p_uploaded_by,
    CASE WHEN v_agent IS NOT NULL THEN 'agent'::actor_kind
         ELSE 'user'::actor_kind END,
    v_agent
  )
  RETURNING id INTO v_id;

  SELECT f.id, f.storage_bucket, f.storage_key, false
    INTO v_ticket
    FROM files f WHERE f.id = v_id;

  RETURN v_ticket;
END;
$$;

-- Confirms the bytes arrived. Returns the id of the canonical blob, which is
-- not always the id passed in: two uploads of identical content can be in
-- flight at once, and the loser is marked superseded rather than kept as a
-- second copy the sweeper would never collect.
CREATE OR REPLACE FUNCTION app.complete_file_upload(
  p_file_id   uuid,
  p_byte_size bigint,
  p_checksum  bytea
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_org       uuid;
  v_canonical uuid;
BEGIN
  SELECT organization_id INTO v_org
    FROM files
   WHERE id = p_file_id AND upload_state = 'pending' AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no pending upload with id %', p_file_id
      USING ERRCODE = 'no_data_found';
  END IF;

  BEGIN
    UPDATE files
       SET byte_size       = p_byte_size,
           checksum_sha256 = p_checksum,
           upload_state    = 'stored',
           uploaded_at     = now()
     WHERE id = p_file_id;
    RETURN p_file_id;

  EXCEPTION WHEN unique_violation THEN
    SELECT id INTO v_canonical
      FROM files
     WHERE organization_id = v_org
       AND checksum_sha256 = p_checksum
       AND upload_state = 'stored'
       AND deleted_at IS NULL
     LIMIT 1;

    UPDATE files
       SET upload_state    = 'failed',
           byte_size       = p_byte_size,
           checksum_sha256 = p_checksum,
           superseded_by   = v_canonical,
           deleted_at      = now()
     WHERE id = p_file_id;

    RETURN v_canonical;
  END;
END;
$$;

CREATE OR REPLACE FUNCTION app.record_scan_result(
  p_file_id uuid,
  p_status  file_scan_status,
  p_detail  text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_status = 'pending' THEN
    RAISE EXCEPTION 'a scan result cannot be "pending"'
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE files
     SET scan_status = p_status,
         scanned_at  = now(),
         scan_detail = p_detail
   WHERE id = p_file_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such file: %', p_file_id
      USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- The download gate
--
-- Shaped like app.can_send: a verdict plus a reason, because a caller that only
-- gets false has nothing to show the user and nothing to log.
-- ---------------------------------------------------------------------------
CREATE TYPE download_verdict AS (
  allowed boolean,
  reason  text
);

CREATE OR REPLACE FUNCTION app.can_download(p_file_id uuid)
RETURNS download_verdict
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_file files%ROWTYPE;
BEGIN
  -- RLS applies to this read, so a file in another tenant is simply not found.
  SELECT * INTO v_file FROM files WHERE id = p_file_id;

  IF NOT FOUND THEN
    RETURN ROW(false, 'file_not_found')::download_verdict;
  END IF;

  IF v_file.deleted_at IS NOT NULL THEN
    RETURN ROW(false, 'file_deleted')::download_verdict;
  END IF;

  IF v_file.upload_state <> 'stored' THEN
    RETURN ROW(false, 'upload_' || v_file.upload_state::text)::download_verdict;
  END IF;

  IF v_file.scan_status = 'infected' THEN
    RETURN ROW(false, 'malware_detected')::download_verdict;
  END IF;

  -- Fail closed. An unscanned file from an unknown source is exactly the file
  -- worth withholding, and 'skipped' exists so a trusted internal path can say
  -- so explicitly instead of arriving here by omission.
  IF v_file.scan_status = 'pending' THEN
    RETURN ROW(false, 'scan_pending')::download_verdict;
  END IF;

  RETURN ROW(true, 'ok')::download_verdict;
END;
$$;

COMMENT ON FUNCTION app.can_download(uuid) IS
  'Whether a presigned download URL may be issued for this file, and why not. '
  'Answers content safety only — tenant isolation is enforced by RLS on the '
  'read inside this function, record-level visibility by the caller.';

-- ---------------------------------------------------------------------------
-- Attach and detach
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.attach_file(
  p_file_id     uuid,
  p_entity_type crm_entity,
  p_entity_id   uuid,
  p_role        attachment_role DEFAULT 'attachment',
  p_label       text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_file  files%ROWTYPE;
  v_id    uuid;
  v_agent text := nullif(current_setting('app.current_agent', true), '');
BEGIN
  SELECT * INTO v_file FROM files WHERE id = p_file_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such file: %', p_file_id
      USING ERRCODE = 'no_data_found';
  END IF;

  INSERT INTO attachments (
    organization_id, file_id, entity_type, entity_id, role, label,
    attached_by, actor_type, actor_agent
  ) VALUES (
    v_file.organization_id, p_file_id, p_entity_type, p_entity_id, p_role,
    p_label, app.current_user_id(),
    CASE WHEN v_agent IS NOT NULL THEN 'agent'::actor_kind
         ELSE 'user'::actor_kind END,
    v_agent
  )
  RETURNING id INTO v_id;

  PERFORM app.log_activity(
    v_file.organization_id, 'file_attached', p_entity_type, p_entity_id,
    v_file.original_filename,
    coalesce(p_label, v_file.original_filename)
  );

  RETURN v_id;
END;
$$;

-- Soft delete. The link is history: "this contract used to hang off this deal"
-- is a question that gets asked, and a hard delete makes it unanswerable.
CREATE OR REPLACE FUNCTION app.detach_file(p_attachment_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE attachments
     SET deleted_at = now()
   WHERE id = p_attachment_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no live attachment with id %', p_attachment_id
      USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Sweeper input
--
-- Reports blobs whose bytes are no longer needed. It does not delete anything,
-- here or in the object store: this function is read-only by design, and the
-- deletion is a Destructive-class action that runs in the sweeper with its own
-- approval story (CLAUDE.md §3).
--
-- The grace period matters. A row can legitimately sit unreferenced between
-- being created and being attached, and a sweeper with no grace period deletes
-- bytes out from under an upload that is still in progress.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sweepable_files(
  p_grace interval DEFAULT interval '24 hours'
)
RETURNS TABLE (
  file_id        uuid,
  storage_bucket text,
  storage_key    text,
  byte_size      bigint,
  reason         text
)
LANGUAGE sql
STABLE
AS $$
  SELECT f.id, f.storage_bucket, f.storage_key, f.byte_size,
         CASE
           WHEN f.upload_state = 'failed' AND f.superseded_by IS NOT NULL
             THEN 'superseded_duplicate'
           WHEN f.upload_state = 'failed'   THEN 'failed_upload'
           WHEN f.upload_state = 'pending'  THEN 'abandoned_upload'
           WHEN f.deleted_at IS NOT NULL    THEN 'deleted'
           ELSE 'never_attached'
         END AS reason
    FROM files f
   WHERE f.attachment_count = 0
     AND (
           (f.upload_state IN ('pending', 'failed') AND f.created_at < now() - p_grace)
        OR (f.deleted_at IS NOT NULL AND f.deleted_at < now() - p_grace)
        OR (f.upload_state = 'stored' AND f.deleted_at IS NULL
            AND f.created_at < now() - p_grace)
         )
   ORDER BY f.created_at;
$$;

COMMENT ON FUNCTION app.sweepable_files(interval) IS
  'Blobs whose bytes can be removed from object storage, with the reason. '
  'Read-only: it reports candidates, it never deletes. Callers should act on '
  'specific reasons rather than the whole set — "never_attached" in particular '
  'is a policy choice, not a fact.';

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
SELECT app.apply_tenant_rls('files');
SELECT app.apply_tenant_rls('attachments');

-- ---------------------------------------------------------------------------
-- Audit
--
-- `attachments` gets the standard trigger: attaching and detaching a document
-- are both events worth a trail.
--
-- `files` gets a column-scoped one. app.refresh_attachment_count() updates
-- files on every attach and detach, and auditing that would fill the trail with
-- rows recording that a derived counter moved — noise that makes the signal
-- (a scan verdict, a deletion, a renamed file) harder to find. UPDATE OF names
-- the columns that matter, so the trigger does not fire for counter churn.
-- ---------------------------------------------------------------------------
SELECT app.attach_audit('attachments');

CREATE TRIGGER record_audit
  AFTER INSERT
     OR UPDATE OF upload_state, scan_status, deleted_at, original_filename,
                  mime_type, storage_bucket, byte_size, checksum_sha256,
                  superseded_by
     OR DELETE
  ON files
  FOR EACH ROW EXECUTE FUNCTION app.record_audit();

COMMIT;
