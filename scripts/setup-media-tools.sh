#!/usr/bin/env bash
# Installs the non-plugin image/video tooling for Yourider.
#
# Claude Code plugins (ECC, HyperFrames, Ponytail, Matt Pocock skills,
# Lemo-Opuscar, opus-video-skills) are declared in .claude/settings.json and
# installed by Claude Code itself after you trust the project — not here.
#
# This script handles the rest. Every repo is pinned to a reviewed commit.
# Bump a pin deliberately after reading the upstream diff.
#
# Usage:
#   scripts/setup-media-tools.sh                 # core: OpenMontage, Graphify, onetake, references
#   scripts/setup-media-tools.sh --with-earshot  # + Earshot (CPU torch, ~1 GB) and its real-sound SFX skill
#   scripts/setup-media-tools.sh --with-animation # + ClaudeAnimationBase (p5.brush + puppeteer)
#
# Requires: git, python3 >= 3.10, uv, node/npm, ffmpeg.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="${YOURIDER_TOOLS_DIR:-$REPO_ROOT/tools}"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

WITH_EARSHOT=0
WITH_ANIMATION=0
for arg in "$@"; do
  case "$arg" in
    --with-earshot) WITH_EARSHOT=1 ;;
    --with-animation) WITH_ANIMATION=1 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

for bin in git python3 uv npm ffmpeg; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: '$bin' not found on PATH" >&2; exit 1; }
done

# fetch <owner/repo> <commit> <dest>: shallow checkout of exactly that commit.
fetch() {
  local repo="$1" sha="$2" dest="$3"
  if [ -d "$dest/.git" ] && [ "$(git -C "$dest" rev-parse HEAD)" = "$sha" ]; then
    echo "==> $repo already at ${sha:0:12}"
    return
  fi
  echo "==> $repo @ ${sha:0:12} -> $dest"
  mkdir -p "$dest"
  git -C "$dest" init -q
  git -C "$dest" remote remove origin 2>/dev/null || true
  git -C "$dest" remote add origin "https://github.com/$repo.git"
  git -C "$dest" fetch -q --depth 1 origin "$sha"
  git -C "$dest" checkout -q --force FETCH_HEAD
}

mkdir -p "$TOOLS_DIR" "$SKILLS_DIR"

# --- OpenMontage: agentic video production (Python venv + Remotion + HyperFrames runtime)
fetch calesthio/OpenMontage 195eab24478dc9363326aec437aefc3701635ddf "$TOOLS_DIR/OpenMontage"
make -C "$TOOLS_DIR/OpenMontage" setup

# --- Graphify: codebase -> knowledge graph; skill installed project-scoped into .claude/skills/graphify
uv tool install --force "graphifyy @ git+https://github.com/Graphify-Labs/graphify@8e6a6d2129d4aeffc7a0e9ed79b153f7f057f42b"
(cd "$REPO_ROOT" && "$(uv tool dir --bin)/graphify" install --project --platform claude)

# --- onetake: single-take motion-film skill (upstream installs it as a user skill)
fetch feitangyuan/onetake 013a61ac8d98883c73733f59c06e49e9ba444f14 "$SKILLS_DIR/onetake"

# --- Reference-only collections (prompts + skill directory). Read, not executed.
fetch yihui-dev/awesome-opus5-5-videos 92aee2f586ac0715cb3cbcb6384834f98a33383d "$TOOLS_DIR/refs/awesome-opus5-5-videos"
fetch zhuyansen/awesome-claude-video-skills 888820fdb61ff5c3085c79b37f23910c81a7519e "$TOOLS_DIR/refs/awesome-claude-video-skills"

# --- Earshot: lets agents hear/QA audio; ships the real-sound (real SFX) skill
if [ "$WITH_EARSHOT" = 1 ]; then
  ES="$TOOLS_DIR/earshot"
  fetch Leonxlnx/earshot 591fa3e028032e6dce56620a20e932e35667e8d8 "$ES"
  [ -x "$ES/.venv/bin/python" ] || python3 -m venv "$ES/.venv"
  "$ES/.venv/bin/python" -m pip install -q torch --index-url https://download.pytorch.org/whl/cpu
  "$ES/.venv/bin/python" -m pip install -q -e "$ES[mcp,llm]"
  "$ES/.venv/bin/python" -m earshot doctor
  for s in earshot real-sound; do ln -sfn "$ES/skills/$s" "$SKILLS_DIR/$s"; done
fi

# --- ClaudeAnimationBase: hand-painted cartoon starter kit
if [ "$WITH_ANIMATION" = 1 ]; then
  fetch JohnHeibel/ClaudeAnimationBase 0ac8bf2b31942376cb6b8c4074715595d512acd2 "$TOOLS_DIR/ClaudeAnimationBase"
  (cd "$TOOLS_DIR/ClaudeAnimationBase" && npm ci)
fi

cat <<EOF

Done.
  Tools:         $TOOLS_DIR
  User skills:   $SKILLS_DIR (onetake$([ "$WITH_EARSHOT" = 1 ] && echo ", earshot, real-sound"))
  Project skill: $REPO_ROOT/.claude/skills/graphify
  OpenMontage API keys go in $TOOLS_DIR/OpenMontage/.env (gitignored there). Never commit them.
  Openverse needs no install: HyperFrames' media-use skill already queries the Openverse API for CC0/CC-BY SFX.
EOF
