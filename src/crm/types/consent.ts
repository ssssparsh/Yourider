/**
 * Consent, suppression, and delivery events.
 *
 * Mirrors src/db/migrations/0011_consent.sql.
 *
 * The governing rule, encoded here as far as types can encode it: nothing
 * outbound is sent without first calling the gate. The approval gate in
 * CLAUDE.md §3 governs whether a send is *attempted*; consent governs whether
 * it is *lawful*. They are separate checks and both must pass.
 */

import type { Id, IntervalString, JsonObject } from './scalars.js';
import type { ActorKind } from './enums.js';
import type { ContactId, OrganizationId, UserId } from './entities.js';

// ---------------------------------------------------------------------------
// Enums — mirrors of the database types
// ---------------------------------------------------------------------------

export const ChannelType = {
  Email: 'email',
  Sms: 'sms',
  Phone: 'phone',
  Push: 'push',
  Postal: 'postal',
} as const;
export type ChannelType = (typeof ChannelType)[keyof typeof ChannelType];

export const ConsentStateKind = {
  /** Asked, awaiting confirmation. Double opt-in lands here first. */
  Pending: 'pending',
  Granted: 'granted',
  /** Explicitly refused when asked. */
  Denied: 'denied',
  /** Previously granted, since revoked. */
  Withdrawn: 'withdrawn',
  /** Time-limited consent that has lapsed. */
  Expired: 'expired',
} as const;
export type ConsentStateKind =
  (typeof ConsentStateKind)[keyof typeof ConsentStateKind];

export const ConsentSource = {
  WebForm: 'web_form',
  /** Confirmed via a clicked confirmation link — the only source that satisfies
   *  a purpose requiring double opt-in. */
  DoubleOptin: 'double_optin',
  /** Bulk load. Weakest evidence; record provenance carefully. */
  Import: 'import',
  Api: 'api',
  Verbal: 'verbal',
  Contract: 'contract',
  PreferenceCentre: 'preference_centre',
  UnsubscribeLink: 'unsubscribe_link',
  Admin: 'admin',
} as const;
export type ConsentSource = (typeof ConsentSource)[keyof typeof ConsentSource];

export const SuppressionReason = {
  HardBounce: 'hard_bounce',
  SoftBounceThreshold: 'soft_bounce_threshold',
  /** Spam report. Permanent. */
  Complaint: 'complaint',
  Manual: 'manual',
  GlobalUnsubscribe: 'global_unsubscribe',
  InvalidAddress: 'invalid_address',
  /** Erasure or do-not-contact order. Permanent. */
  LegalRequest: 'legal_request',
} as const;
export type SuppressionReason =
  (typeof SuppressionReason)[keyof typeof SuppressionReason];

/** Reasons a database CHECK forbids from carrying an expiry. */
export const PERMANENT_SUPPRESSION_REASONS: readonly SuppressionReason[] = [
  SuppressionReason.HardBounce,
  SuppressionReason.Complaint,
  SuppressionReason.LegalRequest,
];

export function isPermanentSuppression(reason: SuppressionReason): boolean {
  return PERMANENT_SUPPRESSION_REASONS.includes(reason);
}

export const MessageEventKind = {
  Queued: 'queued',
  Sent: 'sent',
  Delivered: 'delivered',
  Opened: 'opened',
  Clicked: 'clicked',
  Bounced: 'bounced',
  Complained: 'complained',
  Failed: 'failed',
  Unsubscribed: 'unsubscribed',
} as const;
export type MessageEventKind =
  (typeof MessageEventKind)[keyof typeof MessageEventKind];

export const BounceKind = { Hard: 'hard', Soft: 'soft' } as const;
export type BounceKind = (typeof BounceKind)[keyof typeof BounceKind];

/** Events that cause automatic, permanent suppression on ingestion. */
export const AUTO_SUPPRESSING_EVENTS: readonly MessageEventKind[] = [
  MessageEventKind.Complained,
  MessageEventKind.Unsubscribed,
];

// ---------------------------------------------------------------------------
// Identifiers
// ---------------------------------------------------------------------------

export type ContactChannelId = Id<'ContactChannel'>;
export type ConsentPurposeId = Id<'ConsentPurpose'>;
export type ConsentRecordId = Id<'ConsentRecord'>;
export type SuppressionId = Id<'Suppression'>;
export type MessageEventId = Id<'MessageEvent'>;

// ---------------------------------------------------------------------------
// Entities
// ---------------------------------------------------------------------------

/**
 * An addressable endpoint.
 *
 * Separate from the contact because a person has several, each with its own
 * verification state and its own consent history. Storing the address on the
 * contact makes "which of their two emails did they consent on" unanswerable.
 */
export interface ContactChannel {
  readonly id: ContactChannelId;
  readonly organization_id: OrganizationId;
  readonly contact_id: ContactId;
  readonly channel_type: ChannelType;
  /** Normalised: lowercase email, E.164 phone. Enforced by CHECK constraints. */
  readonly address: string;
  readonly label: string | null;
  readonly is_primary: boolean;
  /**
   * Proof the address reaches this person. Distinct from consent — a verified
   * address may still have no permission to be marketed to.
   */
  readonly verified_at: Date | null;
  readonly created_at: Date;
  readonly updated_at: Date;
  readonly deleted_at: Date | null;
}

export interface ConsentPurpose {
  readonly id: ConsentPurposeId;
  readonly organization_id: OrganizationId;
  readonly key: string;
  readonly name: string;
  readonly description: string | null;
  /**
   * Transactional messages are generally lawful without marketing consent, as
   * performance of a contract. They are NOT exempt from suppression.
   */
  readonly is_transactional: boolean;
  /** A grant only counts once confirmed via a clicked link. */
  readonly requires_double_optin: boolean;
  /** Consent that lapses. Null means it does not expire on its own. */
  readonly default_ttl: IntervalString | null;
  readonly is_active: boolean;
  readonly position: number;
  readonly created_by: UserId | null;
  readonly created_at: Date;
  readonly updated_at: Date;
  readonly deleted_at: Date | null;
}

/**
 * One entry in the append-only ledger.
 *
 * There is no update or delete path, and deliberately no `ConsentRecordUpdate`
 * type. The question asked in a dispute is not "what is their consent" but
 * "what was their consent the day you sent that, and what is your evidence" —
 * which a mutable row cannot answer.
 */
export interface ConsentRecord {
  readonly id: ConsentRecordId;
  readonly organization_id: OrganizationId;
  readonly channel_id: ContactChannelId;
  readonly purpose_id: ConsentPurposeId;
  readonly state: ConsentStateKind;
  readonly source: ConsentSource;
  /** Expected keys: ip, user_agent, form_url, consent_text, confirmation_token. */
  readonly evidence: JsonObject;
  readonly actor_type: ActorKind;
  readonly actor_user_id: UserId | null;
  /** Required by CHECK when actor_type is 'agent'. */
  readonly actor_agent: string | null;
  /** When the consent event happened, not when it was recorded. */
  readonly occurred_at: Date;
  readonly expires_at: Date | null;
  readonly created_at: Date;
}

/**
 * Derived current state — a cache over the ledger so the send-time check is a
 * primary-key lookup. Rebuildable from `consent_records` at any time, and not
 * directly writable: only the ledger trigger maintains it.
 */
export interface ConsentState {
  readonly organization_id: OrganizationId;
  readonly channel_id: ContactChannelId;
  readonly purpose_id: ConsentPurposeId;
  readonly state: ConsentStateKind;
  readonly effective_at: Date;
  readonly expires_at: Date | null;
  readonly source_record_id: ConsentRecordId;
  readonly updated_at: Date;
}

/**
 * An address-level block.
 *
 * Carries no foreign key to contacts, deliberately: an address can be
 * suppressed before any contact exists for it, and deleting a contact must not
 * forget that they asked never to be contacted.
 */
export interface Suppression {
  readonly id: SuppressionId;
  readonly organization_id: OrganizationId;
  readonly channel_type: ChannelType;
  readonly address: string;
  readonly reason: SuppressionReason;
  readonly detail: string | null;
  readonly source: string | null;
  /** Null for permanent reasons; a CHECK enforces that. */
  readonly expires_at: Date | null;
  readonly created_by: UserId | null;
  readonly created_at: Date;
  readonly released_at: Date | null;
  readonly released_by: UserId | null;
  readonly release_reason: string | null;
}

export interface MessageEvent {
  readonly id: MessageEventId;
  readonly organization_id: OrganizationId;
  /** Null when the event arrived for an address with no channel row. */
  readonly channel_id: ContactChannelId | null;
  readonly channel_type: ChannelType;
  readonly address: string;
  readonly purpose_id: ConsentPurposeId | null;
  readonly message_ref: string | null;
  readonly event_kind: MessageEventKind;
  /** Present only on 'bounced'; enforced by CHECK. */
  readonly bounce_kind: BounceKind | null;
  readonly provider: string;
  /** Makes webhook replay idempotent. */
  readonly provider_event_id: string | null;
  readonly occurred_at: Date;
  readonly metadata: JsonObject;
  readonly created_at: Date;
}

// ---------------------------------------------------------------------------
// The gate
// ---------------------------------------------------------------------------

/**
 * Result of `app.can_send(channel_id, purpose_id)`.
 *
 * `reason` is populated on allow as well as deny, because a refusal without a
 * reason produces support tickets and guesswork.
 */
export interface SendVerdict {
  readonly allowed: boolean;
  /**
   * On deny: `channel_not_found`, `purpose_not_found_or_inactive`,
   * `cross_tenant_mismatch`, `suppressed:<reason>`, `legacy_opt_out`,
   * `no_consent_recorded`, `consent_expired`, or `consent_<state>`.
   * On allow: `transactional` or `consent_granted`.
   */
  readonly reason: string;
}

/**
 * Precedence, highest first. Encoded here so callers reason about it without
 * reading the plpgsql, and asserted by src/db/tests/consent_test.sql.
 *
 * Suppression outranks everything including transactional purposes and an
 * explicit grant: a hard-bounced address does not become deliverable because
 * someone consented, and writing to it damages sending reputation for every
 * other contact in the tenant.
 */
export const SEND_PRECEDENCE = [
  'suppression',
  'legacy_opt_out',
  'transactional_purpose',
  'recorded_consent',
] as const;

// ---------------------------------------------------------------------------
// Insert shapes
// ---------------------------------------------------------------------------

export interface ContactChannelInsert {
  contact_id: ContactId;
  channel_type: ChannelType;
  address: string;
  label?: string | null;
  is_primary?: boolean;
  verified_at?: Date | null;
}

export interface ConsentPurposeInsert {
  key: string;
  name: string;
  description?: string | null;
  is_transactional?: boolean;
  requires_double_optin?: boolean;
  default_ttl?: IntervalString | null;
  is_active?: boolean;
  position?: number;
  created_by?: UserId | null;
}

/**
 * Arguments to `app.record_consent()`.
 *
 * Prefer this over inserting into `consent_records` directly: the function
 * applies the double-opt-in downgrade and computes expiry from the purpose's
 * TTL. A caller writing the row itself has to remember both, and the caller who
 * forgets is exactly the one that should not be trusted with it.
 */
export interface RecordConsentArgs {
  channel_id: ContactChannelId;
  purpose_id: ConsentPurposeId;
  state: ConsentStateKind;
  source: ConsentSource;
  evidence?: JsonObject;
  occurred_at?: Date;
}

export interface SuppressionInsert {
  channel_type: ChannelType;
  address: string;
  reason: SuppressionReason;
  detail?: string | null;
  source?: string | null;
  /** Must be null for permanent reasons — see isPermanentSuppression(). */
  expires_at?: Date | null;
  created_by?: UserId | null;
}

/** Arguments to `app.ingest_message_event()`. Returns null on replay. */
export interface IngestMessageEventArgs {
  organization_id: OrganizationId;
  channel_type: ChannelType;
  address: string;
  event_kind: MessageEventKind;
  provider: string;
  provider_event_id?: string | null;
  bounce_kind?: BounceKind | null;
  message_ref?: string | null;
  metadata?: JsonObject;
  occurred_at?: Date;
}

/**
 * Every database enum introduced by 0011, for the drift check in verify.ts.
 * A new enum added to a migration but not registered here is invisible to that
 * check, which is the failure mode the check exists to prevent.
 */
export const CONSENT_DATABASE_ENUMS = {
  channel_type: ChannelType,
  consent_state_kind: ConsentStateKind,
  consent_source: ConsentSource,
  suppression_reason: SuppressionReason,
  message_event_kind: MessageEventKind,
} as const;
