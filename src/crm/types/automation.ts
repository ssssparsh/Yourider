/**
 * The automation engine and the approval gate.
 *
 * Mirrors src/db/migrations/0015_automation.sql.
 *
 * The gate matrix from CLAUDE.md §3 is expressed twice here — once as data
 * (`GATE_MATRIX`) and once in the database (`app.gate_verdict`). That is
 * deliberate duplication: the client needs to render "this will need approval"
 * before submitting, and the database needs to enforce it regardless of what
 * the client believed. `automation_test.sql` asserts the database's answer for
 * all fifteen combinations, so drift between the two is a test failure rather
 * than a silent divergence.
 */

import type { Id, IntervalString, JsonObject } from './scalars.js';
import type { CrmEntity } from './enums.js';
import type { OrganizationId, UserId } from './entities.js';

// ---------------------------------------------------------------------------
// Command classes and autonomy tiers — CLAUDE.md §3
// ---------------------------------------------------------------------------

export const CommandClass = {
  /** View data. No side effects. */
  Read: 'read',
  /** Create or modify a record. */
  Write: 'write',
  /** Outbound call to an external service — scraper, email send, webhook. */
  Network: 'network',
  /** Add or change a dependency. */
  Install: 'install',
  /** Delete, drop, bulk mutation. */
  Destructive: 'destructive',
} as const;
export type CommandClass = (typeof CommandClass)[keyof typeof CommandClass];

export const AutonomyTier = {
  /** Read proceeds; everything else is blocked outright, never prompted. */
  ReadOnly: 'read_only',
  /** Default for new automations. Read and write proceed; the rest pause. */
  Supervised: 'supervised',
  /** Opt-in, must name an agent. All proceed except destructive. */
  Full: 'full',
} as const;
export type AutonomyTier = (typeof AutonomyTier)[keyof typeof AutonomyTier];

export const GateVerdict = {
  /** Execute it now. */
  Proceed: 'proceed',
  /** Suspended; a human has been asked. The worker is released. */
  Approve: 'approve',
  /** The tier forbids this class outright. The run has failed. */
  Blocked: 'blocked',
  /** No steps left; the run has succeeded. */
  Done: 'done',
  /** Steps remain but none are due yet. */
  Wait: 'wait',
} as const;
export type GateVerdict = (typeof GateVerdict)[keyof typeof GateVerdict];

/**
 * What the gate decides, by class and tier. Mirrors `app.gate_verdict`.
 *
 * `as const satisfies` rather than a type annotation: the annotation would
 * widen every cell to `GateVerdict`, and the literal types are the point —
 * `GATE_MATRIX.destructive.full` is the string `'approve'`, so a refactor that
 * lets destructive actions through at the full tier fails to compile rather
 * than merely failing a test.
 */
export const GATE_MATRIX = {
  read: { read_only: 'proceed', supervised: 'proceed', full: 'proceed' },
  write: { read_only: 'blocked', supervised: 'proceed', full: 'proceed' },
  network: { read_only: 'blocked', supervised: 'approve', full: 'proceed' },
  install: { read_only: 'blocked', supervised: 'approve', full: 'proceed' },
  // Destructive pauses at every tier. No automation is ever fully autonomous
  // for deletion, drop, or bulk mutation.
  destructive: { read_only: 'blocked', supervised: 'approve', full: 'approve' },
} as const satisfies Record<CommandClass, Record<AutonomyTier, GateVerdict>>;

export function gateVerdict(
  commandClass: CommandClass,
  tier: AutonomyTier,
): GateVerdict {
  return GATE_MATRIX[commandClass][tier];
}

/** Whether this action will pause for a human at this tier. */
export function needsApproval(
  commandClass: CommandClass,
  tier: AutonomyTier,
): boolean {
  return gateVerdict(commandClass, tier) === GateVerdict.Approve;
}

// ---------------------------------------------------------------------------
// Execution state
// ---------------------------------------------------------------------------

export const AutomationTriggerKind = {
  RecordCreated: 'record_created',
  RecordUpdated: 'record_updated',
  FieldChanged: 'field_changed',
  StageChanged: 'stage_changed',
  Scheduled: 'scheduled',
  Webhook: 'webhook',
  Manual: 'manual',
} as const;
export type AutomationTriggerKind =
  (typeof AutomationTriggerKind)[keyof typeof AutomationTriggerKind];

export const AutomationRunStatus = {
  Queued: 'queued',
  Running: 'running',
  /** Suspended pending a human decision. No worker is held. */
  WaitingApproval: 'waiting_approval',
  /** Suspended on a timer — a delay step or a retry backoff. */
  WaitingUntil: 'waiting_until',
  Succeeded: 'succeeded',
  Failed: 'failed',
  Cancelled: 'cancelled',
} as const;
export type AutomationRunStatus =
  (typeof AutomationRunStatus)[keyof typeof AutomationRunStatus];

/** Statuses from which no further work will happen without intervention. */
export const TERMINAL_RUN_STATUSES: readonly AutomationRunStatus[] = [
  AutomationRunStatus.Succeeded,
  AutomationRunStatus.Failed,
  AutomationRunStatus.Cancelled,
];

export function isTerminalRun(status: AutomationRunStatus): boolean {
  return TERMINAL_RUN_STATUSES.includes(status);
}

export const AutomationStepStatus = {
  Pending: 'pending',
  Running: 'running',
  WaitingApproval: 'waiting_approval',
  Succeeded: 'succeeded',
  Failed: 'failed',
  /** A condition excluded it. */
  Skipped: 'skipped',
  /** The tier forbids this class outright; it was never executable. */
  Blocked: 'blocked',
  Cancelled: 'cancelled',
} as const;
export type AutomationStepStatus =
  (typeof AutomationStepStatus)[keyof typeof AutomationStepStatus];

/**
 * `expired` is distinct from `rejected` on purpose. Silence is not consent —
 * an unanswered request means the action does not happen — but "a human said
 * no" and "nobody answered" are different answers to "why did this not go out",
 * and collapsing them loses the one that indicates a broken process.
 */
export const ApprovalDecision = {
  Pending: 'pending',
  Approved: 'approved',
  Rejected: 'rejected',
  Expired: 'expired',
} as const;
export type ApprovalDecision =
  (typeof ApprovalDecision)[keyof typeof ApprovalDecision];

// ---------------------------------------------------------------------------
// Identifiers
// ---------------------------------------------------------------------------

export type AutomationId = Id<'Automation'>;
export type AutomationVersionId = Id<'AutomationVersion'>;
export type AutomationRunId = Id<'AutomationRun'>;
export type AutomationStepId = Id<'AutomationStep'>;
export type ApprovalRequestId = Id<'ApprovalRequest'>;
export type ScheduledJobId = Id<'ScheduledJob'>;

// ---------------------------------------------------------------------------
// Entities
// ---------------------------------------------------------------------------

export interface Automation {
  readonly id: AutomationId;
  readonly organization_id: OrganizationId;
  readonly name: string;
  readonly description: string | null;
  readonly is_active: boolean;
  readonly autonomy: AutonomyTier;
  /** Required by CHECK when autonomy is 'full'. */
  readonly agent_name: string | null;
  /**
   * A run with no human present. Anything that would need approval fails
   * loudly and records why, rather than skipping or silently proceeding.
   */
  readonly is_unattended: boolean;
  readonly current_version: number;
  readonly created_by: UserId | null;
  readonly created_at: Date;
  readonly updated_at: Date;
  readonly deleted_at: Date | null;
}

/**
 * A published definition. Append-only: a run pins the version it started under,
 * and rewriting it would rewrite the record of what someone approved.
 */
export interface AutomationVersion {
  readonly id: AutomationVersionId;
  readonly organization_id: OrganizationId;
  readonly automation_id: AutomationId;
  readonly version: number;
  readonly trigger_kind: AutomationTriggerKind;
  readonly trigger_config: JsonObject;
  readonly conditions: readonly JsonObject[];
  readonly actions: readonly AutomationAction[];
  readonly published_at: Date | null;
  readonly created_by: UserId | null;
  readonly created_at: Date;
}

/**
 * One action in a definition.
 *
 * `command_class` is declared per action rather than inferred from `kind`.
 * Inference means a new action kind gets whatever the fallback is, and a
 * permissive fallback is a hole that opens by omission rather than by decision.
 */
export interface AutomationAction {
  readonly kind: string;
  readonly command_class: CommandClass;
  readonly config?: JsonObject;
  readonly max_attempts?: number;
}

export interface AutomationRun {
  readonly id: AutomationRunId;
  readonly organization_id: OrganizationId;
  readonly automation_id: AutomationId;
  readonly automation_version_id: AutomationVersionId;
  readonly scheduled_job_id: ScheduledJobId | null;
  readonly status: AutomationRunStatus;
  /** Snapshotted at enqueue, so editing the automation cannot change a run. */
  readonly autonomy: AutonomyTier;
  readonly is_unattended: boolean;
  readonly agent_name: string | null;
  readonly trigger_kind: AutomationTriggerKind;
  readonly trigger_entity_type: CrmEntity | null;
  readonly trigger_entity_id: string | null;
  /** Makes a twice-delivered webhook run once. Null means no natural key. */
  readonly dedup_key: string | null;
  readonly current_step: number;
  readonly claimed_by: string | null;
  readonly claimed_at: Date | null;
  readonly lease_expires_at: Date | null;
  readonly run_after: Date | null;
  readonly started_at: Date | null;
  readonly finished_at: Date | null;
  readonly error_code: string | null;
  readonly error_message: string | null;
  readonly created_at: Date;
  readonly updated_at: Date;
}

/** The cold half of a run: large, read rarely, pruned on its own clock. */
export interface AutomationRunPayload {
  readonly run_id: AutomationRunId;
  readonly organization_id: OrganizationId;
  readonly input: JsonObject;
  /** Accumulated across steps, keyed by step id. Merged, never replaced. */
  readonly context: JsonObject;
  readonly output: JsonObject;
  readonly created_at: Date;
  readonly updated_at: Date;
}

export interface AutomationStep {
  readonly id: AutomationStepId;
  readonly organization_id: OrganizationId;
  readonly run_id: AutomationRunId;
  readonly step_index: number;
  readonly action_kind: string;
  readonly command_class: CommandClass;
  readonly status: AutomationStepStatus;
  readonly attempt: number;
  readonly max_attempts: number;
  readonly run_after: Date | null;
  readonly started_at: Date | null;
  readonly finished_at: Date | null;
  readonly error_code: string | null;
  readonly error_message: string | null;
  readonly output: JsonObject;
  readonly created_at: Date;
  readonly updated_at: Date;
}

/**
 * The durable form of the pause in CLAUDE.md §3.
 *
 * `summary` is what a person actually reads, and the database requires it to be
 * substantive: "Agent X wants to send an email to <address>" is decidable, and
 * an action kind plus a config blob is not.
 */
export interface ApprovalRequest {
  readonly id: ApprovalRequestId;
  readonly organization_id: OrganizationId;
  readonly run_id: AutomationRunId;
  readonly step_id: AutomationStepId;
  readonly command_class: CommandClass;
  readonly autonomy: AutonomyTier;
  readonly summary: string;
  readonly detail: JsonObject;
  readonly requested_at: Date;
  /** Past this, the request expires and the action does not happen. */
  readonly expires_at: Date;
  readonly decision: ApprovalDecision;
  readonly decided_at: Date | null;
  /** Null for an expiry — nobody decided it. */
  readonly decided_by: UserId | null;
  readonly decision_reason: string | null;
  readonly created_at: Date;
}

/**
 * Recurrence, which is not a run.
 *
 * Concrete runs are materialised from this. Collapsing the two makes a missed
 * window indistinguishable from a window that never existed.
 */
export interface ScheduledJob {
  readonly id: ScheduledJobId;
  readonly organization_id: OrganizationId;
  readonly automation_id: AutomationId;
  readonly name: string;
  readonly recurrence: IntervalString;
  readonly next_run_at: Date;
  readonly last_run_at: Date | null;
  /** Missed windows beyond this are skipped, not replayed. */
  readonly catchup_limit: number;
  readonly is_active: boolean;
  readonly created_at: Date;
  readonly updated_at: Date;
  readonly deleted_at: Date | null;
}

// ---------------------------------------------------------------------------
// The worker protocol
// ---------------------------------------------------------------------------

/**
 * Result of `app.begin_step()` — what this worker should do next.
 *
 * A worker loop is: claim → begin_step → act → complete_step/fail_step →
 * begin_step … until the verdict is `done`, `blocked`, `approve`, or `wait`.
 * The last three all mean "stop working this run"; only `approve` will come
 * back, and only once a human decides.
 */
export interface StepTicket {
  readonly step_id: AutomationStepId | null;
  readonly step_index: number | null;
  readonly action_kind: string | null;
  readonly command_class: CommandClass | null;
  readonly verdict: GateVerdict;
  readonly approval_id: ApprovalRequestId | null;
  readonly message: string | null;
}

export interface EnqueueAutomationRunArgs {
  automation_id: AutomationId;
  trigger_entity_type?: CrmEntity | null;
  trigger_entity_id?: string | null;
  input?: JsonObject;
  /** Supply for anything replayable. Two enqueues with one key make one run. */
  dedup_key?: string | null;
  run_after?: Date | null;
}

export interface PublishAutomationVersionArgs {
  automation_id: AutomationId;
  trigger_kind: AutomationTriggerKind;
  trigger_config?: JsonObject;
  conditions?: readonly JsonObject[];
  actions: readonly AutomationAction[];
}

/**
 * Error codes a run can terminate with. Distinguishable on purpose: each names
 * a different thing that went wrong and a different fix.
 */
export const RUN_ERROR_CODES = {
  /** The tier forbids the action's class outright. Misconfiguration. */
  ClassNotPermitted: 'class_not_permitted',
  /** An unattended run hit an action needing approval, with nobody to ask. */
  ApprovalRequiredUnattended: 'approval_required_unattended',
  /** A human said no. */
  ApprovalRejected: 'approval_rejected',
  /** Nobody answered before the request expired. */
  ApprovalExpired: 'approval_expired',
  Cancelled: 'cancelled',
} as const;
export type RunErrorCode =
  (typeof RUN_ERROR_CODES)[keyof typeof RUN_ERROR_CODES];

/**
 * Every database enum introduced by 0015, for the drift check in verify.ts.
 */
export const AUTOMATION_DATABASE_ENUMS = {
  command_class: CommandClass,
  autonomy_tier: AutonomyTier,
  automation_trigger_kind: AutomationTriggerKind,
  automation_run_status: AutomationRunStatus,
  automation_step_status: AutomationStepStatus,
  approval_decision: ApprovalDecision,
} as const;
