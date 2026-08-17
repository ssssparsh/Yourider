#!/usr/bin/env python3
"""Standalone test harness for .claude/hooks/gate.py.

Exists because of a real discovery made while building this system: once
the gate is wired into .claude/settings.json, it inspects every Bash
command's raw text for the same patterns it's designed to catch — which
means a Bash-typed test suite containing the literal string "DROP TABLE"
as JSON test *data* (not a real SQL statement) gets blocked by the outer
gate before the inner test even runs. The SQL checks in gate.py
(_DROP_OR_TRUNCATE_SQL, _DELETE_NO_WHERE_SQL) are plain regex over the raw
command string — unlike the `rm` check, they were never given the same
"parse, don't regex" discipline this system documents as load-bearing (see
knowledge-vault/library/shared/floor-gate-parses-not-regexes.md). This is
recorded honestly in RUNBOOK.md, not quietly patched around.

This script sidesteps the self-reference problem by constructing the test
payloads in Python and piping them to gate.py via subprocess, so the
strings never appear as literal Bash command text.
"""

import json
import subprocess
import sys
from pathlib import Path

GATE = Path(__file__).resolve().parent.parent / ".claude" / "hooks" / "gate.py"

CASES = [
    ("rm -rf blocks", 2, {"tool_name": "Bash", "tool_input": {"command": "rm -rf /tmp/foo"}}),
    ("safe rm allows", 0, {"tool_name": "Bash", "tool_input": {"command": "rm foo.txt"}}),
    ("commit msg mentioning rm -rf allows", 0, {"tool_name": "Bash", "tool_input": {"command": 'git commit -m "fix: remove old rm -rf script"'}}),
    ("DROP TABLE blocks", 2, {"tool_name": "Bash", "tool_input": {"command": 'psql -c "DROP TABLE users;"'}}),
    ("force push blocks", 2, {"tool_name": "Bash", "tool_input": {"command": "git push --force origin main"}}),
    ("normal push allows", 0, {"tool_name": "Bash", "tool_input": {"command": "git push origin main"}}),
    ("reset --hard blocks", 2, {"tool_name": "Bash", "tool_input": {"command": "git reset --hard HEAD~1"}}),
    ("write CHARTER.md blocks", 2, {"tool_name": "Write", "tool_input": {"file_path": "CHARTER.md", "content": "x"}}),
    ("write normal file allows", 0, {"tool_name": "Write", "tool_input": {"file_path": "scripts/foo.py", "content": "x"}}),
    ("edit agents/ blocks", 2, {"tool_name": "Edit", "tool_input": {"file_path": "agents/ceo-agent.md", "old_string": "a", "new_string": "b"}}),
    ("DELETE no WHERE blocks", 2, {"tool_name": "Bash", "tool_input": {"command": 'psql -c "DELETE FROM leads;"'}}),
    ("DELETE with WHERE allows", 0, {"tool_name": "Bash", "tool_input": {"command": 'psql -c "DELETE FROM leads WHERE id = 5;"'}}),
    ("edit .claude/hooks blocks", 2, {"tool_name": "Edit", "tool_input": {"file_path": ".claude/hooks/gate.py", "old_string": "a", "new_string": "b"}}),
    ("TRUNCATE blocks", 2, {"tool_name": "Bash", "tool_input": {"command": 'mysql -e "TRUNCATE TABLE sessions;"'}}),
    ("git clean -fd blocks", 2, {"tool_name": "Bash", "tool_input": {"command": "git clean -fd"}}),
    ("shell redirect into CHARTER.md blocks", 2, {"tool_name": "Bash", "tool_input": {"command": "echo malicious > CHARTER.md"}}),
    ("sed -i on agents/ceo-agent.md blocks", 2, {"tool_name": "Bash", "tool_input": {"command": "sed -i s/x/y/ agents/ceo-agent.md"}}),
    ("cp onto .claude/hooks/gate.py blocks", 2, {"tool_name": "Bash", "tool_input": {"command": "cp evil.py .claude/hooks/gate.py"}}),
    ("tee into audit log blocks", 2, {"tool_name": "Bash", "tool_input": {"command": "echo fake | tee knowledge-vault/audit/tool-calls.jsonl"}}),
    ("reading CHARTER.md still allows", 0, {"tool_name": "Bash", "tool_input": {"command": "cat CHARTER.md"}}),
    ("grep over CHARTER.md still allows", 0, {"tool_name": "Bash", "tool_input": {"command": "grep -n floor CHARTER.md"}}),
    ("unrelated redirection allows", 0, {"tool_name": "Bash", "tool_input": {"command": "echo hi > /tmp/scratch.txt"}}),
    ("malformed json blocks", 2, "not json"),
    ("plain rm on CHARTER.md blocks", 2, {"tool_name": "Bash", "tool_input": {"command": "rm CHARTER.md"}}),
    ("plain rm on agents/ceo-agent.md blocks", 2, {"tool_name": "Bash", "tool_input": {"command": "rm agents/ceo-agent.md"}}),
    ("plain rm on unrelated file still allows", 0, {"tool_name": "Bash", "tool_input": {"command": "rm scripts/scratch.py"}}),
]


def main() -> int:
    passed = 0
    failed = 0
    for desc, expected, payload in CASES:
        raw = payload if isinstance(payload, str) else json.dumps(payload)
        result = subprocess.run(
            [sys.executable, str(GATE)],
            input=raw,
            capture_output=True,
            text=True,
        )
        if result.returncode == expected:
            passed += 1
        else:
            failed += 1
            print(f"FAIL: {desc} (expected exit {expected}, got {result.returncode}) — stderr: {result.stderr.strip()}")
    print(f"\n{passed}/{passed + failed} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
