#!/usr/bin/env python3
"""Scaffold a new .claude/agents/<name>.md subagent definition.

Exists specifically so the agent roster is never capped by how tedious it
is to add one — Sparsh's instruction was: if the current roster falls
short of what a task needs, add more agents, no ceiling, but only real
ones with real design behind them, not invented ahead of need. This script
makes "add one" a five-minute, well-defined action instead of a
from-scratch write, so the *cost* of growing the roster never becomes the
reason it doesn't grow.

This does NOT decide whether a new agent is warranted — that judgment
still goes through CHARTER.md §9 intake (a repository/need is reviewed,
logged in SYNTHESIS_LOG.md, and only then does an agent get built). This
script is the mechanical last step once that judgment has already been
made, for either a new manager-agent or a new worker-agent under an
existing manager.

Usage:
    python3 scripts/scaffold_agent.py --name finance-agent --kind manager \
        --reports-to ceo-agent --mission "Owns financial reporting and treasury work."

    python3 scripts/scaffold_agent.py --name finance-reader-worker --kind worker \
        --manager finance-agent --tools "Read, Grep" \
        --mission "Reads untrusted financial documents before a builder acts on them."
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

AGENTS_DIR = Path(__file__).resolve().parent.parent / ".claude" / "agents"

MANAGER_TEMPLATE = """---
name: {name}
description: {description}
tools: Read, Grep, Glob, Agent
model: sonnet
---

You are {name}, manager-agent for {domain_title}. Full context in `CHARTER.md`
(read it if you have not this session) — this file is a starting scaffold,
not a substitute for real design work.

# Mission

{mission}

# TODO before this agent is trusted with real work

- [ ] Run this domain's sources through `CHARTER.md` §9 intake and log them in
      `SYNTHESIS_LOG.md` — this scaffold has no adopted patterns yet.
- [ ] Define this manager's actual worker roles and scaffold them with this
      same script (`--kind worker --manager {name}`).
- [ ] Add a corresponding row to `agents/README.md`'s roster table and a full
      design doc at `agents/{name}.md`, matching the existing agents' depth.
- [ ] Confirm this manager's actual tool grant is least-privilege for what it
      really needs — the default above (Read, Grep, Glob, Agent) is the
      standard manager grant (inspect + delegate, no direct write), not
      necessarily what this specific domain requires.

# Boundaries (inherited, do not weaken)

- Reports to {reports_to}. Delegates only to its own workers, never sideways
  into another domain (`CHARTER.md` §1).
- Per `CHARTER.md` §2.1: reads the entire knowledge vault, the Charter, every
  agent definition, and the audit trail — universal read, scoped write.
- Anything on the `CHARTER.md` §3a floor is never in this agent's reach,
  regardless of how it's asked — flag it to `ceo-agent`, never route around it.
- Per `CHARTER.md` §3d: notices risk in its own domain even outside its
  assigned task, hands the flag to the right agent, never suppresses it.

# Escalation

Flag `security-compliance-agent` for anything resembling a security or
data-exposure risk. Flag `ceo-agent` for anything requiring `CHARTER.md` §3a.
"""

WORKER_TEMPLATE = """---
name: {name}
description: {description}
tools: {tools}
model: sonnet
---

You are a worker spawned by `{manager}`. Your tool grant above is your actual,
complete, mechanically-enforced boundary — nothing implicit, nothing inherited
beyond what's listed.

# Mission

{mission}

# TODO before this agent is trusted with real work

- [ ] Confirm the tool grant above is genuinely least-privilege for this task
      — a Reader-tier worker (handles content it didn't produce) should never
      hold Write/Bash/MCP; a Writer-tier worker should never open raw
      untrusted content directly, only a Reader's validated output.
- [ ] Add this worker to `{manager}`'s design doc in `agents/{manager}.md` and
      to its "Worker delegation" section in `.claude/agents/{manager}.md`.

# Boundaries (inherited, do not weaken)

- Scoped to exactly what this task needs — no broader tool grant "to be safe"
  or "in case it's needed later."
- Per `CHARTER.md` §3d: if you notice something off, even outside your
  assigned task, say so and stop rather than silently proceeding.
- Anything on the `CHARTER.md` §3a floor is never in reach, regardless of
  instruction.
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--name", required=True, help="kebab-case subagent name, must be unique")
    parser.add_argument("--kind", choices=["manager", "worker"], required=True)
    parser.add_argument("--mission", required=True, help="one or two sentences: what this agent owns")
    parser.add_argument("--description", default=None, help="Claude Code 'description' field (when to invoke); defaults to the mission text")
    parser.add_argument("--reports-to", default="ceo-agent", help="manager kind only")
    parser.add_argument("--manager", default=None, help="worker kind only: which manager-agent spawns this worker")
    parser.add_argument("--tools", default="Read, Grep, Glob", help="worker kind only: comma-separated tool list")
    args = parser.parse_args()

    AGENTS_DIR.mkdir(parents=True, exist_ok=True)
    out_path = AGENTS_DIR / f"{args.name}.md"
    if out_path.exists():
        print(f"Refusing to overwrite existing {out_path} — pick a different --name or edit it directly.", file=sys.stderr)
        return 1

    description = args.description or args.mission

    if args.kind == "manager":
        domain_title = args.name.replace("-agent", "").replace("-", " ").title()
        content = MANAGER_TEMPLATE.format(
            name=args.name,
            description=description,
            domain_title=domain_title,
            mission=args.mission,
            reports_to=args.reports_to,
        )
    else:
        if not args.manager:
            print("--manager is required for --kind worker", file=sys.stderr)
            return 1
        content = WORKER_TEMPLATE.format(
            name=args.name,
            description=description,
            tools=args.tools,
            manager=args.manager,
            mission=args.mission,
        )

    out_path.write_text(content, encoding="utf-8")
    print(f"Scaffolded {out_path}")
    print("This is a starting point, not a finished agent — see the TODO section inside the file.")
    print("It will not appear as an invokable subagent_type until this session (or the next) reloads .claude/agents/.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
