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
- Adding a column to a hot table: nullable or with a default, never a rewrite
  that takes an ACCESS EXCLUSIVE lock for minutes on a large table.
