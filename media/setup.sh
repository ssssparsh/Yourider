#!/usr/bin/env bash
# Installs everything the media pipeline needs into media/.tools (gitignored). Idempotent; every repo pinned.
#
#   media/setup.sh                    core: Python venv, voices (Kokoro + Piper), Whisper model, Lemo-Opuscar
#                                     engine, gbro-collage-info rules + SFX, HyperFrames, GSAP, Inter, Schibsted Grotesk
#   media/setup.sh --with-shotcraft   video-shotcraft (124 shot recipes, aesthetic rules) + its Remotion template
#   media/setup.sh --with-taste       taste-skill (art direction, anti-generic house style, look-and-fix loop)
#   media/setup.sh --with-blender     headless Blender (bpy 5.2, Python 3.13) for 3D shots, Cycles on CPU
#   media/setup.sh --with-openmontage OpenMontage (agentic explainer pipelines, Remotion)
#   media/setup.sh --with-earshot     Earshot + real-sound skill (CPU torch, ~1 GB)
#   media/setup.sh --with-animation   ClaudeAnimationBase (hand-painted cartoons)
#   media/setup.sh --with-onetake     onetake skill into ~/.claude/skills
#   media/setup.sh --with-graphify    Graphify CLI + project skill (codebase knowledge graph)
#   media/setup.sh --with-ytdlp       yt-dlp (only for footage you have rights to; see media/README.md)
#   media/setup.sh --all              everything above
#
# Claude Code plugins (HyperFrames, Lemo-Opuscar, opus-video-skills) are declared in .claude/settings.json.
# Requires: git, uv, node/npm/npx, ffmpeg/ffprobe, a Chromium (see env.sh).
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"
REPO_ROOT="$(cd "$MEDIA_ROOT/.." && pwd)"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

declare -A W=()
for arg in "$@"; do
  case "$arg" in
    --with-openmontage|--with-earshot|--with-animation|--with-onetake|--with-graphify|--with-ytdlp|--with-shotcraft|--with-taste|--with-blender) W[${arg#--with-}]=1 ;;
    --all) for k in openmontage earshot animation onetake graphify ytdlp shotcraft taste blender; do W[$k]=1; done ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done
on() { [ -n "${W[$1]:-}" ]; }

for bin in git uv node npm npx ffmpeg ffprobe; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: '$bin' not found on PATH" >&2; exit 1; }
done
[ -n "${MEDIA_CHROME:-}" ] || { echo "ERROR: no Chromium; set MEDIA_CHROME" >&2; exit 1; }

# fetch <owner/repo> <commit> <dest>: shallow checkout of exactly that commit
fetch() {
  local repo="$1" sha="$2" dest="$3"
  if [ -d "$dest/.git" ] && [ "$(git -C "$dest" rev-parse HEAD)" = "$sha" ]; then echo "==> $repo already at ${sha:0:12}"; return; fi
  echo "==> $repo @ ${sha:0:12}"
  mkdir -p "$dest"; git -C "$dest" init -q
  git -C "$dest" remote remove origin 2>/dev/null || true
  git -C "$dest" remote add origin "https://github.com/$repo.git"
  git -C "$dest" fetch -q --depth 1 origin "$sha"
  git -C "$dest" checkout -q --force FETCH_HEAD
}
# npm_file <package@version> <path inside package> <dest>: one file out of an npm tarball (the registry is reachable when CDNs are not)
npm_file() {
  [ -f "$3" ] && return
  local t; t="$(mktemp -d)"
  (cd "$t" && npm pack -q "$1" >/dev/null && tar -xzf ./*.tgz "package/$2")
  mkdir -p "$(dirname "$3")"; mv "$t/package/$2" "$3"; rm -rf "$t"
}

mkdir -p "$MEDIA_TOOLS" "$PIPER_VOICES" "$MEDIA_TOOLS/web"

# ---- core ---------------------------------------------------------------------------------------------
echo "==> Python venv"
[ -x "$MEDIA_PY" ] || uv venv -q --python 3.11 "$MEDIA_TOOLS/venv"
uv pip install -q --python "$MEDIA_PY" -r "$MEDIA_ROOT/requirements.txt"

echo "==> narration voice (public domain: LJSpeech)"
[ -f "$PIPER_VOICES/en_US-ljspeech-medium.onnx" ] || "$MEDIA_PY" -m piper.download_voices --download-dir "$PIPER_VOICES" en_US-ljspeech-medium
echo "==> Kokoro voice (Apache-2.0, onnx-community/Kokoro-82M-v1.0-ONNX)"
KK="$MEDIA_TOOLS/kokoro"; KB="https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/main"
mkdir -p "$KK"
[ -f "$KK/model_quantized.onnx" ] || curl -sSfL -o "$KK/model_quantized.onnx" "$KB/onnx/model_quantized.onnx"   # q8f16 crashes onnxruntime on some CPUs
for v in $KOKORO_VOICES; do [ -f "$KK/$v.bin" ] || curl -sSfL -o "$KK/$v.bin" "$KB/voices/$v.bin"; done
"$MEDIA_PY" -c "import numpy as np,sys,pathlib;d=pathlib.Path(sys.argv[1]);np.savez(d/'voices.npz',**{v:np.fromfile(d/f'{v}.bin',dtype=np.float32).reshape(-1,1,256) for v in sys.argv[2:]})" "$KK" $KOKORO_VOICES
echo "==> Whisper model (word timestamps)"
"$MEDIA_PY" -c "from faster_whisper import WhisperModel; WhisperModel('base.en', device='cpu', compute_type='int8')"

fetch lemomo-ai/lemo-opuscar bebbbe1aa92a3cb4bb6f83500e61b23a17d1aa00 "$LEMO_DIR"
[ -d "$LEMO_DIR/node_modules/three" ] || (cd "$LEMO_DIR" && npm ci --ignore-scripts --no-audit --no-fund >/dev/null)
fetch pyang5166/gbro-collage-info 0b97a817a6b65285d8aa90431079500a29092eab "$MEDIA_TOOLS/gbro-collage-info"

echo "==> web assets: GSAP $GSAP_VERSION, Inter + Schibsted Grotesk (OFL), HyperFrames $HYPERFRAMES_VERSION"
npm_file "gsap@$GSAP_VERSION" dist/gsap.min.js "$MEDIA_TOOLS/web/gsap.min.js"
npm_file "$INTER_PKG" files/inter-latin-wght-normal.woff2 "$MEDIA_TOOLS/web/Inter.woff2"
npm_file "$SCHIBSTED_PKG" files/schibsted-grotesk-latin-wght-normal.woff2 "$MEDIA_TOOLS/web/SchibstedGrotesk.woff2"
npx --yes "hyperframes@$HYPERFRAMES_VERSION" --version >/dev/null

# ---- optional -----------------------------------------------------------------------------------------
if on openmontage; then
  fetch calesthio/OpenMontage 195eab24478dc9363326aec437aefc3701635ddf "$MEDIA_TOOLS/OpenMontage"
  make -C "$MEDIA_TOOLS/OpenMontage" setup
fi
if on earshot; then
  ES="$MEDIA_TOOLS/earshot"
  fetch Leonxlnx/earshot 591fa3e028032e6dce56620a20e932e35667e8d8 "$ES"
  [ -x "$ES/.venv/bin/python" ] || uv venv -q --python 3.11 "$ES/.venv"
  uv pip install -q --python "$ES/.venv/bin/python" torch --index-url https://download.pytorch.org/whl/cpu
  uv pip install -q --python "$ES/.venv/bin/python" -e "$ES[mcp,llm]"
  mkdir -p "$SKILLS_DIR"; for s in earshot real-sound; do ln -sfn "$ES/skills/$s" "$SKILLS_DIR/$s"; done
fi
if on animation; then
  fetch JohnHeibel/ClaudeAnimationBase 0ac8bf2b31942376cb6b8c4074715595d512acd2 "$MEDIA_TOOLS/ClaudeAnimationBase"
  (cd "$MEDIA_TOOLS/ClaudeAnimationBase" && npm ci --no-audit --no-fund >/dev/null)
fi
if on onetake; then fetch feitangyuan/onetake 013a61ac8d98883c73733f59c06e49e9ba444f14 "$SKILLS_DIR/onetake"; fi
if on graphify; then
  uv tool install --force "graphifyy @ git+https://github.com/Graphify-Labs/graphify@8e6a6d2129d4aeffc7a0e9ed79b153f7f057f42b"
  (cd "$REPO_ROOT" && "$(uv tool dir --bin)/graphify" install --project --platform claude)
fi
if on ytdlp; then uv pip install -q --python "$MEDIA_PY" "yt-dlp[default]==2026.10.26"; fi
if on shotcraft; then
  SC="$MEDIA_TOOLS/video-shotcraft"
  fetch Vincentwei1021/video-shotcraft 1266a3ec4831289c4d893d42dd5102723658039a "$SC"
  (cd "$SC/template" && npm ci --no-audit --no-fund >/dev/null)              # Remotion 4.0.484 for its demos
  mkdir -p "$SKILLS_DIR"; ln -sfn "$SC" "$SKILLS_DIR/video-shotcraft"
fi
if on taste; then
  TS="$MEDIA_TOOLS/taste-skill"
  fetch Leonxlnx/taste-skill 12af471f627f866411b4bd785b19646d3672784c "$TS"
  mkdir -p "$SKILLS_DIR"; ln -sfn "$TS/skills/taste-skill" "$SKILLS_DIR/taste-skill"
fi
if on blender; then
  BV="$MEDIA_TOOLS/blender-venv"
  [ -x "$BV/bin/python" ] || uv venv -q --python 3.13 "$BV"
  uv pip install -q --python "$BV/bin/python" "bpy==5.2.3"
  "$BV/bin/python" -c "import bpy; print('==> Blender', bpy.app.version_string)"
fi

echo
echo "media setup done: tools in $MEDIA_TOOLS, browser $MEDIA_CHROME"
