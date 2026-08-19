-- 0017_saved_views.sql
-- Saved views: filters, sorts, column selection and board configuration as
-- rows instead of frontend state.
--
-- Without this, a filtered list is re-built by hand every session, cannot be
-- shared with a teammate, cannot be set as a role's default, and automation has
-- nothing to point at when a trigger config says "run this for everyone
-- matching view X". A view is opaque JSON here on purpose: the shape of a
-- filter differs per entity type and evolves with the UI far faster than a
-- migration cadence should track, the same reasoning as custom_fields (D5).

BEGIN;

CREATE TYPE saved_view_visibility AS ENUM (
  'private',    -- only the owner sees it
  'team',       -- the owner's team sees it (see 0016 for team membership)
  'organization' -- everyone in the tenant sees it
);

CREATE TABLE saved_views (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  entity_type       crm_entity NOT NULL,
  name              text NOT NULL CHECK (btrim(name) <> ''),

  -- Opaque and versioned by convention (a "v" key inside), not by a schema
  -- column: a frontend filter DSL changes shape far more often than this table
  -- should need a migration.
  filters           jsonb NOT NULL DEFAULT '[]'::jsonb
                      CHECK (jsonb_typeof(filters) = 'array'),
  sort              jsonb NOT NULL DEFAULT '[]'::jsonb
                      CHECK (jsonb_typeof(sort) = 'array'),
  columns           jsonb NOT NULL DEFAULT '[]'::jsonb
                      CHECK (jsonb_typeof(columns) = 'array'),
  -- Board-specific: which field groups rows into columns/swimlanes, collapsed
  -- state, etc. Null for a plain list view.
  board_config      jsonb,

  visibility        saved_view_visibility NOT NULL DEFAULT 'private',
  owner_id          uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- At most one default per (entity_type, owner): the view opened when nothing
  -- else is specified.
  is_default        boolean NOT NULL DEFAULT false,

  -- Lets automation and a saved report point at a stable target ("run for
  -- everyone in view X") instead of re-embedding the same filter twice.
  is_system         boolean NOT NULL DEFAULT false,

  position          numeric NOT NULL DEFAULT 0,

  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz
);

CREATE UNIQUE INDEX saved_views_one_default_per_owner
  ON saved_views (organization_id, entity_type, owner_id)
  WHERE is_default AND deleted_at IS NULL;

CREATE INDEX saved_views_org_entity_idx
  ON saved_views (organization_id, entity_type, visibility)
  WHERE deleted_at IS NULL;

CREATE INDEX saved_views_owner_idx
  ON saved_views (owner_id)
  WHERE deleted_at IS NULL;

SELECT app.attach_tenant_triggers('saved_views');

-- owner_id references users(id), and users carry no organization_id — a user
-- belongs to an org via membership, not a column. assert_same_org (0003) checks
-- a foreign row's own organization_id column and cannot express that, so this
-- reuses the membership check 0013 built for exactly this shape (a `user`
-- crm_entity is "in" an org when they hold a live membership there).
CREATE OR REPLACE FUNCTION app.saved_views_owner_same_org()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM app.assert_entity_in_org('user', NEW.owner_id, NEW.organization_id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER saved_views_owner_same_org
  BEFORE INSERT OR UPDATE OF owner_id ON saved_views
  FOR EACH ROW EXECUTE FUNCTION app.saved_views_owner_same_org();

-- ---------------------------------------------------------------------------
-- Row-level security
--
-- Read visibility follows `visibility` on top of the tenant boundary the
-- standard policy already gives: 'private' narrows to the owner, 'team'
-- narrows to app.visible_team_ids() from 0016, 'organization' is the tenant
-- default apply_tenant_rls already provides. Write stays owner-only — sharing
-- a view for others to see is not the same as letting them edit it.
-- ---------------------------------------------------------------------------
SELECT app.apply_tenant_rls('saved_views');

-- apply_tenant_rls's SELECT policy is organization-wide; replace it with one
-- that also respects `visibility`, rather than layering a second permissive
-- policy that would just re-widen it back to everything.
DROP POLICY tenant_select ON saved_views;

CREATE POLICY tenant_select ON saved_views
  FOR SELECT USING (
    organization_id = app.current_org_id()
    AND (
      visibility = 'organization'
      OR owner_id = app.current_user_id()
      OR (
        visibility = 'team'
        AND EXISTS (
          SELECT 1 FROM memberships m
           WHERE m.organization_id = organization_id
             AND m.user_id = saved_views.owner_id
             AND m.deleted_at IS NULL
             AND m.team_id IN (SELECT team_id FROM app.visible_team_ids(organization_id))
        )
      )
    )
  );

DROP POLICY tenant_update ON saved_views;
CREATE POLICY tenant_update ON saved_views
  FOR UPDATE
  USING (organization_id = app.current_org_id() AND owner_id = app.current_user_id())
  WITH CHECK (organization_id = app.current_org_id() AND owner_id = app.current_user_id());

DROP POLICY tenant_delete ON saved_views;
CREATE POLICY tenant_delete ON saved_views
  FOR DELETE
  USING (organization_id = app.current_org_id() AND owner_id = app.current_user_id());

SELECT app.attach_audit('saved_views');

COMMIT;
