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

---

## D15 — Files are content-addressed blobs; attachments are links to them

**Decided and built** (`0013_attachments.sql`).

**Two tables.** `files` is a stored blob, `attachments` is a link from a blob to
a record. One contract serves a deal, an account and a service job without three
copies of the bytes.

**Over:** a single polymorphic `attachments` table carrying the storage details
inline. That shape re-uploads identical content and cannot answer "where else
does this document appear" — the first question asked when a document turns out
to be wrong.

**Bytes live in object storage.** A `bytea` column puts file content into WAL,
into every base backup, and onto every replica. Postgres holds the metadata and
the authorisation decision; the object store holds the bytes.

**Storage keys are generated columns**, derived as
`organization_id || '/' || id`. A client-chosen key is a tenant-isolation hole
that no policy on this table can close, because the breach happens in the object
store rather than in Postgres. Deriving the key from the row makes it
unrepresentable rather than merely forbidden — the same move as making
`organization_id` immutable (D2) instead of trusting callers not to change it.

**Deduplication is scoped to the tenant**, not global. Sharing blobs across
tenants would halve storage for common documents and is a side channel: an
instant upload tells tenant A that tenant B holds that exact content. Storage is
cheaper than that inference.

**Upload is a two-phase state machine.** The row exists before the bytes,
because the storage key must be known to issue a presigned URL. The alternatives
are trusting the client's report that the upload finished, or writing the row
afterwards and having no way to find objects whose row write failed.

**The download gate fails closed.** An unscanned file is refused. `skipped`
exists so a trusted internal path states that explicitly instead of reaching the
same outcome by omission. A checksum that ever came back infected is refused on
re-upload: content is the identity, so renaming a blocked file changes nothing.

**Attachment targets are validated, activity targets are not.** Both are
polymorphic `(entity_type, entity_id)` pairs with no FK. Attachments pay an
index lookup per write because they are low-volume, long-lived, and a dangling
one surfaces when someone opens a deal that no longer exists to find the
contract. `activities` would pay that lookup on every interaction ever recorded,
which is the wrong trade at that volume. The asymmetry is deliberate, not an
oversight in one of the two.

**The reference counter is recomputed, not incremented.** An increment/decrement
pair must be correct for insert, hard delete, soft delete, restore, and a
re-pointed `file_id`; one missed path either deletes bytes still in use or leaks
them forever. A recomputed count over an indexed lookup cannot drift.

**The sweeper reports, it never deletes.** `app.sweepable_files()` is read-only.
Deleting bytes is a Destructive-class action under `CLAUDE.md` §3, and a
function that could do it from inside a query is a function that will eventually
be called by something that did not mean it.

**Revisit if:** attachment volume per blob grows enough that recomputing the
count on every attach becomes hot — the fix is an incremental counter behind the
same trigger, with a periodic reconciliation job, not a hand-maintained one.

---

## D16 — Audit triggers may be column-scoped

**Decided** (`0013_attachments.sql`), as a general convention.

`files` carries `attachment_count`, maintained by trigger. Auditing it with the
standard `app.attach_audit()` would write an audit row every time a document was
attached or detached, recording that a derived number moved — noise that buries
the signal (a scan verdict, a deletion, a renamed file).

The trigger is therefore declared with an explicit column list:

    AFTER INSERT OR UPDATE OF upload_state, scan_status, deleted_at, ... OR DELETE

**Rule going forward:** a table with a trigger-maintained derived column gets a
column-scoped audit trigger naming the columns that carry intent. `attach_audit`
remains the default for tables without one.

**What this is not:** a licence to exclude columns because they are noisy in
general. The test is whether a human wrote the value. Derived bookkeeping is
excluded; a field someone edited is never excluded.

---

## D17 — One catalogue with a cost basis, priced by books

**Decided and built** (`0014_pricing.sql`).

**Cost added to `services`, not a new `products` table.** A second catalogue
makes "what did we sell" a UNION across two tables that drift apart, and every
report has to remember both. `services` was already the thing a tenant sells; it
was missing the cost side.

**Price books over price columns.** The same item sells at different prices per
currency, per segment, and per volume tier. Each of those as a column on
`services` is a migration per pricing dimension. Tiers are declared by their
floor and the highest applicable wins, so no range can be left with a gap.

**Effective dating rather than overwriting.** A superseded price stays, with an
end date. A quote issued last week has to remain explicable, and a price
overwritten in place cannot be.

**An unusable book named explicitly raises rather than falling back.** Silent
fallback prices the deal from the catalogue while the caller believes a
negotiated book is in effect — a wrong number nobody has a reason to question.

**NULL cost means unknown, not zero.** `deal_totals()` reports `cost_known` and
returns NULL margin rather than the margin of only the lines carrying a cost.
That figure would always be wrong in the flattering direction, which is the
worst kind of wrong for a number people make decisions on.

**Revisit if:** a tenant needs per-account contract pricing rather than
per-segment books — the shape is an `account_id` on `price_books`, and the
resolver gains one more precedence step.

---

## D18 — Deal amount is derived once a deal is itemised

**Decided and built** (`0014_pricing.sql`).

`deals.amount` is maintained by trigger from the line items, in the same
transaction as the line change. A hand edit to an itemised deal is **refused**,
not silently overwritten.

**Why derived at all:** two numbers that can disagree means the one a report
happens to read decides whether the quarter made target.

**Why refused rather than overwritten:** the rollup would overwrite the edit on
the next line change regardless. A number that quietly reverts is worse than one
that is rejected, because the person who typed it never learns it did not take.

**Why not fully generated:** a deal with no line items keeps the manual `amount`
it has always had. Making the column generated would have been a destructive
change to existing rows and would have removed a workflow — an early-stage deal
with an estimated value and nothing itemised yet — that is legitimate.

**Accepted cost:** `deals.amount` is manual or derived depending on state, which
is a mode. The mode is discoverable (does the deal have line items) and the
error message says which one you are in, but it is a mode nonetheless.

**Revisit if:** the manual path stops being used in practice. Then the column
becomes derived unconditionally and the mode disappears.

---

## D19 — Approval is an execution status, not a blocking wait

**Decided and built** (`0015_automation.sql`), settling the constraint D10 said
had to be settled before the table shape was fixed.

When a step needs approval, the run's status becomes `waiting_approval` and the
worker's **lease is released**. A decision re-queues the run for whichever
worker picks it up next.

**Over:** the obvious design — an executor that walks the action list and waits
for a decision when it reaches one that needs approval.

**Why:** a blocking wait holds a worker for as long as a person takes to answer.
Minutes, or a weekend. A hundred pending approvals is a hundred stalled workers,
and the failure is invisible until the queue stops moving.

**What this forced:** the whole engine is a durable state machine — steps as
rows, leases, per-step retry — rather than a function. That is a large cost paid
up front for one requirement, and it is the right time to pay it: retrofitting
suspension into a synchronous executor means rewriting it.

**The database executes nothing.** It owns the state machine, the authorisation
decision and the trail; a worker outside does the effects. An executor inside
would hold a transaction open across every outbound network call.

**Revisit if:** approvals become rare enough that suspension is never exercised
in practice — but the cheap-looking version is only cheap until the first
weekend-long approval.

---

## D20 — An approval authorises one step, including its retries

**Decided** (`0015_automation.sql`), after a bug the tests caught.

`app.begin_step()` originally re-evaluated the gate every time it was called.
After a human approved a Network action, the run was re-queued, the gate saw the
same class at the same tier, and asked again — a run that could never pass its
first Network action however many times someone said yes.

`begin_step` now treats an existing approved request for that step as
authorisation to proceed.

**Scope of the grant, stated deliberately:** one step, for its retries, and not
beyond. It does not carry to later steps — those re-enter the gate. Retrying a
send that timed out is the same action a person already approved, and
re-prompting on every attempt trains people to approve reflexively, which is a
worse security outcome than the extra prompt is worth.

**What this pushes elsewhere:** whether a retry is *safe* to repeat is an
idempotency question for the worker making the call, not an authorisation
question for the gate. The gate answers "may this happen"; it cannot answer
"did it already partly happen".

**How it was found:** an end-to-end test that approved a request and then asked
for the next step. Neither a unit test of `gate_verdict` nor review would have
caught it — every individual piece was correct, and the bug was in the loop
between them.

---

## D21 — Silence is a distinct outcome from refusal

**Decided and built** (`0015_automation.sql`).

`approval_decision` has both `rejected` and `expired`. An unanswered request
expires, and its run fails — the action does not happen, which is `CLAUDE.md`
§3's rule that silence is never consent.

**Why two values rather than one:** both mean the action did not happen, so a
single "denied" would be enough to make the engine behave correctly. They are
kept apart because they answer "why did this not go out" differently. A
rejection is the system working. A queue of expiries is a broken process —
nobody is watching the approvals — and collapsing them hides exactly the signal
worth acting on.

**Consequently:** an expired request carries no `decided_by`, enforced by CHECK.
Nobody decided it. And a request past its deadline cannot be decided afterwards,
which is the "stale prompt" case §3 names.

---

## D22 — An unattended run fails loudly rather than degrading

**Decided and built** (`0015_automation.sql`).

An automation flagged `is_unattended` that reaches an action needing approval
fails with `approval_required_unattended` and records which step and why.

**Over:** the two tempting alternatives, both of which `CLAUDE.md` §3 rules out
by name — skipping the action and carrying on, or proceeding without approval
because no one is there to ask.

**Why loudly:** a skipped action produces a run that reports success while
having done less than it claims, and the gap is discovered when someone notices
the emails were never sent. Proceeding is worse: it makes the unattended flag a
way to escape the gate rather than a constraint on it.

**Steps that already succeeded stay succeeded.** Failing the run does not
rewrite completed work as though it never happened — the record has to show what
actually ran before the stop.

---

## D23 — Teams are rows with a trigger-guarded hierarchy

**Decided and built** (`0016_teams.sql`).

`memberships.team` was free text since D2's foundation. A typo silently
created a new team, and "see everything my team owns" — `membership_role`'s
own comment for the `manager` role since 0002 — had no table to query.

**Retained, not replaced.** `memberships.team` stays; `team_id` is additive,
the same non-destructive transition D13 used for the consent opt-out booleans.

**A real cycle guard, unlike `accounts.parent_id`.** 0003 explicitly defers
deeper hierarchy cycles to "application code" — a CHECK cannot express
reachability, and accounts number in the millions. Teams are dozens of rows,
walked recursively by `app.visible_team_ids()` on every use, so a cycle there
is not a data-quality issue, it is an infinite loop in a query someone runs in
production. The volume difference is why one gets a trigger and the other does
not — not an inconsistency.

**`app.visible_team_ids()` is a read-only helper, not an RLS policy.** It
answers "which teams can this role reach", which a future stricter policy (see
D24) would consult. It does not itself restrict anything — every table's
existing SELECT policy under D2 is unchanged.

---

## D24 — Row- and field-level permissions are groundwork, not enforcement

**Decided and built** (`0018_field_row_permissions.sql`), deliberately partial.

**What is real:** `field_permissions` + `app.redact_fields()` strips hidden
keys from a `custom_fields` blob before the application returns it.
`record_shares` records that a specific record was made visible to a specific
user or team beyond the standing policy, with full validation (one target,
must exist, must be same-tenant) and an audit trail.

**What is deliberately not done:** wiring `record_shares` into the SELECT
policies of `accounts`/`contacts`/`leads`/`deals`/`service_jobs`. Today's RLS
is tenant-only by design (D2) — every member reads every record. Narrowing
that to "unless a share says otherwise" is a behavioural change to every
existing tenant's visibility, on tables the functional and RLS suites already
assert full-tenant read against. That is a product decision — does this CRM
even want per-record restriction as a default posture, or only as an opt-in —
and a migration should not make it as a side effect of adding a table.

**Why field redaction has no such gate:** it is called explicitly by the
application at read time; it cannot silently change what SELECT already
returns, because the database was never asked to enforce it. `record_shares`
is different — the moment it is consulted by a policy, it changes existing
behaviour for data that already exists.

**Column-level security was considered and rejected.** Postgres's real
mechanism (`REVOKE SELECT (column) FROM role`) needs a distinct database role
per application role, which does not fit one pooled multi-tenant connection —
the caller's role is a session variable, not the connecting Postgres role.

**Revisit if:** a tenant needs restricted-by-default visibility. The shape is
already there — `app.visible_team_ids()` (D23) plus `record_shares` — what is
missing is the policy that actually reads them, which should be opt-in per
organization rather than a global behaviour change.

---

## D25 — API key secrets are hashed with SHA-256, not a password hash

**Decided and built** (`0019_platform.sql`).

`api_keys.key_hash` stores `digest(secret, 'sha256')`, not bcrypt or argon2.

**Why not a slow password hash:** those exist to survive an offline
brute-force against low-entropy human-chosen secrets. An API key is
32 cryptographically random bytes generated by `gen_random_bytes()` — the
threat is a stolen database dump being read directly, which a fast hash
already defeats as effectively as a slow one, at a fraction of the CPU cost on
every authenticated request. Applying password-hash reasoning to a
high-entropy machine-generated secret is solving a problem the secret does not
have.

**The secret is returned exactly once**, by `app.issue_api_key()`, and there is
no function that can retrieve it again — `authenticate_api_key()` only ever
compares a hash. This is enforced by the absence of a getter, not by a
convention someone has to remember not to violate.

---

## D26 — Merges repoint live relationships; history keeps the old id

**Decided and built** (`app.merge_contacts()` / `app.merge_accounts()`,
`0019_platform.sql`).

A merge repoints `deals`, `deal_contacts`, `service_jobs`, `contact_channels`,
`attachments`, and `tasks` to the survivor, then soft-deletes the loser.
`activities` and `audit_log` are **not** rewritten — the same choice 0011 made
for the consent ledger: a timeline entry that said "call with Dana" stays a
call with the contact Dana was at the time, and rewriting it fabricates
history that never happened under the survivor's identity.

**`entity_merges` is what makes this non-lossy anyway.** It records
`survivor_id`, `merged_id`, and a full snapshot of the losing row, so "what was
this id before the merge" is answerable in either direction — the fact the
timeline still needs both ids is a documented, queryable property, not a gap.

**Scoped to contacts and accounts.** A fully generic "merge any `crm_entity`"
would mean discovering every FK into every table dynamically at execution
time — plausible, but a much larger and riskier piece of dynamic SQL than two
known, reviewable functions, written for entities nothing in this CRM actually
merges in practice.

---

## D27 — Timeline entries cache a display label; activities still skip FK validation

**Decided and built** (`activities.entity_label`, `0019_platform.sql`).

A timeline entry resolves only while the record it points at still exists.
Caching the name at write time — the same move `deal_line_items` makes for
price (D15) — means "call with Dana Kohli" stays legible after Dana is
deleted, making deletion non-destructive to history.

**Still no FK validation on `activities.entity_id`,** unlike attachments'
`app.assert_entity_in_org()` (D15). That asymmetry was decided once already
for volume reasons — `activities` is partitioned and high-volume, and would
pay an index lookup on every interaction ever recorded — and adding a
best-effort cached label does not change that trade-off. `entity_display_name`
degrades to `NULL` rather than raising for exactly this reason: a lookup that
can fail must not become a write that can fail.

---

## D28 — Messaging identity is schema without a sync worker

**Decided and built** (`0020_messaging_identity.sql`), the same boundary as
D19 drew around the automation worker.

`connected_accounts`, `message_threads`, `messages`, `message_participants`,
and `calendar_events` give a mailbox/calendar sync somewhere to write. Nothing
here calls Gmail or Microsoft Graph — that needs OAuth and a live API
connection this environment does not have, and is one of the four items on the
API-requirements list handed back to the user alongside this migration.

**Why build the identity model before the sync exists:** the gap this closes
(`open-gaps.md` §5) was explicit that adding it *after* activity data already
exists means backfilling identity that was never captured. `messages` needs
`provider_message_id` from day one to deduplicate a message seen twice;
retrofitting that onto years of `activities.kind = 'email'` rows with no
provider id would mean the dedup key never existed for anything already synced.

**`credential_ref` is a pointer, not a token.** An OAuth token has the same
blast radius as a password and does not belong in a plain column even inside
this database, the same "no secrets in code or prompts" rule CLAUDE.md §3
already states for prompts and commits. The real token lives in a secrets
manager; a worker resolves it from this reference at call time.

