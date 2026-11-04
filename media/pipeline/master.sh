#!/usr/bin/env bash
# Master and mux: two-pass loudness normalisation to -14 LUFS / -1.2 dBTP, picture copied untouched.
# usage: media/pipeline/master.sh <video.mp4> <mix.wav> <out.mp4> [duration_seconds]
set -euo pipefail
V="$1" A="$2" OUT="$3" T="${4:-}"
J=$(ffmpeg -hide_banner -nostats -i "$A" -af loudnorm=I=-14:TP=-1.2:LRA=11:print_format=json -f null - 2>&1 | sed -n '/{/,/}/p')
g() { echo "$J" | grep "\"$1\"" | cut -d'"' -f4; }
[ -n "$(g input_i)" ] || { echo "master.sh: could not measure loudness of $A" >&2; exit 1; }
ffmpeg -v error -y -i "$V" -i "$A" -filter_complex \
  "[1:a]loudnorm=I=-14:TP=-1.2:LRA=11:measured_I=$(g input_i):measured_TP=$(g input_tp):measured_LRA=$(g input_lra):measured_thresh=$(g input_thresh):offset=$(g target_offset):linear=true,aresample=48000[a]" \
  -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 256k ${T:+-t "$T"} -movflags +faststart "$OUT"
echo "master.sh: $OUT"
