# Known gaps in the current schema

Things the schema does not yet do, found by comparing it against mature CRMs
(twenty, listmonk, SuiteCRM, n8n). Recorded rather than silently deferred: a gap
that is written down is a decision, a gap that is only known in conversation is
a landmine.

Ordered by how expensive each becomes if deferred; retrofit cost is the real
sort key. Resolved items stay in place with their reasoning, so the record
shows what was done and why — several of these are cheap now and painful once there is data.

---

## 1. ~~Consent is a flag~~ — RESOLVED in `0011_consent.sql`

**Was: high severity. Now built and tested.**

Replaced the two opt-out booleans with a real model:

- `contact_channels` — addressable endpoints, one per email/phone, each with
  its own verification state and consent history.
- `consent_purposes` — tenant-defined, flagged transactional or requiring
  double opt-in, optionally time-limited.
- `consent_records` — **append-only ledger** of every grant, denial and
  withdrawal, with evidence (ip, form url, consent text) and actor attribution.
  No UPDATE or DELETE policy.
- `consent_state` — derived cache so the send check is a primary-key lookup,
  maintained by trigger and guarded against out-of-order arrival.
- `suppressions` — address-level, carrying no FK to contacts, so a suppression
  outlives the contact and can exist before one.
- `message_events` — partitioned, idempotent on `(provider, provider_event_id)`.

`app.can_send(channel, purpose)` is the gate, returning a reason as well as a
verdict. Precedence, asserted by `consent_test.sql`:

    suppression > legacy opt-out > transactional purpose > recorded consent

Suppression outranks even an explicit grant: a hard-bounced address does not
become deliverable because someone consented, and writing to it damages sending
reputation for every other contact in the tenant.

`app.ingest_message_event()` applies bounce and complaint consequences in the
same transaction, so an ESP webhook cannot record a complaint without the
address becoming unsendable.

**Deliberately not built:** the sender. No SMTP pool, no campaign runner, no
bounce mailbox scanner. Those belong to a dedicated service which mirrors
delivery events back in.

**Follow-up requiring approval:** `contacts.email_opt_out` / `sms_opt_out` were
retained rather than dropped, so this migration is non-destructive, and
`can_send()` honours them as a global withdrawal during the transition.
Dropping them is a separate, destructive change.

---

## 2. No attachments

**Severity: high. Trivial now, awkward later.**

There is nowhere to put a file. Every CRM needs one: a contract PDF on a deal, a
site photo on a service job, an imported CSV. Needs a polymorphic table with
storage key, uploader, size, mime type, and a checksum — plus a decision about
where bytes live (object storage, not Postgres).

---

## 3. Deals have an amount but no line items

**Severity: medium.**

`service_jobs` has `service_job_items`, but a deal carries only a scalar
`amount`. Real sales deals are itemised, and quoting, invoicing, and margin
analysis all need the breakdown. Relatedly, `services` is a service catalogue,
not a general product catalogue — no cost basis, so no margin; no price book, so
no per-currency or per-segment pricing.

---

## 4. No automation layer

**Severity: medium. Architecture worth settling early.**

"When a deal enters Negotiation, create a task for the owner" has no home.
SuiteCRM's rules engine and n8n's workflow model both address this. n8n's
licence forbids embedding it, but its data model is the right reference:

- Workflow definitions versioned, with run history split hot/cold (metadata in
  one table, heavy payload in a 1:1 companion) — otherwise execution history
  swamps the table you query for status.
- Recurrence separated from concrete runs: a `scheduled_job` describes *when it
  should run*, `scheduled_task` rows are *specific runs* that workers claim.
- A deduplication key on triggers, so a webhook delivered twice runs once.
- Per-action retry with explicit error branches, rather than exceptions.

**The Yourider-specific requirement:** a Network-class action must *suspend* the
run pending approval — n8n's wait-state pattern — not block a worker thread.
The approval gate in `CLAUDE.md` §3 becomes a first-class execution status. That
design constraint should be settled before the automation table shape is fixed,
because it is hard to add to a synchronous executor afterwards.

---

## 5. Email and calendar have no identity

**Severity: medium. Expensive to retrofit.**

`activities.kind = 'email'` records that an email happened. There is no thread
identity, no provider message-id, and no per-user mailbox connection — so
two-way sync, deduplication of a message seen twice, and threading are all
impossible. twenty models `messageThread` / `message` / `messageParticipant` /
`connectedAccount` / `calendarEvent` as first-class objects. Adding this after
there is activity data means backfilling identity that was never captured.

---

## 6. Teams are free text

**Severity: medium.**

`memberships.team` is a string. Manager-scoped visibility ("see everything my
team owns") needs a real table, and any hierarchy needs it to be recursive.
Currently a typo creates a new team silently.

---

## 7. No saved views

**Severity: low-medium.**

Filters, sorts, column selection, and board configuration have nowhere to live,
so they end up in frontend state and cannot be shared, defaulted per role, or
referenced by automation.

---

## 8. RLS is tenant-level only

**Severity: low now, high if regulated data arrives.**

Isolation is per-organization. There is no field-level redaction — no way to
hide a salary or identifier from some members of the same tenant — and no
row-level sharing rules beyond the tenant boundary. twenty models object-,
field-, and row-level permissions as data. Worth knowing before someone stores
something sensitive in a custom field.

---

## 9. Smaller items

- **Webhooks and API keys** — `actor_type = 'integration'` exists in the enum
  with no mechanism behind it.
- **Notifications** — no in-app notification model.
- **Merge and dedup** — no way to record that two contacts are the same person.
- **Import batches** — a bulk import cannot be traced or rolled back.
- **FX rate provenance** — `deals.fx_rate` records a rate but not where it came
  from or when, so historical conversions are unauditable.
- **Tasks and notes attach to exactly one record** via `entity_type` +
  `entity_id`. twenty uses join tables to allow several targets.
- **Denormalised label on timeline rows** — twenty caches the linked record's
  name so a timeline entry still reads sensibly after the record is deleted.
  Cheap, and it makes deletion non-destructive to history.

---

## Explicitly decided against

**A columnar analytics store.** plausible pairs Postgres with ClickHouse, but
its workload is immutable, joinless, high-cardinality click data at a volume
CRM activity does not approach — and Yourider's reporting questions (pipeline
velocity, conversion rate, agent volume) are *joins*, which is what Postgres is
good at and ClickHouse is not. "Millions of customers" is row count in
`contacts`, not event throughput. Month partitioning and rollup tables are
sufficient. Revisit only if a single tenant's activity partition passes ~10⁸
rows or dashboard p95 exceeds a second after honest index work.

**Schema-per-tenant.** twenty gives each workspace its own Postgres schema with
real typed columns, generated by runtime DDL. It buys native types and cheap
indexing on any field, but costs lock-taking DDL on a live system and catalogue
bloat linear in tenant count. At Yourider's intended tenant count, shared tables
with RLS is the right shape. One idea worth keeping: *promote* a hot custom
field to a real column for a tenant that needs it, with JSONB as the default.
