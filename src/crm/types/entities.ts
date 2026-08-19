/**
 * Row shapes for every CRM table, mirroring src/db/migrations/.
 *
 * Conventions:
 *
 * - A nullable column is `T | null`, never `T | undefined` and never optional.
 *   Optional means "the key may be absent"; a database row always has the key.
 *   Conflating the two is how `undefined` reaches a query parameter and becomes
 *   a silent NULL.
 *
 * - Generated and defaulted columns are present on the Row type but omitted
 *   from the corresponding Insert type, so the compiler refuses an insert that
 *   tries to set a value the database computes.
 *
 * - `organization_id` appears on every tenant Row but is deliberately absent
 *   from Insert types: it is supplied by the request's tenant context, not by
 *   the caller. Letting a caller pass it invites the exact cross-tenant write
 *   that RLS and the assert_same_org triggers exist to prevent.
 */

import type {
  BigIntString,
  CurrencyCode,
  DateOnly,
  Id,
  IntervalString,
  IpAddress,
  Json,
  JsonObject,
  Numeric,
} from './scalars.js';

import type {
  AccountKind,
  ActivityKind,
  ActorKind,
  AuditAction,
  CrmEntity,
  CustomFieldType,
  JobPriority,
  LeadStatus,
  LifecycleStage,
  LifecycleStage as Lifecycle,
  MembershipRole,
  PipelineEntity,
  ServiceBillingKind,
  StageKind,
} from './enums.js';

// ---------------------------------------------------------------------------
// Branded identifiers
// ---------------------------------------------------------------------------

export type OrganizationId = Id<'Organization'>;
export type UserId = Id<'User'>;
export type MembershipId = Id<'Membership'>;
export type AccountId = Id<'Account'>;
export type ContactId = Id<'Contact'>;
export type PipelineId = Id<'Pipeline'>;
export type StageId = Id<'PipelineStage'>;
export type StageTransitionId = Id<'StageTransition'>;
export type LeadId = Id<'Lead'>;
export type DealId = Id<'Deal'>;
export type DealContactId = Id<'DealContact'>;
export type ServiceId = Id<'Service'>;
export type ServiceJobId = Id<'ServiceJob'>;
export type ServiceJobItemId = Id<'ServiceJobItem'>;
export type ActivityId = Id<'Activity'>;
export type AuditLogId = Id<'AuditLog'>;
export type TaskId = Id<'Task'>;
export type CustomFieldDefinitionId = Id<'CustomFieldDefinition'>;

/** Columns present on every tenant-scoped table. */
interface TenantScoped {
  readonly organization_id: OrganizationId;
}

/** Columns present on every soft-deletable, timestamped table. */
interface Timestamped {
  readonly created_at: Date;
  readonly updated_at: Date;
  readonly deleted_at: Date | null;
}

// ---------------------------------------------------------------------------
// 0002_tenancy.sql
// ---------------------------------------------------------------------------

export interface Organization extends Timestamped {
  readonly id: OrganizationId;
  readonly name: string;
  readonly slug: string | null;
  readonly base_currency: CurrencyCode;
  readonly settings: JsonObject;
}

export interface User extends Timestamped {
  readonly id: UserId;
  /** Identity-provider subject (Supabase auth.users.id when self-hosting it). */
  readonly auth_user_id: string | null;
  readonly email: string;
  readonly full_name: string | null;
  readonly avatar_url: string | null;
  readonly is_active: boolean;
  readonly last_seen_at: Date | null;
}

export interface Membership extends TenantScoped, Timestamped {
  readonly id: MembershipId;
  readonly user_id: UserId;
  readonly role: MembershipRole;
  readonly team: string | null;
  readonly invited_by: UserId | null;
  readonly joined_at: Date;
}

// ---------------------------------------------------------------------------
// 0003_accounts_contacts.sql
// ---------------------------------------------------------------------------

export interface Account extends TenantScoped, Timestamped {
  readonly id: AccountId;
  readonly account_kind: AccountKind;
  readonly name: string;
  readonly lifecycle: LifecycleStage;
  /** Company-shaped fields; null when account_kind is 'individual'. */
  readonly domain: string | null;
  readonly industry: string | null;
  readonly employee_count: number | null;
  readonly annual_revenue: Numeric | null;
  readonly phone: string | null;
  readonly website: string | null;
  readonly billing_address: JsonObject;
  readonly service_address: JsonObject;
  readonly owner_id: UserId | null;
  readonly parent_id: AccountId | null;
  readonly custom_fields: JsonObject;
  readonly tags: readonly string[];
  readonly created_by: UserId | null;
}

export interface Contact extends TenantScoped, Timestamped {
  readonly id: ContactId;
  readonly account_id: AccountId | null;
  readonly first_name: string | null;
  readonly last_name: string | null;
  /** Generated column: first_name + ' ' + last_name, trimmed. Never written. */
  readonly full_name: string;
  readonly email: string | null;
  readonly phone: string | null;
  readonly mobile: string | null;
  readonly job_title: string | null;
  readonly department: string | null;
  readonly lifecycle: LifecycleStage;
  readonly is_primary: boolean;
  /**
   * Consent. Anything sending outbound — including agents — must check these
   * before dispatch, not after.
   */
  readonly email_opt_out: boolean;
  readonly sms_opt_out: boolean;
  readonly address: JsonObject;
  readonly social: JsonObject;
  readonly owner_id: UserId | null;
  readonly custom_fields: JsonObject;
  readonly tags: readonly string[];
  readonly created_by: UserId | null;
}

// ---------------------------------------------------------------------------
// 0004_pipelines.sql
// ---------------------------------------------------------------------------

export interface Pipeline extends TenantScoped, Timestamped {
  readonly id: PipelineId;
  readonly entity_type: PipelineEntity;
  readonly name: string;
  readonly description: string | null;
  readonly is_default: boolean;
  readonly is_archived: boolean;
  readonly position: number;
  readonly created_by: UserId | null;
}

export interface PipelineStage extends TenantScoped, Timestamped {
  readonly id: StageId;
  readonly pipeline_id: PipelineId;
  readonly name: string;
  readonly kind: StageKind;
  /** Fractional, so a stage can be inserted between two others. */
  readonly position: Numeric;
  /** 0..1 forecast weighting. */
  readonly probability: Numeric;
  readonly wip_limit: number | null;
  readonly stale_after_days: number | null;
  readonly color: string | null;
}

export interface StageTransition extends TenantScoped {
  readonly id: StageTransitionId;
  readonly entity_type: PipelineEntity;
  readonly entity_id: LeadId | DealId | ServiceJobId;
  readonly from_stage_id: StageId | null;
  readonly to_stage_id: StageId;
  readonly entered_at: Date;
  /** Null while this is the open interval. */
  readonly exited_at: Date | null;
  /** Generated; null until the interval closes. */
  readonly duration_seconds: BigIntString | null;
  readonly actor_user_id: UserId | null;
  readonly actor_agent: string | null;
  readonly note: string | null;
}

// ---------------------------------------------------------------------------
// 0005_leads_deals.sql
// ---------------------------------------------------------------------------

export interface Lead extends TenantScoped, Timestamped {
  readonly id: LeadId;
  readonly first_name: string | null;
  readonly last_name: string | null;
  /** Generated column. */
  readonly full_name: string;
  readonly company_name: string | null;
  readonly email: string | null;
  readonly phone: string | null;
  readonly job_title: string | null;
  readonly website: string | null;
  readonly source: string | null;
  readonly source_details: JsonObject;
  readonly campaign: string | null;
  readonly status: LeadStatus;
  readonly pipeline_id: PipelineId | null;
  readonly stage_id: StageId | null;
  readonly board_position: Numeric;
  /** 0..100, or null when unscored. */
  readonly score: number | null;
  /** Cited signals behind the score. Agents must populate this, not a bare number. */
  readonly score_reasons: readonly Json[];
  readonly scored_at: Date | null;
  readonly scored_by_agent: string | null;
  readonly estimated_value: Numeric | null;
  readonly currency: CurrencyCode | null;
  readonly owner_id: UserId | null;
  readonly converted_at: Date | null;
  readonly converted_account_id: AccountId | null;
  readonly converted_contact_id: ContactId | null;
  readonly converted_deal_id: DealId | null;
  readonly disqualified_at: Date | null;
  readonly disqualified_reason: string | null;
  readonly last_activity_at: Date | null;
  readonly custom_fields: JsonObject;
  readonly tags: readonly string[];
  readonly created_by: UserId | null;
}

export interface Deal extends TenantScoped, Timestamped {
  readonly id: DealId;
  readonly name: string;
  readonly account_id: AccountId | null;
  readonly primary_contact_id: ContactId | null;
  readonly pipeline_id: PipelineId;
  readonly stage_id: StageId;
  readonly board_position: Numeric;
  readonly stage_entered_at: Date;
  readonly amount: Numeric;
  readonly currency: CurrencyCode;
  readonly fx_rate: Numeric;
  /** Generated: amount * fx_rate. Never written. */
  readonly base_amount: Numeric;
  readonly probability: Numeric | null;
  /** Generated: amount * fx_rate * probability. Never written. */
  readonly weighted_amount: Numeric;
  readonly expected_close_date: DateOnly | null;
  readonly closed_at: Date | null;
  readonly close_reason: string | null;
  readonly owner_id: UserId | null;
  readonly source_lead_id: LeadId | null;
  readonly last_activity_at: Date | null;
  readonly custom_fields: JsonObject;
  readonly tags: readonly string[];
  readonly created_by: UserId | null;
}

export interface DealContact extends TenantScoped {
  readonly id: DealContactId;
  readonly deal_id: DealId;
  readonly contact_id: ContactId;
  readonly role: string | null;
  /** 1..5 */
  readonly influence: number | null;
  readonly created_at: Date;
}

// ---------------------------------------------------------------------------
// 0006_services.sql
// ---------------------------------------------------------------------------

export interface Service extends TenantScoped, Timestamped {
  readonly id: ServiceId;
  readonly code: string | null;
  readonly name: string;
  readonly description: string | null;
  readonly category: string | null;
  readonly billing_kind: ServiceBillingKind;
  readonly unit_price: Numeric;
  readonly currency: CurrencyCode;
  readonly unit_label: string | null;
  readonly tax_rate: Numeric;
  readonly default_duration_minutes: number | null;
  /** Required when billing_kind is 'recurring'. */
  readonly recurrence: IntervalString | null;
  readonly requires_assignment: boolean;
  readonly is_active: boolean;

  /**
   * Cost basis, added in 0014. NULL means the cost is *unknown*, which is not
   * the same as zero — a margin computed against a missing cost overstates it,
   * and always in the flattering direction. `app.deal_totals()` reports
   * `cost_known` for exactly this reason.
   */
  readonly unit_cost: Numeric | null;
  /** NULL means the cost is denominated in `currency`. */
  readonly cost_currency: CurrencyCode | null;
  /** Physical goods need stock semantics that services do not. */
  readonly is_stockable: boolean;
  readonly sku: string | null;

  readonly custom_fields: JsonObject;
  readonly tags: readonly string[];
  readonly created_by: UserId | null;
}

export interface ServiceJob extends TenantScoped, Timestamped {
  readonly id: ServiceJobId;
  readonly reference: string | null;
  readonly service_id: ServiceId | null;
  readonly account_id: AccountId | null;
  readonly contact_id: ContactId | null;
  /** The deal this work was sold under; how revenue and delivery reconcile. */
  readonly deal_id: DealId | null;
  readonly title: string;
  readonly description: string | null;
  readonly priority: JobPriority;
  readonly pipeline_id: PipelineId;
  readonly stage_id: StageId;
  readonly board_position: Numeric;
  readonly stage_entered_at: Date;
  /** Planned window. */
  readonly scheduled_start: Date | null;
  readonly scheduled_end: Date | null;
  /** What actually happened; kept distinct so punctuality is measurable. */
  readonly actual_start: Date | null;
  readonly actual_end: Date | null;
  /** Generated from actual_start/actual_end. */
  readonly duration_minutes: number | null;
  readonly assigned_user_id: UserId | null;
  /** Stamped automatically by a trigger when assignment changes. */
  readonly assigned_at: Date | null;
  readonly location: JsonObject;
  readonly latitude: Numeric | null;
  readonly longitude: Numeric | null;
  readonly quoted_amount: Numeric | null;
  readonly final_amount: Numeric | null;
  readonly currency: CurrencyCode;
  readonly fx_rate: Numeric;
  /** Generated: final_amount * fx_rate. */
  readonly base_final_amount: Numeric;
  readonly completed_at: Date | null;
  readonly cancelled_at: Date | null;
  readonly cancellation_reason: string | null;
  /** 1..5 */
  readonly satisfaction_score: number | null;
  readonly owner_id: UserId | null;
  readonly custom_fields: JsonObject;
  readonly tags: readonly string[];
  readonly created_by: UserId | null;
}

export interface ServiceJobItem extends TenantScoped {
  readonly id: ServiceJobItemId;
  readonly job_id: ServiceJobId;
  readonly service_id: ServiceId | null;
  readonly description: string;
  readonly quantity: Numeric;
  readonly unit_price: Numeric;
  readonly tax_rate: Numeric;
  /** Generated: quantity * unit_price * (1 + tax_rate). Never written. */
  readonly line_total: Numeric;
  readonly position: number;
  readonly created_at: Date;
}

// ---------------------------------------------------------------------------
// 0007_activity_audit.sql
// ---------------------------------------------------------------------------

export interface Activity extends TenantScoped {
  readonly id: ActivityId;
  readonly kind: ActivityKind;
  readonly subject: string | null;
  readonly body: string | null;
  readonly entity_type: CrmEntity;
  readonly entity_id: string;
  /** Denormalised links so an account timeline needs no recursive walk. */
  readonly account_id: AccountId | null;
  readonly contact_id: ContactId | null;
  readonly deal_id: DealId | null;
  readonly job_id: ServiceJobId | null;
  readonly actor_type: ActorKind;
  readonly actor_user_id: UserId | null;
  /** Required by a CHECK constraint when actor_type is 'agent'. */
  readonly actor_agent: string | null;
  /** When it happened, which is not always when it was recorded. */
  readonly occurred_at: Date;
  readonly duration_seconds: number | null;
  /** Whether consent was verified before an outbound communication. */
  readonly consent_checked: boolean | null;
  readonly metadata: JsonObject;
  readonly created_at: Date;
}

/**
 * A field-level audit row.
 *
 * There is no Insert type and no update/delete path: audit_log has no UPDATE or
 * DELETE policy, and rows are written by the app.record_audit() trigger rather
 * than by application code. A tamperable audit trail is not an audit trail.
 */
export interface AuditLogEntry extends TenantScoped {
  readonly id: AuditLogId;
  readonly table_name: string;
  readonly record_id: string;
  readonly action: AuditAction;
  readonly changed_fields: readonly string[];
  readonly old_values: JsonObject;
  readonly new_values: JsonObject;
  readonly actor_type: ActorKind;
  readonly actor_user_id: UserId | null;
  readonly actor_agent: string | null;
  /** Set via the app.audit_reason session setting before a write. */
  readonly reason: string | null;
  readonly request_id: string | null;
  readonly ip_address: IpAddress | null;
  readonly user_agent: string | null;
  readonly created_at: Date;
}

export interface Task extends TenantScoped, Timestamped {
  readonly id: TaskId;
  readonly title: string;
  readonly description: string | null;
  readonly priority: JobPriority;
  readonly entity_type: CrmEntity | null;
  readonly entity_id: string | null;
  readonly assignee_id: UserId | null;
  readonly due_at: Date | null;
  readonly reminder_at: Date | null;
  readonly completed_at: Date | null;
  readonly completed_by: UserId | null;
  /** Set when an agent proposed this task; drives the agent-draft styling. */
  readonly created_by_agent: string | null;
  readonly created_by: UserId | null;
}

// ---------------------------------------------------------------------------
// 0008_custom_fields.sql
// ---------------------------------------------------------------------------

export interface CustomFieldOption {
  readonly value: string;
  readonly label: string;
}

export interface CustomFieldDefinition extends TenantScoped, Timestamped {
  readonly id: CustomFieldDefinitionId;
  readonly entity_type: CrmEntity;
  /** Lowercase identifier; constrained by a CHECK to ^[a-z][a-z0-9_]{0,62}$. */
  readonly key: string;
  readonly label: string;
  readonly help_text: string | null;
  readonly field_type: CustomFieldType;
  readonly options: readonly CustomFieldOption[];
  readonly is_required: boolean;
  readonly is_unique: boolean;
  readonly default_value: Json | null;
  readonly min_value: Numeric | null;
  readonly max_value: Numeric | null;
  readonly max_length: number | null;
  readonly pattern: string | null;
  readonly position: number;
  readonly is_active: boolean;
  readonly created_by: UserId | null;
}

// ---------------------------------------------------------------------------
// Insert / update shapes
// ---------------------------------------------------------------------------

/**
 * Columns the database always supplies. Never accepted from a caller.
 *
 * `organization_id` is included: it comes from the request's tenant context.
 * A caller that can name the tenant it writes into is a caller that can get it
 * wrong.
 */
type DatabaseManaged =
  | 'id'
  | 'organization_id'
  | 'created_at'
  | 'updated_at'
  | 'deleted_at';

/** Columns Postgres computes. Writing them is a compile error. */
type GeneratedColumns =
  | 'full_name'
  | 'base_amount'
  | 'weighted_amount'
  | 'base_final_amount'
  | 'line_total'
  | 'duration_seconds'
  | 'duration_minutes';

type Writable<T> = Omit<T, DatabaseManaged | Extract<keyof T, GeneratedColumns>>;

/** Fields with a database default, optional on insert. */
type DefaultedOnInsert =
  | 'lifecycle'
  | 'account_kind'
  | 'status'
  | 'priority'
  | 'currency'
  | 'fx_rate'
  | 'amount'
  | 'tax_rate'
  | 'unit_price'
  | 'quantity'
  | 'position'
  | 'board_position'
  | 'stage_entered_at'
  | 'is_active'
  | 'is_default'
  | 'is_archived'
  | 'is_primary'
  | 'is_required'
  | 'is_unique'
  | 'requires_assignment'
  | 'email_opt_out'
  | 'sms_opt_out'
  | 'custom_fields'
  | 'tags'
  | 'metadata'
  | 'settings'
  | 'options'
  | 'source_details'
  | 'score_reasons'
  | 'address'
  | 'social'
  | 'location'
  | 'billing_address'
  | 'service_address'
  | 'actor_type'
  | 'occurred_at'
  | 'joined_at'
  | 'kind'
  | 'probability'
  | 'billing_kind'
  | 'base_currency';

/**
 * Makes the keys in `K` optional and strips readonly from everything.
 *
 * Constraining `K extends keyof T` is load-bearing: it lets the compiler prove
 * that `Exclude<keyof T, K>` still indexes `T`. Inlining the Exclude against a
 * generic `Writable<T>` instead fails with TS2536, because at that point the
 * compiler has not resolved that the remaining keys are still keys of T.
 */
type WithOptional<T, K extends keyof T> = {
  -readonly [P in Exclude<keyof T, K>]: T[P];
} & {
  -readonly [P in K]?: T[P];
};

/**
 * The shape accepted when creating a row: writable columns, with defaulted ones
 * optional. Readonly is stripped, which is correct for a payload being
 * assembled before it is sent.
 */
export type Insert<T> = WithOptional<
  Writable<T>,
  Extract<keyof Writable<T>, DefaultedOnInsert>
>;

/** The shape accepted when updating a row: any writable column, all optional. */
export type Update<T> = {
  -readonly [K in keyof Writable<T>]?: Writable<T>[K];
};

export type AccountInsert = Insert<Account>;
export type AccountUpdate = Update<Account>;
export type ContactInsert = Insert<Contact>;
export type ContactUpdate = Update<Contact>;
export type LeadInsert = Insert<Lead>;
export type LeadUpdate = Update<Lead>;
export type DealInsert = Insert<Deal>;
export type DealUpdate = Update<Deal>;
export type ServiceInsert = Insert<Service>;
export type ServiceUpdate = Update<Service>;
export type ServiceJobInsert = Insert<ServiceJob>;
export type ServiceJobUpdate = Update<ServiceJob>;
export type ServiceJobItemInsert = Insert<ServiceJobItem>;
export type TaskInsert = Insert<Task>;
export type TaskUpdate = Update<Task>;
export type PipelineInsert = Insert<Pipeline>;
export type PipelineUpdate = Update<Pipeline>;
export type PipelineStageInsert = Insert<PipelineStage>;
export type PipelineStageUpdate = Update<PipelineStage>;
export type ActivityInsert = Insert<Activity>;
export type CustomFieldDefinitionInsert = Insert<CustomFieldDefinition>;
export type CustomFieldDefinitionUpdate = Update<CustomFieldDefinition>;

/** Re-exported for callers that only import from this module. */
export type { LifecycleStage as ContactLifecycle, Lifecycle };
