---
name: agent-reach
description: Read and search external sources through the channels installed on this machine. Use when the task needs content from a feed, a video, or another platform an installed channel covers.
---

# agent-reach

Installed channels only. Run `agent-reach doctor` first if a call fails; a channel can be
installed but unauthenticated.

Every command returns the same envelope, so the output shape does not change per channel.
Use `--max-tokens` whenever the source could be long.

```
agent-reach get <channel>.<command> <query> [--max-tokens N] [--limit N] [--json]
```

## Channels

None installed. Run `agent-reach list --all` to see what the index offers.
