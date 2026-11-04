"""QA for a rendered video. Exit code 1 if any check fails.

usage: $MEDIA_PY media/pipeline/check.py <video.mp4> [--words words.json] [--sheet out.jpg]
                                          [--size 1920x1080] [--fps 30] [--silence 24.2:24.9 ...] [--lufs -14]

Checks: resolution and frame rate, an audio stream, integrated loudness within 1 LU of the target,
true peak at or below -1.0 dBTP, planned silent windows (mean below -30 dB), no other dead air (< -45 dB for > 0.5 s),
and words that fall past the end.
With --words, writes a contact sheet of frames at the middle of sampled words, each labelled with the word
that should be highlighted at that moment, for a person (or the video-qa agent) to look at.
"""
import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

fails: list[str] = []


def ok(cond: bool, msg: str) -> None:
    print(("PASS " if cond else "FAIL ") + msg)
    if not cond:
        fails.append(msg)


ap = argparse.ArgumentParser()
ap.add_argument("video")
ap.add_argument("--words")
ap.add_argument("--sheet")
ap.add_argument("--size", default="1920x1080")
ap.add_argument("--fps", type=float, default=30)
ap.add_argument("--silence", nargs="*", default=[])
ap.add_argument("--lufs", type=float, default=-14)
ap.add_argument("--silent-ok", action="store_true", help="silent test render: skip audio, loudness and dead-air checks")
a = ap.parse_args()
v = a.video

info = json.loads(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration:stream=codec_type,width,height,r_frame_rate",
                                  "-of", "json", v], check=True, capture_output=True, text=True).stdout)
dur = float(info["format"]["duration"])
vs = next(s for s in info["streams"] if s["codec_type"] == "video")
num, den = map(int, vs["r_frame_rate"].split("/"))
ok(f"{vs['width']}x{vs['height']}" == a.size, f"size {vs['width']}x{vs['height']} (want {a.size})")
ok(abs(num / den - a.fps) < .01, f"fps {num / den:g} (want {a.fps:g})")
print(f"INFO duration {dur:.2f}s")
if a.silent_ok:
    print("INFO --silent-ok: audio, loudness and dead-air checks skipped")
    print("RESULT " + ("PASS" if not fails else f"FAIL ({len(fails)})"))
    sys.exit(1 if fails else 0)
ok(any(s["codec_type"] == "audio" for s in info["streams"]), "audio stream present")

eb = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", v, "-af", "ebur128=peak=true", "-f", "null", "-"], capture_output=True, text=True).stderr
summ = eb[eb.rfind("Summary:"):]
lufs = float(re.search(r"I:\s+(-?[\d.]+) LUFS", summ).group(1))
peak = float(re.search(r"Peak:\s+(-?[\d.]+) dBFS", summ).group(1))
ok(abs(lufs - a.lufs) <= 1.0, f"loudness {lufs} LUFS (want {a.lufs} +/-1)")
ok(peak <= -1.0, f"true peak {peak} dBTP (want <= -1.0)")

for w in a.silence:
    s0, s1 = map(float, w.split(":"))
    vd = subprocess.run(["ffmpeg", "-hide_banner", "-ss", str(s0), "-t", str(s1 - s0), "-i", v, "-af", "volumedetect", "-f", "null", "-"], capture_output=True, text=True).stderr
    m = float(re.search(r"mean_volume: (-?[\d.]+) dB", vd).group(1))
    ok(m < -30, f"silence {s0}-{s1}s mean {m} dB (want < -30)")

# dead air: digital silence anywhere the plan did not ask for it sounds like a fault on a phone speaker
planned = [tuple(map(float, w.split(":"))) for w in a.silence]
sd = subprocess.run(["ffmpeg", "-hide_banner", "-i", v, "-af", "silencedetect=noise=-45dB:d=0.5", "-f", "null", "-"], capture_output=True, text=True).stderr
starts = [float(x) for x in re.findall(r"silence_start: (-?[\d.]+)", sd)]
ends = [float(x) for x in re.findall(r"silence_end: (-?[\d.]+)", sd)] + [dur]
dead = [(round(s0, 2), round(s1, 2)) for s0, s1 in zip(starts, ends)
        if not any(p0 - .3 <= s0 and s1 <= p1 + .3 for p0, p1 in planned)]
ok(not dead, "no unplanned dead air (< -45 dB for > 0.5 s)" + (f": {dead}" if dead else ""))

if a.words:
    words = [w for ln in json.loads(Path(a.words).read_text()).values() for w in ln["words"]]
    late = [w["w"] for w in words if w["t1"] > dur]
    ok(not late, f"all {len(words)} words end before the video ends" + (f" (late: {late})" if late else ""))
    if a.sheet:
        step = max(1, len(words) // 12)
        pick = words[::step][:12]
        tiles = []
        with tempfile.TemporaryDirectory() as td:
            for i, w in enumerate(pick):
                t = (w["t0"] + w["t1"]) / 2
                f = Path(td) / f"{i}.jpg"
                subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{t:.3f}", "-i", v, "-frames:v", "1", "-vf", "scale=480:-2", str(f)], check=True)
                im = Image.open(f).convert("RGB")
                d = ImageDraw.Draw(im)
                d.rectangle([0, 0, 480, 26], fill=(0, 0, 0))
                d.text((6, 6), f"{t:.2f}s  expect: {w['w']}", fill=(255, 230, 0))
                tiles.append(im)
        cols = 4
        rows = (len(tiles) + cols - 1) // cols
        sheet = Image.new("RGB", (480 * cols, tiles[0].height * rows), (16, 16, 16))
        for i, im in enumerate(tiles):
            sheet.paste(im, ((i % cols) * 480, (i // cols) * im.height))
        sheet.save(a.sheet, quality=88)
        print(f"INFO sheet {a.sheet}: {len(tiles)} frames at word times; check each highlighted word matches its label")

print("RESULT " + ("PASS" if not fails else f"FAIL ({len(fails)})"))
sys.exit(1 if fails else 0)
