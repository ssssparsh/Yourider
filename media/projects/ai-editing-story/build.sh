#!/usr/bin/env bash
# Build "How I edit video with Claude" end to end (see PLAN.md): evidence stills from our own renders, narration +
# word times, mix, HyperFrames composition (lint must report 0 errors), render, QA.
# usage: media/projects/ai-editing-story/build.sh      -> media/out/ai-editing-story.mp4 (+ .check.jpg)
#        STILLS="1.6,9.5" media/projects/ai-editing-story/build.sh   -> also snapshot those seconds to .build/ai-editing-story/stills
#        NO_RENDER=1 ...                                              -> stop after lint (and stills)
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/env.sh"
P="$MEDIA_ROOT/projects/ai-editing-story"; B="$MEDIA_ROOT/.build/ai-editing-story"; OUT="$MEDIA_ROOT/out"
PIPE="$MEDIA_ROOT/pipeline"; EV="$B/evidence"
[ -f "$MEDIA_TOOLS/web/Inter.woff2" ] || { echo "Inter missing: run media/setup.sh" >&2; exit 1; }
mkdir -p "$B/hf" "$EV" "$OUT"

# evidence stills: frames of our own finished films (media/out, gitignored), taken at fixed times. The collage frame
# contains the licensed Adobe Stock cut-out (media/rights.md). Fails loudly if a source film is missing.
LI="$OUT/linkedin-intro.mp4"; MAP="$OUT/one-map.mp4"; COL="$OUT/collage-handshake.mp4"; SHEET="$OUT/linkedin-intro.check.jpg"
for f in "$LI" "$MAP" "$COL" "$SHEET"; do
  [ -f "$f" ] || { echo "missing evidence source $f: build that project first (media/projects/<name>/build.sh)" >&2; exit 1; }
done
grab() {  # grab <video> <seconds> <name>
  ffmpeg -nostdin -v error -y -ss "$2" -i "$1" -frames:v 1 "$EV/$3.png"
  [ -s "$EV/$3.png" ] || { echo "could not extract $3 at $2 s from $1" >&2; exit 1; }
}
grab "$LI" 1.8 li-hook; grab "$LI" 11.2 li-slam; grab "$LI" 17.5 li-agents; grab "$LI" 29.0 li-lockup
grab "$MAP" 6.4 map-route; grab "$MAP" 25.3 map-drop; grab "$MAP" 31.5 map-whole
grab "$COL" 2.4 collage
cp "$SHEET" "$EV/qa-contact-sheet.jpg"
echo "evidence stills in $EV"

"$MEDIA_PY" "$PIPE/voice.py" "$P" "$B"
cp "$MEDIA_TOOLS/web/gsap.min.js" "$MEDIA_TOOLS/web/Inter.woff2" "$B/hf/"
"$MEDIA_PY" "$PIPE/mix.py" "$P" "$B" "$MEDIA_TOOLS/gbro-collage-info/assets/sfx" "$B/hf/mix.wav"
"$MEDIA_PY" "$P/gen.py" "$P" "$B"

cd "$B/hf"
printf '{"name":"ai-editing-story","private":true}\n' > package.json
LINT=$(npx --yes "hyperframes@$HYPERFRAMES_VERSION" lint 2>&1 || true)
echo "$LINT" | tail -1
echo "$LINT" | grep -q " 0 error(s)" || { echo "$LINT" >&2; echo "lint errors: fix gen.py" >&2; exit 1; }
if [ -n "${STILLS:-}" ]; then
  npx --yes "hyperframes@$HYPERFRAMES_VERSION" snapshot --at "$STILLS" --no-end -o "$B/stills" --timeout 120000 >/dev/null
  echo "stills in $B/stills"
fi
[ -z "${NO_RENDER:-}" ] || exit 0
npx --yes "hyperframes@$HYPERFRAMES_VERSION" render -o "$OUT/ai-editing-story.mp4" --quiet >/dev/null

# the planned voice-free beat, from words.json + script.json: from the end of the line before it (+0.15 s tail)
# to the first sound after it (next line or effect, -0.05 s); gen.py uses the same rule and keeps the picture still in it
SIL=$("$MEDIA_PY" - "$P/script.json" "$B/words.json" <<'PY'
import json, sys
spec, words = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
allw = [w for ln in words.values() for w in ln["words"]]
def wt(k):
    return next(w["t0"] for w in allw if w["w"].lower().strip(".,!?:") == k.lower().strip(".,!?:"))
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
# the picture must hold still in the silence too: first and last frame of each window must match
for w in $SIL; do
  "$MEDIA_PY" - "$OUT/ai-editing-story.mp4" "${w%%:*}" "${w##*:}" <<'PY'
import subprocess, sys, tempfile
from PIL import Image, ImageChops
v, a, b = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
with tempfile.TemporaryDirectory() as d:
    fr = []
    for t in (a + .04, b - .04):
        p = f"{d}/{t:.2f}.png"
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-ss", f"{t:.3f}", "-i", v, "-frames:v", "1", p], check=True)
        fr.append(Image.open(p).convert("L"))
    diff = ImageChops.difference(*fr).point(lambda x: 255 if x > 24 else 0).getbbox()
    print(("PASS" if diff is None else "FAIL") + f" picture still in the silence {a:.2f}-{b:.2f}s" + ("" if diff is None else f" (changed in {diff})"))
    sys.exit(0 if diff is None else 1)
PY
done
"$MEDIA_PY" "$PIPE/check.py" "$OUT/ai-editing-story.mp4" --size 1080x1350 --silence $SIL \
  --words "$B/words.json" --sheet "$OUT/ai-editing-story.check.jpg"
