/**
 * Scalar type mappings between PostgreSQL and TypeScript.
 *
 * These are not cosmetic aliases. Each one encodes a decision about how a
 * Postgres type actually arrives in Node, and getting them wrong produces bugs
 * that survive typechecking and surface as wrong money or wrong dates in
 * production.
 *
 * See src/db/migrations/ for the authoritative schema.
 */

/**
 * A UUID primary key, branded by the table it belongs to.
 *
 * The CRM schema has dozens of uuid columns and most functions take several at
 * once. Plain `string` lets you pass an AccountId where a ContactId is expected
 * and the compiler will not notice. Branding makes that a compile error while
 * remaining a plain string at runtime — no wrapper object, no cost.
 */
export type Id<TBrand extends string> = string & { readonly __brand: TBrand };

/**
 * PostgreSQL `numeric` / `decimal`.
 *
 * Represented as a STRING, not a number. `numeric` is arbitrary precision;
 * IEEE-754 doubles are not. node-postgres returns numeric as a string
 * specifically to avoid silently losing precision, and converting it to a
 * number to "make the types nicer" reintroduces exactly the error the database
 * type was chosen to prevent.
 *
 * Never do arithmetic on this directly. Use a decimal library, or push the
 * arithmetic into SQL where the schema already computes base_amount,
 * weighted_amount and line_total as generated columns.
 */
export type Numeric = string & { readonly __numeric: true };

/**
 * PostgreSQL `bigint` (int8).
 *
 * Also a string. int8 exceeds Number.MAX_SAFE_INTEGER, and node-postgres
 * returns it as a string by default rather than lose the high bits.
 */
export type BigIntString = string & { readonly __bigint: true };

/** PostgreSQL `date` — calendar day with no time or zone, as 'YYYY-MM-DD'. */
export type DateOnly = string & { readonly __dateOnly: true };

/** PostgreSQL `char(3)` ISO-4217 currency code. */
export type CurrencyCode = string & { readonly __currency: true };

/** PostgreSQL `interval`, in ISO-8601 duration or Postgres interval syntax. */
export type IntervalString = string & { readonly __interval: true };

/** PostgreSQL `inet`. */
export type IpAddress = string & { readonly __inet: true };

/**
 * PostgreSQL `bytea`.
 *
 * node-postgres returns a Node `Buffer`, which is a `Uint8Array` subclass —
 * typed as `Uint8Array` here so these types do not require @types/node.
 *
 * Not branded: a brand would break assignability from the `Buffer` the driver
 * actually hands back, which is the one value this type exists to describe.
 */
export type Bytea = Uint8Array;

/**
 * A SHA-256 digest as raw bytes — exactly 32 of them, enforced by a CHECK
 * constraint rather than by the type. Stored raw rather than as 64 hex
 * characters: half the storage, and a malformed digest becomes a constraint
 * violation instead of a silent mismatch that never matches anything.
 */
export type Sha256Digest = Bytea;

/**
 * A JSONB column. Deliberately `unknown`-valued rather than `any`: JSONB
 * contents are not verified by the compiler, so consumers must narrow before
 * use. Custom-field values additionally get runtime validation from the
 * database trigger in 0008_custom_fields.sql.
 */
export type Json =
  | string
  | number
  | boolean
  | null
  | Json[]
  | { [key: string]: Json };

export type JsonObject = { [key: string]: Json };

/**
 * Required driver configuration.
 *
 * node-postgres parses `timestamptz` and `date` into JavaScript Date objects by
 * default. These types assume `timestamptz` arrives as a Date but `date`
 * arrives as a plain 'YYYY-MM-DD' string, because a calendar date coerced to a
 * Date acquires a spurious timezone and can shift by a day.
 *
 * Configure the parser to match before using these types:
 *
 *   import pgTypes from 'pg-types';
 *   // 1082 = DATE: keep as string, do not construct a Date
 *   pgTypes.setTypeParser(1082, (v: string) => v);
 *
 * Without this, `expected_close_date` typed as DateOnly will actually be a Date
 * at runtime and comparisons against it will be subtly wrong.
 */
export const PG_TYPE_OID = {
  DATE: 1082,
  NUMERIC: 1700,
  INT8: 20,
} as const;
