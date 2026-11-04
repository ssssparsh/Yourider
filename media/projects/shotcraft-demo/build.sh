#!/usr/bin/env bash
# Render one video-shotcraft shot card demo unchanged: proof the Remotion toolchain works and a reference for the
# craft level we adapt to Yourider. Silent (the card has no sound). ~11 s per frame on CPU (software GL).
# usage: media/projects/shotcraft-demo/build.sh   (needs: media/setup.sh --with-shotcraft)
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/env.sh"
T="$MEDIA_TOOLS/video-shotcraft/template"; OUT="$MEDIA_ROOT/out"
[ -d "$T/node_modules/remotion" ] || { echo "run media/setup.sh --with-shotcraft first" >&2; exit 1; }
mkdir -p "$T/src/_yourider" "$OUT"
cp "$MEDIA_ROOT/projects/shotcraft-demo/entry.tsx" "$T/src/_yourider/index.tsx"
cd "$T"
npx remotion render src/_yourider/index.tsx DeckDealFlyin "$OUT/shotcraft-demo.mp4" \
  --browser-executable "$MEDIA_CHROME" --gl=swangle --concurrency "${WORKERS:-4}"
"$MEDIA_PY" "$MEDIA_ROOT/pipeline/check.py" "$OUT/shotcraft-demo.mp4" --silent-ok
