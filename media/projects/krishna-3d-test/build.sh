#!/usr/bin/env bash
# 10 s cartoon 3D test reel: Bal Krishna built in code (Blender, CPU Cycles, toon shading, Freestyle outlines).
# usage: media/projects/krishna-3d-test/build.sh   -> media/out/krishna-3d-test.mp4 (1080x1920)
# Renders 120 frames at 12 fps ("on twos", like hand-drawn cartoons) at 540x960 in ONE process, then upscales.
# Measured per frame: Freestyle outlines ~20 s (single-threaded), so outlines are inverted-hull geometry (~free);
# 4 samples + denoise is enough for flat toon shading. Two processes only fight over the 4 CPUs.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/env.sh"
P="$MEDIA_ROOT/projects/krishna-3d-test"; B="$MEDIA_ROOT/.build/krishna-3d-test"; OUT="$MEDIA_ROOT/out"
mkdir -p "$B" "$OUT"
export KR_W=${KR_W:-540} KR_H=${KR_H:-960} KR_SAMPLES=${KR_SAMPLES:-4} KR_LINES=${KR_LINES:-hull}
if [ -z "${SKIP_RENDER:-}" ]; then
  rm -f "$B"/f_*.png
  "$MEDIA_BLENDER_PY" "$P/krishna.py" -- "$B" anim 1 120 > "$B/render.log" 2>&1
fi
[ "$(ls "$B"/f_*.png | wc -l)" -eq 120 ] || { echo "expected 120 frames" >&2; exit 1; }
"$MEDIA_PY" "$MEDIA_ROOT/projects/diwali-2026/sounds.py" "$B/sfx" --duration 10 >/dev/null
ffmpeg -v error -y -i "$B/sfx/drone.mp3" -i "$B/sfx/bell.mp3" -filter_complex \
  "[0]volume=0.8[d];[1]adelay=400|400,volume=0.35[b];[d][b]amix=inputs=2:normalize=0,atrim=0:10,afade=t=out:st=8.8:d=1.2,loudnorm=I=-16:TP=-1.5" \
  -ar 48000 "$B/audio.wav"
ffmpeg -v error -y -framerate 12 -i "$B/f_%04d.png" -i "$B/audio.wav" \
  -vf "scale=1080:1920:flags=lanczos,fps=30,format=yuv420p" -c:v libx264 -crf 17 -preset slow -c:a aac -b:a 192k -shortest \
  "$OUT/krishna-3d-test.mp4"
echo "$OUT/krishna-3d-test.mp4"
