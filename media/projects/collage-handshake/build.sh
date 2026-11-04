#!/usr/bin/env bash
# Build the collage shot end to end: narration + word times, halftone cut-out, paper, mix, HyperFrames render, QA.
# usage: media/projects/collage-handshake/build.sh      -> media/out/collage-handshake.mp4 (+ .check.jpg)
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/env.sh"
P="$MEDIA_ROOT/projects/collage-handshake"; B="$MEDIA_ROOT/.build/collage-handshake"; OUT="$MEDIA_ROOT/out"
PIPE="$MEDIA_ROOT/pipeline"
CUT="$MEDIA_ROOT/assets/$("$MEDIA_PY" -c "import json,sys;print(json.load(open(sys.argv[1]))['assets']['cutout'])" "$P/script.json")"
[ -f "$CUT" ] || { echo "missing licensed asset $CUT: see media/rights.md for how to re-license and cut it out" >&2; exit 1; }
mkdir -p "$B/hf" "$OUT"

"$MEDIA_PY" "$PIPE/voice.py" "$P" "$B"
"$MEDIA_PY" "$PIPE/halftone.py" "$CUT" "$B/hf/handshake-ht.png"
"$MEDIA_PY" "$PIPE/paper.py" "$B/hf" --field "#B8432F"
cp "$MEDIA_TOOLS/web/gsap.min.js" "$MEDIA_TOOLS/web/Inter.woff2" "$B/hf/"
"$MEDIA_PY" "$PIPE/mix.py" "$P" "$B" "$MEDIA_TOOLS/gbro-collage-info/assets/sfx" "$B/hf/mix.wav"
"$MEDIA_PY" "$P/gen.py" "$P" "$B"

cd "$B/hf"
printf '{"name":"collage-handshake","private":true}\n' > package.json
LINT=$(npx --yes "hyperframes@$HYPERFRAMES_VERSION" lint 2>&1 || true)
echo "$LINT" | tail -1
echo "$LINT" | grep -q " 0 error(s)" || { echo "$LINT" >&2; echo "lint errors: fix gen.py" >&2; exit 1; }
npx --yes "hyperframes@$HYPERFRAMES_VERSION" render -o "$OUT/collage-handshake.mp4" --quiet >/dev/null
"$MEDIA_PY" "$PIPE/check.py" "$OUT/collage-handshake.mp4" --words "$B/words.json" --sheet "$OUT/collage-handshake.check.jpg"
