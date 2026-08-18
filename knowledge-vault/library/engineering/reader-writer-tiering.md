---
id: eng-pattern-reader-writer-tiering
domain: engineering
category: patterns
topic: worker-scoping
subtopic: untrusted-content-isolation

title: "Reader/Writer tiering for untrusted content"
summary: "A worker that reads content it didn't produce gets Read/Grep only; a worker that writes never opens that raw content directly, only a Reader's validated summary."
description: |
  Adopted from financial-services (see SYNTHESIS_LOG.md). Any worker handling
  content this system did not itself produce — an external repository under
  review, a customer's raw message, a generated-code output from another
  system — is scoped to Read/Grep/Glob only, with no Write, Bash, or MCP
  access under any circumstance. A separate Writer-tier worker performs the
  actual write, but never opens the untrusted content directly — it consumes
  only the Reader's already-validated, structured output.

  This is not advisory in this system's implementation: it is the actual
  tool grant on the corresponding subagent definitions
  (.claude/agents/eng-reader-worker.md holds Read/Grep/Glob only;
  .claude/agents/eng-builder-worker.md holds Write/Edit/Bash and is
  instructed never to open raw untrusted content directly). The same split
  is mirrored for customer-success-agent's cs-reader-worker /
  cs-drafting-worker pair and knowledge-agent's knowledge-intake-worker /
  knowledge-curation-worker pair.

created_date: 2026-08-17T23:00:00Z
last_re_verified_date: 2026-08-17T23:00:00Z
next_re_verify_date: 2026-11-17T23:00:00Z
re_verify_interval_days: 90

confidence_level: verified
confidence_decay_factor: 1.0
age_category: current

status: approved
is_superseded: false
superseded_by: null
superseded_date: null
historical_reason: null

sources:
  - repo: anthropics/financial-services
    review_date: 2026-08-16
    section: "Reader/Orchestrator/Writer tiering"
  - repo: (this system's own .claude/agents/ definitions)
    review_date: 2026-08-17
    validation: "Directly implemented as the actual tool-grant split on eng-reader-worker / eng-builder-worker, cs-reader-worker / cs-drafting-worker, knowledge-intake-worker / knowledge-curation-worker."

access_count: 0
last_accessed_date: null
accessed_by_agents: []

related_knowledge:
  - id: shared-floor-gate-parses-not-regexes
    domain: shared
    relationship: "co-requisite — both are enforcement mechanisms for CHARTER.md §2/§3"

created_by: intake-worker (via direct build session, 2026-08-17)
curated_by: knowledge-curation-worker[engineering]
verifications:
  - date: 2026-08-17
    verified_by: (direct build session)
    verification_type: direct-implementation-check
    notes: "Confirmed against the actual tool: frontmatter of the six worker-pair subagent definitions currently in .claude/agents/."

tags:
  - reader-writer-tiering
  - untrusted-content
  - least-privilege
  - worker-scoping
---

See `description` above for full content.
