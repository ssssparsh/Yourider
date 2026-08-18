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
