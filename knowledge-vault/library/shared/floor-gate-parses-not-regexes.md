---
id: shared-floor-gate-parses-not-regexes
domain: shared
category: governance
topic: charter-3a-enforcement
subtopic: floor-item-detection

title: "The floor matcher parses, never regexes"
summary: "A real shell tokenizer, not a substring/regex match, is required to distinguish an actual destructive command from text that merely mentions one."
description: |
  Adopted from ECC (see SYNTHESIS_LOG.md): a regex over a raw command string
  cannot distinguish `rm -rf /data` from a commit message that says "fix:
  remove old rm -rf script" — both contain the substring. A real tokenizer
  (this system uses Python's `shlex.split`) parses the command into actual
  argv tokens before checking for the destructive flag combination, so a
  string that merely mentions a dangerous pattern in prose is not falsely
  blocked, while `rm -rf`, a quoted variant, or a flag-combined form like
  `-rf` are all caught correctly.

  Implemented directly in `.claude/hooks/gate.py`, which is the live
  CHARTER.md §3a floor-item gate for this system. Verified empirically, not
  just designed: 17 test cases run against the real script, covering both
  the destructive and the merely-mentioning cases, all passing, plus a live
  end-to-end test in the actual Claude Code harness (a real `rm -rf` Bash
  call blocked mid-session, logged to this vault's own audit trail).

created_date: 2026-08-17T23:00:00Z
last_re_verified_date: 2026-08-17T23:00:00Z
next_re_verify_date: 2027-02-17T23:00:00Z
re_verify_interval_days: 180

confidence_level: verified
confidence_decay_factor: 1.0
age_category: current

status: approved
is_superseded: false
superseded_by: null
superseded_date: null
historical_reason: null

sources:
  - repo: affaan-m/ECC
    review_date: 2026-08-17
    section: "the floor matcher parses, never regexes"
  - repo: (this system's own gate.py)
    review_date: 2026-08-17
    validation: "Implemented and live-tested — see RUNBOOK.md for the test transcript."

access_count: 0
last_accessed_date: null
accessed_by_agents: []

related_knowledge:
  - id: shared-governance-layer-is-a-floor-item
    domain: shared
    relationship: "co-requisite"

created_by: intake-worker (via direct build session, 2026-08-17)
curated_by: knowledge-curation-worker[shared]
verifications:
  - date: 2026-08-17
    verified_by: (direct build session)
    verification_type: live-execution-test
    notes: "17/17 standalone test cases pass; live block confirmed in the running Claude Code session against a real rm -rf call; audit-log entry for the denial confirmed present."

tags:
  - charter-3a
  - gate
  - shell-parsing
  - verified-not-asserted
---

See `description` above for full content. This entry exists specifically as
a demonstration that the knowledge-vault schema in `KNOWLEDGE-SYSTEM-DESIGN.md`
§2.2 works with real content, not only as a design specimen.
