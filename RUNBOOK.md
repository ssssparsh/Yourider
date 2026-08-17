# RUNBOOK — What's Actually Built, What's Actually Verified, What's Not

**Read this before assuming anything below is safe because a design doc said it should be.** Per `CHARTER.md` §11: this document states what the code does, not what it should do. Where something was tested live and the test is described below, it's real. Where something is design-only or partially built, it says so.

---

## 1. What exists right now

```
.claude/
  agents/            ← 19 real, loadable Claude Code subagent definitions
  hooks/
    gate.py          ← CHARTER.md §3a floor-item gate (PreToolUse)
    audit_log.py     ← CHARTER.md §7 audit trail (PostToolUse, allowed calls only)
  settings.json      ← wires both hooks in

knowledge-vault/
  library/           ← 5 domain directories, 2 real seeded entries
  audit/
    tool-calls.jsonl ← the live, append-only audit log (has real entries in it right now)
  archives/          ← empty, per KNOWLEDGE-SYSTEM-DESIGN.md §11.2 phase 4, not built this pass

scripts/
  decay_sweep.py     ← confidence decay per §3.7c, tested live, dry-run by default
  scaffold_agent.py  ← generates a new .claude/agents/*.md, tested, not yet used for a real agent

CHARTER.md, SYNTHESIS_LOG.md, KNOWLEDGE-SYSTEM-DESIGN.md, agents/*.md  ← the design corpus this was built from
```

## 2. How to actually invoke an agent

From this session (or any Claude Code session in this repo), use the `Agent` tool with `subagent_type` set to one of the 19 names below. Example: to have engineering-agent do something, `Agent(subagent_type="engineering-agent", prompt="<scoped task>")`.

**Manager-agents (6):** `ceo-agent`, `engineering-agent`, `design-agent`, `customer-success-agent`, `security-compliance-agent`, `knowledge-agent` (state which domain in the prompt — see its file).

**Worker-agents (13):** `eng-reader-worker`, `eng-builder-worker`, `eng-reviewer-worker`, `design-audit-worker`, `design-proposer-worker`, `cs-analytics-worker`, `cs-reader-worker`, `cs-drafting-worker`, `sec-scan-worker`, `sec-policy-worker`, `knowledge-intake-worker`, `knowledge-curation-worker`, `knowledge-retrieval-worker`.

Per the design, managers spawn their own workers — you (or `ceo-agent`) should generally invoke a manager and let it delegate, not call a worker directly, except when testing a worker in isolation.

**Verified this session:** all 19 names load and are recognized by the harness as invokable `subagent_type` values (confirmed by the harness's own agent-type listing after the files were written). **Not yet verified:** whether a manager successfully invoking `Agent(subagent_type="eng-reader-worker", ...)` from *inside* a spawned subagent actually works in this environment — nested delegation depth was not tested live this pass. If it doesn't work as designed, `ceo-agent`/managers may need to be invoked one level at a time by a human or top-level session instead of truly autonomously delegating multiple levels deep. Test this before relying on it.

## 3. The gate — what's verified, exactly

`.claude/hooks/gate.py` blocks, before execution:

- Bulk delete/overwrite via Bash: `rm -rf`/`-fr` (any flag ordering with r+f), `DROP TABLE`/`DROP DATABASE`/`TRUNCATE TABLE`, `DELETE FROM` with no `WHERE` clause, `git push --force`/`--force-with-lease`, `git reset --hard`, `git clean -f*`.
- Writes to governed paths (`CHARTER.md`, `agents/`, `.claude/agents/`, `.claude/hooks/`, `.claude/settings.json`, `knowledge-vault/audit/`) via Claude Code's own `Write`/`Edit`/`NotebookEdit` tools.
- The same governed-path writes attempted via Bash instead — `echo > CHARTER.md`, `sed -i ... agents/x.md`, `tee`, `cp`/`mv` onto a governed path, or a `python`/`node` one-liner that opens and writes one.
- Malformed/unparseable input on either check (fails closed, never a silent allow).

**How this was verified, not just written:**
- 26 standalone test cases run directly against `gate.py` via stdin, 25 passing (see §5 below for the one that doesn't and why that's expected, not a bug).
- **Live, in this actual session, twice:** a real `rm -rf /tmp/...` Bash call was blocked mid-session (not simulated — the harness genuinely refused to run it), and a real `echo ... > CHARTER.md....` redirect was blocked the same way. Both are visible in `knowledge-vault/audit/tool-calls.jsonl`.
- The hook loads and takes effect **without a session restart** — confirmed by testing immediately after writing `.claude/settings.json` for the first time.

**What is NOT verified, and should not be assumed:**
- Whether the specific hook JSON I/O contract (`sys.stdin` → JSON, exit code 2 to block) is stable across future Claude Code versions. It worked in this environment on this date; if the harness changes its hook schema, this needs re-testing, not re-assertion.
- Whether every possible §3a-relevant Bash invocation is caught. This is a static, string/token-level check — it is not a full shell interpreter and does not execute or simulate the command. It was not designed to, and should not be described as doing so.

## 4. The gate — what's KNOWN incomplete (read this part especially)

This section exists because building this gate is the first time this system's own design corpus met a real deadline, and three real gaps surfaced that no design doc anticipated. Each is recorded here rather than fixed silently or left implicit.

1. **No actor-identity distinction.** The gate cannot tell "Sparsh operating this session directly" from "an autonomous spawned agent acting on its own." It blocks both equally. This is *why* building the gate required temporarily disabling it twice during this build (see git history / commit messages) — there is currently no other way for a governance-file edit to happen, including a legitimate one Sparsh directly asked for. `SYNTHESIS_LOG.md`'s `opencode`/`headroom` entries already named "acting-agent identity in the gate decision" as a real requirement; this is that gap, hit in practice rather than left theoretical. **Not fixed in this pass** — Sparsh chose to proceed without it for now (see the conversation this was built in) rather than build identity-awareness before anything else could ship.
2. **Bash-mediated write detection is substring-based, not path-aware, and biased toward false positives.** A Bash command writing to a file whose name merely *contains* a governed path as a substring (e.g., `CHARTER.md.bak`, `my-CHARTER.md-notes.txt`) will be blocked even though the actual target isn't governed. This was found and left as-is deliberately: the failure direction is the safe one (over-block, not under-block), consistent with the fail-closed-on-ambiguity rule already adopted from `ECC`/`rtk`. If this becomes annoying in practice, the fix is real path resolution/canonicalization before the substring check, not a regex tweak.
3. **Bash-mediated write detection can be defeated by obfuscation.** A command that builds a governed path from character codes, base64, or any other encoding at runtime (rather than writing the literal string `"CHARTER.md"` in the command) will not be caught — confirmed by testing exactly this case (`open(chr(67)+chr(72)+...)`) and watching it pass. This is not a bug to patch reactively; a static string check cannot close this category of bypass in general, and building something that could (executing the command in a sandboxed dry-run to observe its actual file-write targets) is real, separate future work, not a quick fix.
4. **Only one enforcement layer exists.** `CHARTER.md` §3a property 3 requires enforcement "in at least two independent places — the policy gate, and inside the functions that actually perform the action." The second layer (checks inside the actual data-write functions of a real product backend) does not exist because no product backend has been built yet in this pass — there is no real `DROP TABLE` function or bulk-delete endpoint to duplicate the check inside. When `engineering-agent` starts building real data-layer code, that code needs its own floor check, independent of this hook, not an assumption that the hook alone is enough.

## 5. The one deliberately-failing test case

`check "python -c overwriting CHARTER.md blocks"` in the test suite (see the commit that added it) fails on purpose — it's an obfuscated write (`chr()`-encoded path and mode strings) included specifically to find where static detection stops working, per §4.3 above. It's not counted as a real failure; it's the honest boundary of what this approach can do, recorded rather than hidden.

## 5a. A second gap found *while writing the test suite itself* — the SQL checks are not tokenized

`_check_bash`'s `rm`/force-push checks tokenize the command with `shlex` before matching, exactly per the "parse, never regex" rule this system documents as load-bearing (`knowledge-vault/library/shared/floor-gate-parses-not-regexes.md`). The SQL checks (`_DROP_OR_TRUNCATE_SQL`, `_DELETE_NO_WHERE_SQL`) do **not** — they are plain regex over the raw command string. This was inconsistent from the start and the inconsistency surfaced live: once the gate was wired into `.claude/settings.json`, running this system's *own* Bash-typed test suite (containing the literal string `"DROP TABLE"` as JSON test data, not a real SQL statement) got blocked by the outer gate before the inner test could even run — the gate could not tell "this text is quoted test data" from "this is SQL being executed."

This is why `scripts/test_gate.py` exists: it constructs test payloads in Python and pipes them to `gate.py` via `subprocess`, so the matched strings never appear as literal Bash command text the gate itself inspects. It is the correct workaround for *testing*, not a fix to the underlying gap. The underlying gap is real: **any Bash command containing the substring `DROP TABLE`/`TRUNCATE TABLE`/an unWHERE'd `DELETE FROM` anywhere in it — including inside an unrelated quoted string, a log message being echoed, or a docstring being `cat`'d — will be blocked**, exactly the same "commit message merely mentioning rm -rf" false-positive category the `rm` check was specifically built to avoid, except the SQL checks never got that fix. Failure direction is still the safe one (over-block, not under-block), so this was left as-is rather than rushed — a real tokenizer/parser for the SQL checks (matching the discipline the `rm` check already has) is genuine follow-up work, not a same-session patch.

## 6. The audit trail

`knowledge-vault/audit/tool-calls.jsonl` — append-only, one JSON object per line. Two writers: `audit_log.py` (PostToolUse, records tool calls that were *allowed* and actually ran) and `gate.py`'s own `_record_denial` (records a block at the moment it happens, since PostToolUse never fires for a blocked call — **verified empirically**, not assumed; see the git history for the false claim this replaced). Nothing else writes to this path; the gate itself blocks any other writer, including via Bash, per §3 above.

**Deliberately NOT version-controlled**, corrected after a real loop was hit in practice: this file was committed to git for the first pass of this build, and it immediately created a chase-your-tail problem — the log grows on *every* tool call, including the `git status`/`git commit`/`git push` calls used to check and commit it, so checking whether the repo was clean was itself a logged action that made it dirty again. It is `.gitignore`d now (see the entry there) and stays on disk as a real, local, append-only log — operational data, not source. If this log ever needs to be preserved historically (e.g. before a rotation), that's a deliberate snapshot/archive action, not continuous version control.

**Not built:** log rotation, a query/reporting tool over this log, or the "decision-receipt" signing pattern from `alirezarezvani/claude-skills` referenced in `security-compliance-agent.md`. The log is real and growing; nothing reads it back yet except a human with `cat`/`grep`.

## 7. The knowledge vault

Two real entries exist (`knowledge-vault/library/shared/floor-gate-parses-not-regexes.md` and `.../engineering/reader-writer-tiering.md`), following the schema in `KNOWLEDGE-SYSTEM-DESIGN.md` §2.2, using the *later* lifecycle vocabulary from §3.7a (`draft`/`candidate`/`approved`/`deprecated`/`archived`/`failed`) rather than §2.2's own original `status` values — §2.2 predates §3.7 and this implementation follows the more-considered later design. This inconsistency exists in the design docs themselves and hasn't been reconciled there; flagging it here so it isn't mistaken for an implementation bug.

**Explicitly deferred, not done:** migrating the other ~29 reviews in `SYNTHESIS_LOG.md` into individual knowledge-vault entries. That's a large, mostly mechanical task well suited to a `knowledge-intake-worker`/`knowledge-curation-worker` pair run domain-by-domain — a real next task, not something silently skipped. The `_catalog.json` per-domain index files described in `KNOWLEDGE-SYSTEM-DESIGN.md` §2.3 also don't exist yet.

## 8. Decay sweep

`python3 scripts/decay_sweep.py` — dry-run by default, `--apply` to write. Tested live: correctly reports near-zero decay as "unchanged" for the two fresh seeded entries, and correctly decayed a synthetic 85-week-old entry to the confidence floor (0.5) with `age_category` flipped to `aging_unverified` — status/lifecycle untouched, entry still fully present, nothing removed. This implements §3.7c only (truth decay). §3.6 (pointer/fingerprint relocation) is design-only — no code exists for it yet.

**Not built:** a scheduler to run this automatically. `mcp__Claude_Code_Remote__create_trigger` (available in this environment) could turn this into a real recurring Routine, but doing so was not done in this pass — it weilds real account-level scheduling and wasn't set up without asking first.

## 9. Growing the roster — no ceiling, by design

Per Sparsh's explicit instruction this session: the roster is not capped at the current 19. `scripts/scaffold_agent.py --name <x> --kind manager|worker ...` generates a starting `.claude/agents/<x>.md` from a template — tested (scaffolds a file, refuses to overwrite an existing one, correctly rejects a worker with no `--manager`). **What it does not do**: decide whether a new agent is warranted. That judgment still goes through `CHARTER.md` §9 intake — a real source/need reviewed and logged in `SYNTHESIS_LOG.md` — before scaffolding, so the roster grows because a task genuinely needs it, never pre-invented ahead of real design work. The scaffolded file is explicitly a starting point with its own TODO checklist, not a finished agent.

## 10. Salons — not built at all

`KNOWLEDGE-SYSTEM-DESIGN.md` §4's five weekly Knowledge Salon types remain entirely design-only. No scheduling, no dialogue-logging mechanism, nothing. This was true before this session and is still true after it — recorded here so this RUNBOOK doesn't imply otherwise by omission.

## 11. If you're picking this up cold

Read `CHARTER.md` first (the constitution), then this file, then whichever `agents/*.md` design doc matches what you're about to touch — the files in `.claude/agents/` are the *operational* compressed versions; `agents/*.md` has the full reasoning and source provenance. `SYNTHESIS_LOG.md` is the record of *why* each design decision was made, in case something here looks arbitrary — it almost certainly isn't, and the reasoning is there.
