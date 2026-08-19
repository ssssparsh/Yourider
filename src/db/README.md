# Database

Postgres schema for Yourider's CRM core. Plain SQL migrations, applied in
filename order, no ORM-generated DDL.

## Layout

```
migrations/   numbered, forward-only SQL migrations
tests/        functional and RLS suites
run_tests.sh  rebuilds a scratch DB from zero and runs both suites
```

## Running

Apply to a fresh database:

```bash
createdb yourider
for f in src/db/migrations/*.sql; do
  psql -d yourider -v ON_ERROR_STOP=1 -f "$f"
done
```

Run the suites (creates and drops its own scratch database):

```bash
./src/db/run_tests.sh
```

`ON_ERROR_STOP=1` is not optional. Without it psql reports success after a
failed statement, which is how a half-applied migration reaches production.

## The tenant model

Every business table carries `organization_id NOT NULL`. Isolation is enforced
in four overlapping places, because any one of them can be bypassed by a
sufficiently careless query:

1. **RLS policies** (`0009_rls.sql`) compare `organization_id` to
   `app.current_org_id()` on every read and write.
2. **`app.current_org_id()` returns NULL when unset**, and NULL never equals
   anything — so a request that forgets to set tenant context sees zero rows
   rather than every row. Failing closed is the whole point.
3. **`assert_same_org()` triggers** reject a foreign key pointing at another
   tenant's row. RLS governs which rows you can *see*; this governs which rows
   you can *point at*, which policies alone do not cover.
4. **`freeze_organization_id()`** makes `organization_id` immutable after
   insert. Moving a record between tenants is a migration with its own audit
   story, not an UPDATE.

### Setting tenant context

Two supported paths, checked in that order:

```sql
-- Server-side workers, background jobs, agent runs
SELECT set_config('app.current_org_id',  '<uuid>', false);
SELECT set_config('app.current_user_id', '<uuid>', false);

-- Agents additionally identify themselves, which makes their writes
-- attributable in audit_log (see "Agent attribution" below)
SELECT set_config('app.current_agent', 'lead-qualifier', false);
```

On the PostgREST/Supabase request path the JWT's `organization_id` claim and
`sub` are read automatically; no explicit `set_config` is needed.

### The BYPASSRLS escape hatch

Migrations, backups, and provisioning need to cross tenant boundaries. That is
what a `BYPASSRLS` role is for (Supabase calls it `service_role`).

**An API request must never run as that role.** It disables every policy in this
schema silently — no error, no log line, just full visibility. Application
traffic connects as an unprivileged role and sets tenant context per request.

This is also why `run_tests.sh` creates a separate `NOSUPERUSER NOBYPASSRLS`
role for the RLS suite, and why `rls_test.sql` aborts if it detects it is
running as a privileged role. Run those assertions as a superuser and they pass
without testing anything.

## Pipelines

Stages are rows, not an enum. A `pipelines` row declares which entity it drives
(`lead` | `deal` | `service_job`); `pipeline_stages` rows carry order,
win-probability, and a terminal classification (`open` | `won` | `lost`).

Reporting keys off `kind`, never off stage names, so a tenant renaming "Closed
Won" to "Signed" does not break forecasting.

**Change stages only through `app.move_to_stage()`.** It keeps three things in
agreement that are easy to get individually right and collectively wrong: the
row's `stage_id`, its `stage_entered_at`, and the open/closed interval in
`stage_transitions`. It also stamps `closed_at` when entering a terminal stage.

```sql
SELECT app.move_to_stage('deal', '<deal-uuid>', '<stage-uuid>',
                         p_actor_user => '<user-uuid>',
                         p_note       => 'verbal agreement');
```

## Lead conversion

`app.convert_lead()` turns a lead into an account, a contact, and (optionally) a
deal in one transaction, reusing an existing account or contact when one already
matches. Leads deliberately do not reference `accounts`/`contacts` before
conversion — that is what keeps unqualified leads out of the customer database.

```sql
SELECT * FROM app.convert_lead('<lead-uuid>', p_create_deal => true);
```

## Custom fields

Tenant-defined fields live in a JSONB `custom_fields` column, with
`custom_field_definitions` acting as the schema-of-the-schema. A validation
trigger enforces those definitions on write: unknown keys, wrong JSON types,
out-of-range numbers, and select values outside the declared options are all
rejected.

The alternative designs were weighed and rejected — EAV turns every read into a
pivot, and a typed side-table needs a migration per new type. JSONB keeps values
on the row (no join), Postgres indexes them with GIN, and the definitions table
supplies the typing JSONB lacks.

## Activity vs. audit

Two logs, deliberately separate:

- **`activities`** — the business timeline a human reads: calls, emails,
  meetings, notes. Renders the detail page.
- **`audit_log`** — field-level forensics: which column on which row changed,
  from what, to what, by whom, and why.

Merging them makes both worse: the timeline fills with column diffs and the
audit trail becomes unqueryable.

`audit_log` has **no UPDATE or DELETE policy**. A tamperable audit trail is not
an audit trail. Retention is handled by detaching old partitions as a privileged
operation, never by row deletes.

### Agent attribution

`actor_type` is one of `user | agent | system | integration`. When
`app.current_agent` is set, writes are recorded as `actor_type = 'agent'` with
the agent's name — and a CHECK constraint refuses an agent-attributed row that
does not name the agent.

This is what makes the approval gate in `CLAUDE.md` §3 auditable after the fact
rather than only at the moment of the prompt: "which agent changed this deal's
amount, and did anyone approve it" is answerable from the database.

Set `app.audit_reason` before a write to record *why*:

```sql
SELECT set_config('app.audit_reason', 'discount approved by ops', false);
```

## Pricing, line items and margin

A deal carried a single scalar `amount`. That draws a pipeline and answers
nothing else — not what was sold, at what discount, or at what margin.
`service_jobs` has had line items since `0006`, so delivery could be itemised
while the sale could not.

### The catalogue has a cost basis

`services.unit_cost` was added rather than a second `products` table. A separate
catalogue makes "what did we sell last quarter" a UNION across two tables that
drift apart, and every report has to remember both.

**`unit_cost = NULL` means the cost is unknown, not zero.** That distinction is
load-bearing: `app.deal_totals()` reports `cost_known`, and returns a NULL
margin rather than one computed against only the lines that happen to carry a
cost — which would overstate it, and always in the flattering direction.

### Price books

One catalogue entry, several prices: per currency, per segment, per volume tier,
with effective dating. Encoding any of those as a column on `services` means a
migration per pricing dimension.

```sql
SELECT * FROM app.resolve_price(:service_id, :price_book_id, :quantity);
-- (unit_price, unit_cost, price_book_id, price_book_entry_id, source)
```

- **Tiers are declared by their floor.** An entry applies from `min_quantity`
  upward and the highest applicable one wins, so there are no ranges to leave
  gaps between.
- **Effective dating schedules a change without deleting what it replaces**, so
  a quote issued last week can still be explained. Ties on the tier floor break
  toward the later `valid_from`.
- **The default book is per currency, not per organization.** A tenant selling
  in three currencies needs three defaults.
- **A book named explicitly but not in effect raises**, rather than falling back
  to the catalogue. Silent fallback prices the deal from list while the caller
  believes a negotiated book applied.

### Line items snapshot the sale

`app.add_deal_line_item()` copies price, cost, description and SKU onto the row
and records which book the price came from. Reading through to the catalogue
instead would let a repricing silently rewrite what a closed deal was sold for —
the same reasoning as `deals.probability` snapshotting its stage's probability.

The derived amounts are generated columns, computed in this order:

    gross    = round(quantity × unit_price, 4)
    discount = round(percent × gross, or the flat amount, 4)
    net      = gross − discount
    tax      = round(net × tax_rate, 4)
    total    = net + tax

Two properties this ordering buys, both asserted by `pricing_test.sql`:

- **Tax applies to the discounted net, never the gross.** Otherwise the customer
  is charged tax on a discount they received.
- **`net + tax = total` exactly.** Gross and discount are each rounded before
  subtraction, so net is exact at 4dp and tax is computed once from it.
  Rounding each part independently is how an invoice ends up not adding up.

Margin is against **net revenue, not the tax-inclusive total** — tax collected
on behalf of a government was never revenue.

### The deal amount follows its lines

Once a deal has line items, `deals.amount` is maintained by trigger in the same
transaction as the line change, and a hand edit is **refused**:

```
ERROR:  deal ... has line items, so its amount is derived from them
```

Loud rather than silent — the rollup would overwrite the edit on the next line
change anyway, and a number that quietly reverts is worse than one that is
refused. A deal with **no** line items keeps the manual `amount` it has always
had, so this is additive for existing rows.

`app.deal_totals()` reports everything else on demand. A stored subtotal that
nothing forces to agree with its lines is a second source of truth.

## Files and attachments

Two tables, not one. `files` is a stored blob; `attachments` is a link from that
blob to a record. One signed contract can hang off a deal, an account and a
service job without three copies of the bytes existing, and "where else does
this document appear" — the first question asked when a document turns out to
be wrong — stays answerable.

**The bytes live in object storage, not Postgres.** A `bytea` column puts file
content into WAL, into every base backup, and onto every replica, turning a
20 MB upload into 20 MB of replication traffic. These tables are the index and
the authorisation decision; S3 (or MinIO, or Supabase Storage) holds the bytes.

### Storage keys are generated, never supplied

```sql
storage_key text GENERATED ALWAYS AS (organization_id::text || '/' || id::text) STORED
```

A client-chosen key is a tenant-isolation hole that no policy on this table can
close: tenant A asks for `org-b/invoices/secret.pdf` and either reads or
overwrites tenant B's object, and the breach happens in the object store where
Postgres has no say. Deriving the key from the row makes it unrepresentable.

### Uploading is two-phase

```sql
-- 1. reserve a row and get somewhere to put the bytes
SELECT * FROM app.begin_file_upload(
  :org, 'yourider-files', 'contract.pdf', 'application/pdf', :sha256, :user);

-- 2. after the client PUTs to the presigned URL
SELECT app.complete_file_upload(:file_id, :byte_size, :sha256);
```

The row exists before the bytes do, because the storage key has to be known in
order to issue a presigned URL. Without the state machine the only options are
trusting the client's word that the upload succeeded, or writing the row
afterwards and having no way to find objects whose row write failed.

Pass the checksum to `begin_file_upload` when the client hashed the file first:
identical content already held by that organization is returned immediately with
`already_stored = true` and no second upload happens. Deduplication is scoped to
the tenant on purpose — sharing blobs across tenants is a side channel, because
an instant upload tells tenant A that tenant B holds that exact document.

`complete_file_upload` returns the id of the **canonical** blob, which is not
always the id passed in: two uploads of identical content can be in flight at
once, and the loser is marked `superseded_by` rather than left as a second copy
nothing would collect. Use the returned id from that point on.

### Downloads go through the gate

```sql
SELECT * FROM app.can_download(:file_id);   -- (allowed, reason)
```

Shaped like `app.can_send`: a verdict plus a reason, because a caller that only
gets `false` has nothing to show the user and nothing to log. It **fails
closed** — an unscanned file is refused, since a file from an unknown source is
exactly the one worth withholding. `scan_status = 'skipped'` exists so a trusted
internal path can say so explicitly rather than arriving there by omission.

`app.record_scan_result()` records the verdict. A checksum that ever came back
`infected` is refused on re-upload: content is the identity, so renaming a
blocked file changes nothing.

This answers content safety only. Tenant isolation comes from RLS; whether
*this* user may see *this* record is the caller's question.

### Attachments validate their target

`entity_type` + `entity_id` is polymorphic and carries no foreign key, but
unlike `activities` it is checked on write by `app.assert_entity_in_org()`.
Attachments are low-volume and long-lived, and a dangling one surfaces at the
worst possible moment — someone opens a deal that no longer exists to find the
contract. `activities` skips the check because it is partitioned and
high-volume, and would pay that lookup on every interaction ever recorded.

`app.attach_file()` is the way in: it resolves the organization from the file,
records agent attribution, and writes the `file_attached` timeline entry.
`app.detach_file()` soft-deletes the link, because "this contract used to hang
off this deal" is a question that gets asked.

### Cleaning up

```sql
SELECT * FROM app.sweepable_files(interval '24 hours');
```

Reports blobs whose bytes can be removed, with a reason. It never deletes
anything — deletion is a Destructive-class action (`CLAUDE.md` §3) that belongs
to the sweeper. Act on specific reasons: `never_attached` is a policy choice
rather than a fact. The grace period is the safety mechanism; without it the
sweeper deletes bytes out from under an upload still in flight.

`files.attachment_count` is maintained by trigger and **recomputed** rather than
incremented, so it cannot drift: an increment/decrement pair has to be right for
insert, hard delete, soft delete, restore, and a re-pointed `file_id`, and one
missed path either deletes bytes still in use or leaks them forever.

Its audit trigger is column-scoped (`AFTER UPDATE OF upload_state, scan_status,
…`) so that counter churn does not fill the audit trail with rows recording that
a derived number moved.

## Automation, and the approval gate

"When a deal enters Negotiation, create a task for the owner" lives here. The
mechanics follow n8n's data model; its licence forbids embedding it (DECISIONS
D10), and the approval semantics are this system's own, from `CLAUDE.md` §3.

### Why it is a state machine and not a loop

A Network-class action must **suspend** the run pending approval, not block a
worker waiting for a human. A blocking wait holds a connection and a process for
as long as a person takes to answer — minutes, or a weekend — so a hundred
pending approvals is a hundred stalled workers.

So approval is a run *status*, the worker's lease is released, and a decision
re-queues the run for whichever worker picks it up next. Everything else about
the shape follows from that one requirement, which is why it is in the first
design rather than retrofitted.

**This migration executes nothing.** There is no worker in the database. It owns
the state machine, the authorisation decision and the trail; a process outside
does the effects and reports back. An executor inside the database would hold a
transaction open across every outbound network call.

### The gate

`app.gate_verdict(command_class, autonomy_tier)` is `CLAUDE.md` §3 as a
function, and the only place the rule is written in SQL:

| class | read_only | supervised | full |
| --- | --- | --- | --- |
| `read` | proceed | proceed | proceed |
| `write` | blocked | proceed | proceed |
| `network` | blocked | **approve** | proceed |
| `install` | blocked | **approve** | proceed |
| `destructive` | blocked | **approve** | **approve** |

Two rows matter more than the rest:

- **Destructive pauses at every tier**, including `full`. Nothing is ever fully
  autonomous for deletion, drop, or bulk mutation.
- **Read-only blocks rather than prompts.** A read-only automation asking
  permission to write is a misconfiguration, and turning it into a prompt trains
  people to approve reflexively.

The matrix also exists in `src/crm/types/automation.ts` so a client can say
"this will need approval" before submitting. `assertGateMatrixMatches()` in
`verify.ts` compares the two against the live database — duplication that
nothing checks is duplication that drifts.

### The worker protocol

```sql
SELECT app.claim_automation_run('worker-1');       -- leased, status = running
SELECT * FROM app.begin_step(:run_id);             -- verdict + what to do
SELECT app.complete_step(:step_id, :output);
-- or
SELECT app.fail_step(:step_id, 'timeout', 'upstream slow', true);
```

`begin_step` returns one of five verdicts: `proceed`, `approve`, `blocked`,
`done`, `wait`. Only `proceed` means keep working this run; `approve` is the one
that comes back, once a human decides.

An approval authorises **that step**, including its retries. Without that, the
gate re-evaluates after the decision, sees the same class at the same tier, and
asks again — a run that can never pass its first Network action however many
times someone says yes. (That bug was real, and `automation_test.sql` §5 is the
regression test.) Whether a retry is safe to repeat is an idempotency question
for the worker, not an authorisation question for the gate.

### Silence is not consent

`CLAUDE.md` §3: *"No response within the session means it does not happen —
never assume approval from silence or a stale prompt."*

```sql
SELECT app.expire_approvals();   -- run from cron
```

An unanswered request becomes `expired` and its run **fails**. `expired` is a
distinct decision from `rejected` because "a human said no" and "nobody
answered" are different answers to "why did this not go out" — and only one of
them indicates a broken process. A request past its deadline cannot be decided
afterwards, which is the stale-prompt case.

### Unattended runs

An automation flagged `is_unattended` has nobody to ask. When it reaches an
action that would pause, it **fails loudly** with
`error_code = 'approval_required_unattended'` and a message saying which step
and why. It does not skip the action, and it does not proceed. Steps that
already succeeded stay succeeded — failing the run does not pretend completed
work never happened.

### Durability

- **Runs are split hot/cold.** `automation_runs` is metadata the queue and every
  dashboard read; `automation_run_payloads` is the 1:1 companion holding trigger
  bodies and outputs. Retention prunes payloads on a short clock while run
  metadata stays queryable — and the queue never drags payloads through memory.
- **Leases, not locks.** A worker that dies leaves a lease that stops being
  renewed; `app.reclaim_expired_runs()` returns the run and its in-flight step
  to the queue. Without it a crashed worker strands its run in `running`
  forever, which is the most common way a queue quietly stops.
- **Retry is per step.** Re-running a whole workflow because its fourth action
  hit a rate limit repeats three side effects that already succeeded — for a
  Network action, that is the same email twice. Backoff is 30s, 60s, 120s…
  capped at an hour, and the run suspends on a timer rather than being held.
- **Runs pin their version.** Editing an automation cannot change a run already
  under way; a run that suspended on Friday must not resume Monday executing
  actions nobody approved.
- **Dedup keys.** `(automation_id, dedup_key)` is unique, so a twice-delivered
  webhook runs once. `app.enqueue_automation_run` returns the existing run
  rather than raising, so a caller's retry is a no-op instead of an error.
- **Recurrence is not a run.** `scheduled_jobs` says *when*;
  `app.materialise_scheduled_runs()` creates the concrete runs, keyed by window
  so two schedulers produce one run. `catchup_limit` stops a job that was down
  for a day from waking up and firing 288 times.

### What is audited

`automations`, `automation_versions` and `approval_requests` — who changed a
rule, and who approved an action. Runs and steps are not: they are already a
history of themselves and churn through statuses on every poll, so auditing them
would bury the trail in bookkeeping (DECISIONS D16). `approval_requests` has no
DELETE policy and a decided request cannot be re-decided.

## Partitioning and maintenance

`activities` and `audit_log` are RANGE-partitioned by month. These two grow with
interaction volume rather than customer count, so they reach hundreds of
millions of rows long before the customer table does. Partitioning means an old
month detaches in constant time instead of a DELETE that rewrites the table, and
date-scoped queries skip partitions outside their window entirely.

### Partitions and RLS — a trap worth knowing

Enabling row-level security on a partitioned **parent** does not protect its
**children**. Postgres does not propagate `relrowsecurity` to partitions, and a
partition is an ordinary table that any role holding SELECT on it can address
by name:

```sql
SELECT * FROM audit_log_202608;   -- bypasses the parent's policies entirely
```

This was a live hole in this schema between `0009` and `0010`. Reading through
`audit_log` looked correctly isolated while a direct read of the partition
returned every tenant's rows.

`app.ensure_month_partition()` now calls `app.secure_partition()` on every
partition it touches, so partitions are born protected and pre-existing ones are
repaired on the next maintenance run. `0010` also refuses to commit if any
partition is left unprotected, and `rls_test.sql` asserts direct-access
isolation across every partition.

**If you add another partitioned table, route its partition creation through
`ensure_month_partition` rather than issuing `CREATE TABLE ... PARTITION OF`
by hand.** The manual path is exactly how this hole was introduced.

**Partitions must exist before rows need them — an insert with no matching
partition fails outright.** Run this monthly from cron:

```sql
SELECT app.ensure_partition_window('activities', 1, 3);
SELECT app.ensure_partition_window('audit_log',  1, 3);
```

Both are idempotent. `0007` seeds a window of 2 months back and 6 ahead, so
there is runway before the job becomes load-bearing.

To archive an old month:

```sql
ALTER TABLE activities DETACH PARTITION activities_202601;
-- dump, ship to cold storage, then DROP
```

## Indexing conventions

Every index on a tenant table leads with `organization_id`. Not stylistic: it
keeps the planner from ever choosing a path that scans across tenants, and it
makes the composite index usable for the tenant-scoped filter that every real
query carries.

Soft-deleted rows are excluded via `WHERE deleted_at IS NULL` partial indexes,
so dead rows cost nothing in the hot path.

## Scale notes

Designed for millions of accounts/contacts and far more activity rows. What
actually keeps it there:

- **Cursor pagination, never OFFSET.** Indexes are ordered
  `(organization_id, created_at DESC, id)` for exactly this. `OFFSET 100000`
  makes Postgres walk 100,000 rows to discard them.
- **No unbounded result sets.** Every list endpoint needs a hard cap; the
  schema cannot enforce this, the API layer must.
- **`numeric`, never `float`, for money.** A total off by a cent is a support
  ticket. `base_amount` and `line_total` are generated columns so no two callers
  can compute a different answer.
- **Aggregates come from materialized views**, refreshed on a schedule — not
  from `SUM()` over the deal table on every dashboard load.
- **Search uses trigram GIN indexes**, not `LIKE '%term%'`, which cannot use an
  index at all.

Uptime is an operational property, not a schema one: replication, failover,
connection pooling, tested restores, and zero-downtime migration discipline all
live outside this directory.

## Conventions for new migrations

- Forward-only, numbered, never edited after being applied anywhere real.
- Wrap in `BEGIN`/`COMMIT` so a failure leaves nothing half-applied.
- New tenant table: `organization_id NOT NULL`, then
  `SELECT app.attach_tenant_triggers('<table>')`,
  `SELECT app.apply_tenant_rls('<table>')`, and
  `SELECT app.attach_audit('<table>')`.
- Add an `assert_same_org` trigger for every FK pointing at another tenant
  table.
- Polymorphic `(entity_type, entity_id)` reference on a low-volume table:
  validate it on write with `app.assert_entity_in_org()`. Add the branch to
  `app.entity_table()` when introducing a `crm_entity` value — it returns NULL
  for an unmapped one, and callers must treat that as an error rather than
  skipping validation.
- Auditing a table that carries a trigger-maintained derived column: attach the
  audit trigger with an explicit `UPDATE OF <columns>` list so the trail records
  intent rather than bookkeeping.
- Adding a column to a hot table: nullable or with a default, never a rewrite
  that takes an ACCESS EXCLUSIVE lock for minutes on a large table.
