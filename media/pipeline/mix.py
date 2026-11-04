"""Mix narration and sound effects for a project into one master WAV.

usage: $MEDIA_PY media/pipeline/mix.py <project_dir> <build_dir> <sfx_dir> <out.wav>

Uses script.json "lines" (narration starts, wavs in <build_dir>/vo) and optional "sfx":
  [{"file": "whoosh-in", "t": 0.0, "gain": 0.35}]   (file = <sfx_dir>/<file>.mp3)
  or anchored to a spoken word: {"file": "focus", "word": "handshake", "offset": -0.05}
and "duration" (seconds). A quiet room tone runs underneath unless "room_tone": false. Effects duck under the voice; the result is loudness-normalised to -14 LUFS, -1.5 dBTP.
"""
import json
import subprocess
import sys
from pathlib import Path

project, build, sfx_dir, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4])
spec = json.loads((project / "script.json").read_text())
dur = spec["duration"]
WORDS = [w for ln in json.loads((build / "words.json").read_text()).values() for w in ln["words"]] if (build / "words.json").exists() else []


def word_time(word: str) -> float:
    """Start of the first spoken word matching `word` (cues anchored to speech follow whichever voice take was kept)."""
    key = word.lower().strip(".,!?")
    for w in WORDS:
        if w["w"].lower().strip(".,!?") == key:
            return w["t0"]
    raise SystemExit(f"sfx cue anchored to {word!r}, which is not in words.json")


inputs, filt, voices, fx = [], [], [], []
for ln in spec["lines"]:
    k = len(inputs) // 2
    inputs += ["-i", str(build / "vo" / f"{ln['id']}.wav")]
    ms = int(ln["start"] * 1000)
    filt.append(f"[{k}:a]adelay={ms}|{ms},aformat=channel_layouts=stereo[v{k}]")
    voices.append(f"[v{k}]")
for cue in spec.get("sfx", []):
    f = sfx_dir / f"{cue['file']}.mp3"
    if not f.exists():
        raise SystemExit(f"missing sound effect: {f}")
    k = len(inputs) // 2
    inputs += ["-i", str(f)]
    t = cue["t"] if "t" in cue else word_time(cue["word"]) + cue.get("offset", 0.0)
    ms = int(max(0.0, t) * 1000)
    filt.append(f"[{k}:a]adelay={ms}|{ms},volume={cue.get('gain', 0.4)},aformat=channel_layouts=stereo[f{k}]")
    fx.append(f"[f{k}]")
filt.append("".join(voices) + f"amix=inputs={len(voices)}:normalize=0,asplit=2[vk][vm]")
if fx:
    filt.append("".join(fx) + f"amix=inputs={len(fx)}:normalize=0[fx]")
    filt.append("[fx][vk]sidechaincompress=threshold=0.04:ratio=4[fxd]")
    filt.append("[fxd][vm]amix=inputs=2:normalize=0[pre]")
else:
    filt.append("[vm]anull[pre]")
    filt.append("[vk]anullsink")
# a quiet paper room tone under everything: no dead digital silence between lines or at the tail
if spec.get("room_tone", True):
    k = len(inputs) // 2
    inputs += ["-f", "lavfi", "-t", str(dur), "-i", "anoisesrc=color=brown:amplitude=0.5:seed=7"]
    filt.append(f"[{k}:a]lowpass=f=700,highpass=f=60,volume=0.035,aformat=channel_layouts=stereo[room]")
    filt.append("[pre][room]amix=inputs=2:normalize=0,apad[pre2]")
else:
    filt.append("[pre]apad[pre2]")
filt.append(f"[pre2]atrim=0:{dur},loudnorm=I=-14:TP=-1.5[out]")
subprocess.run(["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", ";".join(filt), "-map", "[out]", "-ar", "48000", str(out)], check=True)
print(f"{out}: {len(voices)} lines, {len(fx)} effects, {dur}s")
