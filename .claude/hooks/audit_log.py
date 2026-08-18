#!/usr/bin/env python3
"""CHARTER.md §7 audit trail — PostToolUse hook, for ALLOWED calls only.

Verified empirically, not assumed: PostToolUse does not fire for a call
PreToolUse already blocked (the tool never runs, so there is nothing
downstream to observe). An earlier version of this docstring claimed
denials were recorded here too — that claim was false and was caught by
actually testing the gate live rather than trusting the design. Denials
are recorded from inside gate.py itself, at the moment of the block —
see gate.py's `_record_denial`. This file only ever sees the calls that
were allowed to proceed.

Append-only. Writes to knowledge-vault/audit/tool-calls.jsonl, a path
gate.py blocks every agent from writing to directly (see its
_GOVERNANCE_PATHS) — this script is the one sanctioned writer, invoked by
the harness itself, not by an agent's own tool call.

Fails open, deliberately, and that asymmetry is intentional and documented
here per §11: audit logging is a record-keeping convenience, not a security
boundary (gate.py is the boundary). If the log can't be written — disk full,
permissions, whatever — that must never block the underlying tool call from
completing; per the headroom-derived rule, fail-direction depends on what's
being decided, and this is the "pure convenience" category that fails open.
"""

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

LOG_PATH = Path(__file__).resolve().parent.parent.parent / "knowledge-vault" / "audit" / "tool-calls.jsonl"


def main() -> int:
    try:
        raw = sys.stdin.read()
        payload = json.loads(raw)
    except Exception:
        return 0  # can't parse -> nothing to log; never block on this

    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "hook_event": payload.get("hook_event_name", "unknown"),
        "tool_name": payload.get("tool_name", "unknown"),
        "session_id": payload.get("session_id", "unknown"),
        "cwd": payload.get("cwd", "unknown"),
    }

    tool_input = payload.get("tool_input") or {}
    if isinstance(tool_input, dict):
        if "command" in tool_input:
            entry["command_summary"] = str(tool_input["command"])[:300]
        if "file_path" in tool_input:
            entry["file_path"] = tool_input["file_path"]

    tool_response = payload.get("tool_response")
    if tool_response is not None:
        entry["had_response"] = True

    try:
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        with LOG_PATH.open("a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception:
        pass  # fail open, see module docstring

    return 0


if __name__ == "__main__":
    sys.exit(main())
