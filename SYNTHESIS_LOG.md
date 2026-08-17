# Synthesis Log

Running record of every repository intake decision made under `CHARTER.md` §9. One entry per repository. Nothing here grants any agent extra permissions — see `CHARTER.md` §2.

Entry format:

```
## <repo name/URL> — reviewed <date>

**What it does:** <one line>

**Kept:** <feature> — why it's a positive contribution
**Reshaped:** <feature> — what was good, what was risky, how it was redesigned around the risk
**Rejected:** <feature> — why, and what (if anything) replaces it
```

---

## https://github.com/anthropics/financial-services — reviewed 2026-08-16

**What it does:** Anthropic's official reference templates for deploying Claude agents in regulated financial-services workflows (KYC, GL reconciliation, pitch decks, fund admin, etc.) — 10 named agents, each shipped both as an interactive Cowork plugin and a headless "Managed Agent" cookbook, built on a single source-of-truth system prompt per agent.

**Kept — Reader/Orchestrator/Writer tool tiering.** Every agent that touches untrusted input (customer documents, onboarding forms, statements) is split into three strictly scoped tiers: a **Reader** with only `Read`/`Grep` (no Write, no Bash, no MCP — so a prompt-injection payload hidden in a hostile document has nothing to reach), an **Orchestrator** with read-only connectors, and a single **Writer** that never opens the untrusted document itself, only consuming already-validated structured JSON from the Reader. This is the concrete mechanism our Charter §1–§2 was describing in the abstract — direct fit for how CRM agents should handle inbound customer emails, uploaded files, and web-form submissions. **Adopt as the default shape for every CRM worker-agent that touches customer-supplied content.**

**Kept — deny-by-default tool config.** Tools are declared `enabled: false` by default, then explicitly turned on one at a time. Matches Charter §2 ("every agent starts with zero access") exactly — adopt as the literal implementation pattern for our agent manifests.

**Kept — human-in-the-loop is structural, not a note.** No agent in the repo posts to a ledger, approves onboarding, or sends anything client-facing directly — every output lands in a staged file/queue for a named human role to sign off. This is our Charter §3 (hard-gated actions) in working form — adopt the "staged output, human approves" mechanism for CRM actions like sending customer emails, updating deal/contract status, or merging duplicate records.

**Kept — RBAC/JWT access-policy pattern.** Their Office-add-in bootstrap does deny-wins-over-allow, fails closed on an unreadable/unlabeled resource, and flips a scope to default-deny the moment any allow rule exists for it. Directly reusable for "which rep or agent can see which customer record/field" in the CRM, especially for PII-sensitive fields (Charter §6).

**Reshaped — cross-agent handoffs.** Their `orchestrate.py` extracts a `handoff_request` JSON blob by parsing an agent's streamed text, then allowlists the target agent and schema-validates the payload before acting on it — and their own docstring flags this as fragile: a hostile document could get echoed back and spoof a handoff if the allowlist/schema check were ever skipped. We keep the *validated, allowlisted handoff* concept (it's a good fit for CRM automation chains, e.g. "deal marked won" triggering onboarding) but implement the handoff as a typed structured event/tool call rather than parsing free text, per the repo's own recommendation — removes the injection-spoofing surface instead of just mitigating it.

**Rejected — no real audit-log subsystem.** The repo has no system-wide audit trail; the closest thing is a domain-specific "follow the GL break back to its source entry" trace, which only helps for accounting reconciliation, not general accountability. Our Charter §7 requires every agent action to be logged and traceable — we build this ourselves as a first-class piece of infrastructure rather than copying anything from here.

**Rejected — literal config values not meant to travel.** Their CORS allowlist is hardcoded to `https://pivot.claude.ai` and their JWT/RBAC bootstrap is wired to Microsoft Entra specifically. The *pattern* (origin allowlisting, verified-claims-only JWT checks) is kept per above; the specific values and Entra-specific plumbing are not — they get re-scoped to our own domains and our own identity provider when we build it.

**Noted, not adopted:** their multi-agent delegation is capped at one level because it's a stated research-preview limit of Anthropic's Managed Agent API, not a design choice — we shouldn't assume that ceiling applies to our own manager→worker hierarchy if we're not deploying through that same API.

---

## https://github.com/NVIDIA/garak — reviewed 2026-08-16

**What it does:** NVIDIA's open-source LLM red-teaming/vulnerability scanner — a CLI that fires adversarial "probes" (jailbreaks, prompt injection, data/PII leakage, SQL/code injection via tools, etc.) at a target model or system, classifies failures with "detectors," and emits a structured, statistically-scored report. Apache-2.0, actively maintained. Unlike `financial-services`, this is not application code to borrow patterns from — it's a **tool to point at our own CRM agents**, so the intake decision is about how it enters our security practice, not our codebase.

**Kept — adopt as an external red-team tool in the release pipeline, never as a runtime dependency.** Garak stays outside the CRM's dependency tree entirely; it's something we *run against* the shipped agents (fits alongside gstack's `/cso` and `/qa` skills already in our workflow — see the gstack notes above), not something bundled into the product. This keeps Charter §2 (least privilege / minimal footprint) intact — a security scanner has no business holding runtime access to customer data.

**Kept — `agent_breaker` probe via the `generators.function` wrapper.** This is the one part of garak purpose-built for tool-using agents: it wraps our *actual* agent invocation code (full tool loop — "look up customer," "send email," "update deal stage" — not just the raw Claude call) and red-teams for excessive agency and insecure plugin design. This is the closest thing available to testing the real attack surface our worker-agents will have, and maps directly onto Charter §1's "a worker never receives more access than its task requires" — garak becomes the way we *verify* that claim instead of just asserting it.

**Kept — `latentinjection`, `exploitation`, `sysprompt_extraction`, `leakreplay`/`propile` probes.** Directly relevant to a CRM: injected instructions hidden in customer-supplied records/documents (matches the untrusted-document threat model from `financial-services`, above), SQL/code injection through DB-touching tools, protection of business logic in system prompts, and cross-tenant/PII leakage — the last one is critical given Charter §6's data-protection commitments in a system built to hold real customer data.

**Kept — report format as an audit-trail input.** The JSONL report (with bootstrap confidence intervals on attack-success rate) and AVID-schema export are consumable enough to feed into the audit-log infrastructure we already committed to building ourselves after the `financial-services` review (§7) — scan results become one more class of logged, traceable event rather than a one-off PDF nobody revisits.

**Reshaped — no CI/CD gate exists out of the box.** Garak ships the building blocks (`aggregate_reports.py`, bootstrap/CI-interval tooling, the probe Tier triage system) but not a packaged "fail the build" gate. We wrap it ourselves: a threshold check against the JSONL/AVID output, wired into our own ship pipeline, using the Tier system to decide what's release-blocking ("Tier 1 — of concern") versus informational.

**Reshaped — scan cadence, not every-commit.** `agent_breaker` is disabled by default and depends on configuring a separate red-team model, which adds real cost and latency. We don't run it on every commit — it runs on a periodic/pre-release cadence (same rhythm as a `/cso`-style security review), while cheaper deterministic probes (injection, leakage, exploitation) can run more frequently.

**Rejected — Context-Aware Scanning (CAS).** The maintainers themselves flag it as experimental and incomplete as of mid-2026. We don't build on it yet. Instead, our own Charter (§3, §6) already defines what "acceptable agent behavior" means for this system — that's our policy specification. We revisit CAS as an enforcement mechanism for that policy once it matures, rather than adopting an unfinished subsystem now.

---

## https://github.com/crewAIInc/crewAI — reviewed 2026-08-16

**What it does:** A mature, MIT-licensed, widely-used Python multi-agent orchestration framework. Two composable paradigms: **Crews** (autonomous role-playing agent teams — Agent/Task/Process) and **Flow** (deterministic, event-driven pipelines with typed state that can embed Crews as steps). Unlike the previous two reviews, this is a real candidate for the **orchestration substrate our CEO/manager/worker hierarchy runs on**, not just a source of patterns to copy — so this entry also records a build-vs-adopt decision, not only feature intake.

**Kept — Flow as the deterministic outer shell, Crew as the bounded-autonomy unit.** Map our CEO-agent and each manager's workstream onto separate `Crew` instances, orchestrated by a `Flow` that enforces the actual chain of command and hosts approval gates. This is a working implementation of Charter §1's hierarchy — critically, **never put the CEO-agent, managers, and workers in one shared `Crew`** (see Reshaped, below, for why).

**Kept — `Task.tools` narrowing and action-scoped `apps` grants.** Agent-level tool lists, further narrowed per task, plus action-level scoping strings (e.g. `"gmail/send_email"` rather than whole-app access) are a concrete implementation of Charter §2's least-privilege default — adopt this as the actual mechanism for scoping each worker-agent's toolbox.

**Kept — `PRE_TOOL_CALL` hook with `HookAborted`.** This is the real code-level enforcement point for Charter §3's hard-gated actions list: a hook that inspects an about-to-happen tool call and can block it outright, in-process, before execution — not just an instruction the agent is supposed to remember. This becomes our policy-engine attachment point.

**Kept — `@human_feedback` + async `HumanFeedbackProvider` + `HumanFeedbackPending` + `@persist`.** A Flow step can suspend pending human approval, resume on an external event (e.g. a Slack/CRM-ticket approval), and survive a process restart via checkpointing. This is the closest off-the-shelf match for "nothing gated happens without Sparsh," and pairs with the `PRE_TOOL_CALL` hook as the durable half of that gate.

**Kept — `MemoryScope`/`MemorySlice`.** A built-in way to sandbox what each tier can read and write in shared memory (e.g. a billing worker gets a scope rooted at `/crm/billing` it cannot escape). This gives our "memory is a document, not an agent" principle (established before any repos were reviewed) a structured, access-controlled storage mechanism instead of a flat file.

**Kept — structured `output_pydantic`/`response_model` on tasks.** Forces a worker to emit a typed, schema-validated payload (e.g. an `UpdateDealRequest` object) instead of free text. This makes both guardrails and the human-approval gate tractable — reviewing a typed payload before it executes is far safer than reviewing prose.

**Kept — event bus + OpenTelemetry spans, including `HookDispatchedEvent`.** Every lifecycle point (task start/complete, tool calls, guardrail results, and — importantly — every hook abort) fires a typed event. This is the instrumentation layer for the audit trail Charter §7 requires and that we already committed to building ourselves (see `financial-services`, above) — we subscribe our own listener and persist these events rather than relying on crewAI's default (anonymous, vendor-bound) telemetry.

**Reshaped — delegation is flat and open-by-default within a crew.** `allow_delegation` lets an agent address *any other agent in the same crew* by free-text role-name match — there's no "manager A may delegate only to worker B" concept, and crewAI's own `SecurityConfig` module is an acknowledged stub (its docstring literally lists "Scoping rules: TODO"). We close this gap structurally: **each hierarchy tier lives in its own `Crew`**, so a worker's `Crew.agents` list simply cannot contain the CEO-agent or another domain's workers — plus a custom `PRE_TOOL_CALL` hook that validates the delegation target against an explicit allow-list before `DelegateWorkTool` is allowed to run. This is the direct fix for the "lateral or upward delegation" risk Charter §1 was written to prevent.

**Reshaped — human-in-the-loop as shipped is post-hoc, not pre-action.** `Task.human_input` reviews an agent's output *after* it already ran its full loop — useful for quality review, but not sufficient for Charter §3's "stop before an irreversible action happens." We use the `PRE_TOOL_CALL` hook as the primary gate for anything on the hard-gated-actions list, and reserve `@human_feedback`/`Task.human_input` for softer QA-style review where the action isn't irreversible.

**Reshaped — hooks fail open on unexpected errors.** crewAI's dispatcher swallows generic exceptions from a hook (only an explicitly-raised `HookAborted` reliably blocks a call), to keep a buggy hook from crashing the framework. That default is backwards for a safety gate. Our own policy hook wraps its logic in its own try/except that raises `HookAborted` on *any* internal error — fail closed, not fail open, regardless of what crewAI does by default.

**Reshaped — default anonymous telemetry.** `share_crew` sends usage data to crewAI by default. Per Charter §6 ("no customer data leaves the system without sign-off"), we turn this off explicitly and route all telemetry through our own OTel collector instead of trusting a vendor's claim that no PII is included.

**Rejected — relying on `SecurityConfig` for authorization.** It's identity-only (a stable fingerprint per agent/task/crew) — the framework's own comments mark authentication, scoping, and delegation-token support as not implemented. We build our own authorization/ACL layer on top of the hook system rather than waiting on or assuming this fills in later.

**Rejected — `HallucinationGuardrail`.** A no-op stub in the open-source package (paid-tier only). We rely on the functional `LLMGuardrail`/programmatic `Task.guardrail` instead, or a purpose-built fidelity check for CRM data claims (e.g. a worker citing a deal value or contact detail that doesn't match the system of record).

**Rejected — in-tree code-execution sandboxing.** The Docker-based `CodeInterpreterTool` has been removed/deprecated upstream; `allow_code_execution` is now a no-op. If a CRM agent ever needs code execution, we bring our own sandbox (E2B/Daytona have thin wrappers available) rather than depending on crewAI for that safety boundary — and any such surface gets scanned with garak's `exploitation`/`packagehallucination` probes (see above) before it ships.

---

## https://github.com/emilkowalski/skills — reviewed 2026-08-16

**What it does:** A Claude Code Skills package (pure markdown instruction files, no code) by Emil Kowalski (creator of Sonner, Vaul) encoding animation/motion craft and broader interface-design taste — meant to correct the "little mistakes" AI agents make when building UI (wrong easing, animating from nothing, decorative motion on data surfaces, etc.). Unlike the prior three entries, this one is about the CRM's *interface quality*, not its agent architecture.

**Kept — the frequency gate.** Never animate high-frequency actions (keyboard shortcuts, command palette, 100+/day interactions); reserve the "delight budget" for rare, first-time moments. A CRM is a daily-use, high-frequency tool — this maps directly onto how our UI should behave.

**Kept — the concrete motion ruleset.** `transform`/`opacity` only (GPU-safe), sub-300ms UI animations, never `ease-in`, never animate from `scale(0)`, `transform-origin` set to the trigger element. Tight and enforceable — adopted as literal house-style tokens.

**Kept — "data the user is reading or acting on should not move for style."** No decorative motion on functional data surfaces — tables, pipelines, reports. Directly on-point for a CRM; the skill itself cites "no animation on a graph in a banking app" as the standard.

**Kept — the Before/After/Why review table + Block/Approve gate**, as our own UI PR review template. Also kept: **"delete the animation" as the top remedial move** — a useful bias toward restraint on a data-dense app.

**Kept — the read-only-audit → human-vets-and-prioritizes → self-contained plan artifact → explicit do-not-touch boundaries → human sign-off → then execute** structure from its `improve-animations`/`find-animation-opportunities` skills. This is a UI-specific instance of exactly the pattern Charter §3/§9 already requires — worth mirroring as the template for how any CRM worker-agent proposes and stages a UI change generally, not just animation.

**Kept — Apple's eight design principles, feedback taxonomy (status/completion/warning/error), and wayfinding questions** ("Where am I? Where can I go? What's there? How do I get out?") — general UX-quality checklist material, independent of animation.

**Reshaped — the "delight" register.** Springs, bounce, stagger, and 3D-flip recipes are tuned for consumer/marketing products. The CRM defaults to the "crisp dashboard" end of every spectrum these skills offer (the skills themselves acknowledge this split); bouncier recipes become opt-in exceptions, never defaults.

**Reshaped — the bundled stack picks.** One person's opinionated library list (base-ui, Sonner, cmdk, zustand, etc.) with real gaps for a CRM — no data-grid, no form-validation library, no auth. Treated as a supplementary reference for what it covers well (e.g., Virtuoso for large record lists, base-ui for accessible primitives), not adopted as "the stack."

**Rejected — vendor-specific library documentation (`ask-sonner`).** Only relevant if we actually adopt Sonner for toasts; deferred, not adopted standalone.

**Rejected — the prototyping picker UI.** Explicitly a throwaway internal dev harness per its own docs, not a shippable component.

**Noted, not adopted:** the repo has zero content on governance/permissions/approval-gates as a topic — not a gap in its execution (unlike `financial-services`' missing audit log), just outside its scope. Our Charter already covers that ground.

---

## https://github.com/PleasePrompto/notebooklm-skill — reviewed 2026-08-16

**What it does:** A Claude Code Skill that drives a real, stealth-patched Chrome browser against `notebooklm.google.com` to ask questions of an existing NotebookLM notebook and read back Gemini's synthesized answer. Not an API wrapper — NotebookLM has no public API — so this is browser automation riding a standing, logged-in Google session. This entry is the first where the tool itself, not just a detail, gets rejected.

**Kept — the curated-knowledge-library pattern.** Its local JSON library of named/tagged/described knowledge sources an agent can pick from is a reasonable *design* to borrow for an internal CRM knowledge-base selector, entirely independent of NotebookLM itself.

**Kept — confirm-before-destroy on its cleanup script.** A `--confirm` flag plus an explicit yes/no prompt before deleting local auth/library data — small, and consistent with Charter §5's reversibility-by-default spirit for destructive local operations.

**Rejected — the tool itself, as shipped.** The mechanism, not just a detail, conflicts with the Charter:
- Every query is an **unattended, code-level send of arbitrary text to Google's servers with no approval checkpoint** — a direct conflict with §6 ("no customer data leaves the system without Sparsh's sign-off"). Nothing stops an agent from pasting customer PII into a question.
- It stores a **live, standing Google account session** (plaintext cookies plus a full browser profile on disk) rather than a scoped, revocable credential — the opposite of §2's least-privilege default.
- It depends on a human having **already uploaded documents and made the notebook "anyone with link" shareable**, entirely outside this tool's (or our) controls — a customer-data-leaves-the-system event that would need to have already cleared sign-off, upstream and invisible to it.
- **No audit trail** of what was ever sent — conflicts with §7.
- The tool is **explicitly ToS-gray by its own author's admission** (built-in bot-detection evasion, a recommendation to use a throwaway Google account "just in case") — not something to embed in a system governed by a strict operating charter.
- It's also not a CRM primitive regardless — document Q&A only, no email/contact/record-manipulation capability.

**If a NotebookLM-style "ask questions over curated docs" capability is wanted later**, it gets rebuilt from scratch with an explicit human-approval step gating anything sent externally, scoped/revocable credentials (never standing session cookies), and a real audit log — none of which this repo provides. This repo is a cautionary reference, not a starting point for that build.

---

## https://github.com/alirezarezvani/claude-skills — reviewed 2026-08-16

**What it does:** A large (300+ skill) MIT-licensed library of Claude Code skills spanning many business functions — engineering, product, finance, C-suite advisory (`c-level-advisor`), compliance (`compliance-os`, `ra-qm-team`), marketing, and an `orchestration/` directory. It is a **content/prompt marketplace, not a governance or runtime framework** — there is no execution controller, no enforced permission model, no CRM integration anywhere in it (confirmed by a repo-wide grep for "CRM" — zero skills implement or connect to actual CRM software). Notably, its own internal self-audit (`audit/newgen-2026-06/00-MASTER.md`) found real defects in its content, which shapes how much of this gets trusted below.

**Kept — `business-growth/customer-success-manager` and `revenue-operations` logic.** Deterministic churn/health-scoring and pipeline/forecast-analytics scripts are a solid starting point for the *logic* of read-only analytics worker-agents in our own CRM — mined for their scoring approach, not run as-is (see Reshaped).

**Kept — the `agent-decision-receipts` concept.** A tamper-evident, cryptographically-signed receipt for consequential actions (deploy/delete/pay/grant-access), explicitly built for EU AI Act Article 12 record-keeping, with a clear rule for *when* to mint one ("side-effecting AND consequential AND later-provable"). This is a genuinely well-designed primitive for Charter §7's audit-trail requirement — kept as a concept (see Reshaped for how we actually wire it in).

**Kept — the "drafts-only, never send" defense-in-depth pattern** from its email inbox-triage skill: the rule is stated repeatedly in the skill/agent/command text, only draft-verb tool calls are ever used, and a validator scans for any send-shaped call after the fact. Worth extracting as a pattern for our own hard-gated actions, with one correction (see Reshaped).

**Kept — the practice of a candid, published internal self-audit.** The repo's maintainers ran a rubric across every skill and published the results, including dangerous defects, rather than only marketing the numbers. Worth adopting for our own synthesis process: we periodically self-audit our own agent/skill content the same way, not just external repos.

**Reshaped — `agent-decision-receipts` becomes mandatory and hook-enforced, not opt-in.** As shipped, minting a receipt is a per-skill author's choice and depends on an external pip package that isn't wired into the base agent-invocation path — most of the repo's 300+ skills leave no signed record at all. We tie receipt-minting directly into the `PRE_TOOL_CALL` hook already adopted from `crewAI`, so anything on Charter §3's hard-gated list mints a receipt automatically, with no author opt-in required.

**Reshaped — the "drafts-only" pattern moves from detective to preventive.** As shipped, the validator scans the action log *after* a run for a send-shaped call and fails the run if it finds one — the risky action could already have happened by the time it's caught. We reshape this into a pre-emptive block on the `PRE_TOOL_CALL` hook itself, consistent with the "fail closed" correction already made to `crewAI`'s hook semantics — never allow the call in the first place.

**Reshaped — `customer-success-manager`/`revenue-operations` lose their standing tool grants and local-file assumption.** The source skills read from a JSON file the user manually supplies and run under an agent frontmatter granting `[Read, Write, Bash, Grep, Glob]` regardless of what the task needs. Our versions read from our own CRM's data layer instead of a manually-supplied file, and get only the narrow, task-scoped tool grant Charter §2 requires — no standing Bash or Write access for an analytics worker that only ever reads and scores.

**Rejected — the repo's permission/tool-scoping model, wholesale.** Of 27 agents checked, 19 are issued the identical broad toolset `[Read, Write, Bash, Grep, Glob]` regardless of role — including pure-advisory personas like the CEO/CFO advisors that need none of it. This is the direct opposite of Charter §2's zero-access-by-default, and we reject it outright in favor of the per-task narrowed scoping already established from `crewAI`.

**Rejected — the `orchestration/` model as a governance mechanism.** It describes itself explicitly as "no framework, no dependencies, just structured prompting," with human oversight framed as advisory ("override any phase, persona, or skill choice") rather than a hard blocking gate. It gives us no manager/worker authority-boundary mechanism at all — that role stays filled by the per-tier-`Crew` plus allow-listed delegation hook already adopted from `crewAI`.

**Rejected — taking any domain content at face value.** The repo's own audit found content presented confidently that is actively wrong: a repealed FDA regulation taught as current law, an EU MDR risk-acceptability table that itself violates MDR, a misclassified EU AI Act article, and finance scripts that silently output all-zero results with no error. None of this repo's compliance, regulatory, or financial-modeling content is treated as reliable without independent verification first — this matters more than usual given Sparsh is a non-coder relying on us to get this right, not someone positioned to catch a confidently-wrong regulation citation themselves.

**Rejected — trusting any cross-file reference from this repo without checking it resolves.** The audit found 28 of 39 root slash commands, and roughly 16 C-level agent reference citations, pointing at files that no longer exist after a directory reorg. Any skill or command pulled from this repo gets its referenced paths verified before we rely on them, not assumed to work because the frontmatter says so.

---

## https://github.com/multica-ai/andrej-karpathy-skills — reviewed 2026-08-16

**What it does:** A single Claude Code skill (despite the plural name, the repo contains exactly one) encoding four behavioral principles for how a coding agent should work, inspired by a public tweet from Andrej Karpathy diagnosing common LLM coding-agent failure modes. This entry covers pure engineering *practice*, not permissions or governance, so it interacts with the Charter differently than prior entries — there's nothing here to gate, only house standards to adopt.

**Kept — all four principles, directly, as house engineering practice for every agent that writes code in this project:**
- **Think Before Coding** — surface assumptions explicitly, present tradeoffs instead of silently picking one interpretation, push back when a simpler approach exists, stop and name the confusion when something is genuinely unclear rather than guessing.
- **Simplicity First** — minimum code that solves the actual problem; no speculative abstractions, no unrequested configurability, no error handling for scenarios that can't happen. Litmus test: would a senior engineer call this overcomplicated?
- **Surgical Changes** — touch only what the task requires; don't refactor, reformat, or "improve" adjacent code; every changed line should trace directly to the request; only remove what your own change orphaned.
- **Goal-Driven Execution** — turn vague asks into verifiable success criteria (write a failing test first, then make it pass; state a plan where every step has an explicit verify check) rather than declaring something done on confidence alone.

These aren't new territory — they reinforce discipline this project already operates under — but they're worth stating explicitly as a named, shared standard so every agent in the hierarchy is held to the same bar consistently, not just whichever agent happens to already have good habits.

**Noted, for accuracy — not a restriction, just a fact worth being straight about.** The repo's branding overstates its connection to Andrej Karpathy: the real tweet is quoted accurately, but the four named principles and their specific rules are a third-party packager's own invention built on top of that tweet, not something Karpathy wrote, reviewed, or endorsed. It's unofficial, fan-derived content. Worth knowing so nobody later cites this as "Karpathy's framework" when the diagnosis is his and the specific solution structure isn't.

**Nothing rejected.** This repo carries no permission model, no orchestration claims, and no compliance content — it doesn't touch any part of the Charter, so unlike prior entries there's no governance conflict to resolve here.

---

## https://github.com/DeusData/codebase-memory-mcp — reviewed 2026-08-17

**What it does:** Despite the name, this is not an "agent learns and remembers things" system — it's a mature, security-conscious MCP server that parses a codebase with tree-sitter and stores the resulting structure (functions, classes, calls, routes) in a local SQLite graph, so an agent can query "what calls X" or "what's the architecture" in under a millisecond instead of repeatedly grepping the whole repository. This entry corrects an assumption baked into our own `MemoryScope` concept: we expected this to be a candidate implementation of scoped, decaying, multi-agent knowledge memory. It is not that at all, and finding that out cleanly is itself the value of this review.

**Kept — the code-structure graph as a query source for `engineering-agent`'s workers.** Once our own CRM codebase is indexed, a Reader-worker can ask "what calls this function" or "what's the module structure" as a cheap structural query instead of a token-expensive grep sweep. This is a narrow, single-purpose utility — a tool an engineering worker calls, not a memory system any agent trusts with knowledge.

**Kept — the tool-profile allowlist pattern** (Scout / Analysis / Auditor tiers restricting which tool *names* a session can call at all). This reinforces, rather than replaces, the least-privilege tool-scoping we already run via `crewAI`/`financial-services` — another independent data point for the same practice.

**Kept — path containment for any indexing tool** (`CBM_ALLOWED_ROOT`, confining what directory a tool can index). Adopted as a baseline requirement for any external tool `engineering-agent` invokes, not specific to this repo.

**Reshaped — this does not implement `MemoryScope`, and nothing here is used as if it did.** The data model has no agent/role/user identity at all — no column for "whose memory this is" — and no decay, expiration, or consolidation, which directly contradicts the "old learnings should fade" requirement from our own design discussion. The scoped, decaying, per-domain knowledge memory we described stays something we build ourselves; this tool is folded in only as a narrow code-facts source `engineering-agent` may query, never as the memory store itself.

**Rejected — `manage_adr` as a trusted knowledge-write path.** The one tool in this server that writes free-text "knowledge" replaces the *entire* stored document on every call, with no diffing, no versioning, no author attribution, and no approval gate — any tool-enabled session can silently overwrite a team's persisted architecture record, and a future agent would have no way to know it happened. If an ADR-style capability is wanted later, it gets built through the hook-enforced, attributed audit trail `security-compliance-agent` already owns, never adopted as-is from here.

**Rejected — treating indexed source content as pre-sanitized.** The tool does no trust-tagging of what it returns; a malicious comment embedded in a source file would reach an agent's context verbatim through its query tools, the same untrusted-input threat model as `financial-services`' documents. Anything an `engineering-agent` worker receives from this tool still goes through the same Reader-tier isolation as any other untrusted content — the tool's own security hardening protects its supply chain and binary integrity, not the trustworthiness of the code it's reporting on.

---

## https://github.com/rtk-ai/rtk — reviewed 2026-08-17

**What it does:** "rtk" (Rust Token Killer) is a CLI proxy that sits between an AI coding agent and the shell — it intercepts common developer commands (git, cargo, npm, docker, etc.), runs them, and compresses the output before it reaches the agent's context window, cutting token spend on noisy CLI output. It hooks into 13+ agent hosts (Claude Code, OpenClaw, Cursor, and others). Not an orchestrator, not MCP-related — a narrow, single-purpose tool, but its permission-evaluation and trust model are the genuinely valuable part of this review.

**Kept — the trust-on-review model for local config** (`trust.rs`): a project-local filter/config file is not loaded just because it exists — an untrusted one is skipped outright, trust requires an explicit human review plus a stored content hash, and any later change to the file invalidates that trust and forces re-review. This is a strong, concrete precedent for how per-user automation preferences under `CHARTER.md` §3b should work: a new or edited automation rule doesn't inherit trust silently just because a similar one was approved before.

**Kept — hook integrity verification.** Installed hook scripts are hashed at install time to a read-only record, re-checked at runtime, and execution is blocked if the hash doesn't match — real tamper-evidence, not just a config flag. Directly relevant to protecting our own `PRE_TOOL_CALL` hook (owned by `security-compliance-agent`, adopted from `crewAI`) from being silently modified.

**Kept — fail-safe default on anything unattestable.** A compound or otherwise-unparseable command is never auto-allowed — it defaults to "ask," even when part of the command looks safe. Direct reinforcement of the zero-imposed-cost rule in `CHARTER.md` §3b: when genuinely uncertain, the answer is not to guess toward permissiveness.

**Kept — the Deny > Ask > Allow(explicit) > Default(ask) precedence model**, as a *pattern* for `security-compliance-agent`'s policy engine — not as code, since it's tightly coupled to shell-command parsing. The underlying idea (an explicit deny always wins, an unmatched case defaults to the cautious tier, not the permissive one) transfers directly to a CRM-native policy engine evaluating actions like "send this email" or "change this record" instead of bash strings.

**Kept — the telemetry/consent design** (opt-in only, a fully documented field list, one command for complete local-and-server erasure) as a reference model for how this system should handle anything it ever wants to collect about a CRM user — matches the zero-imposed-cost-by-default spirit of `CHARTER.md` §6.

**Reshaped — the actual token-compression feature.** Potentially useful for `engineering-agent`'s workers to cut noise from routine tool output (test failures, git status, etc.) — but compression is lossy by design, which is in direct tension with the Expert Flagging Duty (`CHARTER.md` §3d): an agent can't reliably notice a risk it never saw because a filter stripped it. Adopted with a carve-out: never applied on any input feeding a flagging decision — that path always gets full, unfiltered content.

**Reshaped — "ask" must never silently degrade to "allow."** The source project documents that some of its host integrations fall back to auto-allow when the host has no native approval UI to display an "ask" prompt through. We explicitly reject that fallback direction for our own system: if a surface can't support a real pause-and-ask, the correct default is deny/incomplete, never silent allow.

**Rejected — adopting the binary/crate itself as a dependency.** This checkout is an unaudited fork ("critical fixes for git argument parsing," per its own `CLAUDE.md`) of an upstream tool, with some doc/version drift already visible (a stale version number quoted in its own README). Given the standing rule from `financial-services` and `alirezarezvani` not to trust third-party content at face value, this isn't run against anything beyond scratch/read-only exploration without independent build verification first — not adopted as a production dependency now.

**Rejected — treating this as filling any governance gap.** Its permission model is scoped narrowly to shell-command execution, with no concept of roles, domains, or a harm boundary. It doesn't replace or extend anything in `CHARTER.md`'s hierarchy — its value here is entirely as a pattern reference for `security-compliance-agent`, not as infrastructure.

---

## https://github.com/thedotmack/claude-mem — reviewed 2026-08-17

**What it does:** A real, actively maintained (near-daily releases for ~11 months), Apache-2.0 persistent-memory system for Claude Code — hooks capture every tool-use event, a local background worker runs a locked-down "Observer" subagent that LLM-compresses raw activity into structured observations, and a hybrid full-text + vector search retrieves them in future sessions. This is the most direct attempt yet at the memory-system gap we've flagged twice (`codebase-memory-mcp` turned out to be code-structure indexing, not memory). It's a genuine candidate — but the honest finding is that it fills the *storage/retrieval* half of that gap and leaves the *scoping* half exactly as open as before.

**Kept — the capture → compress → hybrid-retrieve architecture, as a pattern for whatever memory substrate we build.** Automatic capture from lifecycle hooks, LLM-compression into structured observations, and progressive-disclosure retrieval (a compact search index first, full detail only for what's actually needed — the project's own docs cite roughly 10x token savings over dumping raw context) is a well-reasoned shape for durable, cheaply-queryable agent knowledge.

**Kept — the hardened-observer tool-lockdown pattern, for `security-compliance-agent`.** The subagent that summarizes raw (potentially untrusted) tool activity is given zero tool access — an empty allowlist, an explicit deny-list as backup, and a callback that denies and logs every attempt — with the reasoning stated directly in their source comments: "the redundancy IS the security property; removing any one layer must not re-open the gap." Every denied attempt is written to an append-only audit log specifically so a prompt-injection attempt leaves a permanent, reviewable trail. This is a concrete, well-executed instance of the Reader-tier isolation we already adopted from `financial-services`, with one addition worth folding in: **audit every denied tool-call attempt, not just the allowed ones** — a denied attempt is itself a signal worth keeping.

**Kept — the identity-triad concept for a real access-control layer**, from the project's beta multi-tenant mode: transport identity (a revocable API key) × semantic identity (who/what is actually acting) × a tenant scope, with workers re-validating that scope server-side rather than trusting a queued job's claimed ownership. This is the right *shape* for the access-control layer our own MemoryScope concept still needs — not adopted as code, since their implementation is beta and not fully wired to their own read path, but adopted as the model for how identity and scope should be checked.

**Reshaped — this is a candidate substrate, never a bare dependency.** The default, "just works" mode of this project has **no authentication on its local memory API at all** — any process on the machine, including a different agent tier, can read or write any project's stored memory, because scoping is just a client-supplied label, not an enforced boundary. If any part of this system is ever adopted, it only runs behind our own access-control wrapper enforcing which agent tier can read/write which scope — never bare, exactly the same reshaping principle applied to `codebase-memory-mcp`'s graph store.

**Reshaped — poisoned memory *content* is a distinct risk from poisoned memory *action*, and needs its own answer.** The hardened-observer pattern above stops injected content from causing the summarizer to take a harmful action, but it does not stop injected content from being stored as a plausible-looking, false "observation" that a future session then trusts as fact. Anything derived from untrusted external content (a customer's document, a scraped page) gets a provenance/confidence marker when stored, and is never treated as equivalent to an internally-verified fact — this refines, rather than resolves, the memory-system design we still owe ourselves.

**Reshaped — compressing an observation means calling an external LLM API, which is a data-egress event.** Per `CHARTER.md` §6, this isn't automatic for every domain — `security-compliance-agent` signs off per domain on whether raw tool-use content is allowed to leave for third-party compression at all. `customer-success-agent`'s work, which routinely touches real customer content, is the domain most likely to need a stricter, non-third-party compression path rather than the default flow.

**Rejected — the monetized default install path.** The current installer leads with a paid hosted tier and a trial-to-checkout funnel woven through multiple surfaces. If any component of this project is ever wired in, it's pinned explicitly to the free, self-hosted configuration — never the recommended default — consistent with the zero-imposed-cost principle in `CHARTER.md` §3b.

**Rejected — treating this as a finished MemoryScope implementation.** It isn't one, by the project's own admission: no agent-role scoping in the default path, no memory decay/staleness/consolidation anywhere (an acknowledged, explicit gap in their own docs — the same conclusion we reached independently after `codebase-memory-mcp`), and the one component with real identity scoping is beta and not fully wired. The MemoryScope gap stays open and ours to build; this review narrows what "building it" actually requires rather than closing it.

---

## https://github.com/headroomlabs-ai/headroom — reviewed 2026-08-17

**What it does:** A context-compression layer for AI coding agents — it shrinks huge tool outputs (logs, search results, file dumps) before they reach the LLM, while keeping the original retrievable on demand ("Compress-Cache-Retrieve," or CCR). Despite filenames suggesting an LLM response cache, "cache" here mostly means the *provider's own* prompt cache (Anthropic/OpenAI/Google) — Headroom's job is mainly to avoid breaking that, not to replay stored answers. Multi-provider (Anthropic, OpenAI, Google, Bedrock, Vertex), so this is relevant to how any of our agents call an LLM efficiently, not just Claude specifically.

**Kept — reversible compression as the pattern for any context-compression we build.** The CCR approach (compress what the LLM sees, but always keep the original retrievable via an explicit `retrieve` tool) is a direct match for `CHARTER.md` §5's reversibility-by-default principle. If `engineering-agent` ever needs to compress noisy tool output (the same efficiency problem `rtk` addressed), it does so this way — never a one-way, unrecoverable summarization.

**Kept — "never rewrite, only warn."** The component that protects the provider's own prompt cache (`CacheAligner`) detects risky patterns and reports them; it never silently mutates a prompt itself. Good precedent for any of our own optimization layers: report and let a human or agent decide, don't silently alter what was asked for.

**Kept — a second, independent example of candid self-auditing.** This project's `REALIGNMENT/` directory is a 12-document, self-authored audit admitting its flagship compression system was "built on the wrong mental model," cataloguing specific bugs with file:line evidence, and laying out a phased fix plan — the same practice we adopted from `alirezarezvani/claude-skills`, now validated by a second, independent project doing it well. Reinforces that this is a practice worth holding ourselves to, not a one-off good idea.

**Kept — "propose, don't auto-commit" for anything that writes to shared instructions.** Its `learn --apply` feature (which mines past sessions to suggest updates to an agent's instruction file) is dry-run by default and, even when applied, writes to a gitignored *local* file rather than the shared team instructions. This directly reinforces `CHARTER.md` §10: any agent capability that could ever propose a change to shared governing files (like `CHARTER.md` or an agent definition) defaults to a non-authoritative proposal, never a silent edit to the real thing.

**Kept — a real, documented case of the exact bug our MemoryScope design exists to prevent.** The project's own changelog describes parallel agent sessions that shared a *derived* fallback identity (hashed from model + system prompt, used when no explicit session id was set) having their internal state cross-contaminate — concurrent subagents interfering with each other because nobody gave them distinct identities. This is independent, real-world confirmation of why every agent instance in our hierarchy — including every worker a manager spawns — needs an explicit, unique identity, never an implicit or derived one.

**Kept — a refinement to our "fail closed" rule, not a contradiction of it.** Which way a system should fail depends on what's actually being decided: for a safety/security gate (our `PRE_TOOL_CALL` hook), failing closed remains mandatory, per the `crewAI`/`rtk` reshaping. For a pure efficiency feature like compression, the safe failure direction is the opposite — fall back to the slower, uncompressed, definitely-correct path rather than block. Both are "fail toward the safe outcome"; the safe outcome is just different depending on what the feature does.

**Reshaped — tenant/scope isolation must be the enforced default, not opt-in middleware.** As shipped, Headroom's compression-retrieval store and cross-agent memory store are process-global by default — tenant isolation exists only if an operator deliberately wires in extra middleware. Same reshaping principle applied to `codebase-memory-mcp` and `claude-mem`: if anything like this is ever adopted, scoped storage is the only mode that exists in our version, not a configuration someone could forget to turn on.

**Reshaped — no silent background daemons.** A bundled plugin auto-starts/ensures a local proxy process on every session start and before every shell command, once installed. Any equivalent hook we build routes through our own per-user configurable-automation gate (`CHARTER.md` §3b) instead of silently ensuring a running process exists.

**Reshaped — model routing stays auditable, not just automatic.** A feature that can silently switch which model handles a request logs its reasoning upstream already, which is the right instinct — kept, but treated as something `security-compliance-agent` can review on demand, not a fully invisible optimization.

**Rejected — adopting the Rust core as a dependency right now.** All of its Rust crates are pinned at `0.1.0` and the project's own realignment plan describes it as mid-rewrite with several phases still open. Not run against anything beyond scratch exploration without independent verification, consistent with the `rtk` decision.

**Rejected — trusting the proxy's outbound headers by default.** The project has a documented history of leaking identifying headers (flagged in its own audit as a "subscription-revocation risk") through a proxy that sits inline on every LLM call. Any inline proxy we build or adopt gets its own explicit header audit — not trusted as clean just because upstream says the known cases are fixed.

---

## https://github.com/mukul975/Anthropic-Cybersecurity-Skills — reviewed 2026-08-17

**What it does:** An independent, community-maintained library of 817 Claude/agentskills-compatible security skills across 29 domains — cloud security, threat hunting, red teaming, incident response, compliance, AI security, and more — each with a real, practitioner-level workflow and MITRE ATT&CK/NIST/OWASP framework mapping. This is a genuinely dual-use repo: alongside strong defensive and compliance content, it also contains real, runnable offensive-security tooling (C2 infrastructure, phishing-campaign automation, credential-theft techniques). That combination is the center of this review, not a side note.

**Kept — accuracy note on the name, same pattern as `andrej-karpathy-skills`.** The repo is clearly disclaimed as "not affiliated with Anthropic PBC" in its own README, both top and bottom. Worth stating plainly anyway: the org/repo name trades on Anthropic's brand recognition, and a casual glance at the name alone (not the README) could cause someone to assume it's an Anthropic-published safety resource. It isn't — an individual maintainer (`mukul975`) built it.

**Kept — the `red-teaming-llms-with-garak` skill as a workflow reference.** It's the best-guarded skill in the repo (one of only two carrying a full boxed legal-authorization notice) and gives a genuinely useful structure — enumerate → baseline → mitigate → re-test → report — that extends `security-compliance-agent`'s existing `garak` practice with a clearer reporting cycle, not a new tool.

**Kept — compliance/governance skill structures** (CMMC Level 2, NIST 800-30 risk assessment, HIPAA safeguards, SOC 2 Type II prep) as raw material for how `security-compliance-agent` documents its own audit trail and access-policy work (SSP/POA&M structure, control-family mapping). Per the standing rule from `alirezarezvani/claude-skills`, none of this compliance content is trusted at face value — and this repo hands us a concrete demonstration of why: its own framework-version citations disagree with each other in three different files (ATT&CK v19.1, v16, and v14 cited in different places for the same mapping).

**Kept — the framework-mapping methodology itself**, independent of any specific skill: tagging content against MITRE ATT&CK/NIST CSF/OWASP in structured metadata, and generating a standard Navigator-layer file from it. A good pattern for how `security-compliance-agent` documents its own findings against established frameworks going forward.

**Reshaped — any adopted content gets our own uniform authorized-use gate, not the source's.** Legal/authorization framing in the source repo is broad but shallow and inconsistent — 495 of 817 skills mention "authorized" somewhere, but only 2 carry a real, prominent legal notice; the rest rely on a single word buried in a prerequisites list, with zero technical enforcement anywhere in the code. If anything from this repo is used, it's re-wrapped in our own mandatory, uniformly-applied authorization gate — never inherited as advisory text alone.

**Rejected — any offensive/operational content as an invokable agent capability.** This is the sharp line, and it maps directly onto `CHARTER.md` §6 ("nothing built or automated in this system may be used to harm, deceive, spam, or exploit anyone — inside the business or outside it"). Specifically rejected: the Havoc C2 infrastructure-deployment skill, the GoPhish credential-harvesting campaign automation, OAuth device-code phishing, DPAPI/shadow-credential-abuse skills, and similar `exploiting-*`/`attacking-*`/`abusing-*` content. These are real, working scripts that execute against whatever target they're pointed at, with no technical authorization check in the source repo — only a comment saying "for authorized testing only." Our own Charter's hook-and-approval model is strictly stronger than that, and we do not weaken it to match a source repo's advisory-only posture. This is not a restriction on `security-compliance-agent` understanding offensive techniques (it already runs `garak` against our own agents) — it's a restriction on any agent holding ready-to-run attack tooling as a standing, invokable capability.

**Rejected — MITRE F3 "Monetization" tactic content** (money-mule layering, crypto off-ramping, card cash-out techniques). Even framed as fraud-*detection* material, the technique descriptions themselves are a specification of how to actually launder stolen funds. Only detection-oriented framing is usable from this category; the operational technique descriptions are not.

**Rejected — executing any of the repo's scripts directly inside our agent runtime.** They're built for a human operator running a scoped, pre-authorized engagement, not for autonomous agent execution — consistent with the standing rule from `rtk`/`headroom` not to run third-party code unaudited, with categorically higher stakes here since misuse isn't a bug, it's an actual attack.
