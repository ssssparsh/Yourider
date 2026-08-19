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

## 2. ~~No attachments~~ — RESOLVED in `0013_attachments.sql`

**Was: high severity. Now built and tested.**

Two tables rather than the one this entry originally called for:

- `files` — one row per stored blob, carrying bucket, generated storage key,
  size, SHA-256, upload state, scan verdict, and a trigger-maintained reference
  count. Content-addressed and deduplicated **within a tenant**.
- `attachments` — the polymorphic link to a record, with a role
  (`attachment` / `avatar` / `logo` / `import_source` / `generated`) and a
  partial unique index making the singular roles singular.

Bytes live in object storage. `storage_key` is a generated column
(`organization_id || '/' || id`) so a client cannot choose one — a caller-chosen
key is a cross-tenant read of the object store that no policy in Postgres can
prevent.

Upload is two-phase (`app.begin_file_upload` → `app.complete_file_upload`), so a
reserved key exists before the bytes and an abandoned upload is findable.
`app.can_download()` is the gate, failing closed on an unscanned file and
refusing any checksum previously found infected. `app.sweepable_files()` reports
collectable blobs with a reason and never deletes.

Attachment targets are validated on write by `app.assert_entity_in_org()`;
`activities` deliberately still are not, for volume reasons. See DECISIONS.md
D15 and D16.

**Follow-up, not built:** the other mutating helpers (`app.move_to_stage`,
`app.convert_lead`, `app.stamp_assignment`) write no timeline rows at all.
`app.log_activity()` now exists as the shared emitter and `attach_file` uses it;
routing the others through it would make the timeline consistent. Left alone
because changing what those functions record is a behaviour change to working
code, which is the user's call rather than a side effect of this migration.

---

## 3. ~~Deals have an amount but no line items~~ — RESOLVED in `0014_pricing.sql`

**Was: medium severity. Now built and tested.**

- `services` gained `unit_cost`, `cost_currency`, `sku`, `is_stockable` — a cost
  basis on the existing catalogue rather than a second `products` table that
  would drift from it. NULL cost means *unknown*, not zero.
- `price_books` + `price_book_entries` — per currency, per volume tier, with
  effective dating. `app.resolve_price()` picks the highest applicable tier and
  reports whether the price came from a book or the catalogue.
- `deal_line_items` — price, cost, SKU and description snapshotted at the moment
  of sale, with the source book recorded. Gross, discount, net, tax, total, cost
  and margin are generated columns defined so `net + tax = total` exactly and
  tax lands on the discounted net.
- `deals.amount` now rolls up from the lines in the same transaction, and a hand
  edit on an itemised deal is refused rather than silently overwritten.
- `app.deal_totals()` reports `cost_known`, returning a NULL margin rather than
  one computed against only the lines that happen to carry a cost.

See DECISIONS.md D17 and D18.

**Deliberately not built:** quotes and invoices as documents. A line item is the
basis for both, but a quote has versions, an approval state, and an expiry, and
an invoice has a payment lifecycle — those are their own subsystems, and the
ledger rules in `CLAUDE.md` §7 apply to the invoice one in a way they do not
here.

---

## 4. ~~No automation layer~~ — RESOLVED in `0015_automation.sql`

**Was: medium severity, "architecture worth settling early". Now built and
tested — and settling it early was the right call.**

The design constraint this entry flagged is the one the whole engine is shaped
around: a Network-class action must **suspend** the run pending approval, not
block a worker. Approval is a run status, the worker's lease is released, and a
decision re-queues the run.

What that forced: a durable state machine — `automation_runs` (hot metadata) +
`automation_run_payloads` (cold 1:1 companion), `automation_steps` with per-step
retry and backoff, worker leases with reclaim, `approval_requests` as the
governance trail, `scheduled_jobs` separate from the runs materialised from
them, and dedup keys so a twice-delivered webhook runs once.

`app.gate_verdict()` is `CLAUDE.md` §3 as a function — all fifteen class/tier
combinations asserted in `automation_test.sql`, and `verify.ts` checks the
TypeScript copy of the matrix against the live database. Destructive pauses at
every tier including `full`; read-only blocks rather than prompts; an unanswered
request expires and the run fails; an unattended run that would pause fails
loudly with the reason recorded.

See DECISIONS.md D19–D22.

**Deliberately not built:** the worker. The database owns the state machine, the
authorisation decision and the trail; a process outside does the effects and
reports back through `claim_automation_run` / `begin_step` / `complete_step` /
`fail_step`. An executor inside the database would hold a transaction open
across every outbound network call.

**Also not built:** condition evaluation. `automation_versions.conditions` is
stored and passed through untouched — deciding whether a condition matches means
an expression language, and inventing one is a larger decision than this
migration should make on its own. Until then a worker evaluates conditions and
cancels the run if they do not hold.

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
- **Automation condition language** — `automation_versions.conditions` is stored
  but not evaluated by the database; see §4.
- **Per-account contract pricing** — price books are per currency and segment,
  not per customer. The shape is an `account_id` on `price_books` plus one more
  precedence step in `app.resolve_price()`.
- **Storage quotas** — `files` records `byte_size` per blob but nothing caps a
  tenant's total. A per-organization limit checked on `complete_file_upload` is
  the obvious shape; a running total on `organizations` would serialise every
  upload behind one row, so the counter belongs in its own table or a periodic
  rollup.
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
