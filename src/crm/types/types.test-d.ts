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
  DealId,
  DealInsert,
  LeadInsert,
  ServiceJobItemInsert,
  Update,
} from './entities.js';
import type {
  AttachFileArgs,
  AttachmentId,
  DownloadVerdict,
  File as CrmFile,
  FileId,
  FileUploadTicket,
} from './attachments.js';
import {
  AttachmentRole,
  FileScanStatus,
  FileUploadState,
  isSingletonRole,
} from './attachments.js';
import type {
  AddDealLineItemArgs,
  DealLineItem,
  DealLineItemId,
  DealTotals,
  PriceBookId,
  PriceQuote,
} from './pricing.js';
import { PriceSource } from './pricing.js';
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

// ---------------------------------------------------------------------------
// Files and attachments
// ---------------------------------------------------------------------------

declare const fileId: FileId;
declare const attachmentId: AttachmentId;

function takesFileId(_id: FileId): void {}
takesFileId(fileId); // ok

// @ts-expect-error an AttachmentId is the link, not the blob
takesFileId(attachmentId);

function takesUploadState(_s: FileUploadState): void {}
takesUploadState(FileUploadState.Stored); // ok

// @ts-expect-error 'uploaded' is not a file_upload_state value
takesUploadState('uploaded');

function takesScanStatus(_s: FileScanStatus): void {}
takesScanStatus(FileScanStatus.Skipped); // ok

// @ts-expect-error a scan verdict is never 'unknown'
takesScanStatus('unknown');

const singleton: boolean = isSingletonRole(AttachmentRole.Avatar);
void singleton;

declare const file: CrmFile;

// The storage key is generated by the database from the row. Making it readonly
// in the type is the nearest the compiler gets to the guarantee the schema
// enforces: a caller-chosen key is a cross-tenant read of the object store.
// @ts-expect-error storage_key is derived, never assigned
file.storage_key = 'other-org/anything';

// byte_size is bigint, so a string — assigning a number loses the high bits on
// exactly the files big enough to matter.
// @ts-expect-error bigint arrives as a string, not a number
const size: number = file.byte_size;
void size;

declare const ticket: FileUploadTicket;
// When the content is already held there is nothing to upload.
const skipUpload: boolean = ticket.already_stored;
void skipUpload;

declare const download: DownloadVerdict;
const mayDownload: boolean = download.allowed;
void mayDownload;

// @ts-expect-error the verdict is readonly; callers report it, they do not edit it
download.allowed = true;

// entity_type must be a crm_entity value: the polymorphic target is validated
// on write, so a typo here is a runtime foreign_key_violation.
const attachArgs: AttachFileArgs = {
  file_id: fileId,
  entity_type: 'deal',
  entity_id: '00000000-0000-0000-0000-000000000000',
  role: AttachmentRole.Attachment,
};
void attachArgs;

const badTarget: AttachFileArgs = {
  file_id: fileId,
  // @ts-expect-error 'invoice' is not a crm_entity value
  entity_type: 'invoice',
  entity_id: '00000000-0000-0000-0000-000000000000',
};
void badTarget;

// ---------------------------------------------------------------------------
// Pricing, line items and margin
// ---------------------------------------------------------------------------

declare const priceBookId: PriceBookId;
declare const lineItemId: DealLineItemId;

function takesPriceBookId(_id: PriceBookId): void {}
takesPriceBookId(priceBookId); // ok

// @ts-expect-error a line item id is not a price book id
takesPriceBookId(lineItemId);

declare const line: DealLineItem;

// Every money column is a string. Treating one as a number is how a total ends
// up a cent out, which is the entire reason `numeric` was chosen.
// @ts-expect-error numeric arrives as a string, not a number
const lineTotal: number = line.line_total;
void lineTotal;

// @ts-expect-error generated columns are computed by the database, never assigned
line.line_total = line.net_amount;

// Cost is nullable and the null is meaningful: unknown, not zero.
const cost: Numeric | null = line.cost_total;
void cost;

// @ts-expect-error cost_total may be null — unknown cost is not zero cost
const costNotNull: Numeric = line.cost_total;
void costNotNull;

declare const totals: DealTotals;

// margin_total is nullable for the same reason, and cost_known is the flag that
// says which case you are in.
if (totals.cost_known) {
  const margin: Numeric | null = totals.margin_total;
  void margin;
}

// @ts-expect-error margin may be null when no cost was recorded
const margin: Numeric = totals.margin_total;
void margin;

declare const quote: PriceQuote;
function takesPriceSource(_s: PriceSource): void {}
takesPriceSource(quote.source); // ok
takesPriceSource(PriceSource.Catalogue); // ok

// @ts-expect-error 'list' is not a price source
takesPriceSource('list');

// A one-off line is allowed, but the database requires description and price
// together — expressed here as both being optional at the type level and
// checked at runtime, because "either both or neither" is not a shape the
// compiler can enforce without splitting the type in two.
declare const dealId: DealId;
const oneOff: AddDealLineItemArgs = {
  deal_id: dealId,
  description: 'Custom onboarding',
};
void oneOff;

