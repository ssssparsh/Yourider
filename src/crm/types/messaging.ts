/**
 * Email and calendar identity — without a sync worker.
 *
 * Mirrors src/db/migrations/0020_messaging_identity.sql.
 *
 * This is the identity model a mailbox/calendar sync will write into once one
 * is connected (Gmail or Microsoft Graph, both requiring OAuth this
 * environment does not have — see the top-level API-requirements summary).
 * Nothing here talks to a mail server; it is the shape a worker needs to
 * exist before two-way sync, deduplication, and threading are even possible.
 */

import type { Id } from './scalars.js';
import type { CrmEntity } from './enums.js';
import type { ContactId, OrganizationId, UserId } from './entities.js';

// ---------------------------------------------------------------------------
// Connected accounts
// ---------------------------------------------------------------------------

export type ConnectedAccountId = Id<'ConnectedAccount'>;

export const ConnectedAccountProvider = {
  Gmail: 'gmail',
  Microsoft: 'microsoft',
  Imap: 'imap',
  Caldav: 'caldav',
} as const;
export type ConnectedAccountProvider =
  (typeof ConnectedAccountProvider)[keyof typeof ConnectedAccountProvider];

export const ConnectedAccountStatus = {
  Active: 'active',
  ReauthRequired: 'reauth_required',
  Disconnected: 'disconnected',
} as const;
export type ConnectedAccountStatus =
  (typeof ConnectedAccountStatus)[keyof typeof ConnectedAccountStatus];

/**
 * A mailbox or calendar connection. Personal, like a notification: RLS narrows
 * SELECT to the owner plus admin/owner roles, not the whole tenant.
 */
export interface ConnectedAccount {
  readonly id: ConnectedAccountId;
  readonly organization_id: OrganizationId;
  readonly user_id: UserId;
  readonly provider: ConnectedAccountProvider;
  readonly email_address: string;
  /**
   * An opaque reference into a secrets manager, NOT the OAuth token itself.
   * CLAUDE.md §3's "no secrets in code or prompts" applies here too — a token
   * has the same blast radius as a leaked credential and does not belong in a
   * plain column even inside this database. A worker resolves the real token
   * from this reference at call time.
   */
  readonly credential_ref: string | null;
  readonly status: ConnectedAccountStatus;
  readonly sync_enabled: boolean;
  readonly last_synced_at: Date | null;
  /** Provider-specific pagination/delta token. Opaque to this schema. */
  readonly sync_cursor: string | null;
  readonly created_at: Date;
  readonly updated_at: Date;
  readonly deleted_at: Date | null;
}

export interface ConnectedAccountInsert {
  user_id: UserId;
  provider: ConnectedAccountProvider;
  email_address: string;
  credential_ref?: string | null;
  sync_enabled?: boolean;
}

// ---------------------------------------------------------------------------
// Threads and messages
// ---------------------------------------------------------------------------

export type MessageThreadId = Id<'MessageThread'>;
export type MessageId = Id<'Message'>;
export type MessageParticipantId = Id<'MessageParticipant'>;

export interface MessageThread {
  readonly id: MessageThreadId;
  readonly organization_id: OrganizationId;
  /** Gmail threadId, or the RFC 2822 References-chain root. */
  readonly provider_thread_id: string | null;
  readonly subject: string | null;
  readonly entity_type: CrmEntity | null;
  readonly entity_id: string | null;
  /** Maintained by trigger from live `messages` rows — recomputed, not incremented. */
  readonly last_message_at: Date | null;
  readonly message_count: number;
  readonly created_at: Date;
  readonly updated_at: Date;
}

export interface MessageThreadInsert {
  provider_thread_id?: string | null;
  subject?: string | null;
  entity_type?: CrmEntity | null;
  entity_id?: string | null;
}

export const MessageDirection = { Inbound: 'inbound', Outbound: 'outbound' } as const;
export type MessageDirection =
  (typeof MessageDirection)[keyof typeof MessageDirection];

/**
 * `provider_message_id` is the dedup key — unique per organization, so a
 * message synced twice (two passes, or two connected mailboxes on the same
 * thread) lands as one row.
 */
export interface Message {
  readonly id: MessageId;
  readonly organization_id: OrganizationId;
  readonly thread_id: MessageThreadId;
  readonly connected_account_id: ConnectedAccountId | null;
  readonly provider_message_id: string;
  readonly in_reply_to: string | null;
  readonly direction: MessageDirection;
  readonly from_address: string;
  readonly to_addresses: readonly string[];
  readonly cc_addresses: readonly string[];
  readonly subject: string | null;
  readonly body_text: string | null;
  readonly body_html: string | null;
  readonly sent_at: Date;
  readonly activity_id: Id<'Activity'> | null;
  readonly created_at: Date;
}

export interface MessageInsert {
  thread_id: MessageThreadId;
  connected_account_id?: ConnectedAccountId | null;
  provider_message_id: string;
  in_reply_to?: string | null;
  direction: MessageDirection;
  from_address: string;
  to_addresses?: readonly string[];
  cc_addresses?: readonly string[];
  subject?: string | null;
  body_text?: string | null;
  body_html?: string | null;
  sent_at: Date;
}

export type MessageParticipantRole = 'from' | 'to' | 'cc' | 'bcc';

export interface MessageParticipant {
  readonly id: MessageParticipantId;
  readonly organization_id: OrganizationId;
  readonly message_id: MessageId;
  readonly address: string;
  readonly role: MessageParticipantRole;
  /** Resolved contact, when the address matches one on file. */
  readonly contact_id: ContactId | null;
}

// ---------------------------------------------------------------------------
// Calendar events
// ---------------------------------------------------------------------------

export type CalendarEventId = Id<'CalendarEvent'>;

export type CalendarEventStatus = 'confirmed' | 'tentative' | 'cancelled';

export interface CalendarEvent {
  readonly id: CalendarEventId;
  readonly organization_id: OrganizationId;
  readonly connected_account_id: ConnectedAccountId | null;
  readonly provider_event_id: string;
  readonly title: string | null;
  readonly location: string | null;
  readonly starts_at: Date;
  readonly ends_at: Date;
  readonly is_all_day: boolean;
  readonly entity_type: CrmEntity | null;
  readonly entity_id: string | null;
  readonly attendee_addresses: readonly string[];
  readonly status: CalendarEventStatus;
  readonly created_at: Date;
  readonly updated_at: Date;
}

export interface CalendarEventInsert {
  connected_account_id?: ConnectedAccountId | null;
  provider_event_id: string;
  title?: string | null;
  location?: string | null;
  starts_at: Date;
  ends_at: Date;
  is_all_day?: boolean;
  entity_type?: CrmEntity | null;
  entity_id?: string | null;
  attendee_addresses?: readonly string[];
  status?: CalendarEventStatus;
}

/**
 * Every database enum introduced by 0020, for the drift check in verify.ts.
 */
export const MESSAGING_DATABASE_ENUMS = {
  connected_account_provider: ConnectedAccountProvider,
  connected_account_status: ConnectedAccountStatus,
  message_direction: MessageDirection,
} as const;
