-- 0008_custom_fields.sql
-- Tenant-defined fields on core entities.
--
-- Every real CRM deployment needs fields the vendor did not ship. Three designs
-- are common, and each was weighed here:
--
--   EAV (attribute + attribute_value tables) — maximally flexible, but every
--   read becomes a pivot and a record with 20 custom fields costs 20 extra rows.
--
--   A typed side-table (one row per entity holding a column per data type) —
--   keeps values typed, but still a join, and adding a type means a migration.
--
--   A JSONB column plus a definitions table — values live on the row (no join,
--   no pivot), Postgres indexes them with GIN, and the definitions table
--   supplies the typing that JSONB alone lacks.
--
-- The third is chosen. The definitions table is what makes it safe: it is the
-- schema-of-the-schema, and a validation trigger enforces it on write, so
-- `custom_fields` cannot drift into an untyped junk drawer. This gives the
-- storage benefits of JSONB without giving up the guarantees that make Strict
-- TypeScript on the read side meaningful.

BEGIN;

CREATE TYPE custom_field_type AS ENUM (
  'text',
  'long_text',
  'number',
  'currency',
  'boolean',
  'date',
  'datetime',
  'select',        -- one of `options`
  'multi_select',  -- subset of `options`
  'email',
  'phone',
  'url',
  'user'           -- references users.id
);

CREATE TABLE custom_field_definitions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  entity_type      crm_entity NOT NULL,
  -- The JSONB key. Constrained to an identifier shape so it is safe to use in
  -- generated TypeScript types and in jsonb path expressions.
  key              text NOT NULL CHECK (key ~ '^[a-z][a-z0-9_]{0,62}$'),
  label            text NOT NULL CHECK (length(btrim(label)) > 0),
  help_text        text,

  field_type       custom_field_type NOT NULL,
  -- Allowed values for select/multi_select: [{"value":"gold","label":"Gold"}]
  options          jsonb NOT NULL DEFAULT '[]'::jsonb,

  is_required      boolean NOT NULL DEFAULT false,
  is_unique        boolean NOT NULL DEFAULT false,
  default_value    jsonb,

  -- Optional bounds, applied by the validation function when present.
  min_value        numeric,
  max_value        numeric,
  max_length       integer CHECK (max_length IS NULL OR max_length > 0),
  pattern          text,

  position         integer NOT NULL DEFAULT 0,
  is_active        boolean NOT NULL DEFAULT true,

  created_by       uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  deleted_at       timestamptz,

  CONSTRAINT custom_field_definitions_key_unique
    UNIQUE (organization_id, entity_type, key),
  CONSTRAINT custom_field_definitions_select_has_options CHECK (
    field_type NOT IN ('select', 'multi_select') OR jsonb_array_length(options) > 0
  )
);

CREATE INDEX custom_field_definitions_lookup_idx
  ON custom_field_definitions (organization_id, entity_type, position)
  WHERE deleted_at IS NULL AND is_active = true;

SELECT app.attach_tenant_triggers('custom_field_definitions');

-- ---------------------------------------------------------------------------
-- Validation.
--
-- Runs on write against the tenant's active definitions for that entity type.
-- Rejects unknown keys, missing required values, and type mismatches. This is
-- the difference between "JSONB column" and "tenant-defined schema".
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.validate_custom_fields(
  p_org         uuid,
  p_entity_type crm_entity,
  p_values      jsonb
)
RETURNS void
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_def   record;
  v_key   text;
  v_val   jsonb;
  v_num   numeric;
  v_text  text;
BEGIN
  IF p_values IS NULL OR p_values = '{}'::jsonb THEN
    -- Still need to catch required fields with no value supplied at all.
    NULL;
  END IF;

  -- Unknown keys are a bug in the caller, not data to be silently kept.
  FOR v_key IN SELECT jsonb_object_keys(coalesce(p_values, '{}'::jsonb)) LOOP
    IF NOT EXISTS (
      SELECT 1 FROM custom_field_definitions d
       WHERE d.organization_id = p_org
         AND d.entity_type = p_entity_type
         AND d.key = v_key
         AND d.deleted_at IS NULL
         AND d.is_active = true
    ) THEN
      RAISE EXCEPTION
        'unknown custom field "%" for % in organization %', v_key, p_entity_type, p_org
        USING ERRCODE = 'invalid_parameter_value';
    END IF;
  END LOOP;

  FOR v_def IN
    SELECT * FROM custom_field_definitions d
     WHERE d.organization_id = p_org
       AND d.entity_type = p_entity_type
       AND d.deleted_at IS NULL
       AND d.is_active = true
  LOOP
    v_val := coalesce(p_values, '{}'::jsonb) -> v_def.key;

    IF v_val IS NULL OR jsonb_typeof(v_val) = 'null' THEN
      IF v_def.is_required THEN
        RAISE EXCEPTION 'custom field "%" is required', v_def.key
          USING ERRCODE = 'not_null_violation';
      END IF;
      CONTINUE;
    END IF;

    CASE v_def.field_type
      WHEN 'number', 'currency' THEN
        IF jsonb_typeof(v_val) <> 'number' THEN
          RAISE EXCEPTION 'custom field "%" expects a number, got %',
            v_def.key, jsonb_typeof(v_val)
            USING ERRCODE = 'invalid_parameter_value';
        END IF;
        v_num := (v_val #>> '{}')::numeric;
        IF v_def.min_value IS NOT NULL AND v_num < v_def.min_value THEN
          RAISE EXCEPTION 'custom field "%" is below minimum %', v_def.key, v_def.min_value
            USING ERRCODE = 'check_violation';
        END IF;
        IF v_def.max_value IS NOT NULL AND v_num > v_def.max_value THEN
          RAISE EXCEPTION 'custom field "%" is above maximum %', v_def.key, v_def.max_value
            USING ERRCODE = 'check_violation';
        END IF;

      WHEN 'boolean' THEN
        IF jsonb_typeof(v_val) <> 'boolean' THEN
          RAISE EXCEPTION 'custom field "%" expects a boolean', v_def.key
            USING ERRCODE = 'invalid_parameter_value';
        END IF;

      WHEN 'multi_select' THEN
        IF jsonb_typeof(v_val) <> 'array' THEN
          RAISE EXCEPTION 'custom field "%" expects an array', v_def.key
            USING ERRCODE = 'invalid_parameter_value';
        END IF;
        IF EXISTS (
          SELECT 1 FROM jsonb_array_elements_text(v_val) AS e(val)
           WHERE NOT EXISTS (
             SELECT 1 FROM jsonb_array_elements(v_def.options) AS o
              WHERE o ->> 'value' = e.val
           )
        ) THEN
          RAISE EXCEPTION 'custom field "%" contains a value outside its options', v_def.key
            USING ERRCODE = 'check_violation';
        END IF;

      WHEN 'select' THEN
        IF NOT EXISTS (
          SELECT 1 FROM jsonb_array_elements(v_def.options) AS o
           WHERE o ->> 'value' = (v_val #>> '{}')
        ) THEN
          RAISE EXCEPTION 'custom field "%" value "%" is not one of its options',
            v_def.key, (v_val #>> '{}')
            USING ERRCODE = 'check_violation';
        END IF;

      WHEN 'date', 'datetime' THEN
        BEGIN
          PERFORM (v_val #>> '{}')::timestamptz;
        EXCEPTION WHEN OTHERS THEN
          RAISE EXCEPTION 'custom field "%" is not a valid timestamp', v_def.key
            USING ERRCODE = 'invalid_datetime_format';
        END;

      WHEN 'user' THEN
        BEGIN
          PERFORM (v_val #>> '{}')::uuid;
        EXCEPTION WHEN OTHERS THEN
          RAISE EXCEPTION 'custom field "%" is not a valid user id', v_def.key
            USING ERRCODE = 'invalid_text_representation';
        END;

      WHEN 'email' THEN
        v_text := v_val #>> '{}';
        IF v_text !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
          RAISE EXCEPTION 'custom field "%" is not a valid email address', v_def.key
            USING ERRCODE = 'invalid_parameter_value';
        END IF;

      ELSE  -- text, long_text, phone, url
        v_text := v_val #>> '{}';
        IF v_def.max_length IS NOT NULL AND length(v_text) > v_def.max_length THEN
          RAISE EXCEPTION 'custom field "%" exceeds max length %', v_def.key, v_def.max_length
            USING ERRCODE = 'string_data_right_truncation';
        END IF;
        IF v_def.pattern IS NOT NULL AND v_text !~ v_def.pattern THEN
          RAISE EXCEPTION 'custom field "%" does not match its required pattern', v_def.key
            USING ERRCODE = 'check_violation';
        END IF;
    END CASE;
  END LOOP;
END;
$$;

-- Trigger wrapper: infers the entity type from the table being written.
CREATE OR REPLACE FUNCTION app.enforce_custom_fields()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_entity crm_entity := TG_ARGV[0]::crm_entity;
BEGIN
  PERFORM app.validate_custom_fields(NEW.organization_id, v_entity, NEW.custom_fields);
  RETURN NEW;
END;
$$;

CREATE TRIGGER accounts_validate_custom_fields
  BEFORE INSERT OR UPDATE OF custom_fields ON accounts
  FOR EACH ROW EXECUTE FUNCTION app.enforce_custom_fields('account');

CREATE TRIGGER contacts_validate_custom_fields
  BEFORE INSERT OR UPDATE OF custom_fields ON contacts
  FOR EACH ROW EXECUTE FUNCTION app.enforce_custom_fields('contact');

CREATE TRIGGER leads_validate_custom_fields
  BEFORE INSERT OR UPDATE OF custom_fields ON leads
  FOR EACH ROW EXECUTE FUNCTION app.enforce_custom_fields('lead');

CREATE TRIGGER deals_validate_custom_fields
  BEFORE INSERT OR UPDATE OF custom_fields ON deals
  FOR EACH ROW EXECUTE FUNCTION app.enforce_custom_fields('deal');

CREATE TRIGGER service_jobs_validate_custom_fields
  BEFORE INSERT OR UPDATE OF custom_fields ON service_jobs
  FOR EACH ROW EXECUTE FUNCTION app.enforce_custom_fields('service_job');

CREATE TRIGGER services_validate_custom_fields
  BEFORE INSERT OR UPDATE OF custom_fields ON services
  FOR EACH ROW EXECUTE FUNCTION app.enforce_custom_fields('service');

COMMIT;
