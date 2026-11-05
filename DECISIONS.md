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

## 2026-11-03: Store connected and audited

- Store "Cradlebaby" connected through the claude.ai Shopify connector (not a custom Dev Dashboard app). Read-only audit done, findings in `LAUNCH_PLAN.md`.
- The connector app has wide write scopes. Owner approval rules in `CLAUDE.md` section 3 still apply to every write.
- Niche direction: baby and kids, matching the store name. Not final until the Meta test.

## 2026-11-03: One window for store and Meta ads

- Use Meta's official "Facebook & Instagram" sales channel inside Shopify admin to run Meta ads from the store admin. No custom build.
- Claude side: one claude.ai Project with the Shopify connector. A Meta connector is added later only if Shopify's own marketing data is not enough.

## 2026-11-05: Graphify and scrapers added

- Installed CLIs: Graphify (`graphifyy`), Crawl4AI, Scrapy, Crawlee (Python, with BeautifulSoup extra). Each tested on a local page; outside sites are blocked by this environment's network allowlist.
- Crawl4AI pinned to Playwright 1.63.0 so it uses the browser preinstalled in `/opt/pw-browsers`.
- `graphify install --project` added a skill, a CLAUDE.md section, and two PreToolUse hooks to `.claude/settings.json`.
- Tool reinstall now lives in the "shopify" cloud environment's setup script. `.claude/hooks/setup-tools.sh` is kept for local machines.
