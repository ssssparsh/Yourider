This file is read by Claude Code at the start of every session in this repo. It sets conventions, guardrails, and architecture. It does not provision infrastructure — anything marked [V2 — REQUIRES SETUP] below needs a real tool/script/MCP server built and connected before Claude Code can use it. Until then, Claude Code should use the [V1 — ACTIVE NOW] fallback.
1. Project
Name: [Yourider] What it is: A domain-agnostic backend engine (CRM/ERP/other business system, determined per-instruction) with modular, multi-agent chat interfaces on top. "Domain-agnostic" means the core entity/pipeline model is configurable — Claude Code should ask which domain (sales CRM, inventory ERP, support desk, etc.) before generating entity schemas if it isn't already specified in a task.
Current build target: [CRM MVP: Leads, Pipelines, Deals]
2. Role & Approach
Act as a senior full-stack/systems engineer covering: backend architecture, database design, API security, and basic UX/workflow sense for the chat interfaces. Prioritize working, strictly-typed, tested code over speculative breadth. Skip role-play framing — the standards below are what actually change output quality, not job titles.
No pseudocode, placeholders, or unverified stubs in anything presented as done.
If a request is ambiguous (which domain, which entity shape), state the assumption you're making and proceed, or ask one clarifying question if proceeding would waste real effort.
Three working principles:
  - Boil the ocean. AI makes completeness cheap — build the full implementation a task actually calls for, not the 90% shortcut with edges left for later. "I'll leave X for now" needs a real reason, not just less typing.
  - Search before building. Check for prior art (existing code in this repo, a well-known pattern, a library that already solves it) before designing a mechanism from scratch. Novel isn't better by default.
  - User sovereignty. Recommend, don't decide. If a change looks better than what the user asked for, say so and propose it — don't substitute your judgment for theirs and act on it unasked, even if you're confident you're right.
3. Absolute Operational Guardrails (Human-in-the-Loop)
No autonomous destructive action. Never delete files, drop/alter DB schemas, install new dependencies, or force-push without explicit confirmation in the current session.
Multi-file or destructive tasks follow: Inspect → Plan → Present for Approval → Execute. Present the plan as a short list of file-level changes before touching anything. Wait for a go-ahead.
Blast radius containment. Read access to the repo and any connected knowledge sources is unrestricted. Write/patch/execute actions are scoped to the files explicitly discussed in the current plan — don't drift into adjacent files "while you're in there" without flagging it first.
No secrets in code or prompts. Never write credentials, API keys, or raw unvalidated user input into source files, commit messages, or persisted memory. Use environment variables + .env (gitignored) and reference them by name only.
Pre-completion verification. Before marking any task done: run typecheck + lint + relevant tests (see §7). If something can't be verified (no test harness yet for that module), say so explicitly rather than marking it done. No completion claims without fresh verification evidence from *this* task — re-running an old test result or reasoning "it should work" doesn't count; run the check now and read its actual output before saying done.
Escalate stuck debugging instead of repeating it. After 3 failed attempts to fix the same bug, stop retrying variations of the same fix — stop and question whether the underlying architecture/approach is wrong, and say so, rather than continuing to patch symptoms.
Approval gate (command classes → autonomy tiers). Every tool call an agent makes falls into one command class: Read (view files/data, no side effects), Write (create/modify a file or DB row), Network (outbound call to an external service — scraper, email send, webhook), Install (add/change a dependency), Destructive (delete, drop, force-push, bulk mutation). Each agent definition (see /src/agents/README.md) declares its autonomy tier, which determines what happens per class:
  - Read-only tier: all classes require nothing beyond normal execution for Read; everything else is blocked outright.
  - Supervised tier (default for new agents): Read and Write proceed; Network, Install, and Destructive pause and surface a plain-language approval request in the current session ("Agent X wants to send an email to <address> — approve? y/n") before executing. No response within the session means it does not happen — never assume approval from silence or a stale prompt.
  - Full tier (opt-in, per agent, requires the human explicitly granting it in that agent's definition file): all classes proceed without pausing, except Destructive, which always pauses regardless of tier — no agent is ever fully autonomous for deletion/drop/force-push/bulk-mutation actions.
  Background or scheduled runs (cron-triggered agents with no human present) may only run at Read-only or Supervised-with-nothing-pending tier; anything that would need a pause must fail loudly and log why, not silently skip or silently proceed.
4. Directory Standards
/src/agents        Orchestrator logic, prompt registries, agent-to-agent
                    handoff, context assembly for multi-agent chat. Each
                    agent is a self-contained Markdown file (frontmatter +
                    system prompt) — the directory itself is the registry,
                    no separate manifest to keep in sync. Format, autonomy
                    tiers, and the shared security preamble are defined in
                    /src/agents/README.md; copy /src/agents/AGENT_TEMPLATE.md
                    to start a new one.
/src/crm            Core domain models (Leads, Pipelines, Deals, Accounts,
                    custom entities, audit trails) — domain-agnostic core
                    lives here even when the active build is an ERP, etc.
/src/interfaces     Chat UI framework, token streaming, dynamic
                    schema-driven renderers. Read PRODUCT.md and DESIGN.md
                    (repo root) before any UI work — they're the source of
                    truth for brand/UX intent and design tokens, so
                    decisions stay consistent across sessions instead of
                    being reinvented per task.
/src/api            REST/gRPC endpoints, auth middleware, input
                    sanitization, rate limiting
/src/db             Schema + migrations, DB adapters
/src/ingestion      [V2] Scraper scripts, repo-ingestion scripts, and any
                    vector-store adapters. See §5 and §6.
5. Scraping — Data Ingestion for Agents
Goal: agents (especially enrichment/research agents in /src/agents) should be able to pull live external data (company info, market data, competitor pricing, etc.) rather than relying on static training knowledge.
V1 — ACTIVE NOW
No live scraper is connected yet. Until one exists:
Claude Code writes scraping logic as a real script in /src/ingestion/scrapers/ (e.g. a Node script using fetch/cheerio/playwright, or a Python script using requests/BeautifulSoup), invoked via bash_tool / npm run scrape:<target>.
Every scraper script must: respect robots.txt, rate-limit itself, sanitize and validate scraped output before it touches the DB, and fail loudly (not silently) on blocked/changed page structure.
Agents that need external data call the scraper script as a subprocess or local API endpoint — not by "imagining" data.
Do not fabricate scraped-looking data. If no scraper exists for a needed source yet, say so and propose writing one — don't fill gaps with plausible-sounding invented numbers.
V2 — REQUIRES SETUP (target state)
Once a dedicated scraping MCP server (e.g. Firecrawl, or a custom one) is connected to Claude Code for this project:
Agents call the MCP scraping tool directly instead of shelling out to a local script.
Scraping becomes a first-class agent capability: any agent whose task depends on current external facts (pricing, competitor moves, contact enrichment) must invoke the scraping tool before answering, not after-the-fact — this is a hard requirement once the tool exists, not optional enrichment.
Scraped data gets normalized and written through /src/ingestion into the same validation/sanitization path as V1, then optionally indexed (see §6) for reuse without re-scraping.
Setup checklist before this section activates: MCP scraping server provisioned → connected in Claude Code settings → test call confirmed working → this section's "must invoke" rule becomes binding. Until all four are true, treat this whole subsection as not yet in effect.
6. Multi-Repository Knowledge & GitHub Ingestion
Goal: feed existing GitHub repos to Claude Code so agents understand patterns/conventions/prior art before generating new code.
V1 — ACTIVE NOW
Claude Code can git clone <repo-url> (read-only) into a scratch directory and read files directly via view/bash_tool.
This works well for small-to-medium repos or specific files/modules you point it at. It does not scale to "understand an entire large codebase at once" — context window limits apply like any other file reading.
Practical pattern: tell Claude Code which repo and which part is relevant ("clone X, look at how they structured their pipeline state machine in /src/pipelines") rather than "ingest this whole org."
Cloned repos are read-only references — never treated as part of this project's write-scope (see guardrail 3).
V2 — REQUIRES SETUP (target state)
Once an embedding/indexing pipeline exists (a script that chunks a repo, embeds it, and stores it in a local/hosted vector DB, exposed to Claude Code as an MCP tool or query endpoint):
Claude Code queries by symbol/concept/embedding similarity instead of reading raw file trees — "how did repo X handle idempotent webhook processing" returns the relevant chunk, not the whole file.
This is what makes ingesting many repos or very large repos workable.
Setup checklist before this activates: ingestion/embedding script built → vector store running → query tool connected to Claude Code → test query confirmed returning relevant chunks. Until then, use V1.
7. Engineering Standards
Language: Strict TypeScript. No any. Explicit interfaces for all public functions, API payloads, and DB models.
Style: Prefer pure functions where state isn't required. Isolate side effects (DB writes, network calls) at clear boundaries.
Security: Sanitize all inputs at the API boundary and all agent outputs before they touch the DB or get rendered — prompt injection, XSS, and SQLi are all in scope, especially for the chat interfaces in /src/interfaces where user text flows into agent prompts.
Financial/ledger logic (if the active build involves money — invoicing, payments, ledgers): all mutations must be atomic (transactional), append-only where possible, and never allow a double-write on retry. Flag any non-atomic financial operation before writing it.
8. Build, Lint & Test Commands
npm install                        # install dependencies
npm run dev                        # dev server
npm run typecheck && npm run lint  # static checks — run before marking any task done
npm test                           # full test suite
npm test -- <path_to_file>         # targeted test
npm run build                      # production build
9. Session Memory
Claude Code persists this CLAUDE.md across sessions automatically — no separate memory system exists by default. If you want durable notes beyond this file (decisions made, why a schema looks the way it does), maintain a plain DECISIONS.md in the repo root and have Claude Code append to it after significant architecture decisions. This is a real file, not a vector store — treat any future "vector memory" the same way as §6 V2: build it, connect it, then rely on it.
10. What This File Does Not Do
It does not create MCP servers, scrapers, or vector indices by being written. Those are separate build/connect steps (§5, §6).
It does not make Claude Code infallible at security or architecture — guardrails reduce risk, they don't eliminate the need to review output.
It should be updated as V2 infra actually gets built — move sections from "REQUIRES SETUP" to "ACTIVE NOW" only once the checklist items are true.
11. Adversarial Security Testing (Agents)
Goal: before trusting an /src/agents persona in production, probe it the way an attacker would — jailbreaks, prompt injection, data leakage, toxicity — rather than assuming the approval gate (§3) is sufficient on its own.
V1 — NOT YET ACTIVE (no agent to test)
This section has nothing to run against until at least one real agent from /src/agents is implemented and callable (not just a persona `.md` file — an actual running endpoint). Do not attempt to set this up before then.
V2 — REQUIRES SETUP (target state, once an agent exists)
Tool: garak (github.com/NVIDIA/garak, Apache 2.0), a CLI adversarial-probe scanner for LLM-backed systems.
garak tests raw prompt-in/text-out behavior — it has no native concept of tool calls or the autonomy-tier system in §3. To use it: wrap the target agent behind a single synchronous function or REST endpoint that runs the agent's full loop internally and returns only its final text reply, then point garak's `function` or `rest` generator at that wrapper (see garak's generator docs for the exact interface).
Run the standard probe set first (jailbreak, promptinject, leakreplay, toxicity) to catch generic LLM failure modes.
garak alone cannot tell you whether a probe caused a Destructive/Install-tier tool call — that requires a custom detector reading the agent's own tool-call log alongside garak's text-level verdict. Build that detector before treating a garak run as a real security signal for an agent that has tool access, not just chat output.
Setup checklist before this section activates: at least one agent has a real callable endpoint → wrapper function/REST adapter written → garak installed and a baseline probe run completed → (if the agent has tool access) a custom tool-call-aware detector built. Until all of these are true, treat this section as not yet in effect, same as §5/§6 V2.

<!-- code-review-graph MCP tools -->
## MCP Tools: code-review-graph

**IMPORTANT: This project has a knowledge graph. ALWAYS use the
code-review-graph MCP tools BEFORE using Grep/Glob/Read to explore
the codebase.** The graph is faster, cheaper (fewer tokens), and gives
you structural context (callers, dependents, test coverage) that file
scanning cannot.

### When to use graph tools FIRST

- **Exploring code**: `semantic_search_nodes_tool` or `query_graph_tool` instead of Grep
- **Understanding impact**: `get_impact_radius_tool` instead of manually tracing imports
- **Code review**: `detect_changes_tool` + `get_review_context_tool` instead of reading entire files
- **Finding relationships**: `query_graph_tool` with callers_of/callees_of/imports_of/tests_for
- **Architecture questions**: `get_architecture_overview_tool` + `list_communities_tool`

Fall back to Grep/Glob/Read **only** when the graph doesn't cover what you need.

### Key Tools

| Tool | Use when |
| ------ | ---------- |
| `detect_changes_tool` | Reviewing code changes — gives risk-scored analysis |
| `get_review_context_tool` | Need source snippets for review — token-efficient |
| `get_impact_radius_tool` | Understanding blast radius of a change |
| `get_affected_flows_tool` | Finding which execution paths are impacted |
| `query_graph_tool` | Tracing callers, callees, imports, tests, dependencies |
| `semantic_search_nodes_tool` | Finding functions/classes by name or keyword |
| `get_architecture_overview_tool` | Understanding high-level codebase structure |
| `refactor_tool` | Planning renames, finding dead code |

### Workflow

1. The graph auto-updates on file changes (via hooks).
2. Use `detect_changes_tool` for code review.
3. Use `get_affected_flows_tool` to understand impact.
4. Use `query_graph_tool` pattern="tests_for" to check coverage.
