-- 0004_pipelines.sql
-- Pipelines and stages as data, not enums.
--
-- This is the single most important structural decision in the schema. Every
-- mature CRM examined during design converged on the same conclusion: a
-- hardcoded stage enum forces a migration every time a tenant renames a stage,
-- reorders their funnel, or runs a second process alongside the first. Stages
-- as rows make the pipeline configurable per tenant, and — because a pipeline
-- declares which entity it drives — let the same machinery run a sales funnel,
-- a lead qualification flow, and a service job workflow side by side.

BEGIN;

-- Which entity a pipeline drives. Adding a value here (e.g. 'ticket') extends
-- the engine to a new work type without touching the pipeline machinery.
CREATE TYPE pipeline_entity AS ENUM ('lead', 'deal', 'service_job');

-- How a stage terminates. `open` stages are in-flight; `won`/`lost` are
-- terminal. Reports depend on this classification rather than on stage names,
-- so a tenant renaming "Closed Won" to "Signed" does not break forecasting.
CREATE TYPE stage_kind AS ENUM ('open', 'won', 'lost');

-- ---------------------------------------------------------------------------
-- Pipelines
-- ---------------------------------------------------------------------------
CREATE TABLE pipelines (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  entity_type      pipeline_entity NOT NULL,
  name             text NOT NULL CHECK (length(btrim(name)) > 0),
  description      text,

  is_default       boolean NOT NULL DEFAULT false,
  is_archived      boolean NOT NULL DEFAULT false,
  position         integer NOT NULL DEFAULT 0,

  created_by       uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  deleted_at       timestamptz
);

CREATE INDEX pipelines_org_entity_idx
  ON pipelines (organization_id, entity_type, position)
  WHERE deleted_at IS NULL AND is_archived = false;

-- Exactly one default pipeline per entity type per tenant. Enforced in the
-- database because "which pipeline does a new deal land in" must never be
-- ambiguous.
CREATE UNIQUE INDEX pipelines_one_default_per_entity
  ON pipelines (organization_id, entity_type)
  WHERE is_default = true AND deleted_at IS NULL;

SELECT app.attach_tenant_triggers('pipelines');

-- ---------------------------------------------------------------------------
-- Stages
-- ---------------------------------------------------------------------------
CREATE TABLE pipeline_stages (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  pipeline_id      uuid NOT NULL REFERENCES pipelines(id) ON DELETE CASCADE,

  name             text NOT NULL CHECK (length(btrim(name)) > 0),
  kind             stage_kind NOT NULL DEFAULT 'open',

  -- Display order within the pipeline. Numeric rather than integer so a stage
  -- can be inserted between two others without renumbering the rest.
  position         numeric(12,6) NOT NULL DEFAULT 0,

  -- Forecast weighting, 0..1. Drives weighted pipeline value.
  probability      numeric(5,4) NOT NULL DEFAULT 0
                     CHECK (probability >= 0 AND probability <= 1),

  -- Optional operational guardrails, both borrowed from kanban practice:
  -- wip_limit caps concurrent items in a stage; stale_after_days marks an item
  -- as rotting when it has sat here too long.
  wip_limit        integer CHECK (wip_limit IS NULL OR wip_limit > 0),
  stale_after_days integer CHECK (stale_after_days IS NULL OR stale_after_days > 0),

  color            text,

  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  deleted_at       timestamptz,

  CONSTRAINT pipeline_stages_name_key UNIQUE (pipeline_id, name)
);

CREATE INDEX pipeline_stages_pipeline_pos_idx
  ON pipeline_stages (pipeline_id, position)
  WHERE deleted_at IS NULL;

CREATE INDEX pipeline_stages_org_kind_idx
  ON pipeline_stages (organization_id, kind)
  WHERE deleted_at IS NULL;

SELECT app.attach_tenant_triggers('pipeline_stages');

CREATE TRIGGER pipeline_stages_pipeline_same_org
  BEFORE INSERT OR UPDATE OF pipeline_id ON pipeline_stages
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('pipelines', 'pipeline_id');

-- A pipeline needs at least one terminal stage of each outcome to be usable for
-- reporting. This is advisory rather than a constraint (a pipeline is built up
-- incrementally and would be unconstructable otherwise) — the API layer calls
-- it before marking a pipeline active.
CREATE OR REPLACE FUNCTION app.pipeline_is_reportable(p_pipeline uuid)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT count(*) FILTER (WHERE kind = 'open') > 0
     AND count(*) FILTER (WHERE kind = 'won')  > 0
     AND count(*) FILTER (WHERE kind = 'lost') > 0
  FROM pipeline_stages
  WHERE pipeline_id = p_pipeline AND deleted_at IS NULL;
$$;

-- ---------------------------------------------------------------------------
-- Stage transition history.
--
-- Kept as its own narrow table rather than derived from the audit log: "how
-- long does a deal sit in Negotiation" is one of the few questions every CRM is
-- asked, and answering it from a generic audit table means parsing JSON at
-- query time. A purpose-built table with a closed/open interval answers it with
-- an index scan.
-- ---------------------------------------------------------------------------
CREATE TABLE stage_transitions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  entity_type      pipeline_entity NOT NULL,
  entity_id        uuid NOT NULL,

  from_stage_id    uuid REFERENCES pipeline_stages(id) ON DELETE SET NULL,
  to_stage_id      uuid NOT NULL REFERENCES pipeline_stages(id) ON DELETE CASCADE,

  entered_at       timestamptz NOT NULL DEFAULT now(),
  exited_at        timestamptz,
  -- Generated on exit so "time in stage" aggregates without a self-join.
  duration_seconds bigint GENERATED ALWAYS AS (
                     CASE WHEN exited_at IS NULL THEN NULL
                          ELSE EXTRACT(EPOCH FROM (exited_at - entered_at))::bigint
                     END
                   ) STORED,

  actor_user_id    uuid REFERENCES users(id) ON DELETE SET NULL,
  actor_agent      text,   -- set when an agent moved the record; see 0007 audit notes
  note             text
);

CREATE INDEX stage_transitions_entity_idx
  ON stage_transitions (organization_id, entity_type, entity_id, entered_at DESC);

CREATE INDEX stage_transitions_stage_idx
  ON stage_transitions (organization_id, to_stage_id, entered_at DESC);

-- One open interval per entity at a time.
CREATE UNIQUE INDEX stage_transitions_one_open_per_entity
  ON stage_transitions (entity_type, entity_id)
  WHERE exited_at IS NULL;

COMMIT;
