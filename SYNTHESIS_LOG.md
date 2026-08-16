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
