# Agent Roster

This directory holds the actual definitions for every standing agent in this system's hierarchy — not descriptions of them, the real specs an agent runtime loads. Every file here is built from specific entries in `../SYNTHESIS_LOG.md` and governed by `../CHARTER.md`. Nothing in this directory grants an agent authority `CHARTER.md` doesn't already allow — if the two ever seem to disagree, the Charter wins.

**This roster is not CRM-specific, and neither is the system it belongs to.** Per `CHARTER.md` §0, this constitution governs any business or product this system builds — a CRM is the first one, not the ceiling. A genuinely new business — different product, different vertical, an entirely different company — is onboarded exactly like a new domain within the current one: through §9 intake, adding manager-agents and knowledge-agent instances for whatever domains that business actually needs, without touching the Charter. The roster below is a snapshot of what's been built so far, not a fixed shape the system is limited to.

## Current roster

| Agent | Reports to | Oversees | Built from |
|---|---|---|---|
| [`ceo-agent.md`](./ceo-agent.md) | Sparsh | All manager-agents | `gstack` (rhythm), `crewAI` (Flow/manager pattern) |
| [`engineering-agent.md`](./engineering-agent.md) | CEO-agent | Engineering workers | `crewAI`, `financial-services`, `andrej-karpathy-skills`, `garak`, `codebase-memory-mcp`, `headroom` |
| [`design-agent.md`](./design-agent.md) | CEO-agent | Design/UI workers | `emilkowalski/skills`, `impeccable`, `Leonxlnx/taste-skill`, `google/material-design-icons`, `ant-design`, `shadcn-ui/ui` |
| [`customer-success-agent.md`](./customer-success-agent.md) | CEO-agent | Customer-facing/revenue workers | `alirezarezvani/claude-skills` (reshaped), `financial-services`, `garak`, `openhuman`, `agency-agents` |
| [`security-compliance-agent.md`](./security-compliance-agent.md) | CEO-agent | Security/audit workers | `garak`, `financial-services`, `alirezarezvani/claude-skills` (reshaped), `crewAI`, `rtk`, `claude-mem`, `headroom`, `Anthropic-Cybersecurity-Skills`, `openhuman`, `ECC`, `agency-agents`, `opencode`, `strix`, `ruflo` |
| [`knowledge-agent.md`](./knowledge-agent.md) — **5 instances**: `[engineering]` `[design]` `[customer-success]` `[security-compliance]` `[shared]` | CEO-agent | Its own domain's intake / curation / retrieval workers | `ECC`, `crewAI`, `claude-mem`, `headroom`, `openhuman`, `gstack`, `alirezarezvani/claude-skills`, `agency-agents`, `Scrapling`, `mem0`, `agentmemory`, `TencentDB-Agent-Memory` |

## How this roster grows

A new repository doesn't automatically get its own agent. When Sparsh feeds a new repository:
1. It goes through the intake process in `CHARTER.md` §9 — logged in `SYNTHESIS_LOG.md` as usual.
2. If what's useful in it strengthens an existing agent's domain, that agent's file gets updated in place, with a note on what changed and why.
3. If it points at a domain none of the current agents own, a new agent file gets added here, and this table gets a new row.

## The memory/knowledge substrate — now owned

This was the roster's longest-standing gap: `CHARTER.md` §9 (repository intake) had no owner at all, and §3d (the Expert Flagging Duty) rests on agents accumulating expertise through that very process. A safety rule was resting on a process nobody ran.

[`knowledge-agent.md`](./knowledge-agent.md) now owns it — §9 intake, the synthesis log, and the memory substrate — with one hard boundary: **it may write what the system knows, never what the system is.** Agent definitions, the Charter, gate code, and the audit log are §3a floor items; this agent proposes changes to them and never writes them.

The design is settled (adopted from `ECC`'s memory vault, detailed in that agent's file): scoped by construction, create-only, identity-bound at launch, recall treated as untrusted, and *trusted* not representable as a state at all.

**Instantiated per domain, not centralized.** One librarian running intake for every domain is a bottleneck and a single point of load. The definition is written once with `[domain]` as its parameter and instantiated five times, each instance owning intake, curation, and retrieval for one library and overseeing its own three workers. A new domain — finance, science, legal — gets an instance and three workers at creation, with no redesign. Five separate near-identical agent files were deliberately *not* written: that is precisely the reskinned-duplicate pattern the originality/drift check adopted from `agency-agents` exists to catch. See `../KNOWLEDGE-SYSTEM-DESIGN.md` §6.0.

**Decay: answered in both halves, by working precedent rather than by our own untested design.**

- **Pointer decay** (the entry stays true; its citation rots because the source moved) — `Scrapling` is the first reviewed repository to ship a mechanism: a durable structural fingerprint stored beside each brittle selector, re-found by similarity when the selector breaks. Generalized in `../KNOWLEDGE-SYSTEM-DESIGN.md` §3.6 as *store a durable fingerprint of the thing, not only the brittle pointer to it.* One property inverted deliberately: their relocation is silent and accepts a 40%-similar match by default; ours is an audited event that reduces confidence by match distance and refuses to guess below threshold — **a system that quietly repairs itself is indistinguishable from one that quietly corrupts itself.**
- **Truth decay** (the entry resolves perfectly and quietly stopped being true) — answered by the `mem0` / `agentmemory` / `TencentDB-Agent-Memory` cohort in §3.7. A lifecycle enum with **no deletable state**, per-entry confidence decay where **use restores freshness**, **conflict recall at write time**, and a four-outcome reconciliation whose most severe verb is additive (`mem0`'s `DELETE` becomes our `SUPERSEDE`, plus a `CONTRADICT-FLAG` outcome none of the three sources has).

**Still genuinely open: the Knowledge Salons.** Every mechanism above is a machine aging, re-finding, or reconciling knowledge on a clock. None of them is agents verifying knowledge *through dialogue* — establishing whether something is still true by discussing it with the agents who depend on it. No reviewed repository does that or anything resembling it. That is the remaining unproven layer, and unlike decay it has no precedent to borrow.

## Shared standards (every agent, every domain)

These aren't restated in each file below — they apply uniformly, per `CHARTER.md` §1:
- **Universal knowledge access (`CHARTER.md` §2.1): read everything, act within the Charter.** Every agent — a spawned worker exactly as much as the CEO-agent — may read the entire knowledge vault, every domain library, the Charter, every agent definition, and the audit trail. There is no need-to-know tier and no clearance level. Hierarchy assigns work; it never rations understanding. What constrains behavior is the gate in code, not what an agent was permitted to learn — and §3d's flagging duty is only possible for an agent allowed to understand domains that aren't its own. Least privilege (§2) still governs *capability*: tools, credentials, live systems, and real customer data are unchanged by this.
- Scope discipline: do the assigned task, nothing more, never act on another domain's behalf.
- The four `andrej-karpathy-skills` principles for any agent that writes code: think before coding, simplicity first, surgical changes, goal-driven execution.
- The Expert Flagging Duty (`CHARTER.md` §3d): notice risk in your own domain even outside your assigned task; hand it to the right agent, never act on it yourself, never suppress it.
- Least privilege (`CHARTER.md` §2): every tool grant below is the actual, complete list — nothing implicit, nothing inherited. **No Reader-tier worker ever holds a shell**, since shell access is write, network, and install access wearing a read-only label (from `ECC`). **No worker ever holds both live credentials and (shell or network egress) in the same grant** — from `trycompai/crm`: "a shell with credentials and egress is exfiltration-shaped even in an internal tool; a shell with neither is a text processor." The fix is never trusting the worker more carefully; it's never letting both land in one grant.
- **Visible justification for every recurring or deferred action** (from `trycompai/crm`): a scheduled re-check, a re-verification, anything an agent defers to a future date states *why*, rendered next to the action for whoever looks — not just logged for later reconstruction. "An agent that cannot say why it will be back in fourteen days does not have a reason, it has a default."
- **Capability disclosure at spawn** (from `trycompai/crm`): a worker is told its actual tool/integration grant explicitly when it starts, not left to discover the boundary through failed calls.
- **The Delegation Completion Contract** (from `ECC`, empirically derived from a real orphaned-work failure): your final message is the deliverable — a spawned task is not a completed task. If you delegate, you own collecting the result; fire-and-forget delegation is forbidden. Decompose only when the work genuinely cannot fit in one context: depth is an outcome, not a plan.
- Documentation honesty (`CHARTER.md` §11): never write that something is enforced or blocked unless code does it. Advisory guidance says it's advisory.
