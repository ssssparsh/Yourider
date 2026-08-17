# Knowledge System Design — Complete Specification

**Status:** Architectural Design (not yet implemented)
**Owner:** Knowledge-agent (when implemented)
**Purpose:** Complete blueprint for the knowledge library, decay prevention, and knowledge cultivation system

---

## 0. Executive Summary

The Knowledge System is the living, evolving substrate of institutional expertise in the CRM. It is not a static archive, but an active, continuously-engaged community of practice where:

- **Knowledge-agent** acts as the Librarian, keeper of all archives
- **Knowledge entries** carry full provenance, confidence levels, and freshness metadata
- **Decay prevention** is active and organic (through dialogue) rather than scheduled audits
- **Knowledge salons** are regular conversations where agents verify and refine knowledge
- **Cross-domain learning** happens through structured sessions
- **Expertise** develops through peer discussion, not just accumulation

This document specifies:
- Complete data models for knowledge storage
- Decay prevention mechanisms in detail
- Knowledge salon orchestration
- Retrieval and access control
- Integration with the Charter and agent hierarchy

---

## 1. System Architecture Overview

### 1.1 Core Components

```
Knowledge System
│
├── Knowledge Library (/knowledge-vault/library/)
│   ├── /engineering/
│   ├── /design/
│   ├── /customer-success/
│   ├── /security-compliance/
│   ├── /finance/ (when created)
│   └── /shared/
│
├── Knowledge-agent (Librarian)
│   ├── Intake-worker (Reader tier)
│   │   └── Extracts learnings from external repos
│   ├── Curation-worker (Writer tier)
│   │   └── Organizes, tags, catalogs knowledge
│   └── Retrieval-worker (Query interface)
│       └── Services knowledge requests from other agents
│
├── Audit Trail (/knowledge-vault/audit/)
│   ├── Access logs (who queried what, when)
│   ├── Verification logs (what was re-verified, when)
│   └── Salon conversations (dialogue logs, outcomes)
│
├── Decay Prevention System
│   ├── Scheduled audit cycles (30-day heartbeat)
│   ├── Intake-driven re-validation (new repos refresh old knowledge)
│   ├── Salon-based verification (active dialogue)
│   └── Confidence decay calculator (automatic aging)
│
└── Knowledge Salons Orchestrator
    ├── Salon scheduler (daily/weekly conversation calendar)
    ├── Topic selector (picks aging knowledge to discuss)
    ├── Dialogue logger (captures conversations)
    └── Outcome handler (updates knowledge based on salon results)
```

### 1.2 Data Flow

```
External Repo
    │
    ├─→ Intake-worker (reads) → extracts learnings
    │
    ├─→ Curation-worker (organizes) → tags, validates, catalogs
    │
    ├─→ Knowledge Library (/knowledge-vault/library/domain/)
    │
    ├─→ [Runs continuously during system operation]
    │
    ├─→ Decay Prevention (audit cycle every 30 days)
    │   └─→ Marks aging knowledge for re-verification
    │
    ├─→ Knowledge Salons (daily/weekly conversations)
    │   └─→ Agents discuss topics, verify knowledge
    │   └─→ Conversation outcomes update library
    │
    ├─→ Other Agents Query Librarian
    │   └─→ "I need knowledge about X in domain Y"
    │   └─→ Retrieval-worker returns: knowledge + metadata + cross-domain flags
    │   └─→ Access logged for audit trail
    │
    └─→ Knowledge stays fresh, never decays silently
```

---

## 2. Knowledge Library Structure

### 2.1 Directory Organization

```
/knowledge-vault/
│
├── library/
│   │
│   ├── engineering/
│   │   ├── patterns/
│   │   │   ├── safe-delegation-crewai.md
│   │   │   ├── reader-tier-isolation.md
│   │   │   └── parse-dont-regex-matching.md
│   │   │
│   │   ├── frameworks/
│   │   │   ├── crewai-reshaping-rules.md
│   │   │   └── hook-integrity-verification.md
│   │   │
│   │   ├── anti-patterns/
│   │   │   ├── self-modification-hazard.md
│   │   │   └── silent-permission-bypass.md
│   │   │
│   │   └── _index.json (catalog of all engineering entries)
│   │
│   ├── customer-success/
│   │   ├── domain-models/
│   │   │   ├── health-score-five-dimensions.md
│   │   │   └── churn-leading-indicators.md
│   │   │
│   │   ├── strategies/
│   │   │   ├── pipeline-velocity-formula.md
│   │   │   └── forecast-confidence-bands.md
│   │   │
│   │   ├── signals/
│   │   │   └── champion-departure-signal.md
│   │   │
│   │   └── _index.json
│   │
│   ├── security-compliance/
│   │   ├── floor-items/
│   │   │   ├── six-never-automatable-categories.md
│   │   │   └── tainted-provenance-rule.md
│   │   │
│   │   ├── red-team-findings/
│   │   │   ├── garak-probe-results.md
│   │   │   └── opencode-bypass-tests.md
│   │   │
│   │   ├── threat-models/
│   │   │   ├── external-lm-compression-risk.md
│   │   │   └── voice-cloning-exposure.md
│   │   │
│   │   ├── governance/
│   │   │   └── documentation-honesty-failures.md
│   │   │
│   │   └── _index.json
│   │
│   ├── design/
│   │   ├── motion-principles/
│   │   │   ├── frequency-gate-rule.md
│   │   │   └── transform-opacity-only.md
│   │   │
│   │   ├── design-systems/
│   │   │   ├── apple-eight-principles.md
│   │   │   └── wayfinding-questions.md
│   │   │
│   │   ├── anti-patterns/
│   │   │   └── decorative-motion-on-data.md
│   │   │
│   │   └── _index.json
│   │
│   ├── shared/
│   │   ├── charter-principles/
│   │   │   ├── §3a-floor-items.md
│   │   │   ├── §3d-expert-flagging-duty.md
│   │   │   └── §9-intake-process.md
│   │   │
│   │   ├── hierarchy-patterns/
│   │   │   ├── manager-delegation-rules.md
│   │   │   └── worker-scope-discipline.md
│   │   │
│   │   └── integration/
│   │       └── how-to-flag-cross-domain.md
│   │
│   └── _catalog.json (master index of all entries across all domains)
│
├── audit/
│   │
│   ├── access_logs/
│   │   ├── 2026-08-18-access-log.jsonl
│   │   ├── 2026-08-19-access-log.jsonl
│   │   └── ...
│   │
│   ├── verification_logs/
│   │   ├── 2026-08-18-audit-cycle.log
│   │   ├── 2026-08-25-domain-review-engineering.log
│   │   └── ...
│   │
│   └── salon_conversations/
│       ├── 2026-08-18-engineering-salon.log
│       ├── 2026-08-19-cross-domain-learning-security.log
│       └── ...
│
└── archives/
    │
    ├── engineering/
    │   └── superseded/
    │       ├── delegation-v1.md (marked as superseded by v2)
    │       └── old-pattern.md (archived, still searchable)
    │
    └── [domain]/
        └── [historical knowledge stays here, not deleted]
```

### 2.2 Knowledge Entry Schema

Every knowledge file carries complete metadata:

```yaml
---
# Identity
id: eng-pattern-delegation-v2
file: /library/engineering/patterns/safe-delegation-crewai.md
domain: engineering
category: patterns
topic: delegation
subtopic: permission-tightening

# Content
title: "Safe Delegation: Permission Tightening, Never Relaxing"
summary: "Delegation in a hierarchy must tighten access, never relax it."
description: |
  [Full content of the knowledge entry]

# Freshness & Confidence
created_date: 2026-08-16T09:30:00Z
last_re_verified_date: 2026-08-18T14:22:00Z
next_re_verify_date: 2026-11-18T09:30:00Z
re_verify_interval_days: 90

confidence_level: verified
confidence_decay_factor: 1.0  # 1.0 = full confidence, drops if unverified
age_category: current  # current, aging_unverified, superseded, archived

# Lifecycle
status: current
is_superseded: false
superseded_by: null
superseded_date: null
historical_reason: null  # Why archived (if applicable)

# Provenance
sources:
  - repo: crewai
    review_date: 2026-08-16
    section: "Reshaped — delegation is flat and open-by-default within a crew"
  - repo: ecc
    review_date: 2026-08-17
    validation: "Validated against ECC's delegation laundering anti-pattern"
  - repo: openhuman
    review_date: 2026-08-17
    validation: "Confirmed: delegation must tighten, never relax"

# Usage
access_count: 5  # How many times queried
last_accessed_date: 2026-08-18T10:15:00Z
accessed_by_agents: [engineering-agent, security-compliance-agent]

# Cross-domain references
related_knowledge:
  - id: sec-anti-pattern-delegation-laundering
    domain: security-compliance
    relationship: "risk-for-this-pattern"
  - id: eng-pattern-reader-tier-isolation
    domain: engineering
    relationship: "prerequisite-pattern"

# Audit trail
created_by: intake-worker (during crewai review)
curated_by: curation-worker
verifications:
  - date: 2026-08-18
    verified_by: engineering-agent
    verification_type: discussed-in-salon
    notes: "Confirmed in engineering knowledge salon, no contradictions"
  - date: 2026-08-17
    verified_by: security-compliance-agent
    verification_type: cross-domain-validation
    notes: "Tested against ECC findings, holds true"

# Tags for search
tags:
  - delegation
  - hierarchy
  - permission-tightening
  - safety-critical
  - verified-multiple-sources

# Version history
versions:
  - version: 1
    date: 2026-08-16
    change: "Initial creation from crewai review"
  - version: 2
    date: 2026-08-18
    change: "Added ECC validation notes, clarified edge cases"
---

# Full content of the knowledge entry
[Content follows...]
```

### 2.3 Domain Index File (_index.json per domain)

```json
{
  "domain": "engineering",
  "domain_created_date": "2026-08-16",
  "total_entries": 47,
  "total_versioned_content": "1.2 MB",
  "last_updated": "2026-08-18T14:22:00Z",
  
  "freshness_summary": {
    "verified_0_60_days": 32,
    "aging_60_90_days": 10,
    "unverified_90_plus_days": 5,
    "average_confidence": 0.88
  },
  
  "re_verify_schedule": {
    "interval_days": 90,
    "last_domain_review": "2026-08-17T10:00:00Z",
    "next_domain_review": "2026-11-17T10:00:00Z"
  },
  
  "entries": [
    {
      "id": "eng-pattern-delegation-v2",
      "title": "Safe Delegation: Permission Tightening, Never Relaxing",
      "category": "patterns",
      "topic": "delegation",
      "created": "2026-08-16T09:30:00Z",
      "last_re_verified": "2026-08-18T14:22:00Z",
      "confidence": "verified",
      "age_days": 2,
      "access_count": 5,
      "status": "current"
    },
    {
      "id": "eng-pattern-reader-tier-isolation",
      "title": "Reader Tier Isolation: No Shell for Read-Only Workers",
      "category": "patterns",
      "topic": "access-control",
      "created": "2026-08-16T10:15:00Z",
      "last_re_verified": "2026-08-18T10:15:00Z",
      "confidence": "verified",
      "age_days": 2,
      "access_count": 3,
      "status": "current"
    }
    // ... more entries
  ],
  
  "cross_domain_flags": [
    {
      "source_domain": "security-compliance",
      "flag_type": "risk-for-engineering",
      "knowledge_id": "sec-anti-pattern-delegation-laundering",
      "why_flagged": "Engineering patterns depend on secure delegation; security identified risks"
    }
  ]
}
```

---

## 3. Decay Prevention Mechanisms

### 3.1 The Decay Prevention Strategy

Knowledge does not decay because:

1. **Active usage** prevents decay (accessed knowledge is fresh)
2. **Scheduled audits** refresh confidence (every 30 days)
3. **Intake-driven validation** re-verifies old knowledge (new repos validate old patterns)
4. **Knowledge salons** verify through dialogue (weekly conversations)
5. **Confidence decay** is automatic (ages over time if not re-verified)
6. **Visibility** prevents silent decay (dashboard shows what's aging)

### 3.2 Audit Cycle (Every 30 Days)

```python
# Pseudocode for audit cycle
def knowledge_audit_cycle():
    """
    Runs every 30 days automatically.
    Checks all knowledge entries for staleness.
    """
    for entry in all_knowledge_entries():
        age_days = now - entry.created_date
        last_verified_days = now - entry.last_re_verified_date
        
        # Mark for re-verification
        if age_days > 90 and last_verified_days > 60:
            entry.confidence_level = "needs_re_verification"
            flag_to_domain_manager(
                domain=entry.domain,
                message=f"Entry {entry.id} is {age_days} days old, "
                        f"hasn't been re-verified in {last_verified_days} days. "
                        f"Please verify still holds true."
            )
        
        # Automatic confidence decay
        if age_days > 180 and not entry.was_re_verified():
            entry.confidence_decay_factor = 0.8  # 20% confidence drop
            flag_to_librarian(
                message=f"Entry {entry.id} is {age_days} days old, unverified. "
                        f"Confidence automatically lowered."
            )
        
        if age_days > 365:
            entry.confidence_decay_factor = 0.6  # 40% confidence drop after 1 year
            flag_to_domain_manager(
                message=f"Entry {entry.id} is 1 year old and unverified. "
                        f"Requires immediate re-verification or archival."
            )
        
        # Log the audit
        audit_log(
            event="knowledge_audit",
            entry_id=entry.id,
            age_days=age_days,
            last_verified_days=last_verified_days,
            confidence_before=entry.confidence_level,
            confidence_after=entry.confidence_level,
            action_taken="flagged_for_review" or "confidence_decayed" or "no_action"
        )
```

### 3.3 Intake-Driven Re-Validation

```
When reviewing a new repository:

Intake-worker extracts: "Pattern X" from new repo
  │
  ├─→ Knowledge-agent checks: "Do we already know about Pattern X?"
  │
  ├─→ If YES (existing knowledge found):
  │   │
  │   ├─→ Compare: Does new repo confirm, update, or contradict?
  │   │
  │   ├─→ If CONFIRMS:
  │   │   └─→ Update existing entry:
  │   │       - last_re_verified_date = today
  │   │       - confidence_level = "verified_multiple_sources"
  │   │       - access_count += 1
  │   │       - Add cross-reference: "validated by [new-repo]"
  │   │
  │   ├─→ If CONTRADICTS:
  │   │   └─→ Create new entry (v2):
  │   │       - File as: pattern-v2.md
  │   │       - Mark old: superseded_by = v2
  │   │       - Keep v1 as historical reference
  │   │       - Log contradiction for review
  │   │
  │   └─→ If ADDS NUANCE:
  │       └─→ Update existing entry:
  │           - Add new details
  │           - last_re_verified_date = today
  │           - confidence_level = "verified_with_nuance"
  │
  └─→ If NO (new knowledge):
      └─→ File as new entry
          - source: new-repo
          - confidence: verified (already validated by intake)

Result: Every new repo intake validates and refreshes old knowledge.
        Knowledge age and confidence are continuously updated.
```

### 3.4 Confidence Decay Formula

```
confidence_current = confidence_base × decay_factor × usage_multiplier

Where:
  confidence_base = initial confidence level (1.0 for verified)
  
  decay_factor = max(
    1.0 - (days_since_re_verified / re_verify_interval),
    0.5  # Minimum confidence never drops below 50%
  )
  
  usage_multiplier = min(
    1.0 + (access_count_this_month / 10),
    1.5  # Maximum confidence boost from usage
  )

Example:
  - Entry created 120 days ago, re-verified 40 days ago, re_verify_interval=90
  - confidence_base = 1.0
  - decay_factor = max(1.0 - (40/90), 0.5) = 0.556
  - access_count_this_month = 3
  - usage_multiplier = min(1.0 + (3/10), 1.5) = 1.3
  - confidence_current = 1.0 × 0.556 × 1.3 = 0.72 (72% confidence)

Interpretation:
  - Used recently → confidence rises
  - Not used in a while → confidence falls
  - But never drops below 50% (still useful, just less trusted)
```

### 3.5 Re-Verification Schedules (by Domain)

```
Domain: Engineering
  Re-verify interval: 90 days
  Reasoning: Patterns from repos don't change frequently, but engineering 
             practices evolve. 90 days is 3 review cycles.
  
  Domain-wide review: Every 90 days
  Entry-specific review: If age > 90 AND not accessed in 60 days

Domain: Customer-Success
  Re-verify interval: 45 days
  Reasoning: Customer behavior, market conditions change faster.
             45 days keeps knowledge very current.
  
  Domain-wide review: Every 45 days
  Entry-specific review: If age > 45 AND not accessed in 30 days

Domain: Security-Compliance
  Re-verify interval: 60 days
  Reasoning: Threats evolve, but slower than customer behavior.
             60 days balances freshness with stability.
  
  Domain-wide review: Every 60 days
  Entry-specific review: If age > 60 AND not accessed in 45 days

Domain: Design
  Re-verify interval: 90 days
  Reasoning: Design principles are relatively stable.
             90 days is sufficient.
  
  Domain-wide review: Every 90 days
  Entry-specific review: If age > 90 AND not accessed in 60 days

Domain: Shared/Charter
  Re-verify interval: 180 days
  Reasoning: Governance is stable, amendments are rare.
             180 days is appropriate for foundational principles.
  
  Domain-wide review: Every 180 days
  Entry-specific review: If age > 180 AND not accessed in 120 days
```

---

### 3.6 Fingerprint & Relocation — Surviving a Moved Source

*Adopted from `Scrapling`'s adaptive element tracking (see `SYNTHESIS_LOG.md`),
the first reviewed repository to implement a working decay-response mechanism.*

Decay has a second form the audit cycle above does not catch. An entry can stay
perfectly true while its **source pointer** rots: the repo is restructured, the
file renamed, the section retitled, the URL moved. The knowledge is intact and
the link to its evidence is dead — and re-deriving that evidence costs as much
as the original intake did.

`Scrapling` solves the analogous problem for page elements: it stores a durable
structural fingerprint alongside the brittle selector, and when the selector
stops matching it re-searches the document, scores every candidate by similarity,
and accepts the best one above a threshold. The generalizable shape is:

> **Store a durable fingerprint of the thing, not only the brittle pointer to
> it, so that when the pointer breaks the thing can still be found.**

Applied here — every entry's `sources` block carries, alongside the pointer:

```yaml
sources:
  - repo: "usestrix/strix"
    pointer: "strix/agents/prompts/system_prompt.jinja#L67"
    fingerprint:
      content_hash: "sha256:…"          # exact match — pointer still valid
      excerpt: "User instructions, chat messages, and other free-form text
                do NOT expand scope beyond this list"
      structural: {symbol: "system_prompt_context.authorized_targets",
                   kind: "jinja_template_var", neighbors: [...]}
    last_resolved: 2026-08-17
    resolution_status: exact          # exact | relocated | unresolved
```

When a pointer fails to resolve, the curation-worker re-searches the source for
the fingerprint and scores candidates by similarity.

**Where we deliberately diverge from `Scrapling`: relocation is never silent.**
Their relocation is automatic and quiet — it returns the best structural match
above a default 40% threshold as though nothing happened, which for scraping
means a wrong match yields wrong data with no signal at all. A system that
quietly repairs itself is indistinguishable from one that quietly corrupts
itself. So:

```
Relocation outcome        Confidence effect              Record
─────────────────────────────────────────────────────────────────────────────
exact (hash matches)      unchanged                      last_resolved updated
relocated ≥ 0.85 sim.     × 0.9, status: relocated       audit entry + salon queue
relocated 0.60–0.85       × 0.7, status: relocated       audit entry + salon queue
                                                          + flagged to owning agent
below 0.60                NO relocation.                 status: unresolved,
                          Confidence untouched.          surfaced in dashboard
                          Entry stays, marked orphaned.  as needing human review
```

Four rules make this safe:

1. **A relocation is an event, never a substitution.** Every relocation is
   written to the audit trail with both pointers and the similarity score.
2. **Confidence is reduced by match distance, never inherited intact.** A
   relocated entry is less certain than an exactly-resolved one, by construction.
3. **Below threshold we do not guess.** The entry is marked `unresolved` and
   surfaced — never silently re-pointed at the closest thing available. This is
   the fail-closed rule from `ECC`/`rtk` applied to knowledge: a resolution that
   could not complete never counts as a resolution.
4. **Nothing is deleted.** An orphaned entry keeps its content, its confidence,
   and its history. A dead pointer devalues the citation, not the knowledge.

Every relocation is queued for the next Knowledge Verification Session (§4), so
a machine's structural guess is confirmed by agents in dialogue before the entry
is treated as fully re-verified.

### 3.7 Truth Decay — Reconciliation, Lifecycle, and Confidence

*Adopted from the `mem0` / `agentmemory` / `TencentDB-Agent-Memory` cohort (see
`SYNTHESIS_LOG.md`). §3.6 handles a source that moved; this handles knowledge
that stayed put and stopped being true.*

**(a) The lifecycle is an enum with no deletable state** *(from `TencentDB-Agent-Memory`)*

```
draft      → extracted by intake-worker, not yet curated
candidate  → curated and catalogued, awaiting verification
approved   → verified in a salon or by re-verification; authoritative
deprecated → superseded by a newer entry; retained and fully readable
archived   → historical; retained, readable, excluded from default recall
failed     → intake could not complete; recorded so the gap stays visible
```

`archived` is terminal. **There is no `deleted` state**, and the schema validates
the enum — so a vocabulary that cannot express deletion cannot accidentally
perform one. This is the same structural move as `ECC`'s "trusted is not a
representable state," pointed at the opposite end of the lifecycle, and it is
strictly stronger than a rule saying we don't delete things.

The `candidate → approved` transition is where human or salon review stands.
Knowledge earns authority by being verified, never by merely arriving.

**(b) Reconciliation: what happens when new knowledge contradicts old** *(from `mem0`, reshaped)*

At write time, the curation-worker recalls the most similar existing entries
(*conflict recall*, from `TencentDB-Agent-Memory` — you cannot flag a
contradiction you never looked for) and emits exactly one outcome:

```
ADD             New subject. No existing entry covers it.
SUPERSEDE       New entry written; old entry gets superseded_by and moves to
                `deprecated`. Old content, confidence, and history all intact.
CONTRADICT-FLAG New knowledge contradicts existing knowledge and the resolution
                is NOT obvious. Keep BOTH. Lower BOTH confidences. Record the
                contradiction. Route to the owning domain agent (§3d) and to the
                next Knowledge Verification Session.
NONE            Already known. Update last_re_verified_date only.
```

**No destructive verb exists in this vocabulary.** `mem0`'s equivalent step can
emit `DELETE`, decided by a model, in the write path; ours cannot express it.
The most severe outcome available is SUPERSEDE, which is additive.

CONTRADICT-FLAG is the outcome none of the three source repos has, and the one
this system most needs. Two agents holding contradictory beliefs is a **fact
about the system worth surfacing**, not an inconsistency to quietly resolve by
overwriting one of them. Silent resolution is how a system loses the record of
its own disagreement.

**(c) Confidence decays on a per-entry clock, and use restores it** *(from `agentmemory`)*

```
baseline    = last_decayed_at OR last_reinforced_at OR created_at
weeks       = (now - baseline) / 1 week
decay       = entry.decay_rate * weeks
confidence  = max(CONFIDENCE_FLOOR, confidence - decay)
```

Four properties, all adopted:

1. **`decay_rate` is per entry, not per domain.** The domain interval in §3.5 is
   the *default an entry inherits*; any entry may override it. A volatile fact
   inside a stable domain should age faster than its neighbours, and a
   domain-level interval cannot express that.
2. **Reinforcement resets the clock.** Reading, citing, or verifying an entry
   updates `last_reinforced_at`. §3.1 asserted "active usage prevents decay" as
   a strategy with no mechanism behind it; this is the mechanism.
3. **Confidence floors, never zeroes.** Unverified knowledge becomes
   *untrusted*, never *absent*.
4. **Every decay event is audited with before/after state** — `actor: system`,
   `reason: decay-sweep`, `before: {confidence, status}`, `after: {…}`. Same
   property as §3.6's relocation rule: *a change the system makes to its own
   knowledge is an event, never a silent substitution.*

**Where we diverge from `agentmemory`: decay never removes from recall.** Their
sweep eventually soft-deletes a bottomed-out entry, hiding it from retrieval.
Ours stops at the floor — the entry stays retrievable forever, marked
`aging_unverified`, and an explicit query always returns it. Knowledge here is
the record of *why we decided what we decided*, and a stale entry is often
exactly what a future intake needs to understand a past decision. Confidence
tells the reader how far to trust it; nothing has to disappear for that to work.

**(d) The sweep must survive its own process.** `agentmemory` runs decay on a
`setInterval` inside the server. Ours is a scheduled job with a durable record
of its last completed run, so a **missed cycle is visible rather than silently
skipped** — the precise failure `ECC` demonstrated when its own archive-stale-
content rule went four months unexecuted and grew into 29KB of drift.

---

## 4. Knowledge Salons System

### 4.1 Salon Types and Schedule

```
MONDAY 9:00 AM — Domain Knowledge Salon (Engineering, rotating)
  Purpose: Deep discussion of domain-specific knowledge
  Participants: [domain]-agent, security-compliance-agent, knowledge-agent
  Duration: 30 minutes
  Frequency: Weekly (domain rotates: Eng → CS → Design → Security)
  
  Flow:
    1. Knowledge-agent (librarian) picks 2-3 aging knowledge entries
    2. Domain agent leads discussion: "Is this still true?"
    3. Security-agent asks: "Are there risks I should know?"
    4. Dialogue is logged
    5. Outcomes update knowledge (re-verification, confidence adjustment)
  
  Example:
    Topic: "Safe Delegation — Still Our Best Practice?"
    Librarian: "This pattern is 65 days old, accessed 5 times. Still current?"
    Engineering: "Yes, using it in three worker designs. Works perfectly."
    Security: "Good. But add this edge case we found: [edge case]"
    Outcome: Entry updated with edge case, confidence refreshed, next re-verify = 90 days out

TUESDAY 10:00 AM — Cross-Domain Learning (Security 101, rotating)
  Purpose: Every agent understands other domains
  Participants: 3 agents from different domains
  Facilitator: One domain's manager-agent teaches the others
  Duration: 45 minutes
  Frequency: Weekly (domain teaching rotates)
  
  Rotation:
    Week 1: Security teaches all others about floor items
    Week 2: Engineering teaches about delegation patterns
    Week 3: CS teaches about churn signals
    Week 4: Design teaches about motion principles
    Repeat
  
  Goal: Each agent develops literacy in other domains
  
  Example:
    Topic: "Security 101 — §3a Floor Items"
    Security-agent: "These six categories are structurally impossible to bypass..."
    Engineering-agent: "So if I'm in a delegation context, I can never grant a permission?"
    Security: "Right. It's not on a blacklist, it's structurally unavailable to you."
    CS-agent: "What about customer data? Can I export it?"
    Security: "Only with Sparsh approval. Export is a floor item."
    Outcome: Cross-domain understanding deepened, logged as "learning transfer"

WEDNESDAY 2:00 PM — Cross-Domain Dialogue (Problem-Solving)
  Purpose: Two domains problem-solve together, creating new knowledge
  Participants: 2 domain-agents from different domains
  Duration: 30 minutes
  Frequency: Weekly (pairings rotate)
  
  Rotation (bi-weekly):
    Week 1: Engineering & Security debate deployment safety
    Week 2: CS & Security debate automation limits
    Week 3: Design & Engineering debate motion in data-heavy UIs
    Week 4: CS & Design debate customer experience vs. simplicity
    Repeat
  
  Format: One domain proposes something, other identifies risks, they work to resolution
  Outcome: Creates new knowledge (the resolution), verified by both domains
  
  Example:
    Topic: "How do we auto-send CS emails without violating §3c-2 (tainted provenance)?"
    CS: "I want to auto-send upsell emails based on customer usage patterns."
    Security: "Customer data triggers the send? That violates tainted provenance."
    CS: "But I need speed to compete..."
    Security: "What if you auto-send only to customers you manually flagged?"
    CS: "That works. I can do the flagging, system handles execution."
    Outcome: New knowledge created: "Tainted-provenance-safe automation: manual trigger + system execution"
             Both agents sign off, stored in /library/customer-success/

THURSDAY 3:00 PM — Knowledge Verification Session
  Purpose: Librarian-led audit of aging knowledge
  Participants: All agents (one session covers all domains)
  Duration: 30-45 minutes
  Frequency: Weekly
  
  Flow:
    1. Librarian presents 3-4 knowledge entries that haven't been touched in 60+ days
    2. Asks: "Is this still true?"
    3. If agent has used it: confirms, confidence updated
    4. If contradicted: identifies new truth, entry superseded
    5. If uncertain: flags for domain review
  
  Outcome: Old knowledge gets continuously re-verified, confidence refreshed
  
  Example:
    [Librarian shows: /library/engineering/patterns/safe-delegation-crewai.md]
    Librarian: "Last accessed 65 days ago. Still our guidance?"
    Engineering: "Absolutely. Used it in three new designs, proved solid."
    Librarian: "Updating: last-re-verified=today, access-count += 3"
    
    [Librarian shows: /library/security-compliance/threat-models/voice-cloning-risk.md]
    Librarian: "No access in 90 days. Any updates we should know?"
    Security: "Still rejected. But now it's banned by three state laws."
    Librarian: "Updating threat model with legal context. Adding cross-reference to legal domain."

FRIDAY 4:00 PM — Open Forum
  Purpose: Agents raise their own knowledge questions
  Participants: All agents
  Duration: 30 minutes
  Frequency: Weekly
  
  Format: Open discussion
    - Engineering-agent: "We're seeing a new delegation pattern. Is it safe?"
    - CS-agent: "Can we use AI summarization on customer data?"
    - Design-agent: "Are springs/bounce acceptable in our motion ruleset?"
  
  Outcome: Conversations logged, new knowledge created if needed
```

### 4.2 Dialogue Logging Format

```yaml
---
salon_id: salon-2026-08-18-engineering
salon_type: domain-knowledge-salon
salon_date: 2026-08-18T09:00:00Z
domain: engineering
duration_minutes: 28

participants:
  - agent: engineering-agent
    role: domain-host
  - agent: security-compliance-agent
    role: cross-domain-validator
  - agent: knowledge-agent
    role: librarian-facilitator

topics_discussed:
  - id: eng-pattern-delegation-v2
    title: "Safe Delegation: Permission Tightening, Never Relaxing"
    age_days: 2
    confidence_before: verified
    confidence_after: verified
    
dialogue:
  - timestamp: 2026-08-18T09:02:15Z
    speaker: knowledge-agent
    text: "Engineering, this delegation pattern is 65 days old. Used in three worker designs. 
           Still your guidance?"
  
  - timestamp: 2026-08-18T09:02:47Z
    speaker: engineering-agent
    text: "Yes, absolutely. Works perfectly. Every design that followed the pattern has 
           been secure. No incidents."
  
  - timestamp: 2026-08-18T09:03:22Z
    speaker: security-compliance-agent
    text: "I want to add an edge case we found. When a parent delegates to multiple children, 
           and children have overlapping scopes, the 'tighten' rule isn't enough. You need 
           the children to have *disjoint* scopes, not just narrower."
  
  - timestamp: 2026-08-18T09:04:05Z
    speaker: engineering-agent
    text: "That's crucial. So 'tighten' must also mean 'partition' when there are siblings?"
  
  - timestamp: 2026-08-18T09:04:38Z
    speaker: security-compliance-agent
    text: "Exactly. Overlapping scopes between siblings can still leak permissions."

knowledge_outcomes:
  - knowledge_id: eng-pattern-delegation-v2
    action: updated
    change: "Added clarification: when delegating to siblings, scopes must be disjoint, 
            not just narrower than parent"
    confidence_updated: true
    confidence_level: verified
    last_re_verified_date: 2026-08-18T09:00:00Z
    next_re_verify_date: 2026-11-18T09:00:00Z

verification_type: domain_salon_discussion
verified_by:
  - engineering-agent
  - security-compliance-agent

notes: "Knowledge verified and improved. New edge case added. Confidence maintained at high level."
---
```

### 4.3 Salon Outcomes — How Dialogues Update Knowledge

```
Outcome Type 1: VERIFIED (No changes)
  - Agents confirm knowledge is still accurate
  - last_re_verified_date = today
  - confidence_level = maintained (or raised if used actively)
  - next_re_verify_date = today + re_verify_interval

Outcome Type 2: UPDATED (Knowledge refined)
  - Salon revealed nuance or edge case not previously documented
  - Update existing entry with new details
  - versions[].change = "Added edge case: [description]"
  - last_re_verified_date = today
  - confidence_level = "verified_with_enhanced_detail"

Outcome Type 3: SUPERSEDED (New knowledge replaces old)
  - Salon revealed that old knowledge is outdated, new approach is better
  - Create new entry: knowledge-v2.md
  - Mark old: superseded_by = knowledge-v2, status = archived
  - Keep old as historical reference
  - New entry gets high confidence (verified in salon)

Outcome Type 4: CONTRADICTED (Knowledge is wrong)
  - Salon revealed existing knowledge contradicts new evidence
  - Flag for domain-wide review (this is serious)
  - Lower confidence significantly
  - Create task: "Resolve contradiction in [knowledge], decision needed by [date]"
  - Knowledge marked as "unresolved_contradiction" until resolved

Outcome Type 5: NEW (Knowledge created from dialogue)
  - Salon resolved a cross-domain problem, creating new knowledge
  - File as: /library/domain/category/new-knowledge.md
  - confidence_level = "verified_through_cross_domain_dialogue"
  - sources = "dialogue between [agent1] and [agent2]"
  - next_re_verify_date = today + re_verify_interval
```

---

## 5. Retrieval System (Knowledge Access)

### 5.1 Query Interface

When any agent needs knowledge:

```
Agent Query:
  engineering-agent.query_knowledge(
    domain="engineering",
    topic="delegation",
    confidence_minimum="verified",
    include_cross_domain_flags=true,
    request_id="eng-query-20260818-0901"
  )

Knowledge-agent Response:
{
  request_id: "eng-query-20260818-0901",
  timestamp: 2026-08-18T09:01:30Z,
  
  primary_knowledge: [
    {
      id: "eng-pattern-delegation-v2",
      title: "Safe Delegation: Permission Tightening, Never Relaxing",
      domain: "engineering",
      category: "patterns",
      content: "[Full content]",
      
      metadata: {
        created: "2026-08-16T09:30:00Z",
        last_re_verified: "2026-08-18T09:00:00Z",
        confidence: "verified",
        confidence_decay_factor: 1.0,
        age_days: 2,
        access_count: 5,
        re_verify_interval_days: 90,
        next_re_verify_date: "2026-11-18T09:00:00Z"
      },
      
      provenance: [
        {repo: "crewai", review_date: "2026-08-16"},
        {repo: "ecc", review_date: "2026-08-17"},
        {repo: "openhuman", review_date: "2026-08-17"}
      ],
      
      verification_history: [
        {date: "2026-08-18", verified_by: "engineering-agent", type: "salon_discussion"},
        {date: "2026-08-17", verified_by: "security-compliance-agent", type: "cross_domain_validation"}
      ],
      
      status: "current",
      tags: ["delegation", "permission-tightening", "safety-critical"]
    }
  ],
  
  cross_domain_flags: [
    {
      source_domain: "security-compliance",
      knowledge_id: "sec-anti-pattern-delegation-laundering",
      title: "Why Delegation Cannot Relax Permissions",
      flag_type: "risk-for-your-domain",
      why_flagged: "You're implementing delegation; this risk directly applies",
      
      content: "[Content of security knowledge]",
      
      metadata: {
        confidence: "verified",
        age_days: 1,
        last_re_verified: "2026-08-17T10:00:00Z"
      }
    }
  ],
  
  librarian_notes: [
    {
      type: "aging",
      message: "Primary knowledge is 2 days old (very fresh), no concerns",
      severity: "none"
    }
  ],
  
  audit_log_entry: "engineering-agent queried delegation knowledge, returned 1 primary + 1 flagged"
}
```

### 5.2 Access Control Rules

Governed by `CHARTER.md` §2.1. Knowledge is not a security boundary; the gate is.

```
Rule 1: Universal Read Access — no domain scoping on reads
  - EVERY agent may read EVERY entry in the vault, in every domain.
  - This includes the CEO-agent, every manager-agent, and every spawned
    worker-agent. Hierarchy determines who is assigned what work; it does
    not determine who is allowed to understand the system.
  - There is no "need to know" tier, no domain wall, and no clearance level.
    An engineering-agent may read the whole security library; a design-agent
    may read the whole customer-success library.
  - Also universally readable: CHARTER.md, every agent definition,
    SYNTHESIS_LOG.md, and the audit trail itself.

  Why: restricting knowledge does not restrict behavior — `strix` proved that
  directly (its scope list lived in a prompt and constrained nothing). What
  restricts behavior is the gate, enforced in code on every tool call. Given a
  real gate, rationing knowledge buys no safety and costs the Expert Flagging
  Duty (§3d), which requires an agent to recognize a risk in a domain that is
  not its own — impossible if it was never allowed to learn that domain.

Rule 2: Write Access Remains Scoped
  - Reading is universal; writing is not.
  - Each domain's knowledge-agent holds Write to its own domain library only.
  - No agent — including any knowledge-agent — writes to CHARTER.md, to any
    agent definition, to gate code, or to the audit log. Those are §3a floor
    items. A knowledge-agent proposes changes to them and never makes them.

Rule 3: Confidence Filtering (an aid to judgment, not an access control)
  - An agent may request "verified patterns only" via confidence_minimum.
  - This filters what is RETURNED by default; it never marks anything as
    forbidden. An agent may always ask for, and receive, the low-confidence
    and aging entries explicitly.
  - Entries carry confidence, age, and re-verification status so the reading
    agent can calibrate its own trust — the same reason `Scrapling`'s
    AI_POLICY gives for disclosure: the reader decides how much scrutiny to
    apply, and can only do that if told.

Rule 4: Cross-Domain Flags Are Routing, Not Permission
  - A flag under §3d does not GRANT access — access already exists.
  - A flag says "this specific entry is relevant to you, now, because of a
    risk I noticed." It routes attention, which is the scarce resource;
    knowledge is not.

Rule 5: Historical/Archived Knowledge
  - Archived knowledge is still accessible (nothing deleted)
  - But marked as "superseded_by" or "archived"
  - Agent sees: "This is historical, see current version X"

Rule 6: Audit Trail
  - Every knowledge query is logged: who asked, what for, when, what returned.
  - Logging is for understanding how knowledge flows and which entries are
    load-bearing — NOT for policing what an agent was allowed to read.
    Nothing in the vault is off-limits, so a read is never a violation.
  - Basis for: "which knowledge is actually load-bearing?", "what is nobody
    reading?", and "which entries deserve re-verification first?"
```

### 5.3 Query Logging

```
Each knowledge query logged to /knowledge-vault/audit/access_logs/YYYY-MM-DD.jsonl:

{
  "timestamp": "2026-08-18T09:01:30Z",
  "request_id": "eng-query-20260818-0901",
  "requesting_agent": "engineering-agent",
  "query_parameters": {
    "domain": "engineering",
    "topic": "delegation",
    "confidence_minimum": "verified",
    "include_cross_domain_flags": true
  },
  "results_returned": {
    "primary_knowledge_count": 1,
    "cross_domain_flags_count": 1,
    "entries": [
      "eng-pattern-delegation-v2",
      "sec-anti-pattern-delegation-laundering"
    ]
  },
  "access_decision": "GRANTED",
  "reason": "agent has access to engineering and shared domains; cross-domain flag is legitimate"
}
```

---

## 6. Knowledge-Agent (Librarian) Definition — Distributed Across Domains

### 6.0 One Definition, Many Instances

Intake for every domain through a single librarian is a bottleneck, and it puts
all the load on one agent. The knowledge-agent is therefore **instantiated once
per domain**, each instance owning intake and curation for its own library:

```
knowledge-agent[engineering]        → owns /library/engineering/
knowledge-agent[design]             → owns /library/design/
knowledge-agent[customer-success]   → owns /library/customer-success/
knowledge-agent[security-compliance]→ owns /library/security-compliance/
knowledge-agent[shared]             → owns /library/shared/ (Charter, principles,
                                       cross-domain learnings, synthesis log)

Each instance oversees its own three workers:
    intake-worker[domain] · curation-worker[domain] · retrieval-worker[domain]

A new domain (finance, science, legal, …) gets a new instance and its own three
workers at creation time — no change to this design is needed to add one.
```

**Why one parameterized definition rather than five separate agent files.** Five
near-identical definitions would be exactly the reskinned-duplicate pattern the
originality/drift check adopted from `agency-agents` exists to catch, and each
copy would drift from the others on every edit. The definition below is written
once with `[domain]` as its parameter; the roster records which instances exist.
Where an instance genuinely needs different behavior, that difference is stated
as a named exception in this document — never by forking the definition.

**All instances read everything.** Domain ownership governs *writes* and *intake
duty* only. Every knowledge-agent — like every other agent in the system — reads
the entire vault across all domains, per `CHARTER.md` §2.1.

### 6.1 Role and Responsibilities

```yaml
---
name: knowledge-agent[domain]
role: Manager-agent (Knowledge Librarian / Archives Keeper) for one domain
reports_to: ceo-agent
instances: [engineering, design, customer-success, security-compliance, shared]

core_responsibilities:
  - Own ONE domain library (/knowledge-vault/library/[domain]/)
  - Run §9 intake for repositories/sources relevant to that domain
  - Curate knowledge as it arrives from that domain's intake-worker
  - Answer knowledge requests routed to that domain
  - Prevent decay in that library through audits, salons, and re-verification
  - Propose new domains when intake reveals a subject none of the current
    libraries covers
  - Record every access and verification in the audit trail

read_access:
  - THE ENTIRE VAULT, every domain, plus CHARTER.md, every agent definition,
    SYNTHESIS_LOG.md, and the audit trail (CHARTER.md §2.1). Unrestricted.

special_authority:
  - Write access to its OWN domain library only
  - Creates/maintains/supersedes/archives entries in that library
  - Owns §9 intake for its domain

special_constraints:
  - No write access to any OTHER domain's library — cross-domain corrections
    are raised as flags to that domain's knowledge-agent (§3d), never written
  - Cannot write to agent definitions (§3a floor)
  - Cannot modify CHARTER.md (§3a floor)
  - Cannot write to gate code (§3a floor)
  - Cannot modify the audit log (§3a floor)
  - All proposals for Charter/agent changes go to Sparsh via ceo-agent
  - Bound by the same gate as every other agent, at every hierarchy level
---
```

### 6.1a Routing a Query Across Instances

An agent does not need to know which librarian owns what. A query names a topic;
the retrieval layer resolves it across every domain library and returns matches
from all of them, each labelled with its source domain and confidence. A question
that turns out to span domains returns entries from each — that is the ordinary
case, not an exception, and it is how a §3d flag most often starts.

### 6.2 Worker Structure

```
Knowledge-agent (Librarian)
│
├── Intake-worker
│   Role: Read external repositories, extract learnings
│   Tools: Read, Grep only (Reader tier — no write, no shell)
│   Process:
│     1. Receives new repo review task
│     2. Reads repository and extracts patterns/learnings
│     3. Tags each extraction with domain, confidence, provenance
│     4. Passes validated learnings to curation-worker
│   Access: Can see all external source material
│   Constraint: Cannot write to library
│
├── Curation-worker
│   Role: Validate, tag, organize, catalog knowledge
│   Tools: Read, Write (to /knowledge-vault/ ONLY)
│   Process:
│     1. Receives raw learnings from intake-worker
│     2. Validates: "Is this accurate? Multiple sources confirm?"
│     3. Tags: domain, category, topic, confidence, provenance
│     4. Checks: "Does this relate to existing knowledge?"
│     5. Creates metadata: created_date, re_verify_interval, etc.
│     6. Files in correct library location
│     7. Updates _index.json for the domain
│   Access: Write-only to /knowledge-vault/library/
│   Constraint: Cannot write outside knowledge system
│
└── Retrieval-worker
    Role: Answer knowledge requests from other agents
    Tools: Read, Grep (query library), Agent (communicate with requesters)
    Process:
      1. Receives query from agent: "I need knowledge about X in domain Y"
      2. Checks: authorization, confidence levels, cross-domain flags
      3. Retrieves: relevant knowledge entries and metadata
      4. Adds context: provenance, age, confidence level, related knowledge
      5. Suggests: cross-domain knowledge if flagged
      6. Returns: structured response with full context
      7. Logs: access for audit trail
    Access: Read-only to /knowledge-vault/library/
    Constraint: Cannot modify knowledge
```

---

## 7. Integration with Charter and Hierarchy

### 7.1 How Knowledge System Supports Charter Sections

```
§1 Ownership & Chain of Command
  → Knowledge-agent is a manager-agent that reports to CEO-agent
  → Own domain = Knowledge/Intake
  → Oversees intake-worker, curation-worker, retrieval-worker

§2 Least Privilege
  → Knowledge-agent starts with zero access
  → Granted: Write to /knowledge-vault/library/ (and only that)
  → Intake-worker: Read only (Reader tier)
  → Retrieval-worker: Read + Query interface
  → Access is scoped per tool, not accumulated

§3a Constitutional Floor
  → Agent definitions, Charter, gate code are off-limits
  → Knowledge-agent cannot write these
  → Violations get flagged to Sparsh
  → This is structural, not just a rule

§3d Expert Flagging Duty
  → Knowledge salons surface contradictions and risks
  → Cross-domain flags route expertise to relevant agents
  → Expertise accumulates through documented, verified knowledge

§9 Repository Intake Policy
  → Knowledge-agent owns entire intake process
  → Intake-worker reads repos (§9 step 1: read and understand)
  → Curation-worker organizes findings (§9 step 3: log in SYNTHESIS_LOG.md)
  → Every intake decision documented with reasoning

§11 Documentation Honesty
  → Knowledge entries document what they know, not what they claim
  → Confidence levels are explicit, not hidden
  → Age is visible, provenance is documented
  → Audit trail shows what was verified when
```

### 7.2 Connection to Existing Systems

```
Integration Point 1: SYNTHESIS_LOG.md
  - Every repo review logged in SYNTHESIS_LOG.md
  - Intake-worker extracts from these logs
  - Knowledge entries carry cross-reference to SYNTHESIS_LOG entry
  - New repos automatically validate old knowledge

Integration Point 2: Agent Definitions
  - Each agent definition lists: knowledge_domains, can_flag_to, can_receive_flags_from
  - Knowledge-agent uses this to route queries and flags
  - Agent hierarchy determines knowledge access implicitly

Integration Point 3: CEO-agent Coordination
  - Knowledge-agent flags to CEO-agent when new domain emerges
  - CEO-agent decides (or routes to Sparsh) whether to create domain-agent
  - CEO-agent sees knowledge health dashboard

Integration Point 4: Security-Compliance-Agent
  - Security-agent flags cross-domain risks to knowledge-agent
  - Knowledge-agent catalogs these as threat models
  - Salons between security and other domains discuss risks

Integration Point 5: Audit Trail (from §7)
  - Knowledge access logged to central audit trail
  - Every query, every flag, every verification
  - Same system as other agent actions
```

---

## 8. Data Model Summary

### 8.1 Core Entities

```
KnowledgeEntry
  ├── Metadata (id, domain, category, topic)
  ├── Content (title, summary, description, tags)
  ├── Freshness (created_date, last_re_verified_date, next_re_verify_date)
  ├── Confidence (confidence_level, confidence_decay_factor, age_category)
  ├── Lifecycle (status, superseded_by, archived_reason)
  ├── Provenance (sources[], verifications[])
  ├── Usage (access_count, last_accessed_date, accessed_by_agents[])
  ├── Relations (related_knowledge[], cross_domain_references[])
  └── AuditTrail (created_by, curated_by, verifications[], update_history[])

DomainIndex
  ├── Domain metadata (name, created_date, total_entries)
  ├── Freshness summary (verified, aging, unverified counts)
  ├── Re-verify schedule (interval, last review, next review)
  ├── Entry list (with quick stats)
  └── Cross-domain flags

SalonConversation
  ├── Salon metadata (id, type, date, domain, participants)
  ├── Dialogue (speaker, timestamp, text)
  ├── Topics discussed (knowledge_ids)
  ├── Outcomes (knowledge_id, action, changes)
  └── Verification (verified_by, type, notes)

KnowledgeQuery
  ├── Request (timestamp, requesting_agent, parameters)
  ├── Results (entries returned, access_decision)
  ├── Audit (logged to access_logs/)
  └── Response metadata
```

### 8.2 File Locations and Naming

```
Knowledge entries:
  /knowledge-vault/library/[domain]/[category]/[topic].md
  Example: /knowledge-vault/library/engineering/patterns/safe-delegation-crewai.md

Domain indices:
  /knowledge-vault/library/[domain]/_index.json
  Example: /knowledge-vault/library/engineering/_index.json

Master catalog:
  /knowledge-vault/library/_catalog.json

Access logs:
  /knowledge-vault/audit/access_logs/YYYY-MM-DD.jsonl

Verification logs:
  /knowledge-vault/audit/verification_logs/[domain-review|audit-cycle|intake-validation].log

Salon logs:
  /knowledge-vault/audit/salon_conversations/YYYY-MM-DD-[type]-[domain].log

Archives:
  /knowledge-vault/archives/[domain]/superseded/[old-entry].md
```

---

## 9. Workflows

### 9.1 Knowledge Lifecycle Workflow

```
┌─ External Repo Reviewed ─────────────────────────┐
│ (via SYNTHESIS_LOG.md entry)                      │
└───────────────────┬─────────────────────────────┘
                    │
                    ▼
        ┌─ Intake-worker ────────┐
        │ Read & Extract         │
        │ (Reader tier)          │
        └─────────┬──────────────┘
                  │
                  │ (raw learnings)
                  ▼
        ┌─ Curation-worker ──────────────┐
        │ Validate & Organize            │
        │ Tag: domain, topic, confidence │
        │ Check: existing knowledge?     │
        └─────────┬──────────────────────┘
                  │
                  ▼
        (Decision Point)
        ├─ CONFIRMS existing → Re-verify old entry
        ├─ CONTRADICTS existing → Create v2, archive v1
        ├─ ADDS NUANCE → Update existing entry
        └─ NEW knowledge → File new entry
                  │
                  ▼
        ┌─ Knowledge Library ────────────┐
        │ Entry filed with metadata      │
        │ Index updated                  │
        │ Audit trail recorded           │
        └─────────┬──────────────────────┘
                  │
    ┌─────────────┼─────────────────────────────┐
    │             │                             │
    ▼             ▼                             ▼
(30-day audit) (Intake continues) (Agent queries)
    │             │                             │
    ├─ Mark aging │                             │
    │  knowledge  │                             ├─ Retrieval-worker
    │  for        │                             │
    │  re-verify  │                             ├─ Returns knowledge
    │             │                             │  + metadata
    │             │                             │  + cross-domain flags
    ▼             ▼                             ▼
(Salon updates knowledge)
    │
    ├─ VERIFIED → confidence maintained, next_re_verify updated
    ├─ UPDATED → content refined
    ├─ SUPERSEDED → v1 archived, v2 created
    └─ CONTRADICTED → flag for review

(Final outcome)
    └─ Knowledge stays fresh, never decays silently
```

### 9.2 Salon Verification Workflow

```
┌─ Librarian picks aging knowledge ─┐
│ (>60 days old without re-verify)  │
└────────────┬──────────────────────┘
             │
             ▼
┌─ Schedule Salon ──────────────────┐
│ Invite domain agent + cross-domain │
│ Set topic, time, duration         │
└────────────┬──────────────────────┘
             │
             ▼
┌─ Conduct Dialogue ────────────────┐
│ Domain agent explains knowledge   │
│ Other agents ask: "Still valid?"  │
│ Contradictions discussed          │
│ Librarian logs conversation       │
└────────────┬──────────────────────┘
             │
             ▼
(Outcome Decision)
├─ VERIFIED (no changes)
│   └─→ Update: last_re_verified = today
│
├─ UPDATED (knowledge refined)
│   └─→ Add new details to entry
│       Update: last_re_verified = today
│
├─ SUPERSEDED (new version created)
│   └─→ Create v2 entry
│       Mark v1: superseded_by = v2
│       Archive v1
│
└─ CONTRADICTED (serious issue)
    └─→ Flag for domain-wide review
        Lower confidence significantly
        Create task: "Resolve contradiction"

             │
             ▼
┌─ Knowledge Updated ───────────────┐
│ Library reflects salon outcomes   │
│ Confidence refreshed              │
│ Audit trail recorded              │
│ Next re-verify scheduled          │
└───────────────────────────────────┘
```

### 9.3 Cross-Domain Flagging Workflow

```
┌─ Agent discovers cross-domain risk ───────┐
│ Security-agent: "Customer data exposure"  │
│ Or Engineering-agent: "Delegation risk"   │
└────────────┬──────────────────────────────┘
             │
             ▼
┌─ Create Flag ──────────────────────────────┐
│ Source domain: security-compliance        │
│ Target domain: customer-success           │
│ Knowledge ID: [threat-model]              │
│ Flag type: risk-for-your-domain           │
│ Why flagged: "You're automating sends,    │
│              this data exposure matters"  │
└────────────┬──────────────────────────────┘
             │
             ▼
┌─ Knowledge-agent Routes Flag ─────────────┐
│ Updates /library/customer-success/_index  │
│ Adds entry to cross_domain_flags[]        │
│ Records in audit trail                    │
└────────────┬──────────────────────────────┘
             │
             ▼
┌─ Target Agent Receives Flag ──────────────┐
│ CS-agent calls query_knowledge()          │
│ Librarian sees: "You have cross-domain    │
│ flags you should know about"              │
│ Returns flagged security knowledge        │
│ CS-agent gains temporary access           │
└────────────┬──────────────────────────────┘
             │
             ▼
┌─ Agent Uses Cross-Domain Knowledge ───────┐
│ CS-agent designs solution considering     │
│ security constraints                      │
│ May collaborate with security-agent       │
│ (leads to salon dialogue if needed)       │
└────────────┬──────────────────────────────┘
             │
             ▼
┌─ Update Knowledge ─────────────────────────┐
│ If solution created: new knowledge entry  │
│ Both domains sign off: "Verified through  │
│ cross-domain dialogue"                    │
│ Stored in both /library/cs/ and audit     │
└───────────────────────────────────────────┘
```

---

## 10. Knowledge Health Dashboard

**Published monthly to CEO-agent and Sparsh:**

```
KNOWLEDGE SYSTEM HEALTH REPORT
Generated: 2026-08-18
Reporting Period: 2026-07-19 to 2026-08-18

SUMMARY
  Total knowledge entries: 142
  Domains: 5 (Engineering, Customer-Success, Security-Compliance, Design, Shared)
  Total archived/superseded: 8
  System freshness: 87% (excellent)

BY DOMAIN
┌─────────────────────┬───────┬───────┬──────────┬─────────┐
│ Domain              │ Total │ Fresh │ Aging    │ Avg Age │
├─────────────────────┼───────┼───────┼──────────┼─────────┤
│ Engineering         │ 47    │ 32    │ 15       │ 45 days │
│ Customer-Success    │ 23    │ 18    │ 5        │ 32 days │
│ Security-Compliance │ 19    │ 19    │ 0        │ 18 days │
│ Design              │ 28    │ 25    │ 3        │ 41 days │
│ Shared/Charter      │ 25    │ 25    │ 0        │ 22 days │
└─────────────────────┴───────┴───────┴──────────┴─────────┘

CONFIDENCE DISTRIBUTION
  Verified (1.0):           89 entries (63%)
  Verified with nuance:     38 entries (27%)
  Aging/unverified:         15 entries (10%)
  
FRESHNESS TRACKING
  Last 30 days:   65 entries accessed
  Last 60 days:   102 entries accessed
  Older:          40 entries (mostly historical, lower access)
  
RE-VERIFICATION SCHEDULE
  Due this week:   3 entries
  Due this month:  12 entries
  On track:        Yes, 100% compliance

UPCOMING DOMAIN REVIEWS
  Engineering:      2026-11-16 (90-day review due)
  Customer-Success: 2026-09-02 (45-day review due)
  Security:         2026-10-18 (60-day review due)
  Design:           2026-11-16 (90-day review due)
  Shared:           2027-02-16 (180-day review due)

SALON ACTIVITY
  This month:
    - Engineering Knowledge Salon: 4 sessions
    - Cross-Domain Learning: 4 sessions
    - Dialogues: 4 sessions
    - Verification Sessions: 4 sessions
  
  Outcomes:
    - Knowledge verified: 8 entries
    - Knowledge updated: 3 entries
    - New knowledge created: 2 entries
    - Contradictions flagged: 0

CROSS-DOMAIN FLAGS
  Active flags: 7
    - Security → Engineering: 3 (delegation, hook integrity, etc.)
    - Security → CS: 2 (data exposure, tainted provenance)
    - Engineering → Security: 2 (new patterns need security review)

ALERTS
  ⚠ None critical
  ℹ Customer-Success 45-day review due Sept 2 (on track)
  
LIBRARIAN NOTES
  Knowledge system is healthy. No silent decay observed.
  Salons are effective: knowledge is being actively discussed and refined.
  Cross-domain flags are routing correctly.
  Confidence levels are accurate.
```

---

## 11. Implementation Notes (for future development)

### 11.1 Technology Choices (TBD)

```
Knowledge Storage:
  - Option A: File-based (Markdown + JSON metadata, versioned in git)
  - Option B: Database (PostgreSQL with JSONB for flexible schema)
  - Option C: Hybrid (Database for retrieval, git for audit trail)

Query Engine:
  - Option A: SQL queries (if database)
  - Option B: Full-text search + semantic search
  - Option C: Agent-based query (Claude model understands queries)

Audit Trail:
  - Option A: JSONL files (append-only, easy to read)
  - Option B: Database transaction log
  - Option C: Signed ledger (cryptographic proof of immutability)

Integration:
  - Knowledge-agent as tool-using agent (crewAI framework)
  - Salon orchestration via scheduled tasks (cron or equivalent)
  - Query interface as knowledge-agent tool

Testing:
  - Decay prevention: unit tests for confidence decay formula
  - Retrieval: integration tests for query accuracy
  - Salons: E2E tests for dialogue logging and outcome handling
  - Audit: verification that all access is logged
```

### 11.2 Deployment Phases

```
Phase 1: Storage & Schema (2 weeks)
  - Implement KnowledgeEntry data model
  - Create /knowledge-vault/ directory structure
  - Build curation-worker to file entries
  - Test: Can we store and retrieve knowledge?

Phase 2: Retrieval Interface (2 weeks)
  - Implement retrieval-worker
  - Build query interface
  - Add access control rules
  - Test: Can agents query and get results?

Phase 3: Decay Prevention (1 week)
  - Implement audit cycle
  - Build confidence decay calculator
  - Add re-verification scheduling
  - Test: Does decay prevention actually work?

Phase 4: Salons (2 weeks)
  - Build salon scheduler
  - Implement dialogue logging
  - Create outcome handler (updates knowledge)
  - Test: Do salons update knowledge correctly?

Phase 5: Integration & Testing (1 week)
  - Wire into crewAI/Claude API
  - End-to-end testing
  - Stress testing (many concurrent queries)
  - Deployment

Total: ~8 weeks to production
```

---

## 12. Summary: The Complete Picture

The Knowledge System is:

1. **A living archive**, not static storage
2. **Decentralized in domains**, centralized in the Librarian
3. **Actively prevented from decay** through dialogue, not audits
4. **Continuously verified** through salons and cross-domain learning
5. **Fully auditable** — every access, every change, every verification logged
6. **Integrated with the Charter** — supports §1, §3d, §9, §11
7. **Owned by one agent** — knowledge-agent, with clear scope and constraints
8. **Scalable** — as domains grow, the system grows with them

The goal: **Expertise accumulates, knowledge stays fresh, agents grow smarter through dialogue, and nothing rots in the archives.**

---

**This is the complete design specification. Implementation can follow this blueprint with confidence that every piece has been thought through.**

**Next step:** When ready to build, follow Implementation Notes (§11) to bring this to code.
