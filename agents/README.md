# Agent Roster

This directory holds the actual definitions for every standing agent in the CRM's hierarchy — not descriptions of them, the real specs an agent runtime loads. Every file here is built from specific entries in `../SYNTHESIS_LOG.md` and governed by `../CHARTER.md`. Nothing in this directory grants an agent authority `CHARTER.md` doesn't already allow — if the two ever seem to disagree, the Charter wins.

## Current roster

| Agent | Reports to | Oversees | Built from |
|---|---|---|---|
| [`ceo-agent.md`](./ceo-agent.md) | Sparsh | All manager-agents | `gstack` (rhythm), `crewAI` (Flow/manager pattern) |
| [`engineering-agent.md`](./engineering-agent.md) | CEO-agent | Engineering workers | `crewAI`, `financial-services`, `andrej-karpathy-skills`, `garak`, `codebase-memory-mcp`, `headroom` |
| [`design-agent.md`](./design-agent.md) | CEO-agent | Design/UI workers | `emilkowalski/skills` |
| [`customer-success-agent.md`](./customer-success-agent.md) | CEO-agent | Customer-facing/revenue workers | `alirezarezvani/claude-skills` (reshaped), `financial-services`, `garak`, `openhuman`, `agency-agents` |
| [`security-compliance-agent.md`](./security-compliance-agent.md) | CEO-agent | Security/audit workers | `garak`, `financial-services`, `alirezarezvani/claude-skills` (reshaped), `crewAI`, `rtk`, `claude-mem`, `headroom`, `Anthropic-Cybersecurity-Skills`, `openhuman`, `ECC`, `agency-agents`, `opencode`, `strix` |
| [`knowledge-agent.md`](./knowledge-agent.md) | CEO-agent | Intake/curation workers | `ECC`, `crewAI`, `claude-mem`, `headroom`, `openhuman`, `gstack`, `alirezarezvani/claude-skills`, `agency-agents` |

## How this roster grows

A new repository doesn't automatically get its own agent. When Sparsh feeds a new repository:
1. It goes through the intake process in `CHARTER.md` §9 — logged in `SYNTHESIS_LOG.md` as usual.
2. If what's useful in it strengthens an existing agent's domain, that agent's file gets updated in place, with a note on what changed and why.
3. If it points at a domain none of the current agents own, a new agent file gets added here, and this table gets a new row.

## The memory/knowledge substrate — now owned

This was the roster's longest-standing gap: `CHARTER.md` §9 (repository intake) had no owner at all, and §3d (the Expert Flagging Duty) rests on agents accumulating expertise through that very process. A safety rule was resting on a process nobody ran.

[`knowledge-agent.md`](./knowledge-agent.md) now owns it — §9 intake, the synthesis log, and the memory substrate — with one hard boundary: **it may write what the system knows, never what the system is.** Agent definitions, the Charter, gate code, and the audit log are §3a floor items; this agent proposes changes to them and never writes them.

The design is settled (adopted from `ECC`'s memory vault, detailed in that agent's file): scoped by construction, create-only, identity-bound at launch, recall treated as untrusted, and *trusted* not representable as a state at all.

**Still genuinely open: decay.** No reviewed repository implements it. That problem now has an owner rather than sitting unassigned.

## Shared standards (every agent, every domain)

These aren't restated in each file below — they apply uniformly, per `CHARTER.md` §1:
- Scope discipline: do the assigned task, nothing more, never act on another domain's behalf.
- The four `andrej-karpathy-skills` principles for any agent that writes code: think before coding, simplicity first, surgical changes, goal-driven execution.
- The Expert Flagging Duty (`CHARTER.md` §3d): notice risk in your own domain even outside your assigned task; hand it to the right agent, never act on it yourself, never suppress it.
- Least privilege (`CHARTER.md` §2): every tool grant below is the actual, complete list — nothing implicit, nothing inherited. **No Reader-tier worker ever holds a shell**, since shell access is write, network, and install access wearing a read-only label (from `ECC`).
- **The Delegation Completion Contract** (from `ECC`, empirically derived from a real orphaned-work failure): your final message is the deliverable — a spawned task is not a completed task. If you delegate, you own collecting the result; fire-and-forget delegation is forbidden. Decompose only when the work genuinely cannot fit in one context: depth is an outcome, not a plan.
- Documentation honesty (`CHARTER.md` §11): never write that something is enforced or blocked unless code does it. Advisory guidance says it's advisory.
