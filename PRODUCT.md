<!-- yourider:product-schema 1 -->

# Product

This file captures durable product truth — the things that shouldn't change
week to week. Claude Code should read this before any UI or UX work in
`/src/interfaces` so design decisions are consistent across sessions instead
of reinvented each time. Update it when something here actually changes;
don't let it silently go stale while the product does.

## Platform

web

## Users

[fill in — who actually uses Yourider day to day? e.g. "Sales reps managing
their own pipeline" / "Support agents triaging tickets" / "Ops managers
reviewing team-wide dashboards." List the primary user type(s) — this
drives information density, jargon level, and what's above the fold.]

## Product purpose

Yourider is a CRM: leads, pipelines, deals, and accounts, with multi-agent
chat interfaces assisting the humans who work them (see `CLAUDE.md` for the
technical architecture). This file is about how it should *feel* to use, not
how it's built.

## Brand personality (three words)

[fill in — e.g. "Direct, fast, unfussy" or "Warm, structured, trustworthy."
Pick three words that would make a design choice obviously right or
obviously wrong. Vague words like "modern" or "clean" don't count — they
don't rule anything out.]

## Anti-references

Named things Yourider should NOT look like, and why:

- [fill in — e.g. "Not a generic AI-purple-gradient SaaS landing page — we're
  a working tool, not a pitch deck."]
- [fill in — e.g. "Not as dense/cluttered as <specific legacy CRM>, even
  though we're a data-heavy tool."]

(Leave this section thin rather than padded — one or two real anti-references
that would actually stop a bad design choice are worth more than five vague
ones.)

## Design principles

- Data-dense views (pipelines, lead lists) prioritize scanability over
  decoration — a CRM is used dozens of times a day, not admired once.
- Agent-authored content (drafts, scores, recommendations) must be visually
  distinguishable from human-authored/human-confirmed content — never let an
  AI draft look identical to a sent, human-approved action.
- [fill in any additional principles specific to how you want Yourider to
  feel to use]

## Accessibility commitments

- WCAG AA contrast minimum on all text and interactive elements.
- All agent-approval prompts (see `CLAUDE.md` §3 approval gate) must be
  operable via keyboard, not mouse-only.
- [fill in any additional commitments]
