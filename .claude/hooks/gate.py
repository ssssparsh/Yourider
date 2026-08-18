#!/usr/bin/env python3
"""CHARTER.md §3a floor-item gate — PreToolUse hook.

Blocks the six §3a categories before a tool call executes. This is currently
the ONLY enforcement layer for these rules — §3a property 3 calls for
enforcement "in at least two independent places" (the gate, and inside the
functions that actually perform the action), and the second layer does not
exist yet because no actual product backend has been built in this pass.
Do not describe this gate as satisfying §3a property 3 in full until that
second layer exists. This file is what's true right now; say so, per §11.

Reads a Claude Code PreToolUse hook payload from stdin (JSON: tool_name,
tool_input, ...). Exits 0 to allow. Exits 2 with a reason on stderr to block
— this is the stable, longest-supported block mechanism across Claude Code
versions; it was chosen deliberately over the newer structured JSON output
schema because that schema has changed across versions and this file's
correctness was verified by literally invoking a blocked command and
confirming the block, not by reading documentation. See RUNBOOK.md for the
actual test transcript.

Fails closed: any error parsing the payload, reading tool_input, or
tokenizing a shell command results in a block, never a silent allow. A
check that could not complete never counts as a pass (from the ECC / rtk
reviews in SYNTHESIS_LOG.md).
"""

import json
import re
import shlex
import sys
from datetime import datetime, timezone
from pathlib import Path

_AUDIT_LOG_PATH = Path(__file__).resolve().parent.parent.parent / "knowledge-vault" / "audit" / "tool-calls.jsonl"


def _record_denial(payload: dict, reason: str) -> None:
    """Write the denial to the audit log directly, from inside the gate.

    Verified empirically (see RUNBOOK.md) that PostToolUse does NOT fire for
    a call PreToolUse blocks — the tool never runs, so there is nothing for
    a downstream hook to observe. §7 requires the audit sink record denials
    first; the only place that can actually happen is here, at the moment
    of the block. Fails open on the logging step itself — the block already
    happened via the exit code regardless of whether this write succeeds; a
    logging failure must never turn a real block into a silent allow, and
    must never itself become a block either.
    """
    try:
        entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "hook_event": "PreToolUse",
            "decision": "block",
            "tool_name": payload.get("tool_name", "unknown"),
            "session_id": payload.get("session_id", "unknown"),
            "cwd": payload.get("cwd", "unknown"),
            "reason": reason,
        }
        _AUDIT_LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        with _AUDIT_LOG_PATH.open("a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception:
        pass

# --- §3a category 1: bulk deleting or overwriting data ------------------
# Real tokenization, not a substring/regex match on the raw string, so
# `rm -rf`, `"rm" -rf`, and a commit message merely mentioning "rm -rf"
# are distinguished correctly (the ECC-derived rule: the floor matcher
# parses, never regexes).
_DESTRUCTIVE_RM_FLAGS = {"-r", "-rf", "-fr", "-R", "-Rf", "-fR"}

_DROP_OR_TRUNCATE_SQL = re.compile(
    r"\b(drop\s+(table|database|schema)|truncate\s+table)\b", re.IGNORECASE
)

# DELETE without a WHERE clause on the same statement is a bulk delete.
_DELETE_NO_WHERE_SQL = re.compile(
    r"\bdelete\s+from\s+[^\s;]+\s*(;|$)", re.IGNORECASE
)


def _tokens_contain_destructive_rm(tokens: list[str]) -> bool:
    for i, tok in enumerate(tokens):
        base = tok.rsplit("/", 1)[-1]
        if base != "rm":
            continue
        rest = tokens[i + 1 :]
        has_r = any(f in _DESTRUCTIVE_RM_FLAGS or ("r" in f.lstrip("-").lower() and f.startswith("-") and f != "-") for f in rest)
        has_f = any(f.startswith("-") and "f" in f.lstrip("-").lower() for f in rest)
        # Combined single-flag forms like -rf / -fr already satisfy both.
        if has_r and has_f:
            return True
        for f in rest:
            if f.startswith("-") and not f.startswith("--"):
                letters = f.lstrip("-").lower()
                if "r" in letters and "f" in letters:
                    return True
    return False


def _tokens_contain_rm_on_governed_path(tokens: list[str]) -> str | None:
    """A single-file `rm CHARTER.md` needs no -r (not a directory) and no
    -f (non-interactive rm doesn't prompt anyway) to be catastrophic — it
    was found, live, to slip past the recursive-force check above entirely.
    Any `rm` naming a governed path, with or without flags, is blocked.
    """
    for i, tok in enumerate(tokens):
        base = tok.rsplit("/", 1)[-1]
        if base != "rm":
            continue
        for arg in tokens[i + 1 :]:
            if arg.startswith("-"):
                continue
            normalized = arg.replace("\\", "/")
            for guarded in _GOVERNANCE_PATHS:
                needle = guarded.rstrip("/")
                if normalized == needle or normalized.startswith(guarded) or normalized.endswith("/" + needle):
                    return needle
    return None


def _tokens_contain_force_push_or_hard_reset(tokens: list[str]) -> bool:
    joined = " ".join(tokens)
    if re.search(r"\bgit\b.*\bpush\b.*(--force\b|--force-with-lease\b|(?<!\S)-f(?!\S))", joined):
        return True
    if re.search(r"\bgit\b.*\breset\b.*--hard\b", joined):
        return True
    if re.search(r"\bgit\b.*\bclean\b.*-[a-z]*f", joined, re.IGNORECASE):
        return True
    return False


def _bash_command_targets_governed_path(command: str) -> str | None:
    """Catch a Bash-mediated write to a governed path that doesn't go
    through Claude Code's own Write/Edit tool — python/node one-liners,
    sed -i, tee, cp, mv, or plain shell redirection. NOT exhaustive (an
    obfuscated or encoded write could still evade a static string check);
    this closes the obvious, common vectors, not every conceivable one.
    See RUNBOOK.md for what this does and does not cover.
    """
    for guarded in _GOVERNANCE_PATHS:
        needle = guarded.rstrip("/")
        if needle not in command:
            continue
        # `>` / `>>` redirection targeting the path
        if re.search(rf">>?\s*[^\s;|&]*{re.escape(needle)}", command):
            return needle
        # tee / cp / mv / sed -i naming the path anywhere in the command
        if re.search(r"\b(tee|cp|mv|sed\s+-i)\b", command):
            return needle
        # a Python/Node one-liner that opens/writes the path
        if re.search(r"\b(python3?|node)\b.*(-c|-e)\b", command) and re.search(r"\b(open|writeFile|write_text)\b", command):
            return needle
    return None


def _check_bash(command: str) -> str | None:
    """Return a block reason, or None to allow."""
    try:
        tokens = shlex.split(command, comments=False)
    except ValueError:
        # Unbalanced quotes etc. — cannot safely parse, fail closed.
        return "BLOCKED (§3a): shell command could not be safely tokenized; failing closed rather than guessing."

    if _tokens_contain_destructive_rm(tokens):
        return "BLOCKED (§3a category 1 — bulk delete/overwrite): recursive-force rm is a constitutional floor item. No agent automation reaches this, regardless of confidence or automation settings."

    rm_governed = _tokens_contain_rm_on_governed_path(tokens)
    if rm_governed:
        return (
            f"BLOCKED (§3a category 6 — governance layer): this command runs `rm` naming "
            f"'{rm_governed}', a protected path. A single-file rm needs no -r/-f flags to be "
            "catastrophic; found live during testing that the recursive-force-only check above "
            "did not cover this case. Governance files are never deleted by any agent through "
            "any avenue."
        )

    if _DROP_OR_TRUNCATE_SQL.search(command):
        return "BLOCKED (§3a category 1 — bulk delete/overwrite): DROP/TRUNCATE is a constitutional floor item."

    if _DELETE_NO_WHERE_SQL.search(command):
        return "BLOCKED (§3a category 1 — bulk delete/overwrite): DELETE with no WHERE clause is an unscoped bulk delete."

    if _tokens_contain_force_push_or_hard_reset(tokens):
        return "BLOCKED (§3a category 1 — bulk delete/overwrite): force-push / reset --hard / git clean -f is a constitutional floor item."

    governed = _bash_command_targets_governed_path(command)
    if governed:
        return (
            f"BLOCKED (§3a category 6 — governance layer): this Bash command appears to target "
            f"'{governed}', a protected path, via something other than Claude Code's own Write/Edit "
            "tool (redirection, tee/cp/mv/sed -i, or a script writing the file directly). Governance "
            "files are never written by any agent through any avenue — propose the change instead."
        )

    return None


# --- §3a category 6: the governance layer itself -------------------------
_GOVERNANCE_PATHS = (
    "CHARTER.md",
    "agents/",
    ".claude/agents/",
    ".claude/hooks/",
    ".claude/settings.json",
    "knowledge-vault/audit/",
)


def _check_write_target(file_path: str) -> str | None:
    normalized = file_path.replace("\\", "/")
    for guarded in _GOVERNANCE_PATHS:
        if guarded in normalized or normalized.endswith(guarded.rstrip("/")):
            return (
                f"BLOCKED (§3a category 6 — governance layer): '{file_path}' matches a "
                "protected path (Charter, agent definitions, gate/hook code, or the audit "
                "log). No agent authors or edits an agent, writes or disables a gate, or "
                "alters the record of what it did. Propose the change instead; it lands "
                "only by Sparsh's own hand."
            )
    return None


def main() -> int:
    try:
        raw = sys.stdin.read()
        payload = json.loads(raw)
    except Exception as exc:  # noqa: BLE001 - fail closed on any parse error
        reason = f"BLOCKED: gate could not parse its own input ({exc}); failing closed."
        _record_denial({}, reason)
        sys.stderr.write(reason + "\n")
        return 2

    tool_name = payload.get("tool_name", "")
    tool_input = payload.get("tool_input", {}) or {}

    if tool_name == "Bash":
        command = tool_input.get("command", "")
        if not isinstance(command, str):
            reason = "BLOCKED: Bash tool_input.command was not a string; failing closed."
            _record_denial(payload, reason)
            sys.stderr.write(reason + "\n")
            return 2
        reason = _check_bash(command)
        if reason:
            _record_denial(payload, reason)
            sys.stderr.write(reason + "\n")
            return 2

    if tool_name in ("Write", "Edit", "NotebookEdit"):
        file_path = tool_input.get("file_path", "")
        if not isinstance(file_path, str) or not file_path:
            reason = "BLOCKED: write-tool tool_input.file_path was missing or not a string; failing closed."
            _record_denial(payload, reason)
            sys.stderr.write(reason + "\n")
            return 2
        reason = _check_write_target(file_path)
        if reason:
            _record_denial(payload, reason)
            sys.stderr.write(reason + "\n")
            return 2

    return 0


if __name__ == "__main__":
    sys.exit(main())
