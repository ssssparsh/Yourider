# Prior-art research

Catalogue of external repositories examined while designing Yourider, with the
licence of each and what was concluded. It exists because a Claude Code session
has no memory across restarts: anything learned in conversation and not written
here is gone when the session ends. This file is the memory.

46 repositories were read. Most produced nothing usable, which is itself worth
recording — it stops the same repo being re-examined next month.

## Licence policy

The licence determines what may be done with what was learned, and it is not
uniform across this list.

| Class | Repos | What is permitted |
| --- | --- | --- |
| **Permissive** (MIT, Apache-2.0, BSD) | most | Patterns adaptable; small verbatim excerpts fine with attribution |
| **Copyleft** (GPL-3.0, AGPL-3.0) | openhuman, frappe/crm, SuiteCRM, monica, erpnext, twenty, plausible, listmonk | **Concepts only.** Copying code would oblige Yourider to adopt the same licence |
| **Source-available** (BSL, Elastic, Sustainable Use) | caveman engine, context-mode, n8n | **Concepts only.** Usage restrictions bar embedding in a commercial product |
| **No licence** | andrej-karpathy-skills, DaybydayCRM | **Read-only.** All rights reserved by default; nothing may be reused |

Nothing in Yourider is copied from a copyleft, source-available, or unlicensed
repository. Where such a repo informed a decision, the decision was
reimplemented from the idea, and this file names the source so the provenance is
auditable.

## What actually changed the product

Four findings account for nearly all the value; the rest is catalogued below for
completeness.

1. **Pipelines as rows, not enums** — converged on independently by frappe/crm,
   Krayin, and django-crm. Became the core of `0004_pipelines.sql` and the
   reason one engine drives both sales and service.
2. **Defence-in-depth multi-tenancy** — django-crm (MIT) pairs an application
   filter with Postgres RLS rather than trusting either alone. Yourider extends
   this to four layers.
3. **Consent is a ledger, not a flag** — listmonk (AGPL, concepts only) showed
   that two opt-out booleans cannot express purpose-scoped consent, opt-in
   confirmation state, or suppression. See `docs/research/open-gaps.md`.
4. **Analytics does not need a columnar store yet** — plausible splits Postgres
   and ClickHouse, but its workload is orders of magnitude larger and joinless.
   Partitioned Postgres plus rollup tables is the right call at Yourider's
   shape. Recorded in `DECISIONS.md`.

## Catalogue

### CRM and ERP applications

| Repo | Licence | Verdict |
| --- | --- | --- |
| `trycompai/crm` | MIT | Typed `FieldDefinition`/`FieldValue` custom fields; single global pipeline enum. Simplest of the three. |
| `krayin/laravel-crm` | MIT | Best pipeline model: pipeline + stage + join table carrying probability and order. Directly informed `0004`. |
| `Django-CRM` | MIT | `BaseOrgModel` + org-scoped manager + Postgres RLS. Directly informed the tenancy design. |
| `twentyhq/twenty` | AGPL-3.0 | Schema-per-workspace with runtime DDL. Rejected for Yourider's tenant count, but its object model exposed real gaps — see open-gaps.md. |
| `frappe/crm` | AGPL-3.0 | Stage-as-record with colour/probability/terminal type. Confirmed the `0004` design. |
| `SuiteCRM` | AGPL-3.0 | Metadata-driven modules; `AOW_WorkFlow` is the clearest rules-engine reference found. |
| `monicahq/monica` | AGPL-3.0 | Personal-relationship CRM. Different shape entirely (vaults, life events, gifts) — a legitimate alternative reading of "CRM" that was consciously not taken. |
| `frappe/erpnext` | GPL-3.0 | CRM as the front of a quote-to-cash chain. Useful for understanding where a CRM ends. |
| `Bottelet/DaybydayCRM` | **none** | One polymorphic `Status` model shared across entities. Idea only; nothing reusable. |

### Backend platform and infrastructure

| Repo | Licence | Verdict |
| --- | --- | --- |
| `supabase/supabase` | Apache-2.0 | **Adopted as the intended platform.** Self-hosted: Postgres + GoTrue + PostgREST + Realtime, with RLS as the authorisation mechanism. See `DECISIONS.md`. |
| `plausible/analytics` | AGPL-3.0 | Postgres/ClickHouse split examined and deliberately *not* copied. Rollup-table patterns adopted. |
| `knadh/listmonk` | AGPL-3.0 | Consent, suppression, and bounce model. Drove the largest known gap in Yourider's schema. |
| `n8n-io/n8n` | Sustainable Use | Workflow-as-DAG, hot/cold execution split, wait-state resumption. Licence forbids embedding; build a narrower layer instead. |

### Agent frameworks and orchestration

| Repo | Licence | Verdict |
| --- | --- | --- |
| `crewAIInc/crewAI` | MIT | Manager-agent-delegates-via-tool-call became Yourider's handoff pattern. Python-only, so reimplemented rather than depended on. |
| `msitarzewski/agency-agents` | MIT | Persona file format (frontmatter + deliverable templates). Informed `/src/agents`. |
| `affaan-m/ECC` | MIT | Directory-as-registry, shared security preamble, gated pipelines. All three adopted. |
| `tinyhumansai/openhuman` | GPL-3.0 | Command-classified approval gate with autonomy tiers — the direct inspiration for `CLAUDE.md` §3, reimplemented from the concept. |
| `PrimeIntellect-ai/prime-agent` | MIT | TypeScript-native but ships **no** default approval gate and self-modifies under LLM judgement. Kept as a counter-example. |
| `ruvnet/ruflo` | MIT | Coordination ledger around a single CLI, not real parallel agents. Weaker safety story than Yourider's. Rejected. |
| `semantica-agi/semantica` | MIT | Real W3C PROV-O provenance export. Candidate sidecar for regulator-grade audit export. Still open. |

### Developer tooling (this workflow, not the product)

| Repo | Licence | Verdict |
| --- | --- | --- |
| `rtk-ai/rtk` | Apache-2.0 | **Installed.** Filters noisy shell output before it reaches the agent. |
| `tirth8205/code-review-graph` | MIT | **Installed.** Tree-sitter graph + MCP server; measurably cuts review context. |
| `headroomlabs-ai/headroom` | Apache-2.0 | Real compression, heavy stack. Deferred until tool-output volume justifies it. |
| `thedotmack/claude-mem` | Apache-2.0 | Genuine cross-session memory via hooks + SQLite/Chroma. Not viable in an ephemeral container; revisit for local use. |
| `DeusData/codebase-memory-mcp` | MIT | Structural code memory as a graph. Overlaps code-review-graph. |
| `mksglu/context-mode` | Elastic 2.0 | Overlaps rtk at the same interception point. Its session-continuity layer is the novel part. |
| `JuliusBrussee/caveman` | MIT + BSL-1.1 | Engine is BSL. Benchmark honestly labelled but not independently reproducible. Deferred. |
| `diegosouzapw/OmniRoute` | MIT | Routes to non-Anthropic providers; its "RTK" branding is a reimplementation, not integration. Not applicable. |
| `Yeachan-Heo/oh-my-claudecode` | MIT | 19 task-specialised dev agents, model routing. Workflow tooling, unevaluated. |
| `microsoft/playwright-cli` | Apache-2.0 | Agent-shaped browser driving. Worth adopting once there is UI to verify. |

### Design and quality

| Repo | Licence | Verdict |
| --- | --- | --- |
| `pbakaus/impeccable` | Apache-2.0 | `PRODUCT.md`/`DESIGN.md` pattern and hook-enforced anti-pattern detection. The former was adopted. |
| `Leonxlnx/taste-skill` | MIT | Opinionated frontend rules. Reference only. |
| `emilkowalski/skills` | MIT | Motion: easing curves, duration scale, reduced-motion policy. Adopted into `DESIGN.md`. |
| `obra/superpowers` | MIT | Verification-before-completion and the 3-failed-fixes escalation rule. Both adopted into `CLAUDE.md` §3. |
| `garrytan/gstack` | MIT | The three working principles in `CLAUDE.md` §2, and the pre-code planning gate. |
| `alirezarezvani/claude-skills` | MIT | `deal-desk` and `customer-success-manager` scoring patterns — deterministic scorer plus named-approver routing, never auto-approve. |
| `multica-ai/andrej-karpathy-skills` | **none** | Engineering-discipline guidance overlapping `CLAUDE.md` §2. Nothing reused. |

### Security

| Repo | Licence | Verdict |
| --- | --- | --- |
| `NVIDIA/garak` | Apache-2.0 | LLM adversarial probes. Gated in `CLAUDE.md` §11 until an agent endpoint exists. |
| `usestrix/strix` | Apache-2.0 | Autonomous app pentesting. Complements garak at a different layer; needs a running app and metered LLM spend. |
| `zhaoxuya520/reverse-skill` | MIT | `api-security`, `database-security`, `supply-chain-security` are relevant defensively. The rest is offensive tooling, not applicable. |
| `Z4nzu/hackingtool` | MIT | Useful only as a map of attack-surface categories to defend. |
| `Hack-with-Github/Awesome-Hacking` | CC0 | Two relevant sub-lists: Node.js security, prompt injection. |

### Examined, not applicable

`google/skills` (Apache-2.0, GCP-specific), `avelino/awesome-go` (MIT, wrong
language), `awesome-selfhosted` (CC-BY-SA-3.0 — surfaced Corteza, EspoCRM,
Twenty, Dolibarr as further CRM prior art),
`SimoneAvogadro/android-reverse-engineering-skill` (Apache-2.0, mobile APK
analysis).

## Method

Each repo was cloned shallowly, its licence read first, then its actual source
inspected — not just its README, which routinely oversells. Where a claim was
checkable it was checked: caveman's benchmark says outright it is not
independently reproducible, and OmniRoute's own credits admit its "RTK"
compression is a reimplementation rather than the tool it names.
