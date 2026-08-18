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

**Verified this session:** all 19 names load and are recognized by the harness as invokable `subagent_type` values, and two direct invocations were actually run and produced correct, sensible results — `knowledge-retrieval-worker` genuinely queried the real vault, correctly parsed both seeded entries' frontmatter, and (unprompted, from its own system prompt, not the task instructions) explicitly flagged that it was reporting vault content as untrusted data rather than treating it as instructions. That's real evidence the design's principles are actually landing in a spawned agent's behavior, not just present in a file.

**Verified this session, and this is the most important finding in this document: nested delegation does not work.** `engineering-agent` was spawned and instructed to delegate to `eng-reader-worker` via its own `Agent` tool, exactly as its design specifies. It could not — the `Agent` tool was **not present in its toolset at all** when it introspected what it had available, despite `.claude/agents/engineering-agent.md`'s frontmatter declaring `tools: Read, Grep, Glob, Agent`. This is not a permission error or a failed call; the tool simply doesn't exist for a spawned subagent in this environment. Only a top-level session (a human, or the main Claude Code session driving this work) can invoke `Agent`.

**What this means practically, and it's significant:** the entire "CEO-agent → manager-agent → worker-agent" hierarchy this whole design assumes — a manager autonomously spawning and scoping its own workers, as stated repeatedly across `CHARTER.md`, `agents/README.md`, and every manager's own design doc — **cannot execute as one autonomous chain in this environment.** A manager cannot actually delegate further once spawned. The practical operating model is instead: **the top-level session drives every hop by hand.** To get engineering-agent's plan executed, the top-level session calls `engineering-agent` for the plan, then separately calls `eng-builder-worker` itself (not through engineering-agent) with a scoped task derived from that plan — manually playing the role the design assumed a manager would play automatically.

This does not invalidate the design — the tool-grant scoping, the Reader/Writer tiering, the escalation rules, all of that still describes real, correct boundaries for what each role should do. What it changes is *who enforces the sequencing*: not the manager-agent autonomously, but whoever is driving the top-level session, by hand, one hop at a time, until/unless this environment's subagent-nesting restriction changes. This may well be a deliberate platform boundary (unbounded recursive subagent spawning is a real cost/loop risk), not a bug — but the Charter's own design was written assuming it wasn't there, and that assumption is now known to be false rather than merely undocumented.

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

This section exists because building this gate is the first time this system's own design corpus met a real deadline, and real gaps surfaced that no design doc anticipated — several during the initial build, more during a dedicated test pass afterward. Each is recorded here rather than fixed silently or left implicit.

1. **No actor-identity distinction.** The gate cannot tell "Sparsh operating this session directly" from "an autonomous spawned agent acting on its own." It blocks both equally. This is *why* building the gate required temporarily disabling it several times during this build (see git history / commit messages) — there is currently no other way for a governance-file edit to happen, including a legitimate one Sparsh directly asked for. `SYNTHESIS_LOG.md`'s `opencode`/`headroom` entries already named "acting-agent identity in the gate decision" as a real requirement; this is that gap, hit in practice rather than left theoretical. **Not fixed in this pass** — Sparsh chose to proceed without it for now rather than build identity-awareness before anything else could ship.
2. **Bash-mediated write detection is substring-based, not path-aware, and biased toward false positives.** A Bash command writing to a file whose name merely *contains* a governed path as a substring (e.g., `CHARTER.md.bak`, `my-CHARTER.md-notes.txt`) will be blocked even though the actual target isn't governed. This was found and left as-is deliberately: the failure direction is the safe one (over-block, not under-block), consistent with the fail-closed-on-ambiguity rule already adopted from `ECC`/`rtk`. If this becomes annoying in practice, the fix is real path resolution/canonicalization before the substring check, not a regex tweak.
3. **Bash-mediated write detection can be defeated by obfuscation — AND by a completely ordinary, non-adversarial subprocess, with no obfuscation involved.** The obfuscation case was already known (a `chr()`-encoded path is not caught, per §5 below). A dedicated test pass afterward found something more consequential: `scripts/scaffold_agent.py --name x --kind worker ...`, one of this system's own sanctioned tools, writes into `.claude/agents/` from *inside its own Python process*. The governed path string never appears in the Bash command text at all — not obfuscated, just architecturally invisible to a hook that can only read command text. Confirmed live: the gate raised no objection to running it, and the file was genuinely created. **This is why item 5b below (a second, independent enforcement layer) exists** — a text-level PreToolUse hook cannot, in general, see what a spawned subprocess does, and patching the text-matching further cannot close this category.
4. **A single-file `rm` on a governed path was not blocked at all, until this test pass found it.** The recursive-force check (`rm -rf`) requires both flags; a plain `rm CHARTER.md` needs neither (a single file needs no `-r`, and non-interactive `rm` doesn't prompt, so `-f` buys nothing) — so it sailed through both the destructive-rm check and the Bash-write-target check (which only looked for redirection/tee/cp/mv/sed-i/python-write patterns, not plain `rm`). **Fixed in this pass**: any `rm` naming a governed path is now blocked regardless of flags. Verified live — `rm CHARTER.md` is now refused by the running hook, and the fix passes 26/26 in `scripts/test_gate.py`.
5. **Disabling the gate itself, mid-session, is caught by neither enforcement layer.** Building and fixing the gate this pass required repeatedly moving `.claude/settings.json` aside and back (since editing a live-governed file requires the gate to not be watching). That toggle is invisible to `gate.py` (text-level, doesn't see the rename) and invisible to the pre-commit hook (item 5b) too, *as long as the toggle-then-restore never gets committed while disabled* — which is exactly what happened here, deliberately and transparently, but a less transparent actor could do the same thing silently. This is a real, structural limitation of the current two-layer design: it protects the *committed, pushed* state of governance files strongly, and protects *most* direct/common local-write attempts, but a determined local actor with subprocess access could disable the gate for one action and restore it, leaving no trace in either layer. Recorded plainly rather than assumed away — this affects how much trust this system currently warrants against a genuinely adversarial local actor, as opposed to the honest-mistake and common-case protection it does provide.

### 5b. A second, independent enforcement layer now exists — a git pre-commit hook

Directly in response to item 3 above: `.githooks/pre-commit` checks what's actually *staged for commit* against the governed-path list, independent of how the change got there. This is architecturally more robust than patching `gate.py` further, because it doesn't depend on seeing the triggering command — it checks the *result*. Verified live, in this exact order: `scaffold_agent.py` created a real file in `.claude/agents/` with the gate raising no objection (confirming item 3); `git add` + `git commit` on that file was then blocked by this second layer, with the standard error naming exactly which staged path matched and why. This is a genuine, tested instance of `CHARTER.md` §3a property 3's "at least two independent places" — the first time this system has actually demonstrated that property rather than stating it.

Activation isn't automatic in a fresh clone: run `git config core.hooksPath .githooks` (this repo's local git config already has it set from this session) or copy `.githooks/pre-commit` into `.git/hooks/pre-commit` directly, since git does not track `.git/hooks/` itself.

An explicit override exists for Sparsh's own deliberate governance commits: `GOVERNANCE_COMMIT_OVERRIDE=1 git commit ...`. This is the same pattern as the earlier "no actor-identity distinction" gap (item 1) — the override is a blunt, all-or-nothing escape hatch, not identity-aware, and should be treated with the same caution.

**Still not covered by this second layer:** an uncommitted, working-tree-only change to a governed file (item 5's mid-session-disable case) — this hook only fires at commit time.

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
