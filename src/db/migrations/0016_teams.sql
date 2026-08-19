-- 0016_teams.sql
-- Teams as rows, with a recursive hierarchy.
--
-- `memberships.team` has been a free-text column since 0002. A typo creates a
-- new team silently, "see everything my team owns" has nothing to query, and a
-- hierarchy ("see my team and every team under it") cannot be expressed in text
-- at all. This replaces it with a real table.
--
-- NON-DESTRUCTIVE: `memberships.team` is retained, exactly as `email_opt_out`
-- was in 0011 (see DECISIONS.md D13). `team_id` is additive. Dropping the text
-- column is a separate, destructive change requiring explicit approval per
-- CLAUDE.md §3.

BEGIN;

CREATE TABLE teams (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  name              text NOT NULL CHECK (btrim(name) <> ''),
  parent_team_id    uuid REFERENCES teams(id) ON DELETE SET NULL,
  lead_user_id      uuid REFERENCES users(id) ON DELETE SET NULL,
  description       text,

  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz,

  CONSTRAINT teams_no_self_parent CHECK (parent_team_id IS NULL OR parent_team_id <> id)
);

CREATE UNIQUE INDEX teams_org_name_key
  ON teams (organization_id, name)
  WHERE deleted_at IS NULL;

CREATE INDEX teams_org_parent_idx
  ON teams (organization_id, parent_team_id)
  WHERE deleted_at IS NULL;

SELECT app.attach_tenant_triggers('teams');

CREATE TRIGGER teams_parent_same_org
  BEFORE INSERT OR UPDATE OF parent_team_id ON teams
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('teams', 'parent_team_id');

CREATE TRIGGER teams_lead_same_org
  BEFORE INSERT OR UPDATE OF lead_user_id ON teams
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('teams', 'lead_user_id');

-- A cycle deeper than self-parenting cannot be expressed as a CHECK — it needs
-- reachability, which is what accounts.parent_id explicitly defers to
-- "application code" (0003). Teams get a real guard instead: the hierarchy is
-- small (dozens of rows, not millions) and it is walked recursively by the
-- visibility functions below, so a cycle there is not a data-quality issue, it
-- is an infinite loop in a query someone runs in production.
CREATE OR REPLACE FUNCTION app.assert_no_team_cycle()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_depth  integer := 0;
  v_cursor uuid := NEW.parent_team_id;
BEGIN
  IF NEW.parent_team_id IS NULL THEN
    RETURN NEW;
  END IF;

  LOOP
    IF v_cursor = NEW.id THEN
      RAISE EXCEPTION 'team hierarchy cycle: % is an ancestor of itself', NEW.id
        USING ERRCODE = 'check_violation';
    END IF;

    v_depth := v_depth + 1;
    IF v_depth > 100 THEN
      RAISE EXCEPTION 'team hierarchy exceeds 100 levels — refusing as a likely cycle'
        USING ERRCODE = 'check_violation';
    END IF;

    SELECT parent_team_id INTO v_cursor FROM teams WHERE id = v_cursor;
    EXIT WHEN v_cursor IS NULL;
  END LOOP;

  RETURN NEW;
END;
$$;

CREATE TRIGGER teams_no_cycle
  BEFORE INSERT OR UPDATE OF parent_team_id ON teams
  FOR EACH ROW EXECUTE FUNCTION app.assert_no_team_cycle();

-- ---------------------------------------------------------------------------
-- memberships gains a real team reference alongside the old text one.
-- ---------------------------------------------------------------------------
ALTER TABLE memberships
  ADD COLUMN team_id uuid REFERENCES teams(id) ON DELETE SET NULL;

CREATE INDEX memberships_team_idx
  ON memberships (team_id)
  WHERE deleted_at IS NULL AND team_id IS NOT NULL;

CREATE TRIGGER memberships_team_same_org
  BEFORE INSERT OR UPDATE OF team_id ON memberships
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('teams', 'team_id');

-- ---------------------------------------------------------------------------
-- Recursive visibility
-- ---------------------------------------------------------------------------

-- A team and everything under it. STABLE, not IMMUTABLE: the hierarchy can
-- change between calls in the same statement's planning window.
CREATE OR REPLACE FUNCTION app.team_and_descendants(p_team_id uuid)
RETURNS TABLE (team_id uuid)
LANGUAGE sql
STABLE
AS $$
  WITH RECURSIVE tree AS (
    SELECT id FROM teams WHERE id = p_team_id AND deleted_at IS NULL
    UNION ALL
    SELECT t.id FROM teams t
      JOIN tree ON t.parent_team_id = tree.id
     WHERE t.deleted_at IS NULL
  )
  SELECT id FROM tree;
$$;

-- The teams a manager's role gives them reach over: owner and admin see every
-- team in the organization (matching their existing full read access under the
-- current tenant-only RLS — see DECISIONS.md D2); a manager sees their own
-- team and everything beneath it; member and viewer see only their own team.
--
-- Read-only helper, not an RLS policy. Row-level enforcement of "a manager only
-- sees their team's records" is a separate, larger change — see D23 and
-- open-gaps.md §8 — because today's RLS is deliberately tenant-only and every
-- member already sees every record in the tenant. This function is what a
-- narrower policy, or an application-layer filter, would be built on.
CREATE OR REPLACE FUNCTION app.visible_team_ids(p_org uuid DEFAULT NULL)
RETURNS TABLE (team_id uuid)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_org  uuid := coalesce(p_org, app.current_org_id());
  v_role membership_role;
  v_team uuid;
BEGIN
  v_role := app.current_role_in(v_org);
  IF v_role IS NULL THEN
    RETURN;
  END IF;

  IF v_role IN ('owner', 'admin') THEN
    RETURN QUERY SELECT t.id FROM teams t
     WHERE t.organization_id = v_org AND t.deleted_at IS NULL;
    RETURN;
  END IF;

  SELECT m.team_id INTO v_team FROM memberships m
   WHERE m.organization_id = v_org AND m.user_id = app.current_user_id()
     AND m.deleted_at IS NULL;
  IF v_team IS NULL THEN
    RETURN;
  END IF;

  IF v_role = 'manager' THEN
    RETURN QUERY SELECT d.team_id FROM app.team_and_descendants(v_team) d;
  ELSE
    RETURN QUERY SELECT v_team;
  END IF;
END;
$$;

COMMENT ON FUNCTION app.visible_team_ids(uuid) IS
  'Teams the caller''s role gives them reach over. member/manager -- everything '
  'owned by their team'' from membership_role''s comment in 0002, made queryable.';

SELECT app.apply_tenant_rls('teams');
SELECT app.attach_audit('teams');

COMMIT;
