/**
 * TypeScript mirrors of the PostgreSQL enum types.
 *
 * Each is declared as a const object plus a derived union rather than a
 * TypeScript `enum`. The reason: a TS `enum` is a runtime construct with its
 * own identity, so a value read from the database is not assignable to it
 * without a cast, which defeats the point. A const-object union gives exact
 * string literal types that a driver row satisfies directly.
 *
 * These MUST stay in sync with the database. `assertEnumsMatchDatabase` in
 * src/crm/types/verify.ts checks them against pg_enum at runtime, so drift is
 * caught by a test rather than by a production insert failing.
 */

/** 0002_tenancy.sql — membership_role */
export const MembershipRole = {
  Owner: 'owner',
  Admin: 'admin',
  Manager: 'manager',
  Member: 'member',
  Viewer: 'viewer',
} as const;
export type MembershipRole = (typeof MembershipRole)[keyof typeof MembershipRole];

/** Roles permitted to write. Mirrors app.can_write_in() in the database. */
export const WRITE_CAPABLE_ROLES: readonly MembershipRole[] = [
  MembershipRole.Owner,
  MembershipRole.Admin,
  MembershipRole.Manager,
  MembershipRole.Member,
];

/** 0003_accounts_contacts.sql — account_kind */
export const AccountKind = {
  Company: 'company',
  Individual: 'individual',
} as const;
export type AccountKind = (typeof AccountKind)[keyof typeof AccountKind];

/** 0003_accounts_contacts.sql — lifecycle_stage */
export const LifecycleStage = {
  Prospect: 'prospect',
  Customer: 'customer',
  Former: 'former',
  Partner: 'partner',
  Other: 'other',
} as const;
export type LifecycleStage = (typeof LifecycleStage)[keyof typeof LifecycleStage];

/**
 * 0004_pipelines.sql — pipeline_entity
 *
 * Which entity a pipeline drives. Adding a member here extends the pipeline
 * engine to a new work type; it must be added to the database enum in the same
 * migration.
 */
export const PipelineEntity = {
  Lead: 'lead',
  Deal: 'deal',
  ServiceJob: 'service_job',
} as const;
export type PipelineEntity = (typeof PipelineEntity)[keyof typeof PipelineEntity];

/**
 * 0004_pipelines.sql — stage_kind
 *
 * Reporting keys off this classification, never off stage names, so a tenant
 * renaming "Closed Won" to "Signed" does not break forecasting.
 */
export const StageKind = {
  Open: 'open',
  Won: 'won',
  Lost: 'lost',
} as const;
export type StageKind = (typeof StageKind)[keyof typeof StageKind];

/** Terminal stages close their entity. */
export const TERMINAL_STAGE_KINDS: readonly StageKind[] = [
  StageKind.Won,
  StageKind.Lost,
];

export function isTerminalStage(kind: StageKind): boolean {
  return TERMINAL_STAGE_KINDS.includes(kind);
}

/** 0005_leads_deals.sql — lead_status */
export const LeadStatus = {
  New: 'new',
  Working: 'working',
  Nurturing: 'nurturing',
  Qualified: 'qualified',
  Unqualified: 'unqualified',
  Recycled: 'recycled',
} as const;
export type LeadStatus = (typeof LeadStatus)[keyof typeof LeadStatus];

/** 0006_services.sql — service_billing_kind */
export const ServiceBillingKind = {
  Fixed: 'fixed',
  Hourly: 'hourly',
  Recurring: 'recurring',
  Usage: 'usage',
  Free: 'free',
} as const;
export type ServiceBillingKind =
  (typeof ServiceBillingKind)[keyof typeof ServiceBillingKind];

/** 0006_services.sql — job_priority (also used by tasks) */
export const JobPriority = {
  Low: 'low',
  Normal: 'normal',
  High: 'high',
  Urgent: 'urgent',
} as const;
export type JobPriority = (typeof JobPriority)[keyof typeof JobPriority];

/** 0007_activity_audit.sql — activity_kind */
export const ActivityKind = {
  Note: 'note',
  Call: 'call',
  Email: 'email',
  Meeting: 'meeting',
  Sms: 'sms',
  TaskCompleted: 'task_completed',
  StageChange: 'stage_change',
  Assignment: 'assignment',
  JobScheduled: 'job_scheduled',
  JobCompleted: 'job_completed',
  FileAttached: 'file_attached',
  System: 'system',
} as const;
export type ActivityKind = (typeof ActivityKind)[keyof typeof ActivityKind];

/**
 * 0007_activity_audit.sql — actor_kind
 *
 * `Agent` is first-class. A database CHECK constraint refuses an
 * agent-attributed row that does not name the agent, which is what makes the
 * approval gate in CLAUDE.md §3 auditable after the fact.
 */
export const ActorKind = {
  User: 'user',
  Agent: 'agent',
  System: 'system',
  Integration: 'integration',
} as const;
export type ActorKind = (typeof ActorKind)[keyof typeof ActorKind];

/** 0007_activity_audit.sql — crm_entity */
export const CrmEntity = {
  Account: 'account',
  Contact: 'contact',
  Lead: 'lead',
  Deal: 'deal',
  ServiceJob: 'service_job',
  Service: 'service',
  Task: 'task',
  User: 'user',
} as const;
export type CrmEntity = (typeof CrmEntity)[keyof typeof CrmEntity];

/** 0007_activity_audit.sql — audit_action */
export const AuditAction = {
  Insert: 'insert',
  Update: 'update',
  Delete: 'delete',
  Restore: 'restore',
  Read: 'read',
} as const;
export type AuditAction = (typeof AuditAction)[keyof typeof AuditAction];

/** 0008_custom_fields.sql — custom_field_type */
export const CustomFieldType = {
  Text: 'text',
  LongText: 'long_text',
  Number: 'number',
  Currency: 'currency',
  Boolean: 'boolean',
  Date: 'date',
  DateTime: 'datetime',
  Select: 'select',
  MultiSelect: 'multi_select',
  Email: 'email',
  Phone: 'phone',
  Url: 'url',
  User: 'user',
} as const;
export type CustomFieldType =
  (typeof CustomFieldType)[keyof typeof CustomFieldType];

/**
 * Every database enum, keyed by its Postgres type name. Used by the runtime
 * drift check in verify.ts.
 */
export const DATABASE_ENUMS = {
  membership_role: MembershipRole,
  account_kind: AccountKind,
  lifecycle_stage: LifecycleStage,
  pipeline_entity: PipelineEntity,
  stage_kind: StageKind,
  lead_status: LeadStatus,
  service_billing_kind: ServiceBillingKind,
  job_priority: JobPriority,
  activity_kind: ActivityKind,
  actor_kind: ActorKind,
  crm_entity: CrmEntity,
  audit_action: AuditAction,
  custom_field_type: CustomFieldType,
} as const;
