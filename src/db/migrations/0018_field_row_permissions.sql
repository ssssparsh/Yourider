-- 0018_field_row_permissions.sql
-- Field-level redaction and row-level sharing.
--
-- Today's RLS (0009) is deliberately tenant-only: any member of an
-- organization can read any record in it, and only writes are gated by role
-- (see DECISIONS.md D2). That is a reasonable default and this migration does
-- not change it — every existing table's SELECT policy is untouched, and the
-- functional and RLS test suites must still pass unmodified.
--
-- What this adds is the data a tenant needs once "everyone sees everything" is
-- no longer good enough for one field or one record:
--
--   1. field_permissions — which custom fields are hidden from which roles.
--      Real Postgres column-level security (REVOKE SELECT (col) FROM role)
--      does not fit a pooled multi-tenant connection: it needs a distinct
--      database role per application role, not per row. Redaction is done as
--      a function instead — the application calls it before a record leaves
--      the database, the same way it already must call app.can_download or
--      app.can_send before acting on their answers.
--
--   2. record_shares — a specific record made visible to a specific user or
--      team beyond whatever the standing policy would otherwise show them.
--      This is the exception list a *stricter* future policy would consult.
--      WIRING IT IN — changing accounts/contacts/leads/deals/service_jobs'
--      SELECT policies to check it — is deliberately not done here. That is a
--      behavioural change to every tenant's existing visibility, which is a
--      product decision for the user to make deliberately, not a side effect
--      of adding a table. See DECISIONS.md D24.

BEGIN;

-- ---------------------------------------------------------------------------
-- Field-level redaction
-- ---------------------------------------------------------------------------
CREATE TABLE field_permissions (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  entity_type       crm_entity NOT NULL,
  -- A custom_fields JSONB key, or a known column name on that entity's table.
  -- Not an FK to custom_field_definitions: a tenant may want to hide a bare
  -- column (e.g. a lead's phone number) that has no definition row at all.
  field_key         text NOT NULL CHECK (btrim(field_key) <> ''),

  -- Roles this field is hidden from. A role not listed sees it. Empty array
  -- means "hidden from nobody", which is a real, if pointless, permission row
  -- rather than a special case.
  hidden_from_roles membership_role[] NOT NULL DEFAULT '{}',

  reason            text,

  created_by        uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX field_permissions_unique
  ON field_permissions (organization_id, entity_type, field_key);

SELECT app.attach_tenant_triggers('field_permissions');
SELECT app.apply_tenant_rls('field_permissions');
SELECT app.attach_audit('field_permissions');

-- Strips every key hidden from p_role. Owner and admin always see everything —
-- redaction exists to protect data from colleagues, not from the people
-- accountable for the tenant's configuration of it.
CREATE OR REPLACE FUNCTION app.redact_fields(
  p_entity_type crm_entity,
  p_org         uuid,
  p_role        membership_role,
  p_fields      jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_key  text;
  v_out  jsonb := p_fields;
BEGIN
  IF p_role IN ('owner', 'admin') OR p_fields IS NULL THEN
    RETURN p_fields;
  END IF;

  FOR v_key IN
    SELECT field_key FROM field_permissions
     WHERE organization_id = p_org
       AND entity_type = p_entity_type
       AND p_role = ANY (hidden_from_roles)
  LOOP
    v_out := v_out - v_key;
  END LOOP;

  RETURN v_out;
END;
$$;

COMMENT ON FUNCTION app.redact_fields(crm_entity, uuid, membership_role, jsonb) IS
  'Strips keys hidden from p_role from a custom_fields blob. The application '
  'must call this before a record reaches a response — the database cannot '
  'redact columns per caller inside a single pooled role, so nothing enforces '
  'this automatically. See DECISIONS.md D24.';

-- ---------------------------------------------------------------------------
-- Row-level sharing — the exception list, not (yet) an enforcement mechanism
-- ---------------------------------------------------------------------------
CREATE TYPE share_permission AS ENUM ('view', 'edit');

CREATE TABLE record_shares (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  entity_type       crm_entity NOT NULL,
  entity_id         uuid NOT NULL,

  -- Exactly one of these: a share is granted to a person or to a team, not to
  -- a free-floating nobody.
  shared_with_user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  shared_with_team_id uuid REFERENCES teams(id) ON DELETE CASCADE,

  permission        share_permission NOT NULL DEFAULT 'view',
  reason            text,
  expires_at        timestamptz,

  granted_by        uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  revoked_at        timestamptz,
  revoked_by        uuid REFERENCES users(id) ON DELETE SET NULL,

  CONSTRAINT record_shares_one_target CHECK (
    (shared_with_user_id IS NOT NULL) <> (shared_with_team_id IS NOT NULL)
  )
);

-- One live share per (record, recipient). A second grant to the same person
-- for the same record is a permission bump, which is an UPDATE, not a new row.
CREATE UNIQUE INDEX record_shares_unique_user
  ON record_shares (entity_type, entity_id, shared_with_user_id)
  WHERE revoked_at IS NULL AND shared_with_user_id IS NOT NULL;

CREATE UNIQUE INDEX record_shares_unique_team
  ON record_shares (entity_type, entity_id, shared_with_team_id)
  WHERE revoked_at IS NULL AND shared_with_team_id IS NOT NULL;

CREATE INDEX record_shares_entity_idx
  ON record_shares (organization_id, entity_type, entity_id)
  WHERE revoked_at IS NULL;

CREATE INDEX record_shares_user_idx
  ON record_shares (shared_with_user_id)
  WHERE revoked_at IS NULL AND shared_with_user_id IS NOT NULL;

-- Not app.attach_tenant_triggers(): that pair also includes set_updated_at,
-- and this table has no updated_at column — a share is granted or revoked,
-- never edited. organization_id still needs its immutability guard, attached
-- directly as an UPDATE-only trigger (freeze_organization_id reads OLD, which
-- does not exist on INSERT).
CREATE TRIGGER record_shares_freeze_org
  BEFORE UPDATE ON record_shares
  FOR EACH ROW EXECUTE FUNCTION app.freeze_organization_id();

CREATE OR REPLACE FUNCTION app.record_shares_validate()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM app.assert_entity_in_org(NEW.entity_type, NEW.entity_id, NEW.organization_id);

  IF NEW.shared_with_user_id IS NOT NULL THEN
    PERFORM app.assert_entity_in_org('user', NEW.shared_with_user_id, NEW.organization_id);
  END IF;
  IF NEW.shared_with_team_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM teams
     WHERE id = NEW.shared_with_team_id AND organization_id = NEW.organization_id
       AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'cross-tenant reference: team % is not in organization %',
      NEW.shared_with_team_id, NEW.organization_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER record_shares_validate
  BEFORE INSERT OR UPDATE OF entity_type, entity_id, shared_with_user_id,
                             shared_with_team_id ON record_shares
  FOR EACH ROW EXECUTE FUNCTION app.record_shares_validate();

CREATE OR REPLACE FUNCTION app.revoke_share(p_share_id uuid, p_by uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE record_shares
     SET revoked_at = now(), revoked_by = coalesce(p_by, app.current_user_id())
   WHERE id = p_share_id AND revoked_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no live share with id %', p_share_id
      USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;

-- Everyone in the tenant can already see the underlying record under today's
-- policy, so this table's own confidentiality is about who-shared-what-with-
-- whom, not the shared record itself. Visible to owner/admin (who administer
-- access) and to either party of the grant.
SELECT app.apply_tenant_rls('record_shares');
DROP POLICY tenant_select ON record_shares;
CREATE POLICY tenant_select ON record_shares
  FOR SELECT USING (
    organization_id = app.current_org_id()
    AND (
      coalesce(app.current_role_in(organization_id) IN ('owner', 'admin'), false)
      OR granted_by = app.current_user_id()
      OR shared_with_user_id = app.current_user_id()
    )
  );

SELECT app.attach_audit('record_shares');

COMMIT;
