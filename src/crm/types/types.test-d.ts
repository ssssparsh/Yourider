/**
 * Compile-time assertions about the domain types.
 *
 * This file is never executed. Its correctness is proved by `tsc --noEmit`
 * succeeding: every `@ts-expect-error` below is itself an assertion — if the
 * expression on the following line stops being an error, the compiler reports
 * an *unused* expect-error and the build fails.
 *
 * That inversion is the point. A test that merely compiles proves nothing about
 * whether the types reject what they are supposed to reject.
 */

import type {
  AccountId,
  AccountInsert,
  ContactId,
  Deal,
  DealInsert,
  LeadInsert,
  ServiceJobItemInsert,
  Update,
} from './entities.js';
import { MembershipRole, StageKind, isTerminalStage } from './enums.js';
import type { Numeric } from './scalars.js';

// ---------------------------------------------------------------------------
// Branded ids must not be interchangeable
// ---------------------------------------------------------------------------

declare const accountId: AccountId;
declare const contactId: ContactId;

function takesAccountId(_id: AccountId): void {}

takesAccountId(accountId); // ok

// @ts-expect-error a ContactId is not an AccountId, despite both being strings
takesAccountId(contactId);

// @ts-expect-error a bare string is not an AccountId
takesAccountId('7b1c3f2e-0000-0000-0000-000000000000');

// ---------------------------------------------------------------------------
// Insert types must reject database-managed columns
// ---------------------------------------------------------------------------

const validAccount: AccountInsert = {
  name: 'Acme Industries',
  domain: null,
  industry: null,
  employee_count: null,
  annual_revenue: null,
  phone: null,
  website: null,
  owner_id: null,
  parent_id: null,
  created_by: null,
  // account_kind, lifecycle, custom_fields, tags all have database defaults
};
void validAccount;

const withDefaultsSet: AccountInsert = {
  name: 'Beta LLC',
  account_kind: 'individual',
  lifecycle: 'customer',
  tags: ['vip'],
  custom_fields: {},
  domain: null,
  industry: null,
  employee_count: null,
  annual_revenue: null,
  phone: null,
  website: null,
  owner_id: null,
  parent_id: null,
  created_by: null,
};
void withDefaultsSet;

const forgedTenant: AccountInsert = {
  name: 'Smuggled',
  // @ts-expect-error organization_id comes from tenant context, never the caller
  organization_id: 'some-other-org',
  domain: null,
  industry: null,
  employee_count: null,
  annual_revenue: null,
  phone: null,
  website: null,
  owner_id: null,
  parent_id: null,
  created_by: null,
};
void forgedTenant;

const forgedId: AccountInsert = {
  // @ts-expect-error id is assigned by the database
  id: 'abc',
  name: 'Nope',
  domain: null,
  industry: null,
  employee_count: null,
  annual_revenue: null,
  phone: null,
  website: null,
  owner_id: null,
  parent_id: null,
  created_by: null,
};
void forgedId;

// ---------------------------------------------------------------------------
// Generated columns must be unwritable
// ---------------------------------------------------------------------------

declare const numeric: Numeric;

const forgedBaseAmount: DealInsert = {
  name: 'Deal',
  pipeline_id: '' as DealInsert['pipeline_id'],
  stage_id: '' as DealInsert['stage_id'],
  // @ts-expect-error base_amount is GENERATED ALWAYS AS (amount * fx_rate)
  base_amount: numeric,
  account_id: null,
  primary_contact_id: null,
  probability: null,
  expected_close_date: null,
  closed_at: null,
  close_reason: null,
  owner_id: null,
  source_lead_id: null,
  last_activity_at: null,
  created_by: null,
};
void forgedBaseAmount;

const forgedLineTotal: ServiceJobItemInsert = {
  job_id: '' as ServiceJobItemInsert['job_id'],
  service_id: null,
  description: 'x',
  // @ts-expect-error line_total is GENERATED ALWAYS AS (quantity * unit_price * (1 + tax_rate))
  line_total: numeric,
};
void forgedLineTotal;

const forgedFullName: LeadInsert = {
  // @ts-expect-error full_name is generated from first_name and last_name
  full_name: 'Dana Doe',
  first_name: 'Dana',
  last_name: 'Doe',
  company_name: null,
  email: null,
  phone: null,
  job_title: null,
  website: null,
  source: null,
  campaign: null,
  pipeline_id: null,
  stage_id: null,
  score: null,
  scored_at: null,
  scored_by_agent: null,
  estimated_value: null,
  currency: null,
  owner_id: null,
  converted_at: null,
  converted_account_id: null,
  converted_contact_id: null,
  converted_deal_id: null,
  disqualified_at: null,
  disqualified_reason: null,
  last_activity_at: null,
  created_by: null,
};
void forgedFullName;

// ---------------------------------------------------------------------------
// Money must not be a number
// ---------------------------------------------------------------------------

declare const deal: Deal;

function takesNumeric(_n: Numeric): void {}
takesNumeric(deal.amount); // ok — Numeric is a branded string

// @ts-expect-error numeric arrives as a string; treating it as a number loses precision
const amountAsNumber: number = deal.amount;
void amountAsNumber;

// ---------------------------------------------------------------------------
// Nullable columns are `| null`, not optional
// ---------------------------------------------------------------------------

// A nullable column must be stated explicitly, so `undefined` cannot silently
// reach a query parameter and become a NULL nobody intended.
const update: Update<Deal> = { close_reason: null };
void update;

// @ts-expect-error undefined is not null
const undefinedNotNull: Update<Deal> = { close_reason: undefined };
void undefinedNotNull;

// ---------------------------------------------------------------------------
// Enum unions accept database values directly, without a cast
// ---------------------------------------------------------------------------

declare const rowValueFromDriver: string;

function takesStageKind(_k: StageKind): void {}

takesStageKind('won'); // ok — literal is assignable to the union
takesStageKind(StageKind.Lost); // ok

// @ts-expect-error a stage kind not in the database enum
takesStageKind('abandoned');

// @ts-expect-error an unnarrowed string could be anything
takesStageKind(rowValueFromDriver);

const terminal: boolean = isTerminalStage(StageKind.Won);
void terminal;

function takesRole(_r: MembershipRole): void {}
takesRole('viewer'); // ok

// @ts-expect-error not a membership_role value
takesRole('superuser');

// ---------------------------------------------------------------------------
// Consent layer
// ---------------------------------------------------------------------------

import type {
  ContactChannelId,
  ConsentPurposeId,
  ConsentRecord,
  SendVerdict,
  SuppressionInsert,
} from './consent.js';
import {
  ConsentSource,
  ConsentStateKind,
  MessageEventKind,
  SuppressionReason,
  isPermanentSuppression,
} from './consent.js';

declare const channelId: ContactChannelId;
declare const purposeId: ConsentPurposeId;

function takesChannelId(_id: ContactChannelId): void {}
takesChannelId(channelId); // ok

// @ts-expect-error a purpose id is not a channel id
takesChannelId(purposeId);

// @ts-expect-error an AccountId is not a ContactChannelId either
takesChannelId(accountId);

// A consent record is immutable: the ledger is append-only, so there is no
// update path and the row type says so.
declare const record: ConsentRecord;

// @ts-expect-error consent_records has no UPDATE policy; the row is readonly
record.state = ConsentStateKind.Granted;

// @ts-expect-error evidence cannot be swapped out after the fact
record.evidence = {};

function takesConsentState(_s: ConsentStateKind): void {}
takesConsentState('withdrawn'); // ok

// @ts-expect-error not a consent_state_kind value
takesConsentState('revoked');

function takesSource(_s: ConsentSource): void {}
takesSource(ConsentSource.DoubleOptin); // ok

// @ts-expect-error not a consent_source value
takesSource('email_reply');

// A permanent suppression reason must not carry an expiry — the database
// enforces it with a CHECK; this keeps the intent visible in the type layer.
const permanentBlock: SuppressionInsert = {
  channel_type: 'email',
  address: 'bounced@example.test',
  reason: SuppressionReason.HardBounce,
  expires_at: null,
};
void permanentBlock;

const permanent: boolean = isPermanentSuppression(SuppressionReason.Complaint);
void permanent;

// @ts-expect-error 'unsubscribed' is a message event, not a suppression reason
const wrongReason: SuppressionReason = MessageEventKind.Unsubscribed;
void wrongReason;

// The gate returns a reason on allow as well as deny.
declare const verdict: SendVerdict;
const allowed: boolean = verdict.allowed;
const why: string = verdict.reason;
void allowed;
void why;

// @ts-expect-error the verdict is readonly; callers report it, they do not edit it
verdict.allowed = true;
