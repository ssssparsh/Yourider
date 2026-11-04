"""Score, foley and narration mix for "One Map" (Yourider). Every sound is synthesized (core/audio) or our own Piper narration.

D major, 96 BPM, D-Bm-G-A one chord per bar. Stops pluck as the pen reaches them, the source lines bring the groove in,
the river is a rumble, a real silence precedes Closed Won, and the network then runs on the full groove.
Writes mix.wav (48 kHz stereo) next to this file.
"""
import json
import os
import sys
from pathlib import Path

import numpy as np
import soundfile as sf
import soxr

HERE = Path(__file__).resolve().parent
LIB = Path(os.environ["LEMO_DIR"])                  # Lemo-Opuscar library (core/audio)
sys.path.insert(0, str(LIB))
from core.audio import pluck as P  # noqa: E402
from core.audio import sfx as X  # noqa: E402

SR = X.SR
FILM = Path(sys.argv[1])                       # folder with vo/*.wav and words.json
EV = json.loads((HERE / "events.json").read_text())
DUR = EV["dur"] + 1.0
music = np.zeros((int(DUR * SR), 2), np.float32)
fx = np.zeros_like(music)
voice = np.zeros_like(music)

BPM = 96
BEAT = 60 / BPM
BAR = 4 * BEAT
CHORDS = [["D3", "A3", "D4", "F#4"], ["B2", "F#3", "B3", "D4"], ["G2", "D3", "G3", "B3"], ["A2", "E3", "A3", "C#4"]]
ARP = [["D5", "F#5", "A5", "F#5"], ["B4", "D5", "F#5", "D5"], ["G4", "B4", "D5", "B4"], ["A4", "C#5", "E5", "C#5"]]
BASS = ["D2", "B1", "G1", "A1"]
LINE_NOTE = {"L": "D5", "W": "F#5", "E": "A5", "O": "B5", "R": "E5"}
RED_STOPS = {"NEW": "D5", "CON": "E5", "QUA": "F#5", "PRO": "A5", "NEG": "B5", "FUP": "D6"}
cue = {e["type"]: e["t"] for e in EV["ev"] if e["type"] not in ("stop", "minor", "depart", "x", "drop")}
SILENCE = (cue["silence"], cue["arrive"])


def groove(t0, t1, kal=0.0, gtr=0.0, bass=0.0, eighths=True):
    """Bars aligned to the film's bar grid from t0 to t1."""
    b = int(np.ceil(t0 / BAR - 1e-6))
    while b * BAR < t1:
        tb, ch = b * BAR, b % 4
        if gtr: X.add(music, P.strum("nylon_guitar", CHORDS[ch], 2.4, vel=.55, spread=.03), tb, gtr * .5, -.25)
        if bass:
            for k in (0, 2):
                X.add(music, P.pluck("upright_bass_pizz", BASS[ch], 1.2, vel=.75), tb + k * BEAT, bass, 0)
        if kal:
            step = BEAT / 2 if eighths else BEAT
            for i in range(int(BAR / step)):
                tt = tb + i * step
                if t0 <= tt < t1: X.add(music, P.pluck("kalimba", ARP[ch][i % 4], .9, vel=.5), tt, kal * (1 if i % 2 == 0 else .7), .3)
        b += 1


# ---------------------------------------------------------------- music
X.add(music, X.lp(X.brown(DUR), 900) * .02, 0, 1, 0)                               # paper room tone, whole film
X.add(music, P.pluck("harp", "D4", 4, vel=.35), 0.35, .35, -.2)                     # the empty sheet
groove(4.4, 9.4, kal=.16, eighths=False)                                            # the route is drawn
groove(cue["pullback"], 15.6, kal=.2, gtr=.42, bass=.5)                             # leads arrive: the groove enters
groove(19.4, SILENCE[0] - .02, bass=.4)                                             # waiting at Follow-up: bass pedal only
groove(25.0, 32.4, kal=.22, gtr=.5, bass=.55)                                       # the network runs
# riser into the silence, then the arrival chord
riser = X.bp(X.noise(1.6), 600, 5000) * np.linspace(0, 1, int(1.6 * SR)) ** 2 * .05
X.add(music, riser, SILENCE[0] - 1.6, 1, 0)
X.add(music, P.strum("harp", ["D3", "A3", "D4", "F#4", "A4", "D5", "F#5", "A5"], 6, vel=.85, spread=.035), SILENCE[1], .55, 0)
X.add(music, P.strum("nylon_guitar", CHORDS[0], 4, vel=.8), SILENCE[1], .35, -.3)
# ending: one last D chord that rings out under the title
X.add(music, P.strum("harp", ["D4", "F#4", "A4", "D5"], 5, vel=.6, spread=.06, up=True), 32.4, .45, .1)
# hard silence: nothing but room tone between the last word and the arrival
s0, s1 = int(SILENCE[0] * SR), int((SILENCE[1] - .03) * SR)
music[s0:s1] *= 0.04

# ---------------------------------------------------------------- foley on picture events
def chime():
    a, b = P.pluck("music_box", "A5", 2, vel=.7), P.pluck("music_box", "F#5", 2, vel=.6)
    out = np.zeros(max(len(a), len(b) + int(.18 * SR)), np.float32); out[:len(a)] += a; out[int(.18 * SR):int(.18 * SR) + len(b)] += .7 * b
    return out
for e in EV["ev"]:
    t, ty, pan = e["t"], e["type"], e.get("pan", 0) * .6
    if ty == "stop":
        note = RED_STOPS.get(e["id"]) if e.get("line") == "L" else LINE_NOTE.get(e.get("line"), "A5")
        X.add(fx, P.pluck("kalimba", note, 1.4, vel=.8), t, .5 if e.get("tier") == 1 else .38, pan)
        X.add(fx, X.click(1.3, .5), t, .08, pan)
    elif ty == "minor":
        X.add(fx, X.click(1.6, .4), t, .035, pan)
    elif ty == "depart" and t > 3:
        X.add(fx, X.whoosh(.3, .5), t - .1, .06, pan)
    elif ty == "x":
        X.add(fx, X.ding(.5), t, .14, pan)
    elif ty == "drop":
        X.add(fx, X.thump(1.0, 52), t, .7, 0)
        X.add(fx, X.crash(.4), t, .07, 0)
        X.add(fx, X.whoosh(.42, .8), t - .45, .12, .2)
X.add(fx, chime(), cue["firstdot"], .4, 0)
X.add(fx, chime(), cue["title"], .3, 0)
X.add(fx, X.whoosh(.6, .7), cue["dive"], .1, 0)
X.add(fx, X.lp(X.rumble(1.4, 1.0), 400), 17.2, .35, 0)                                # under the river
for k in range(int((32.4 - 26.0) / (BEAT / 2))):                                      # rail clacks once the network runs
    if k % 2 == 0: X.add(fx, X.clack(1.0 + .2 * (k % 4 == 0), .4), 26.0 + k * BEAT / 2, .035, (-.4, .4)[k % 4 == 0])

# ---------------------------------------------------------------- narration, ducked music
words = json.loads((FILM / "words.json").read_text())
duck = np.ones(len(music), np.float32)
for lid, ln in words.items():
    v, sr = sf.read(FILM / "vo" / f"{lid}.wav", dtype="float32")
    v = soxr.resample(v, sr, SR) * 1.0
    X.add(voice, v, ln["start"], 1.0, 0)
    a, b = int((ln["start"] - .12) * SR), int((ln["start"] + ln["dur"] + .15) * SR)
    duck[a:b] = .42
k = int(.12 * SR)
duck = np.convolve(duck, np.ones(k) / k, mode="same").astype(np.float32)          # smooth the ducking
mix = music * duck[:, None] * 1.0 + fx * (.6 + .4 * duck[:, None]) + voice * 1.15
peak = np.abs(mix).max()
mix = mix * (.89 / peak)
sf.write(HERE / "mix.wav", mix.astype(np.float32), SR, subtype="PCM_24")
print(f"mix.wav {len(mix) / SR:.1f}s peak-normalised from {peak:.2f}")
