#!/usr/bin/env bash
# Installs the CLI tools this project uses, if they are missing.
# Runs on SessionStart. Safe to run many times.
set -euo pipefail

# Only auto-install in Claude Code cloud sessions. Local machines install by hand.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "setup-tools: uv not found, skipping CLI installs" >&2
  exit 0
fi

export PATH="$HOME/.local/bin:$PATH"

install_if_missing() {
  local cmd="$1" pkg="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    uv tool install --quiet --python 3.13 "$pkg" >&2 || echo "setup-tools: failed to install $pkg" >&2
  fi
}

# Headroom plugin hooks need the headroom CLI.
install_if_missing headroom "headroom-ai[proxy]"
install_if_missing agent-reach agent-reach

if command -v agent-reach >/dev/null 2>&1; then
  agent-reach install rss >/dev/null 2>&1 || true
  agent-reach install youtube >/dev/null 2>&1 || true
fi

# crewAI is large. Install it in the background so the session starts fast.
if ! command -v crewai >/dev/null 2>&1; then
  nohup uv tool install --quiet --python 3.13 crewai >/dev/null 2>&1 &
fi

exit 0
