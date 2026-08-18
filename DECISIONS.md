# Decisions

Architecture decisions and why they were made, per `CLAUDE.md` §9. Append, do
not rewrite: a decision that turned out wrong is more useful with its original
reasoning intact than quietly edited to look correct.

Each entry records what was decided, what it was chosen over, and what would
justify revisiting it. That last part matters — a decision with no stated
reversal condition is a belief, not a decision.

---

## D1 — PostgreSQL, self-hosted Supabase stack

**Decided.** Postgres as the database; the Supabase component stack
(GoTrue for auth, PostgREST, Realtime) self-hosted via docker-compose rather
than the hosted product.

**Over:** hand-rolled auth and REST layers; a hosted BaaS; MySQL.

**Why:** the components are proven and independently replaceable, self-hosting
keeps control over secrets and data residency, and Realtime's WAL-based change
feed matches the chat interfaces in `/src/interfaces` needing live updates
without a separate pub/sub layer.

**Accepted cost:** authorisation lives in Postgres RLS, which is Postgres-specific.
Moving to another database later would mean rebuilding the authorisation model,
not swapping a driver. This is deliberate — RLS is the reason for the choice, not
an incidental detail of it.

**Revisit if:** RLS policy complexity starts exceeding what is reviewable, or a
requirement appears that Postgres genuinely cannot serve.

---

## D2 — Multi-tenancy by shared tables with row-level security

**Decided.** One set of tables, `organization_id` on every business row, RLS
enforcing isolation.

**Over:** schema-per-tenant (twenty's approach); database-per-tenant;
application-layer filtering alone.

**Why:** an application-layer filter must be correct in every query ever
written, including ad-hoc ones and anything an agent generates. An RLS policy
must be correct once. Schema-per-tenant buys native typed columns for custom
fields but costs lock-taking DDL on a live system and catalogue bloat linear in
tenant count — wrong at the intended scale.

**Depth, not a single control.** Four overlapping layers, because any one can be
circumvented: RLS policies; a tenant resolver returning NULL when unset so
missing context sees nothing rather than everything; `assert_same_org` triggers
rejecting cross-tenant foreign keys on write; and an immutable `organization_id`.

**Revisit if:** a tenant needs physical data isolation for regulatory reasons —
that is a database-per-tenant requirement and RLS cannot satisfy it.

---

## D3 — Pipeline stages are rows, not enum values

**Decided.** `pipelines` declares which entity it drives; `pipeline_stages`
carries order, probability, and a terminal classification.

**Over:** a hardcoded stage enum per entity type.

**Why:** an enum forces a migration every time a tenant renames a stage or runs
a second process alongside the first. Rows make the funnel tenant-configurable,
and the `entity_type` discriminator lets one engine drive leads, deals, and
service jobs. Independently converged on by frappe/crm, Krayin, and django-crm.

**Consequence:** reporting keys off `stage_kind` (open/won/lost), never stage
names, so renaming a stage cannot break forecasting.

---

## D4 — Sales and service share one engine

**Decided.** Deals and service jobs are separate tables sharing the pipeline,
stage-transition, activity, and audit machinery.

**Over:** a single polymorphic `work_item` table; two disconnected subsystems.

**Why:** the user's requirement is a CRM that covers acquiring customers *and*
delivering to them, generic enough that a mobility or field-service business
could adopt it. Separate tables keep queries typed and indexes tight; shared
machinery avoids implementing the board, the history, and the analytics twice.

**Consequence:** a mobility business maps on without schema change — a service
is a ride type, a job is a booking, `assigned_user_id` is the driver.

---

## D5 — Custom fields as validated JSONB

**Decided.** A JSONB `custom_fields` column plus a `custom_field_definitions`
table, with a trigger validating writes against those definitions.

**Over:** EAV (attribute + value tables); a typed side-table per data type.

**Why:** EAV turns every read into a pivot and costs a row per field per record.
A typed side-table still needs a join and a migration per new type. JSONB keeps
values on the row, Postgres indexes them with GIN, and the definitions table
supplies the typing JSONB lacks. Without that trigger this would be an untyped
junk drawer; with it, it is a tenant-defined schema.

**Revisit if:** a tenant needs range queries or sorts on a custom field hot
enough that GIN is insufficient. The escape hatch is promoting that field to a
real column for that tenant while JSONB remains the default.

---

## D6 — Activity timeline separate from audit log

**Decided.** Two tables. `activities` is the business timeline a human reads;
`audit_log` is field-level forensics.

**Over:** one combined event table; event sourcing.

**Why:** merged, the timeline fills with column diffs and the audit trail
becomes unqueryable — they need different shapes and answer different questions.

**`audit_log` has no UPDATE or DELETE policy.** A tamperable audit trail is not
an audit trail. Retention happens by detaching old partitions, never by row
deletes.

---

## D7 — Agent writes are attributable at the database level

**Decided.** `actor_type` distinguishes user / agent / system / integration, and
a CHECK constraint refuses an agent-attributed row that does not name the agent.

**Why:** `CLAUDE.md` §3 gates agent tool calls at the moment of the call. That
governs whether an action is attempted; it leaves no evidence afterwards. Making
attribution a database constraint means "which agent changed this deal, and
why" is answerable from the data, not from logs that may not have been kept.

**Consequence:** an agent must set `app.current_agent` before writing.
Attribution cannot be forgotten silently — a write claiming to be from an agent
without naming one is rejected.

---

## D8 — No columnar analytics store

**Decided.** Reporting from partitioned Postgres plus rollup tables. No
ClickHouse.

**Over:** the Postgres + ClickHouse split plausible uses.

**Why:** plausible's workload is immutable, joinless, high-cardinality event
data at a volume CRM activity does not approach. Yourider's reporting questions
are joins against pipelines, stages, users, and deals — what Postgres is good at
and a columnar store is not. "Millions of customers" is row count in `contacts`,
not event throughput.

**Revisit if:** a single tenant's activity partition passes ~10⁸ rows, or
dashboard p95 exceeds a second after honest index and rollup work.

---

## D9 — Money as `numeric`, surfaced to TypeScript as a string

**Decided.** All monetary columns are `numeric`. Derived totals are generated
columns. The TypeScript type is a branded string, not `number`.

**Why:** `numeric` is arbitrary precision, IEEE-754 doubles are not.
node-postgres returns numeric as a string precisely to avoid that loss, and
converting it to a number to make the types tidier reintroduces the exact error
the column type was chosen to prevent. Generated columns mean no two callers can
compute a different total.

---

## D10 — Build the automation layer, do not embed n8n

**Decided in principle, not yet built.** A narrow CRM-specific
trigger → condition → action layer, informed by n8n's data model.

**Why not n8n:** its Sustainable Use License permits internal use but forbids
offering it as part of a commercial product, and `.ee` files are excluded
entirely.

**What to borrow:** versioned definitions; run history split hot/cold;
recurrence separated from concrete runs; a deduplication key so a
twice-delivered webhook runs once; explicit error branches rather than
exceptions.

**The constraint that must be settled first:** a Network-class action has to
*suspend* the run pending approval — n8n's wait-state pattern — rather than
block a worker. The approval gate becomes an execution status. This is hard to
add to a synchronous executor afterwards, so it belongs in the first design.

---

## D11 — Consent must become a ledger before anything sends

**Decided.** The current opt-out booleans are insufficient and will be replaced
by channels, append-only consent records, and suppressions. Not yet built; see
`docs/research/open-gaps.md` §1.

**Why it is urgent:** the approval gate governs whether a send is *attempted*;
consent governs whether it is *lawful*. Only one of those currently has an
answer, and agents are expected to draft outbound. Retrofitting consent history
after sending has begun means the evidence for consent given earlier does not
exist.

**Scope boundary:** Yourider owns consent truth and suppression. It does not
build a campaign sender, SMTP pool, or bounce ingester — those belong to a
dedicated service, with delivery events mirrored back into `activities`.

---

## D12 — Partition security is applied at creation, not by convention

**Decided.** `app.ensure_month_partition()` secures every partition it touches.
Manual `CREATE TABLE ... PARTITION OF` is not an approved path.

**Why:** enabling RLS on a partitioned parent does not protect its children —
Postgres does not propagate `relrowsecurity`, and a partition is an ordinary
table addressable by name. This was a live hole between migrations `0009` and
`0010`: reading through `audit_log` was correctly isolated while a direct read
of a partition returned every tenant's rows.

**The general lesson, which is the reason this is written down:** the hole
existed because creating a partition and securing it were separate steps. A
control that must be remembered is not a control. `0010` refuses to commit if
any partition is unprotected, and the RLS suite asserts direct-access isolation
across every partition.

---

## D13 — Consent is a ledger with a gate, not a column

**Decided and built** (`0011_consent.sql`), superseding the placeholder in D11.

**Model:** addressable `contact_channels`; tenant-defined `consent_purposes`;
an append-only `consent_records` ledger carrying evidence and actor; a derived
`consent_state` cache; address-level `suppressions`; partitioned
`message_events`.

**Precedence, deliberately in this order:**

    suppression > legacy opt-out > transactional purpose > recorded consent

Suppression outranks even an explicit grant. A hard-bounced address does not
become deliverable because someone consented — continuing to write to it
degrades sending reputation for every other contact in the tenant, so one
person's consent cannot be allowed to damage everyone else's deliverability.

**Why a ledger rather than a state column:** the question asked in a dispute is
not "what is their consent" but "what was their consent on the day you sent
that, and what is your evidence". A mutable column cannot answer it. The state
table exists only so the send-time check is a primary-key lookup; it is a cache
over the ledger and rebuildable from it.

**Why the state cache guards on `effective_at`:** consent events arrive out of
order — a verbal consent logged three days late must not resurrect permission
withdrawn yesterday. Asserted by `consent_test.sql` §5.

**Suppressions carry no foreign key to contacts.** Two consequences, both
intended: an address can be suppressed before any contact exists for it, and
deleting a contact does not forget that they asked never to be contacted.

**Scope boundary:** Yourider owns consent truth and suppression. It does not
build a sender — no SMTP pool, no campaign runner, no bounce mailbox scanner.
Those belong to a dedicated service that mirrors delivery events back in.

**Non-destructive transition:** the old `email_opt_out` / `sms_opt_out` booleans
are retained and honoured by `can_send()` as a global withdrawal. Dropping them
is a separate change requiring explicit approval, per `CLAUDE.md` §3.

---

## D14 — Generic triggers read columns through jsonb

**Decided** (`0012_audit_without_soft_delete.sql`), after a bug.

`app.record_audit()` read `OLD.deleted_at` directly. plpgsql resolves that
against the actual row type at runtime, so attaching the trigger to any table
without that column raised `record "old" has no field "deleted_at"`. Every
audited table happened to have it until `suppressions`, which uses `released_at`
because a suppression is released rather than soft-deleted.

**Rule going forward:** a trigger attached to more than one table reads
optional columns as `to_jsonb(NEW) ->> 'col'`, which yields NULL for a missing
key instead of raising. Direct field access couples a generic trigger to one
table's shape.

**How it was found:** the consent suite exercised an UPDATE on `suppressions`.
It would not have been found by review — the trigger was correct for every table
that existed when it was written.
