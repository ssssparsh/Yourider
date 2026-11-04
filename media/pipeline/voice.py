"""Narration + word timings for a project.

usage: $MEDIA_PY media/pipeline/voice.py <project_dir> <build_dir>

Reads <project_dir>/script.json:
  {"voice": {"provider": "auto",
             "elevenlabs": {"voice_id": "...", "model_id": "eleven_multilingual_v2"},
             "kokoro": {"voice": "am_michael", "speed": 1.0},
             "piper": {"model": "en_US-ljspeech-medium", "length_scale": 1.05}},
   "heard_as": {"writer": "rider"},
   "lines": [{"id": "L1", "start": 0.7, "say": "text the voice speaks", "show": "text the captions show"}]}

Providers (provider "auto" picks the first available):
  elevenlabs  paid, best voice; needs ELEVENLABS_API_KEY (Network secrets) and api.elevenlabs.io allowed.
              Word times come from ElevenLabs' own character alignment.
  kokoro      free, local (Apache-2.0); model installed by media/setup.sh.
  piper       free, local; last resort.
A legacy string "voice": "en_US-ljspeech-medium" still means Piper.

Every take is checked with Whisper: if the speech does not match the script the line is re-taken (up to 4 times
for local voices, 2 for paid ones) and the clearest take kept; the build fails if none is intelligible.
"heard_as" maps known mishearings of names back to the script. "show" may join spoken words ("Yourider" for
the spoken "Your Rider"). Fails loudly when lines overlap or a shown word cannot be mapped.

Writes <build_dir>/vo/<id>.wav and <build_dir>/words.json (word times in film seconds).
"""
import base64
import difflib
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import wave
from pathlib import Path

GAP = 0.1  # minimum silence between two lines, seconds
MATCH_MIN = 0.7  # homophones ("route"/"root") are expected; below this the audio is not the script
TAKE_GOOD = 0.9  # stop re-taking a line once Whisper understands this much of it
TAKES = {"elevenlabs": 2, "kokoro": 4, "piper": 4}
norm = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())
TOOLS = Path(os.environ.get("MEDIA_TOOLS", ""))
Words = list[tuple[str, float, float]]  # (normalised word, start s, end s)


def wav_seconds(p: Path) -> float:
    with wave.open(str(p)) as w:
        return w.getnframes() / w.getframerate()


# ---------------------------------------------------------------- providers: (text, out wav) -> (seconds, word times or None)
def piper(cfg: dict):
    model = Path(os.environ["PIPER_VOICES"]) / f"{cfg.get('model', 'en_US-ljspeech-medium')}.onnx"
    if not model.exists():
        raise SystemExit(f"Piper voice missing: {model} (run media/setup.sh)")
    exe = Path(sys.executable).with_name("piper")

    def say(text: str, out: Path):
        subprocess.run([str(exe), "-m", str(model), "--length-scale", str(cfg.get("length_scale", 1.0)), "-f", str(out)],
                       input=text, text=True, check=True, capture_output=True)
        return wav_seconds(out), None
    return say


def kokoro(cfg: dict):
    d = TOOLS / "kokoro"
    if not (d / "model_quantized.onnx").exists():
        raise SystemExit(f"Kokoro model missing in {d} (run media/setup.sh)")
    import soundfile as sf
    from kokoro_onnx import Kokoro
    k = Kokoro(str(d / "model_quantized.onnx"), str(d / "voices.npz"))
    voice, speed = cfg.get("voice", "am_michael"), cfg.get("speed", 1.0)

    def say(text: str, out: Path):
        samples, sr = k.create(text, voice=voice, speed=speed, lang="en-us")
        sf.write(out, samples, sr)
        return len(samples) / sr, None
    return say


def elevenlabs(cfg: dict):
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key or not cfg.get("voice_id"):
        raise SystemExit("ElevenLabs needs ELEVENLABS_API_KEY in the environment and voice.elevenlabs.voice_id in script.json")
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{cfg['voice_id']}/with-timestamps?output_format=mp3_44100_128"
    body = {"text": "", "model_id": cfg.get("model_id", "eleven_multilingual_v2")}
    if cfg.get("voice_settings"):
        body["voice_settings"] = cfg["voice_settings"]

    def say(text: str, out: Path):
        req = urllib.request.Request(url, data=json.dumps({**body, "text": text}).encode(), method="POST",
                                     headers={"xi-api-key": key, "Content-Type": "application/json", "Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                res = json.load(r)
        except urllib.error.HTTPError as e:
            raise SystemExit(f"ElevenLabs HTTP {e.code}: {e.read()[:300]!r}") from None
        except urllib.error.URLError as e:
            raise SystemExit(f"ElevenLabs unreachable ({e.reason}): allow api.elevenlabs.io in the environment's network settings") from None
        al = res.get("alignment")
        if not res.get("audio_base64") or not al or "characters" not in al:
            raise SystemExit(f"ElevenLabs response missing audio or alignment; keys: {sorted(res)}")
        with tempfile.NamedTemporaryFile(suffix=".mp3") as mp3:
            mp3.write(base64.b64decode(res["audio_base64"]))
            mp3.flush()
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", mp3.name, "-ar", "44100", "-ac", "1", str(out)], check=True)
        return wav_seconds(out), chars_to_words(al)
    return say


def chars_to_words(al: dict) -> Words:
    """ElevenLabs character alignment -> (normalised word, start, end); punctuation-only tokens are dropped."""
    words, cur, t0, t1 = [], "", 0.0, 0.0
    for ch, s, e in zip(al["characters"], al["character_start_times_seconds"], al["character_end_times_seconds"]):
        if ch.isspace():
            if norm(cur):
                words.append((norm(cur), t0, t1))
            cur = ""
            continue
        if not cur:
            t0 = s
        cur, t1 = cur + ch, e
    if norm(cur):
        words.append((norm(cur), t0, t1))
    return words


def pick(spec: dict):
    v = spec.get("voice", {})
    if isinstance(v, str):  # legacy: a Piper model name
        return "piper", piper({"model": v, "length_scale": spec.get("length_scale", 1.0)})
    want = v.get("provider", "auto")
    order = [want] if want != "auto" else ["elevenlabs", "kokoro", "piper"]
    for name in order:
        if name == "elevenlabs" and want == "auto" and not (os.environ.get("ELEVENLABS_API_KEY") and v.get("elevenlabs", {}).get("voice_id")):
            continue
        if name == "kokoro" and want == "auto" and not (TOOLS / "kokoro" / "model_quantized.onnx").exists():
            continue
        return name, {"elevenlabs": elevenlabs, "kokoro": kokoro, "piper": piper}[name](v.get(name, {}))
    raise SystemExit("no voice provider available (run media/setup.sh)")


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


def align(said: list[str], timed: Words, dur: float) -> tuple[list[tuple[float, float]], float]:
    sm = difflib.SequenceMatcher(a=said, b=[t[0] for t in timed], autojunk=False)
    timing: list[tuple[float, float] | None] = [None] * len(said)
    for a, b, n in sm.get_matching_blocks():
        for k in range(n):
            timing[a + k] = timed[b + k][1:]
    for i, tm in enumerate(timing):  # unmatched (misheard) words: between their neighbours
        if tm is None:
            prev = next((timing[j][1] for j in range(i - 1, -1, -1) if timing[j]), 0.0)
            nxt = next((timing[j][0] for j in range(i + 1, len(timing)) if timing[j]), dur)
            timing[i] = (prev, max(prev + 0.05, nxt))
    return timing, sm.ratio()


def main() -> None:
    project, build = Path(sys.argv[1]), Path(sys.argv[2])
    spec = json.loads((project / "script.json").read_text())
    (build / "vo").mkdir(parents=True, exist_ok=True)
    lines = spec["lines"]
    provider, say = pick(spec)
    print(f"voice provider: {provider}")
    alias = {norm(k): norm(v) for k, v in spec.get("heard_as", {}).items()}
    from faster_whisper import WhisperModel
    model = WhisperModel("base.en", device="cpu", compute_type="int8")

    takes: dict[str, tuple] = {}
    for ln in lines:
        wav, said, best = build / "vo" / f"{ln['id']}.wav", [norm(x) for x in ln["say"].split()], None
        for k in range(TAKES[provider]):
            tmp = wav.with_suffix(f".take{k}.wav")
            dur, timed = say(ln["say"], tmp)
            segs, _ = model.transcribe(str(tmp), word_timestamps=True, language="en")
            heard = [(alias.get(norm(x.word), norm(x.word)), x.start, x.end) for s in segs for x in s.words]
            ratio = difflib.SequenceMatcher(a=said, b=[h[0] for h in heard], autojunk=False).ratio()
            if best is None or ratio > best[0]:
                best = (ratio, dur, timed or heard, tmp, "provider" if timed else "whisper")
            if ratio >= TAKE_GOOD:
                break
        ratio, dur, timed, tmp, source = best
        if ratio < MATCH_MIN:
            raise SystemExit(f"{ln['id']}: no intelligible take in {k + 1} ({ratio:.2f}); rephrase the line or fix heard_as")
        tmp.replace(wav)
        for t in wav.parent.glob(f"{ln['id']}.take*.wav"):
            t.unlink()
        takes[ln["id"]] = (ratio, dur, timed, source, k + 1)
    for a, b in zip(lines, lines[1:]):
        end = a["start"] + takes[a["id"]][1]
        if end + GAP > b["start"]:
            raise SystemExit(f"{a['id']} ends at {end:.2f}s, too close to {b['id']} at {b['start']:.2f}s: move {b['id']} to >= {end + GAP:.2f}")

    out = {}
    for ln in lines:
        start = ln["start"]
        ratio, dur, timed, source, ntakes = takes[ln["id"]]
        said = [norm(x) for x in ln["say"].split()]
        timing, _ = align(said, timed, dur)
        words = [{"w": wd, "t0": round(start + timing[a][0], 3), "t1": round(start + timing[b][1], 3)}
                 for wd, a, b in map_shown(ln["show"], said, ln["id"])]
        out[ln["id"]] = {"start": start, "dur": round(dur, 3), "match": round(ratio, 2), "takes": ntakes,
                         "provider": provider, "timing": source, "words": words}
        print(f"{ln['id']} {start:.2f}-{start + dur:.2f} match {ratio:.2f} ({ntakes} take{'s' if ntakes > 1 else ''}, {source} timing)  "
              + " ".join(f"{w['w']}@{w['t0']:.2f}" for w in words))
    (build / "words.json").write_text(json.dumps(out, indent=1))


if __name__ == "__main__":
    main()
