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

## 5. ~~Email and calendar have no identity~~ — RESOLVED in `0020_messaging_identity.sql`

**Was: medium severity, "expensive to retrofit". Now built and tested — the
identity model, not the sync.**

`connected_accounts` / `message_threads` / `messages` / `message_participants`
/ `calendar_events`, mirroring twenty's shape. `messages.provider_message_id`
is the dedup key; `message_threads.message_count` / `last_message_at` are
recomputed on every message change, the same shape as `files.attachment_count`
(D15) and for the same reason a hand-maintained counter drifts.

See DECISIONS.md D28.

**Deliberately not built: the sync.** Nothing here talks to Gmail, Microsoft
Graph, or a mail server — that needs OAuth and a live API connection this
environment does not have. `connected_accounts.credential_ref` is a pointer
into a secrets manager, not the token itself, for the same reason CLAUDE.md §3
keeps secrets out of prompts and commits. See the API-requirements note at the
end of this document.

---

## 6. ~~Teams are free text~~ — RESOLVED in `0016_teams.sql`

**Was: medium severity. Now built and tested.**

`teams`, with a recursive `parent_team_id` guarded against cycles by a trigger
(0003's `accounts.parent_id` defers deeper cycles to application code; teams
are dozens of rows walked on every visibility check, so a real guard is worth
it here). `memberships.team` is retained non-destructively; `team_id` is
additive. `app.visible_team_ids()` answers what a role can reach — owner/admin
see everything, a manager sees their team and its descendants, everyone else
sees just their own team — matching the comment `membership_role` has carried
since 0002.

See DECISIONS.md D23.

**Not (yet) wired into RLS.** `visible_team_ids()` is a read-only helper; no
SELECT policy consults it. See §8 / D24 for why.

---

## 7. ~~No saved views~~ — RESOLVED in `0017_saved_views.sql`

**Was: low-medium severity. Now built and tested.**

`saved_views`: filters/sort/columns/board config as opaque JSONB (D5's
reasoning — a frontend filter DSL outlives migration cadence), with
`private` / `team` / `organization` visibility enforced by a policy that
replaces the tenant default rather than layering on top of it.

---

## 8. RLS is tenant-level only — PARTIALLY ADDRESSED in `0018_field_row_permissions.sql`

**Was: low now, high if regulated data arrives. Groundwork built; enforcement
deliberately deferred.**

`field_permissions` + `app.redact_fields()` is real and enforced (by the
application, at read time — see the migration for why column-level Postgres
security does not fit a pooled connection). `record_shares` records
who-can-see-what beyond the standing policy, but **nothing consults it yet**:
wiring it into every business table's SELECT policy would change existing
tenant-wide visibility behaviour, which is a product decision, not a side
effect of adding a table.

See DECISIONS.md D24 for the full reasoning and the revisit condition.

**Still true:** isolation beyond "restrict this one field or record" is
per-organization only. Worth knowing before someone stores something sensitive
in a custom field with no `field_permissions` row protecting it.

---

## 9. Smaller items

- **~~Webhooks and API keys~~ — RESOLVED in `0019_platform.sql`.**
  `api_keys` (SHA-256-hashed secrets, shown once — D25) and
  `webhook_subscriptions` / `webhook_deliveries` (server-generated HMAC signing
  secret, same reasoning as a storage key). Delivery — the outbound HTTP call —
  is not built; a worker outside makes it, the same boundary as the automation
  engine.
- **~~Notifications~~ — RESOLVED in `0019_platform.sql`.** `notifications`,
  addressed to one person, with a policy narrower than the tenant default —
  the case that needed it immediately rather than waiting on §8's general
  mechanism.
- **~~Merge and dedup~~ — RESOLVED in `0019_platform.sql`.**
  `app.merge_contacts()` / `app.merge_accounts()` repoint every live reference
  and soft-delete the loser; `entity_merges` snapshots what was lost. History
  (`activities`, `audit_log`) is not rewritten — see D26.
- **~~Import batches~~ — RESOLVED in `0019_platform.sql`.** `import_batches` +
  `import_batch_id` on accounts/contacts/leads/deals +
  `app.rollback_import_batch()`, which soft-deletes everything a batch created.
- **~~FX rate provenance~~ — RESOLVED in `0019_platform.sql`.** `fx_rates`:
  immutable, point-in-time, sourced. Does not fetch rates — that needs a live
  rates API; see the API-requirements note below.
- **~~Denormalised label on timeline rows~~ — RESOLVED in `0019_platform.sql`.**
  `activities.entity_label`, cached at write time. `activities.entity_id`
  itself still carries no FK validation — see D27 for why that trade-off is
  unchanged by adding the label.
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

---

## What now genuinely needs a third-party API

Everything above this line was built without one — 22 migrations, 8 test
suites, 249 database assertions, all running against local Postgres. What is
left in `open-gaps.md` that a schema and a state machine cannot finish alone:

1. **Object storage** (S3 / R2 / MinIO / Supabase Storage) — attachments
   (`0013`) have nowhere to put bytes yet; the schema is the index, not the
   filesystem, by design (D15).
2. **Email/SMS sending** (SendGrid, Postmark, SES, Twilio, ...) — the consent
   gate (`0011`) has nothing to authorise sends *to*; nothing is currently
   dispatching anything.
3. **Antivirus scanning** (ClamAV self-hosted, or a hosted scanner) — the
   attachment download gate (`0013`) fails closed on `scan_status = 'pending'`
   and there is no scanner recording a verdict yet.
4. **Mailbox/calendar OAuth** (Gmail API, Microsoft Graph) — the identity model
   (`0020`) is ready; nothing syncs into it yet.
5. **A live FX rates feed** — `fx_rates` (`0019`) records a rate, its source,
   and when it applied; nothing is fetching one yet.

Everything else flagged as remaining (§4's condition language, §8's
row-sharing enforcement, per-account pricing, storage quotas, teams/tasks
join-table generalisation) is more schema and state-machine work, the same
kind already done here — no key required.

