"""Join short videos into one long video with crossfades.

usage: python join.py out.mp4 clip1.mp4 clip2.mp4 ... [--fade 0.6] [--size 1920x1080] [--fps 30]

Each clip is first normalised (size, fps, 48 kHz stereo, two-pass -14 LUFS) so clips from different engines match,
then picture and sound crossfade together and a limiter keeps the true peak under -1 dBTP. Fails loudly if a clip has no audio or is shorter than two fades.
"""
import argparse
import json
import subprocess
import tempfile
from pathlib import Path


def probe(p: Path) -> dict:
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration:stream=codec_type", "-of", "json", str(p)],
                         check=True, capture_output=True, text=True).stdout
    j = json.loads(out)
    return {"dur": float(j["format"]["duration"]), "audio": any(s["codec_type"] == "audio" for s in j["streams"])}


def loudnorm_2pass(clip: Path) -> str:
    """A linear (two-pass) loudnorm filter for this clip: exact -14 LUFS without the overshoot of the one-pass mode."""
    err = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(clip), "-af", "loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json",
                          "-f", "null", "-"], capture_output=True, text=True).stderr
    m = json.loads(err[err.rindex("{"):err.rindex("}") + 1])
    return (f"loudnorm=I=-14:TP=-1.5:LRA=11:measured_I={m['input_i']}:measured_TP={m['input_tp']}:measured_LRA={m['input_lra']}"
            f":measured_thresh={m['input_thresh']}:offset={m['target_offset']}:linear=true")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("clips", nargs="+")
    ap.add_argument("--fade", type=float, default=0.6)
    ap.add_argument("--size", default="1920x1080")
    ap.add_argument("--fps", type=int, default=30)
    a = ap.parse_args()
    w, h = a.size.split("x")
    tmp = Path(tempfile.mkdtemp(prefix="join_"))
    norm, durs = [], []
    for i, c in enumerate(map(Path, a.clips)):
        info = probe(c)
        if not info["audio"]:
            raise SystemExit(f"{c}: no audio stream")
        if info["dur"] < 2 * a.fade:
            raise SystemExit(f"{c}: {info['dur']:.2f}s is shorter than two fades")
        n = tmp / f"n{i}.mkv"   # lossless PCM audio in the intermediates: one AAC encode at the very end
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(c),
                        "-vf", f"scale={w}:{h}:force_original_aspect_ratio=decrease,pad={w}:{h}:(ow-iw)/2:(oh-ih)/2:color=0x0f0f10,fps={a.fps},format=yuv420p,settb=1/{a.fps}",
                        "-af", f"aformat=channel_layouts=stereo,{loudnorm_2pass(c)},aresample=48000",
                        "-c:v", "libx264", "-crf", "16", "-preset", "medium", "-c:a", "pcm_s24le", "-ar", "48000", str(n)], check=True)
        norm.append(n)
        durs.append(probe(n)["dur"])
    inputs = [x for n in norm for x in ("-i", str(n))]
    f, vprev, aprev, off, graph = a.fade, "[0:v]", "[0:a]", 0.0, []
    for i in range(1, len(norm)):
        off += durs[i - 1] - f
        graph.append(f"{vprev}[{i}:v]xfade=transition=fade:duration={f}:offset={off:.3f}[v{i}]")
        graph.append(f"{aprev}[{i}:a]acrossfade=d={f}:c1=tri:c2=tri[a{i}]")
        vprev, aprev = f"[v{i}]", f"[a{i}]"
    # crossfades can stack peaks: a limiter at -1.9 dBFS keeps the true peak under -1 dBTP after AAC
    graph.append(f"{aprev}alimiter=limit=0.8:level=disabled,aresample=48000[aout]")
    cmd = ["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", ";".join(graph), "-map", vprev, "-map", "[aout]"]
    cmd += ["-c:v", "libx264", "-crf", "18", "-preset", "medium", "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart", a.out]
    subprocess.run(cmd, check=True)
    total = sum(durs) - f * (len(durs) - 1)
    print(f"{a.out}: {len(norm)} clips, expected {total:.2f}s, got {probe(Path(a.out))['dur']:.2f}s")


if __name__ == "__main__":
    main()
