/**
 * Teams, saved views, and field/row permissions.
 *
 * Mirrors src/db/migrations/0016_teams.sql, 0017_saved_views.sql, and
 * 0018_field_row_permissions.sql.
 */

import type { Id, JsonObject } from './scalars.js';
import type { CrmEntity, MembershipRole } from './enums.js';
import type { OrganizationId, UserId } from './entities.js';

// ---------------------------------------------------------------------------
// Teams
// ---------------------------------------------------------------------------

export type TeamId = Id<'Team'>;

/**
 * Replaces the free-text `memberships.team` column (retained, non-destructive
 * — see DECISIONS.md D23). A typo in a string silently creates a new team; a
 * row cannot.
 */
export interface Team {
  readonly id: TeamId;
  readonly organization_id: OrganizationId;
  readonly name: string;
  readonly parent_team_id: TeamId | null;
  readonly lead_user_id: UserId | null;
  readonly description: string | null;
  readonly created_at: Date;
  readonly updated_at: Date;
  readonly deleted_at: Date | null;
}

export interface TeamInsert {
  name: string;
  parent_team_id?: TeamId | null;
  lead_user_id?: UserId | null;
  description?: string | null;
}

// ---------------------------------------------------------------------------
// Saved views
// ---------------------------------------------------------------------------

export type SavedViewId = Id<'SavedView'>;

export const SavedViewVisibility = {
  /** Only the owner sees it. */
  Private: 'private',
  /** The owner's team (and, for a manager, its subtree) sees it. */
  Team: 'team',
  Organization: 'organization',
} as const;
export type SavedViewVisibility =
  (typeof SavedViewVisibility)[keyof typeof SavedViewVisibility];

/**
 * Filters, sorts, columns, and board config are opaque JSON on purpose — the
 * same reasoning as `custom_fields` (DECISIONS.md D5). A frontend filter DSL
 * changes shape far more often than this table should need a migration.
 */
export interface SavedView {
  readonly id: SavedViewId;
  readonly organization_id: OrganizationId;
  readonly entity_type: CrmEntity;
  readonly name: string;
  readonly filters: readonly JsonObject[];
  readonly sort: readonly JsonObject[];
  readonly columns: readonly JsonObject[];
  readonly board_config: JsonObject | null;
  readonly visibility: SavedViewVisibility;
  readonly owner_id: UserId;
  readonly is_default: boolean;
  /** Lets automation point at a stable target instead of re-embedding a filter. */
  readonly is_system: boolean;
  readonly position: number;
  readonly created_at: Date;
  readonly updated_at: Date;
  readonly deleted_at: Date | null;
}

export interface SavedViewInsert {
  entity_type: CrmEntity;
  name: string;
  filters?: readonly JsonObject[];
  sort?: readonly JsonObject[];
  columns?: readonly JsonObject[];
  board_config?: JsonObject | null;
  visibility?: SavedViewVisibility;
  owner_id: UserId;
  is_default?: boolean;
  is_system?: boolean;
  position?: number;
}

// ---------------------------------------------------------------------------
// Field-level redaction
// ---------------------------------------------------------------------------

export type FieldPermissionId = Id<'FieldPermission'>;

/**
 * Which roles a custom field (or bare column) is hidden from.
 *
 * There is no database-enforced column-level security here — see
 * `redactFields` below and DECISIONS.md D24 for why. The application must call
 * it before a record leaves the database.
 */
export interface FieldPermission {
  readonly id: FieldPermissionId;
  readonly organization_id: OrganizationId;
  readonly entity_type: CrmEntity;
  readonly field_key: string;
  readonly hidden_from_roles: readonly MembershipRole[];
  readonly reason: string | null;
  readonly created_by: UserId | null;
  readonly created_at: Date;
  readonly updated_at: Date;
}

export interface FieldPermissionInsert {
  entity_type: CrmEntity;
  field_key: string;
  hidden_from_roles?: readonly MembershipRole[];
  reason?: string | null;
}

/**
 * Client-side mirror of `app.redact_fields()`. Owner and admin are never
 * redacted — the same rule the database function enforces — so a client
 * rendering ahead of a round-trip does not have to special-case them
 * differently from what the server will actually return.
 */
export function redactFields(
  fields: JsonObject,
  role: MembershipRole,
  hiddenKeysForRole: readonly string[],
): JsonObject {
  if (role === 'owner' || role === 'admin') return fields;
  const out = { ...fields };
  for (const key of hiddenKeysForRole) delete out[key];
  return out;
}

// ---------------------------------------------------------------------------
// Row-level sharing
// ---------------------------------------------------------------------------

export type RecordShareId = Id<'RecordShare'>;

export const SharePermission = { View: 'view', Edit: 'edit' } as const;
export type SharePermission =
  (typeof SharePermission)[keyof typeof SharePermission];

/**
 * A specific record made visible to a specific user or team beyond whatever
 * the standing policy would otherwise show them.
 *
 * GROUNDWORK, NOT ENFORCEMENT. Today's RLS is tenant-wide (DECISIONS.md D2):
 * every member already sees every record in the tenant, so this table is not
 * yet consulted by any SELECT policy. It is the exception list a *stricter*
 * future policy would be built on. See DECISIONS.md D24.
 */
export interface RecordShare {
  readonly id: RecordShareId;
  readonly organization_id: OrganizationId;
  readonly entity_type: CrmEntity;
  readonly entity_id: string;
  /** Exactly one of these is set. */
  readonly shared_with_user_id: UserId | null;
  readonly shared_with_team_id: TeamId | null;
  readonly permission: SharePermission;
  readonly reason: string | null;
  readonly expires_at: Date | null;
  readonly granted_by: UserId | null;
  readonly created_at: Date;
  readonly revoked_at: Date | null;
  readonly revoked_by: UserId | null;
}

/**
 * Exactly one of `shared_with_user_id` / `shared_with_team_id` — expressed as
 * a union rather than two optional fields, so a caller cannot construct the
 * "both" or "neither" shape the database CHECK constraint would reject anyway.
 */
export type RecordShareInsert = {
  entity_type: CrmEntity;
  entity_id: string;
  permission?: SharePermission;
  reason?: string | null;
  expires_at?: Date | null;
} & (
  | { shared_with_user_id: UserId; shared_with_team_id?: never }
  | { shared_with_team_id: TeamId; shared_with_user_id?: never }
);

/**
 * Every database enum introduced by 0017 and 0018, for the drift check in
 * verify.ts. 0016 (teams) introduces no new enum.
 */
export const WORKSPACE_DATABASE_ENUMS = {
  saved_view_visibility: SavedViewVisibility,
  share_permission: SharePermission,
} as const;
