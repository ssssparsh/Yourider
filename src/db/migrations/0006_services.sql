-- 0006_services.sql
-- The service side: what you offer, and the scheduled work that delivers it.
--
-- This is what makes Yourider more than a sales CRM. A sales deal ends when it
-- closes; a service relationship starts there. Service jobs run on the same
-- pipeline/stage machinery as deals (so the board, the transition history and
-- the stage analytics are shared code), but add the things sales does not have:
-- a catalogue of what is being delivered, scheduling windows, and assignment to
-- the person or resource who performs the work.
--
-- A mobility business maps onto this without modification: a "service" is a ride
-- type, a "job" is a booking, `assigned_user_id` is the driver, and the pipeline
-- is requested -> accepted -> en route -> completed. That was the design target
-- for keeping this generic rather than sales-specific.

BEGIN;

CREATE TYPE service_billing_kind AS ENUM (
  'fixed',       -- flat price per job
  'hourly',      -- price * duration
  'recurring',   -- subscription; billed on a cycle, not per job
  'usage',       -- metered (distance, units)
  'free'
);

CREATE TYPE job_priority AS ENUM ('low', 'normal', 'high', 'urgent');

-- ---------------------------------------------------------------------------
-- Service catalogue — the offerings a tenant sells and delivers.
-- ---------------------------------------------------------------------------
CREATE TABLE services (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  code              text,      -- tenant-facing SKU/short code
  name              text NOT NULL CHECK (length(btrim(name)) > 0),
  description       text,
  category          text,

  billing_kind      service_billing_kind NOT NULL DEFAULT 'fixed',
  unit_price        numeric(18,4) NOT NULL DEFAULT 0 CHECK (unit_price >= 0),
  currency          char(3) NOT NULL DEFAULT 'USD',
  unit_label        text,      -- 'hour', 'km', 'seat' — display only
  tax_rate          numeric(6,4) NOT NULL DEFAULT 0
                      CHECK (tax_rate >= 0 AND tax_rate <= 1),

  default_duration_minutes integer
                      CHECK (default_duration_minutes IS NULL OR default_duration_minutes > 0),
  -- Recurrence for billing_kind = 'recurring'; ISO-8601-ish interval, e.g. '1 month'.
  recurrence        interval,

  requires_assignment boolean NOT NULL DEFAULT true,
  is_active         boolean NOT NULL DEFAULT true,

  custom_fields     jsonb NOT NULL DEFAULT '{}'::jsonb,
  tags              text[] NOT NULL DEFAULT '{}',

  created_by        uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz,

  CONSTRAINT services_recurring_has_recurrence CHECK (
    billing_kind <> 'recurring' OR recurrence IS NOT NULL
  )
);

CREATE UNIQUE INDEX services_org_code_key
  ON services (organization_id, code)
  WHERE deleted_at IS NULL AND code IS NOT NULL;

CREATE INDEX services_org_active_idx
  ON services (organization_id, is_active, category)
  WHERE deleted_at IS NULL;

CREATE INDEX services_org_name_trgm_idx
  ON services USING gin (organization_id, name gin_trgm_ops)
  WHERE deleted_at IS NULL;

SELECT app.attach_tenant_triggers('services');

-- ---------------------------------------------------------------------------
-- Service jobs — a scheduled unit of work delivering a service to a customer.
-- ---------------------------------------------------------------------------
CREATE TABLE service_jobs (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  -- Human-facing reference. Sequential per tenant is assigned by the API layer;
  -- the column is here so it is queryable and unique when set.
  reference         text,

  service_id        uuid REFERENCES services(id) ON DELETE RESTRICT,
  account_id        uuid REFERENCES accounts(id) ON DELETE SET NULL,
  contact_id        uuid REFERENCES contacts(id) ON DELETE SET NULL,
  -- The deal this work was sold under, when there was one. This is the join
  -- that makes "revenue sold" and "work delivered" reconcilable.
  deal_id           uuid REFERENCES deals(id) ON DELETE SET NULL,

  title             text NOT NULL CHECK (length(btrim(title)) > 0),
  description       text,
  priority          job_priority NOT NULL DEFAULT 'normal',

  -- Same state machine as deals.
  pipeline_id       uuid NOT NULL REFERENCES pipelines(id) ON DELETE RESTRICT,
  stage_id          uuid NOT NULL REFERENCES pipeline_stages(id) ON DELETE RESTRICT,
  board_position    numeric(20,10) NOT NULL DEFAULT 0,
  stage_entered_at  timestamptz NOT NULL DEFAULT now(),

  -- Scheduling. Planned window vs. what actually happened; both matter, and
  -- conflating them is how service businesses lose the ability to measure
  -- punctuality.
  scheduled_start   timestamptz,
  scheduled_end     timestamptz,
  actual_start      timestamptz,
  actual_end        timestamptz,
  duration_minutes  integer GENERATED ALWAYS AS (
                      CASE WHEN actual_start IS NOT NULL AND actual_end IS NOT NULL
                           THEN (EXTRACT(EPOCH FROM (actual_end - actual_start)) / 60)::integer
                      END
                    ) STORED,

  -- Who performs the work. Nullable until dispatch.
  assigned_user_id  uuid REFERENCES users(id) ON DELETE SET NULL,
  assigned_at       timestamptz,

  -- Where. Structured address plus optional coordinates, so a mobility or
  -- field-service tenant can do proximity queries without a schema change.
  location          jsonb NOT NULL DEFAULT '{}'::jsonb,
  latitude          numeric(9,6) CHECK (latitude IS NULL OR (latitude BETWEEN -90 AND 90)),
  longitude         numeric(9,6) CHECK (longitude IS NULL OR (longitude BETWEEN -180 AND 180)),

  -- What it costs. Quoted up front, actual on completion.
  quoted_amount     numeric(18,4) CHECK (quoted_amount IS NULL OR quoted_amount >= 0),
  final_amount      numeric(18,4) CHECK (final_amount IS NULL OR final_amount >= 0),
  currency          char(3) NOT NULL DEFAULT 'USD',
  fx_rate           numeric(18,8) NOT NULL DEFAULT 1 CHECK (fx_rate > 0),
  base_final_amount numeric(18,4) GENERATED ALWAYS AS (
                      coalesce(final_amount, 0) * fx_rate
                    ) STORED,

  -- Outcome.
  completed_at      timestamptz,
  cancelled_at      timestamptz,
  cancellation_reason text,
  satisfaction_score smallint
                      CHECK (satisfaction_score IS NULL OR (satisfaction_score BETWEEN 1 AND 5)),

  owner_id          uuid REFERENCES users(id) ON DELETE SET NULL,
  custom_fields     jsonb NOT NULL DEFAULT '{}'::jsonb,
  tags              text[] NOT NULL DEFAULT '{}',

  created_by        uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz,

  CONSTRAINT service_jobs_schedule_ordered CHECK (
    scheduled_start IS NULL OR scheduled_end IS NULL OR scheduled_end >= scheduled_start
  ),
  CONSTRAINT service_jobs_actual_ordered CHECK (
    actual_start IS NULL OR actual_end IS NULL OR actual_end >= actual_start
  ),
  CONSTRAINT service_jobs_not_both_outcomes CHECK (
    completed_at IS NULL OR cancelled_at IS NULL
  ),
  CONSTRAINT service_jobs_coords_paired CHECK (
    (latitude IS NULL) = (longitude IS NULL)
  )
);

CREATE UNIQUE INDEX service_jobs_org_reference_key
  ON service_jobs (organization_id, reference)
  WHERE deleted_at IS NULL AND reference IS NOT NULL;

CREATE INDEX service_jobs_org_created_idx
  ON service_jobs (organization_id, created_at DESC, id)
  WHERE deleted_at IS NULL;

CREATE INDEX service_jobs_org_stage_position_idx
  ON service_jobs (organization_id, stage_id, board_position)
  WHERE deleted_at IS NULL AND completed_at IS NULL AND cancelled_at IS NULL;

-- The dispatch board: open work, by scheduled time. This is the hottest query
-- in any service operation and the one that must never degrade.
CREATE INDEX service_jobs_org_schedule_idx
  ON service_jobs (organization_id, scheduled_start)
  WHERE deleted_at IS NULL AND completed_at IS NULL AND cancelled_at IS NULL;

-- "What is on my plate today" — per assignee, ordered by time.
CREATE INDEX service_jobs_org_assignee_schedule_idx
  ON service_jobs (organization_id, assigned_user_id, scheduled_start)
  WHERE deleted_at IS NULL AND completed_at IS NULL AND cancelled_at IS NULL;

-- Unassigned work waiting for dispatch.
CREATE INDEX service_jobs_org_unassigned_idx
  ON service_jobs (organization_id, priority, scheduled_start)
  WHERE deleted_at IS NULL AND assigned_user_id IS NULL
        AND completed_at IS NULL AND cancelled_at IS NULL;

CREATE INDEX service_jobs_org_account_idx
  ON service_jobs (organization_id, account_id, created_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX service_jobs_org_deal_idx
  ON service_jobs (organization_id, deal_id)
  WHERE deleted_at IS NULL AND deal_id IS NOT NULL;

CREATE INDEX service_jobs_org_completed_idx
  ON service_jobs (organization_id, completed_at DESC)
  WHERE deleted_at IS NULL AND completed_at IS NOT NULL;

CREATE INDEX service_jobs_custom_fields_idx
  ON service_jobs USING gin (custom_fields jsonb_path_ops);

CREATE INDEX service_jobs_tags_idx ON service_jobs USING gin (tags);

SELECT app.attach_tenant_triggers('service_jobs');

CREATE TRIGGER service_jobs_service_same_org
  BEFORE INSERT OR UPDATE OF service_id ON service_jobs
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('services', 'service_id');

CREATE TRIGGER service_jobs_account_same_org
  BEFORE INSERT OR UPDATE OF account_id ON service_jobs
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('accounts', 'account_id');

CREATE TRIGGER service_jobs_contact_same_org
  BEFORE INSERT OR UPDATE OF contact_id ON service_jobs
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('contacts', 'contact_id');

CREATE TRIGGER service_jobs_deal_same_org
  BEFORE INSERT OR UPDATE OF deal_id ON service_jobs
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('deals', 'deal_id');

CREATE TRIGGER service_jobs_pipeline_same_org
  BEFORE INSERT OR UPDATE OF pipeline_id ON service_jobs
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('pipelines', 'pipeline_id');

CREATE TRIGGER service_jobs_stage_same_org
  BEFORE INSERT OR UPDATE OF stage_id ON service_jobs
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('pipeline_stages', 'stage_id');

-- Keep assigned_at honest without making every caller remember to set it.
CREATE OR REPLACE FUNCTION app.stamp_assignment()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.assigned_user_id IS NOT NULL AND NEW.assigned_at IS NULL THEN
      NEW.assigned_at := now();
    END IF;
  ELSE
    IF NEW.assigned_user_id IS DISTINCT FROM OLD.assigned_user_id THEN
      NEW.assigned_at := CASE WHEN NEW.assigned_user_id IS NULL THEN NULL ELSE now() END;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER service_jobs_stamp_assignment
  BEFORE INSERT OR UPDATE OF assigned_user_id ON service_jobs
  FOR EACH ROW EXECUTE FUNCTION app.stamp_assignment();

-- ---------------------------------------------------------------------------
-- Line items — what a job actually consists of, when it is more than one thing.
-- Kept separate from the job so a job can bundle several catalogue services
-- (and so invoicing has a real basis rather than a single opaque amount).
-- ---------------------------------------------------------------------------
CREATE TABLE service_job_items (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  job_id            uuid NOT NULL REFERENCES service_jobs(id) ON DELETE CASCADE,
  service_id        uuid REFERENCES services(id) ON DELETE SET NULL,

  description       text NOT NULL,
  quantity          numeric(14,4) NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_price        numeric(18,4) NOT NULL DEFAULT 0 CHECK (unit_price >= 0),
  tax_rate          numeric(6,4) NOT NULL DEFAULT 0
                      CHECK (tax_rate >= 0 AND tax_rate <= 1),
  -- Money is computed once, in the database, so no two callers can disagree
  -- about the total.
  line_total        numeric(18,4) GENERATED ALWAYS AS (
                      round(quantity * unit_price * (1 + tax_rate), 4)
                    ) STORED,

  position          integer NOT NULL DEFAULT 0,
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX service_job_items_job_idx
  ON service_job_items (job_id, position);

CREATE TRIGGER service_job_items_job_same_org
  BEFORE INSERT OR UPDATE OF job_id ON service_job_items
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('service_jobs', 'job_id');

CREATE TRIGGER service_job_items_service_same_org
  BEFORE INSERT OR UPDATE OF service_id ON service_job_items
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('services', 'service_id');

COMMIT;
