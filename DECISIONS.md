# Decisions

Append only. Newest at the bottom.

## 2026-11-02: Fresh start as a Shopify store workspace

- Old `README.md` and `CLAUDE.md` removed at the owner's request. New `CLAUDE.md` holds the owner's style rules, instruction priority, and the Shopify approval list.
- Plugins declared at project scope in `.claude/settings.json`, so every session gets the same setup.
- ECC installed but disabled by default. Its always-on cost is about 48k tokens per session, measured with `claude plugin details ecc@ecc`.
- From alirezarezvani/claude-skills, only the marketing, business-growth, finance, and commercial packs are enabled. The full set has 100+ packs, mostly unrelated to a store.
- From agency-agents, 27 store-relevant agents copied into `.claude/agents/`. Each has an "Owner Rules" footer that puts the owner and `CLAUDE.md` first.
- Emil Kowalski skills and the Agent Reach skill vendored into `.claude/skills/` (both MIT).
- Headroom, Agent Reach, and crewAI are Python CLIs. Cloud containers are temporary, so `.claude/hooks/setup-tools.sh` reinstalls them. It is not yet registered as a SessionStart hook in `.claude/settings.json`: that needs the owner's OK.
- No Shopify API connection yet. All store changes stay owner-approved.
