# Source this before any media command:  . media/env.sh
# One place for every environment fix the pipeline needs (found the hard way, 2026-11-03):
#   - renderers must use a local Chromium (Remotion/HyperFrames otherwise download one from blocked hosts)
#   - Hugging Face's Xet storage host is blocked; plain CDN downloads work
#   - HyperFrames sends usage telemetry by default; we turn it off
# Nothing here is a secret. Keys (PEXELS_API_KEY, GEMINI_API_KEY, ...) come from the environment's Network secrets, never this file.

MEDIA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export MEDIA_ROOT
export MEDIA_TOOLS="${MEDIA_TOOLS:-$MEDIA_ROOT/.tools}"
export MEDIA_PY="$MEDIA_TOOLS/venv/bin/python"
export PIPER_VOICES="$MEDIA_TOOLS/voices"
export LEMO_DIR="$MEDIA_TOOLS/lemo-opuscar"
export HYPERFRAMES_VERSION="0.9.8"
export GSAP_VERSION="3.15.0"
export INTER_PKG="@fontsource-variable/inter@5.2.5"
export SCHIBSTED_PKG="@fontsource-variable/schibsted-grotesk@5.3.0"
export KOKORO_VOICES="am_michael am_adam am_eric af_heart af_bella bf_emma"
export MEDIA_BLENDER_PY="$MEDIA_TOOLS/blender-venv/bin/python"

export HF_HUB_DISABLE_XET=1
export HYPERFRAMES_NO_TELEMETRY=1
export DO_NOT_TRACK=1

# a local Chromium for every headless renderer
if [ -z "${MEDIA_CHROME:-}" ]; then
  for c in /opt/pw-browsers/chromium-*/chrome-linux64/chrome "$(command -v chromium 2>/dev/null)" "$(command -v google-chrome 2>/dev/null)"; do
    [ -n "$c" ] && [ -x "$c" ] && { MEDIA_CHROME="$c"; break; }
  done
fi
if [ -n "${MEDIA_CHROME:-}" ]; then
  export MEDIA_CHROME
  export HYPERFRAMES_BROWSER_PATH="$MEDIA_CHROME" PLAYWRIGHT_CHROME="$MEDIA_CHROME" PUPPETEER_EXECUTABLE_PATH="$MEDIA_CHROME"
else
  echo "media/env.sh: no Chromium found; set MEDIA_CHROME=/path/to/chrome" >&2
fi
