#!/usr/bin/env bash
# Build the Diwali 2026 greeting end to end (see PLAN.md, DESIGN.md): plan gate, narration + word times (kept if
# words.json matches script.json), synthesised sounds, mix, HyperFrames composition (lint 0 errors), motion gate,
# browser sync/layout check, stills, render, cover image, QA.
# usage: media/projects/diwali-2026/build.sh                 -> media/out/diwali-2026.mp4 (+ .check.jpg, -cover.png)
#        STILLS="3.0,12.5" media/projects/diwali-2026/build.sh -> snapshot those seconds to .build/diwali-2026/stills
#        NO_RENDER=1 ...                                       -> stop after the gates (and stills)
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/env.sh"
P="$MEDIA_ROOT/projects/diwali-2026"; B="$MEDIA_ROOT/.build/diwali-2026"; OUT="$MEDIA_ROOT/out"
PIPE="$MEDIA_ROOT/pipeline"
[ -f "$MEDIA_TOOLS/web/SchibstedGrotesk.woff2" ] || { echo "Schibsted Grotesk missing: run media/setup.sh" >&2; exit 1; }
mkdir -p "$B/hf" "$OUT"

python3 "$PIPE/plancheck.py" "$P"
# narration: re-take only when the spoken lines or voice settings change (a new take would move every word time)
VKEY=$("$MEDIA_PY" -c "import json,sys,hashlib;s=json.load(open(sys.argv[1]));print(hashlib.sha256(json.dumps([s['voice'],[[l['id'],l['start'],l['say']] for l in s['lines']]],sort_keys=True).encode()).hexdigest())" "$P/script.json")
if [ -f "$B/words.json" ] && [ "$(cat "$B/vo/.lines.sha" 2>/dev/null)" = "$VKEY" ]; then
  echo "voice: kept $B/words.json (lines unchanged)"
else
  "$MEDIA_PY" "$PIPE/voice.py" "$P" "$B"
  echo "$VKEY" > "$B/vo/.lines.sha"
fi
"$MEDIA_PY" "$P/sounds.py" "$B/sfx" --duration "$("$MEDIA_PY" -c "import json,sys;print(json.load(open(sys.argv[1]))['duration'])" "$P/script.json")"
"$MEDIA_PY" "$PIPE/mix.py" "$P" "$B" "$B/sfx" "$B/hf/mix.wav"
cp "$MEDIA_TOOLS/web/gsap.min.js" "$MEDIA_TOOLS/web/SchibstedGrotesk.woff2" "$B/hf/"
"$MEDIA_PY" "$P/gen.py" "$P" "$B"

cd "$B/hf"
printf '{"name":"diwali-2026","private":true}\n' > package.json
LINT=$(npx --yes "hyperframes@$HYPERFRAMES_VERSION" lint 2>&1 || true)
echo "$LINT" | tail -1
echo "$LINT" | grep -q " 0 error(s)" || { echo "$LINT" >&2; echo "lint errors: fix gen.py" >&2; exit 1; }
python3 "$PIPE/motionlint.py" "$B/hf/index.html" --exceptions "$P/script.json"
NODE_PATH="${NODE_PATH:-/opt/node-tools/node_modules}" node "$P/verify.js" "$B/hf/index.html" "$P/script.json" "$B/words.json"
if [ -n "${STILLS:-}" ]; then
  rm -rf "$B/stills"
  npx --yes "hyperframes@$HYPERFRAMES_VERSION" snapshot --at "$STILLS" --no-end -o "$B/stills" --timeout 120000 >/dev/null
  echo "stills in $B/stills"
fi
[ -z "${NO_RENDER:-}" ] || exit 0
npx --yes "hyperframes@$HYPERFRAMES_VERSION" render -o "$OUT/diwali-2026.mp4" --quiet >/dev/null

# cover for the post (the film opens dark on purpose): the full lockup at 19 s
ffmpeg -loglevel error -y -ss 19.0 -i "$OUT/diwali-2026.mp4" -frames:v 1 "$OUT/diwali-2026-cover.png"

# no planned --silence window: the voice-free beat (14.0-15.4 s) keeps the drone under it (script.json _voice_free_beat)
"$MEDIA_PY" "$PIPE/check.py" "$OUT/diwali-2026.mp4" --size 1080x1350 \
  --words "$B/words.json" --sheet "$OUT/diwali-2026.check.jpg"
