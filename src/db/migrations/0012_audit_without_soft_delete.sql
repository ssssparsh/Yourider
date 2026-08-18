-- 0012_audit_without_soft_delete.sql
-- Makes the audit trigger work on tables that have no `deleted_at` column.
--
-- THE BUG
--
-- app.record_audit() from 0007 reads OLD.deleted_at directly to classify a soft
-- delete. plpgsql resolves that field reference at runtime against the actual
-- row type, so on any audited table without that column the trigger raises:
--
--   record "old" has no field "deleted_at"
--
-- Every table audited before now happened to have `deleted_at`, so the
-- assumption held silently. `suppressions` (0011) breaks it: it uses
-- `released_at`, because a suppression is not soft-deleted — it is released,
-- which is a distinct and auditable act. Attaching audit to it made every
-- UPDATE fail.
--
-- THE FIX
--
-- Read the column through the row's jsonb representation instead. A missing key
-- yields NULL rather than an error, so the classification degrades to a plain
-- 'update' on tables that do not do soft deletes — which is the correct answer
-- for them.
--
-- Worth noting for future triggers: `to_jsonb(NEW) ->> 'col'` is the portable
-- way to touch a column that may not exist on every table a generic trigger is
-- attached to. Direct field access couples the trigger to one table shape.

BEGIN;

CREATE OR REPLACE FUNCTION app.record_audit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_old_json jsonb;
  v_new_json jsonb;
  v_old      jsonb := '{}'::jsonb;
  v_new      jsonb := '{}'::jsonb;
  v_changed  text[] := '{}';
  v_action   audit_action;
  v_org      uuid;
  v_record   uuid;
  v_key      text;
  v_actor_type actor_kind;
  v_agent    text;
  v_was_deleted text;
  v_is_deleted  text;
BEGIN
  v_agent := nullif(current_setting('app.current_agent', true), '');
  IF v_agent IS NOT NULL THEN
    v_actor_type := 'agent';
  ELSIF app.current_user_id() IS NOT NULL THEN
    v_actor_type := 'user';
  ELSE
    v_actor_type := 'system';
  END IF;

  IF TG_OP = 'INSERT' THEN
    v_new_json := to_jsonb(NEW);
    v_action := 'insert';
    v_new := v_new_json;
    v_org := (v_new_json ->> 'organization_id')::uuid;
    v_record := (v_new_json ->> 'id')::uuid;

  ELSIF TG_OP = 'UPDATE' THEN
    v_old_json := to_jsonb(OLD);
    v_new_json := to_jsonb(NEW);
    v_org := (v_new_json ->> 'organization_id')::uuid;
    v_record := (v_new_json ->> 'id')::uuid;

    -- Via jsonb, so a table without `deleted_at` yields NULL instead of raising.
    v_was_deleted := v_old_json ->> 'deleted_at';
    v_is_deleted  := v_new_json ->> 'deleted_at';

    IF v_was_deleted IS NULL AND v_is_deleted IS NOT NULL THEN
      v_action := 'delete';
    ELSIF v_was_deleted IS NOT NULL AND v_is_deleted IS NULL THEN
      v_action := 'restore';
    ELSE
      v_action := 'update';
    END IF;

    FOR v_key IN SELECT jsonb_object_keys(v_new_json) LOOP
      IF v_new_json -> v_key IS DISTINCT FROM v_old_json -> v_key THEN
        IF v_key <> 'updated_at' THEN
          v_changed := v_changed || v_key;
          v_old := v_old || jsonb_build_object(v_key, v_old_json -> v_key);
          v_new := v_new || jsonb_build_object(v_key, v_new_json -> v_key);
        END IF;
      END IF;
    END LOOP;

    IF array_length(v_changed, 1) IS NULL THEN
      RETURN NEW;
    END IF;

  ELSE  -- DELETE
    v_old_json := to_jsonb(OLD);
    v_action := 'delete';
    v_old := v_old_json;
    v_org := (v_old_json ->> 'organization_id')::uuid;
    v_record := (v_old_json ->> 'id')::uuid;
  END IF;

  INSERT INTO audit_log (
    organization_id, table_name, record_id, action,
    changed_fields, old_values, new_values,
    actor_type, actor_user_id, actor_agent, reason, request_id
  ) VALUES (
    v_org, TG_TABLE_NAME, v_record, v_action,
    v_changed, v_old, v_new,
    v_actor_type, app.current_user_id(), v_agent,
    nullif(current_setting('app.audit_reason', true), ''),
    nullif(current_setting('app.request_id', true), '')
  );

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

COMMIT;
