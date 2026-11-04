#!/usr/bin/env bash
# Build the 30 s LinkedIn intro end to end (see PLAN.md): narration + word times, halftone cut-out, paper, mix,
# HyperFrames composition (lint must report 0 errors), render, QA.
# usage: media/projects/linkedin-intro/build.sh      -> media/out/linkedin-intro.mp4 (+ .check.jpg)
#        STILLS="3.0,10.7" media/projects/linkedin-intro/build.sh   -> also snapshot those seconds to .build/linkedin-intro/stills
#        NO_RENDER=1 ...                                              -> stop after lint (and stills)
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/env.sh"
P="$MEDIA_ROOT/projects/linkedin-intro"; B="$MEDIA_ROOT/.build/linkedin-intro"; OUT="$MEDIA_ROOT/out"
PIPE="$MEDIA_ROOT/pipeline"
CUT="$MEDIA_ROOT/assets/$("$MEDIA_PY" -c "import json,sys;print(json.load(open(sys.argv[1]))['assets']['cutout'])" "$P/script.json")"
[ -f "$CUT" ] || { echo "missing licensed asset $CUT: see media/rights.md for how to re-license and cut it out" >&2; exit 1; }
[ -f "$MEDIA_TOOLS/web/SchibstedGrotesk.woff2" ] || { echo "Schibsted Grotesk missing: run media/setup.sh" >&2; exit 1; }
mkdir -p "$B/hf" "$OUT"

"$MEDIA_PY" "$PIPE/voice.py" "$P" "$B"
"$MEDIA_PY" "$PIPE/halftone.py" "$CUT" "$B/hf/handshake-ht.png"
# paper (palette from script.json): paper-grey field, yellow and bottle-green colour pages, cardstock pieces with a cream keyline
"$MEDIA_PY" "$PIPE/paper.py" "$B/hf" --size 1080x1350 --field "#f7f7f7" \
  --extra-field "yellow=#f6e016" --extra-field "green=#0d2a1c" \
  --piece "leadcard:380x230:#ebebeb:2.5:2" \
  --piece "tag0:240x104:#ebebeb:2:2" --piece "tag1:340x104:#ebebeb:2:2" --piece "tag2:232x104:#ebebeb:2:2" \
  --piece "slip0:660x180:#0d2a1c:2:2" --piece "slip1:660x180:#0d2a1c:2:2" --piece "slip2:660x180:#0d2a1c:2:2" \
  --piece "slip3:660x180:#f7f7f7:2:2" \
  --piece "panel:900x440:#ebebeb:3:2"
cp "$MEDIA_TOOLS/web/gsap.min.js" "$MEDIA_TOOLS/web/SchibstedGrotesk.woff2" "$B/hf/"
"$MEDIA_PY" "$PIPE/mix.py" "$P" "$B" "$MEDIA_TOOLS/gbro-collage-info/assets/sfx" "$B/hf/mix.wav"
"$MEDIA_PY" "$P/gen.py" "$P" "$B"

cd "$B/hf"
printf '{"name":"linkedin-intro","private":true}\n' > package.json
LINT=$(npx --yes "hyperframes@$HYPERFRAMES_VERSION" lint 2>&1 || true)
echo "$LINT" | tail -1
echo "$LINT" | grep -q " 0 error(s)" || { echo "$LINT" >&2; echo "lint errors: fix gen.py" >&2; exit 1; }
if [ -n "${STILLS:-}" ]; then
  npx --yes "hyperframes@$HYPERFRAMES_VERSION" snapshot --at "$STILLS" --no-end -o "$B/stills" --timeout 120000 >/dev/null
  echo "stills in $B/stills"
fi
[ -z "${NO_RENDER:-}" ] || exit 0
npx --yes "hyperframes@$HYPERFRAMES_VERSION" render -o "$OUT/linkedin-intro.mp4" --quiet >/dev/null

# the planned voice-free beat, from words.json + script.json: from the end of the line before it (+0.15 s tail)
# to the first sound after it (next line or effect, -0.05 s)
SIL=$("$MEDIA_PY" - "$P/script.json" "$B/words.json" <<'PY'
import json, sys
spec, words = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
allw = [w for ln in words.values() for w in ln["words"]]
def wt(k):
    return next(w["t0"] for w in allw if w["w"].lower().strip(".,!?") == k.lower().strip(".,!?"))
cues = [c["t"] if "t" in c else wt(c["word"]) + c.get("offset", 0.0) for c in spec["sfx"]]
out = []
for s in spec["silence"]:
    prev = max((ln for ln in words.values() if ln["start"] < s["to"]), key=lambda ln: ln["start"])
    a = prev["start"] + prev["dur"] + .15
    b = min([ln["start"] for ln in words.values() if ln["start"] > a] + [t for t in cues if t > a - .15]) - .05
    if b - a < .8:
        raise SystemExit(f"planned silence {a:.2f}-{b:.2f}s is shorter than 0.8 s")
    out.append(f"{a:.2f}:{b:.2f}")
print(" ".join(out))
PY
)
echo "planned silence window(s): $SIL"
"$MEDIA_PY" "$PIPE/check.py" "$OUT/linkedin-intro.mp4" --size 1080x1350 --silence $SIL \
  --words "$B/words.json" --sheet "$OUT/linkedin-intro.check.jpg"
