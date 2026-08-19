/**
 * API keys, webhooks, notifications, merge/dedup, import batches, and FX
 * provenance.
 *
 * Mirrors src/db/migrations/0019_platform.sql.
 *
 * Webhook DELIVERY (the outbound HTTP call) is not built here, for the same
 * reason the automation worker (0015) is not: this module's types describe
 * state and authorisation; a process outside makes the network call.
 */

import type { Bytea, Id, JsonObject } from './scalars.js';
import type { CrmEntity } from './enums.js';
import type { OrganizationId, UserId } from './entities.js';

// ---------------------------------------------------------------------------
// API keys
// ---------------------------------------------------------------------------

export type ApiKeyId = Id<'ApiKey'>;

/**
 * Only the hash and a short prefix are ever stored — see `issue_api_key`.
 * There is no field that could round-trip into a usable credential, which is
 * deliberate: this type is safe to log or send to a client in full.
 */
export interface ApiKey {
  readonly id: ApiKeyId;
  readonly organization_id: OrganizationId;
  readonly name: string;
  readonly key_hash: Bytea;
  /** First few characters, shown in a UI list — never enough to be usable. */
  readonly key_prefix: string;
  readonly scopes: readonly string[];
  readonly created_by: UserId | null;
  readonly created_at: Date;
  readonly last_used_at: Date | null;
  readonly expires_at: Date | null;
  readonly revoked_at: Date | null;
  readonly revoked_by: UserId | null;
  readonly updated_at: Date;
}

/**
 * Result of `app.issue_api_key()`. `secret` is shown to the user exactly once
 * — there is no function that can retrieve it again after this call returns,
 * by construction, so the caller must display or hand it off immediately.
 */
export interface IssuedApiKey {
  readonly id: ApiKeyId;
  readonly secret: string;
  readonly prefix: string;
}

export interface IssueApiKeyArgs {
  name: string;
  scopes?: readonly string[];
}

// ---------------------------------------------------------------------------
// Webhooks
// ---------------------------------------------------------------------------

export type WebhookSubscriptionId = Id<'WebhookSubscription'>;
export type WebhookDeliveryId = Id<'WebhookDelivery'>;

export interface WebhookSubscription {
  readonly id: WebhookSubscriptionId;
  readonly organization_id: OrganizationId;
  /** Always https:// — enforced by CHECK. */
  readonly url: string;
  /**
   * HMAC signing secret, generated server-side. Never supplied by the caller —
   * a value whose whole purpose is proving authenticity must not be choosable
   * by the party being authenticated, the same reasoning as a storage key
   * (see DECISIONS.md D15).
   */
  readonly signing_secret: Bytea;
  readonly event_types: readonly string[];
  readonly is_active: boolean;
  readonly created_by: UserId | null;
  readonly created_at: Date;
  readonly updated_at: Date;
  readonly deleted_at: Date | null;
}

export interface WebhookSubscriptionInsert {
  url: string;
  event_types: readonly string[];
  is_active?: boolean;
}

export const WebhookDeliveryStatus = {
  Pending: 'pending',
  Delivered: 'delivered',
  Failed: 'failed',
} as const;
export type WebhookDeliveryStatus =
  (typeof WebhookDeliveryStatus)[keyof typeof WebhookDeliveryStatus];

export interface WebhookDelivery {
  readonly id: WebhookDeliveryId;
  readonly organization_id: OrganizationId;
  readonly subscription_id: WebhookSubscriptionId;
  readonly event_type: string;
  readonly payload: JsonObject;
  readonly status: WebhookDeliveryStatus;
  readonly attempt: number;
  readonly run_after: Date;
  readonly response_code: number | null;
  /** Truncated by the application before insert — never store an unbounded body. */
  readonly response_body: string | null;
  readonly created_at: Date;
  readonly delivered_at: Date | null;
}

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

export type NotificationId = Id<'Notification'>;

export const NotificationKind = {
  Assignment: 'assignment',
  Mention: 'mention',
  /** An approval_requests row (0015) needs the recipient's decision. */
  ApprovalNeeded: 'approval_needed',
  StageChange: 'stage_change',
  TaskDue: 'task_due',
  System: 'system',
} as const;
export type NotificationKind =
  (typeof NotificationKind)[keyof typeof NotificationKind];

/**
 * Addressed to exactly one person. Unlike most tenant tables, RLS narrows
 * SELECT to `user_id = current_user_id()` — the standing tenant-wide default
 * would let a colleague read someone else's inbox.
 */
export interface Notification {
  readonly id: NotificationId;
  readonly organization_id: OrganizationId;
  readonly user_id: UserId;
  readonly kind: NotificationKind;
  readonly title: string;
  readonly body: string | null;
  readonly entity_type: CrmEntity | null;
  readonly entity_id: string | null;
  readonly is_read: boolean;
  readonly read_at: Date | null;
  readonly created_at: Date;
}

export interface NotificationInsert {
  user_id: UserId;
  kind: NotificationKind;
  title: string;
  body?: string | null;
  entity_type?: CrmEntity | null;
  entity_id?: string | null;
}

// ---------------------------------------------------------------------------
// Merge and dedup
// ---------------------------------------------------------------------------

export type EntityMergeId = Id<'EntityMerge'>;

/** The two entities `app.merge_contacts()` / `app.merge_accounts()` support. */
export type MergeableEntity = 'contact' | 'account';

/**
 * Append-only record of a merge, with a full snapshot of the losing row.
 *
 * History is not rewritten: `activities` and `audit_log` keep the merged-away
 * id, so this is what makes the survivor's full timeline reconstructable
 * across both ids. See the migration header for the full reasoning.
 */
export interface EntityMerge {
  readonly id: EntityMergeId;
  readonly organization_id: OrganizationId;
  readonly entity_type: MergeableEntity;
  readonly survivor_id: string;
  readonly merged_id: string;
  readonly merged_snapshot: JsonObject;
  readonly merged_by: UserId | null;
  readonly merged_at: Date;
}

// ---------------------------------------------------------------------------
// Import batches
// ---------------------------------------------------------------------------

export type ImportBatchId = Id<'ImportBatch'>;

/** The entity types `app.rollback_import_batch()` knows how to undo. */
export type ImportableEntity = 'account' | 'contact' | 'lead' | 'deal';

export const ImportBatchStatus = {
  Processing: 'processing',
  Completed: 'completed',
  CompletedWithErrors: 'completed_with_errors',
  Failed: 'failed',
  RolledBack: 'rolled_back',
} as const;
export type ImportBatchStatus =
  (typeof ImportBatchStatus)[keyof typeof ImportBatchStatus];

export interface ImportRowError {
  readonly row: number;
  readonly error: string;
}

export interface ImportBatch {
  readonly id: ImportBatchId;
  readonly organization_id: OrganizationId;
  readonly entity_type: CrmEntity;
  readonly source_filename: string | null;
  readonly source_file_id: Id<'File'> | null;
  readonly status: ImportBatchStatus;
  readonly total_rows: number | null;
  readonly succeeded_rows: number;
  readonly failed_rows: number;
  readonly errors: readonly ImportRowError[];
  readonly created_by: UserId | null;
  readonly created_at: Date;
  readonly completed_at: Date | null;
}

// ---------------------------------------------------------------------------
// FX provenance
// ---------------------------------------------------------------------------

export type FxRateId = Id<'FxRate'>;

/**
 * A point-in-time exchange rate, with where it came from. Immutable — a
 * correction is a new row with a later `as_of`, not an edit.
 *
 * This does not fetch rates; it gives a place to record one once a live rates
 * API is connected. See the top-level API-requirements summary.
 */
export interface FxRate {
  readonly id: FxRateId;
  readonly organization_id: OrganizationId;
  readonly from_currency: string;
  readonly to_currency: string;
  readonly rate: string;
  readonly source: string;
  readonly as_of: Date;
  readonly created_at: Date;
}

export interface FxRateInsert {
  from_currency: string;
  to_currency: string;
  rate: string;
  source: string;
  as_of: Date;
}

/**
 * Every database enum introduced by 0019, for the drift check in verify.ts.
 */
export const PLATFORM_DATABASE_ENUMS = {
  webhook_delivery_status: WebhookDeliveryStatus,
  notification_kind: NotificationKind,
  import_batch_status: ImportBatchStatus,
} as const;
