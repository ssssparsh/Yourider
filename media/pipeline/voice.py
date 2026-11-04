"""Narration + word timings for a project.

usage: $MEDIA_PY media/pipeline/voice.py <project_dir> <build_dir>

Reads <project_dir>/script.json:
  {"voice": "en_US-ljspeech-medium", "length_scale": 1.05,
   "lines": [{"id": "L1", "start": 0.7, "say": "text the voice speaks", "show": "text the captions show"}]}
Optional "heard_as": {"writer": "rider"} maps known speech-recognition mishearings of names back to the script.
"show" may join spoken words ("Yourider" for the spoken "Your Rider"); every shown word must equal one or more
consecutive spoken words once punctuation and case are removed.

Writes <build_dir>/vo/<id>.wav (Piper) and <build_dir>/words.json (Whisper word times in film seconds).
Fails loudly when lines overlap, the speech does not match the script, or a shown word cannot be mapped.
"""
import difflib
import json
import os
import re
import subprocess
import sys
import wave
from pathlib import Path

GAP = 0.1  # minimum silence between two lines, seconds
MATCH_MIN = 0.7  # homophones ("route"/"root") are expected; below this the audio is not the script
TAKE_GOOD = 0.9  # stop re-taking a line once Whisper understands this much of it
TAKES = 4
norm = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())


def tts(text: str, out: Path, voice: Path, length_scale: float) -> float:
    piper = Path(sys.executable).with_name("piper")
    subprocess.run([str(piper), "-m", str(voice), "--length-scale", str(length_scale), "-f", str(out)],
                   input=text, text=True, check=True, capture_output=True)
    with wave.open(str(out)) as w:
        return w.getnframes() / w.getframerate()


def map_shown(show: str, said: list[str], lid: str) -> list[tuple[str, int, int]]:
    """(shown word, first spoken index, last spoken index) for each shown word."""
    out, i = [], 0
    for wd in show.split():
        target, acc, j = norm(wd), "", i
        while j < len(said) and len(acc) < len(target):
            acc += said[j]
            j += 1
        # joined spellings can differ slightly from the brand spelling ("your"+"rider" = "yourrider" vs "yourider")
        if acc != target and difflib.SequenceMatcher(a=acc, b=target).ratio() < .85:
            raise SystemExit(f"{lid}: shown word {wd!r} does not match spoken words {said[i:j]}")
        out.append((wd, i, j - 1))
        i = j
    if i != len(said):
        raise SystemExit(f"{lid}: spoken words left over after the shown text: {said[i:]}")
    return out


def main() -> None:
    project, build = Path(sys.argv[1]), Path(sys.argv[2])
    spec = json.loads((project / "script.json").read_text())
    voice = Path(os.environ["PIPER_VOICES"]) / f"{spec.get('voice', 'en_US-ljspeech-medium')}.onnx"
    if not voice.exists():
        raise SystemExit(f"voice model missing: {voice} (run media/setup.sh)")
    (build / "vo").mkdir(parents=True, exist_ok=True)
    lines = spec["lines"]
    # known mishearings of names the voice says correctly, e.g. {"writer": "rider"}: applied to what Whisper heard
    alias = {norm(k): norm(v) for k, v in spec.get("heard_as", {}).items()}
    from faster_whisper import WhisperModel
    model = WhisperModel("base.en", device="cpu", compute_type="int8")

    # Piper's synthesis varies run to run and sometimes slurs a word: take each line up to TAKES times,
    # keep the take Whisper understands best, and fail only if no take is intelligible.
    takes: dict[str, tuple] = {}
    for ln in lines:
        wav, said, best = build / "vo" / f"{ln['id']}.wav", [norm(x) for x in ln["say"].split()], None
        for k in range(TAKES):
            tmp = wav.with_suffix(f".take{k}.wav")
            dur = tts(ln["say"], tmp, voice, spec.get("length_scale", 1.0))
            segs, _ = model.transcribe(str(tmp), word_timestamps=True, language="en")
            heard = [(alias.get(norm(x.word), norm(x.word)), x.start, x.end) for s in segs for x in s.words]
            sm = difflib.SequenceMatcher(a=said, b=[h[0] for h in heard], autojunk=False)
            if best is None or sm.ratio() > best[0]:
                best = (sm.ratio(), dur, heard, sm, tmp)
            if sm.ratio() >= TAKE_GOOD:
                break
        ratio, dur, heard, sm, tmp = best
        if ratio < MATCH_MIN:
            raise SystemExit(f"{ln['id']}: no intelligible take in {TAKES} ({ratio:.2f}): heard {[h[0] for h in heard]}; rephrase the line")
        tmp.replace(wav)
        for t in wav.parent.glob(f"{ln['id']}.take*.wav"):
            t.unlink()
        takes[ln["id"]] = (ratio, dur, heard, sm, k + 1)
    for a, b in zip(lines, lines[1:]):
        end = a["start"] + takes[a["id"]][1]
        if end + GAP > b["start"]:
            raise SystemExit(f"{a['id']} ends at {end:.2f}s, too close to {b['id']} at {b['start']:.2f}s: move {b['id']} to >= {end + GAP:.2f}")

    out = {}
    for ln in lines:
        start = ln["start"]
        ratio, dur, heard, sm, ntakes = takes[ln["id"]]
        said = [norm(x) for x in ln["say"].split()]
        timing: list[tuple[float, float] | None] = [None] * len(said)
        for a, b, n in sm.get_matching_blocks():
            for k in range(n):
                timing[a + k] = heard[b + k][1:]
        for i, tm in enumerate(timing):  # unmatched (misheard) words: between their neighbours
            if tm is None:
                prev = next((timing[j][1] for j in range(i - 1, -1, -1) if timing[j]), 0.0)
                nxt = next((timing[j][0] for j in range(i + 1, len(timing)) if timing[j]), dur)
                timing[i] = (prev, max(prev + 0.05, nxt))
        words = [{"w": wd, "t0": round(start + timing[a][0], 3), "t1": round(start + timing[b][1], 3)}
                 for wd, a, b in map_shown(ln["show"], said, ln["id"])]
        out[ln["id"]] = {"start": start, "dur": round(dur, 3), "match": round(ratio, 2), "takes": ntakes, "words": words}
        print(f"{ln['id']} {start:.2f}-{start + dur:.2f} match {ratio:.2f} ({ntakes} take{'s' if ntakes > 1 else ''})  " + " ".join(f"{w['w']}@{w['t0']:.2f}" for w in words))
    (build / "words.json").write_text(json.dumps(out, indent=1))


if __name__ == "__main__":
    main()
