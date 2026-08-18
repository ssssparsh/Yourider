/**
 * Runtime verification that these TypeScript types still match the database.
 *
 * Hand-written types drift. The compiler cannot catch it, because both sides
 * typecheck fine while disagreeing — a new enum value added in a migration is
 * invisible to TypeScript until a row carrying it arrives at runtime and
 * something downstream silently mishandles it.
 *
 * These checks close that gap by querying the live catalog. Run them in CI
 * against a freshly migrated database.
 */

import { DATABASE_ENUMS } from './enums.js';
import { CONSENT_DATABASE_ENUMS } from './consent.js';
import { ATTACHMENT_DATABASE_ENUMS } from './attachments.js';

/** Every registered enum across all modules. */
const ALL_DATABASE_ENUMS = {
  ...DATABASE_ENUMS,
  ...CONSENT_DATABASE_ENUMS,
  ...ATTACHMENT_DATABASE_ENUMS,
} as const;

/** Minimal query interface — satisfied by a `pg` Pool or Client. */
export interface Queryable {
  query<R>(sql: string, params?: readonly unknown[]): Promise<{ rows: R[] }>;
}

export interface DriftReport {
  readonly enumName: string;
  /** Present in the database, missing from the TypeScript union. */
  readonly missingInTypeScript: readonly string[];
  /** Present in the TypeScript union, missing from the database. */
  readonly missingInDatabase: readonly string[];
}

/**
 * Compares every registered enum against pg_enum.
 * Returns one report per enum that disagrees; an empty array means no drift.
 */
export async function findEnumDrift(db: Queryable): Promise<DriftReport[]> {
  const { rows } = await db.query<{ enum_name: string; values: string[] }>(
    `SELECT t.typname AS enum_name,
            array_agg(e.enumlabel ORDER BY e.enumsortorder) AS values
       FROM pg_type t
       JOIN pg_enum e ON e.enumtypid = t.oid
       JOIN pg_namespace n ON n.oid = t.typnamespace
      WHERE n.nspname = 'public'
      GROUP BY t.typname`,
  );

  const dbEnums = new Map(rows.map((r) => [r.enum_name, new Set(r.values)]));
  const reports: DriftReport[] = [];

  for (const [enumName, tsEnum] of Object.entries(ALL_DATABASE_ENUMS)) {
    const tsValues = new Set<string>(Object.values(tsEnum));
    const dbValues = dbEnums.get(enumName);

    if (dbValues === undefined) {
      reports.push({
        enumName,
        missingInTypeScript: [],
        missingInDatabase: [...tsValues],
      });
      continue;
    }

    const missingInTypeScript = [...dbValues].filter((v) => !tsValues.has(v));
    const missingInDatabase = [...tsValues].filter((v) => !dbValues.has(v));

    if (missingInTypeScript.length > 0 || missingInDatabase.length > 0) {
      reports.push({ enumName, missingInTypeScript, missingInDatabase });
    }
  }

  return reports;
}

/** Throws with a readable diff when any enum has drifted. */
export async function assertNoEnumDrift(db: Queryable): Promise<void> {
  const drift = await findEnumDrift(db);
  if (drift.length === 0) return;

  const detail = drift
    .map((d) => {
      const parts: string[] = [];
      if (d.missingInTypeScript.length > 0) {
        parts.push(`missing in TypeScript: ${d.missingInTypeScript.join(', ')}`);
      }
      if (d.missingInDatabase.length > 0) {
        parts.push(`missing in database: ${d.missingInDatabase.join(', ')}`);
      }
      return `  ${d.enumName}: ${parts.join('; ')}`;
    })
    .join('\n');

  throw new Error(
    `Enum drift between src/crm/types/enums.ts and the database:\n${detail}\n` +
      `Update enums.ts (and DATABASE_ENUMS) to match the migrations.`,
  );
}

/**
 * Verifies that every table carrying an organization_id has RLS enabled and
 * forced.
 *
 * This is a security regression test, not a typing one. A new tenant table
 * added without `SELECT app.apply_tenant_rls(...)` is readable across tenants
 * and nothing else will tell you. FORCE matters as much as ENABLE: without it
 * the table owner bypasses every policy.
 */
export async function findTablesMissingRls(db: Queryable): Promise<string[]> {
  const { rows } = await db.query<{ tablename: string }>(
    `SELECT c.relname AS tablename
       FROM pg_class c
       JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relkind IN ('r', 'p')
        AND EXISTS (
          SELECT 1 FROM pg_attribute a
           WHERE a.attrelid = c.oid
             AND a.attname = 'organization_id'
             AND NOT a.attisdropped
        )
        AND NOT (c.relrowsecurity AND c.relforcerowsecurity)
      ORDER BY c.relname`,
  );
  return rows.map((r) => r.tablename);
}

export async function assertAllTenantTablesHaveRls(db: Queryable): Promise<void> {
  const missing = await findTablesMissingRls(db);
  if (missing.length === 0) return;
  throw new Error(
    `Tables with organization_id but without ENABLE + FORCE row level ` +
      `security:\n  ${missing.join('\n  ')}\n` +
      `Add SELECT app.apply_tenant_rls('<table>') to the migration.`,
  );
}
