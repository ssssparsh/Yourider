# Agent Roster

This directory holds the actual definitions for every standing agent in the CRM's hierarchy — not descriptions of them, the real specs an agent runtime loads. Every file here is built from specific entries in `../SYNTHESIS_LOG.md` and governed by `../CHARTER.md`. Nothing in this directory grants an agent authority `CHARTER.md` doesn't already allow — if the two ever seem to disagree, the Charter wins.

## Current roster

| Agent | Reports to | Oversees | Built from |
|---|---|---|---|
| [`ceo-agent.md`](./ceo-agent.md) | Sparsh | All manager-agents | `gstack` (rhythm), `crewAI` (Flow/manager pattern) |
| [`engineering-agent.md`](./engineering-agent.md) | CEO-agent | Engineering workers | `crewAI`, `financial-services`, `andrej-karpathy-skills`, `garak`, `codebase-memory-mcp`, `headroom` |
| [`design-agent.md`](./design-agent.md) | CEO-agent | Design/UI workers | `emilkowalski/skills` |
| [`customer-success-agent.md`](./customer-success-agent.md) | CEO-agent | Customer-facing/revenue workers | `alirezarezvani/claude-skills` (reshaped), `financial-services`, `garak`, `openhuman` |
| [`security-compliance-agent.md`](./security-compliance-agent.md) | CEO-agent | Security/audit workers | `garak`, `financial-services`, `alirezarezvani/claude-skills` (reshaped), `crewAI`, `rtk`, `claude-mem`, `headroom`, `Anthropic-Cybersecurity-Skills`, `openhuman`, `ECC` |

## How this roster grows

A new repository doesn't automatically get its own agent. When Sparsh feeds a new repository:
1. It goes through the intake process in `CHARTER.md` §9 — logged in `SYNTHESIS_LOG.md` as usual.
2. If what's useful in it strengthens an existing agent's domain, that agent's file gets updated in place, with a note on what changed and why.
3. If it points at a domain none of the current agents own, a new agent file gets added here, and this table gets a new row.

## Open gap: the memory/knowledge substrate — now half-closed

`CHARTER.md` §3d and §9 both assume agents accumulate real, scoped domain expertise over time — that's what the `MemoryScope` concept (adopted from `crewAI`) is for. **Still unbuilt, but the design is now largely settled.**

Four repositories were reviewed against this gap. `codebase-memory-mcp` and `claude-mem` turned out to solve adjacent problems (code-structure indexing; session capture/retrieval) and neither offered agent-tier scoping. `ECC`'s Memory Vault then supplied most of what was missing, and is adopted as the reference design:

- **Scoped by construction** — `project` / `team` / `user`, where user scope is never included implicitly.
- **Trust is unrepresentable.** The set of legal trust states contains exactly one value: `unreviewed`. There is no code path that can mark a memory trusted, because "trusted" isn't a value the schema admits. This is the structural answer to stored-false-memory: stronger than any rule telling agents not to trust recalled content.
- **Create-only.** Memories are never mutated; a correction is a new record that supersedes the old, so the history of what was believed stays intact.
- **Identity is bound at launch, not supplied by the caller** — and a caller-supplied targeting parameter is explicitly a routing filter, never an authorization boundary.
- **Recall is untrusted context**, never promoted into policy, rules, or agent definitions without human review — which is now also a floor item (§3a).

**What remains genuinely open: decay.** No reviewed project implements it — `ECC` included, whose own working-context file carries a hand-written "summarize and archive once stale" rule that went four months unexecuted and drifted to 29KB, demonstrating the failure mode precisely. The closest usable pattern is `ECC`'s 30-day expiry on session summaries, generalized. Designing and building the decay/consolidation layer is ours.

## Shared standards (every agent, every domain)

These aren't restated in each file below — they apply uniformly, per `CHARTER.md` §1:
- Scope discipline: do the assigned task, nothing more, never act on another domain's behalf.
- The four `andrej-karpathy-skills` principles for any agent that writes code: think before coding, simplicity first, surgical changes, goal-driven execution.
- The Expert Flagging Duty (`CHARTER.md` §3d): notice risk in your own domain even outside your assigned task; hand it to the right agent, never act on it yourself, never suppress it.
- Least privilege (`CHARTER.md` §2): every tool grant below is the actual, complete list — nothing implicit, nothing inherited. **No Reader-tier worker ever holds a shell**, since shell access is write, network, and install access wearing a read-only label (from `ECC`).
- **The Delegation Completion Contract** (from `ECC`, empirically derived from a real orphaned-work failure): your final message is the deliverable — a spawned task is not a completed task. If you delegate, you own collecting the result; fire-and-forget delegation is forbidden. Decompose only when the work genuinely cannot fit in one context: depth is an outcome, not a plan.
- Documentation honesty (`CHARTER.md` §11): never write that something is enforced or blocked unless code does it. Advisory guidance says it's advisory.
