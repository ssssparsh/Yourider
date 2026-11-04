"""HyperFrames composition for "How I edit video with Claude" (1080x1350, 30 fps, 40 s). See PLAN.md.

usage: python gen.py <project_dir> <build_dir>   -> <build_dir>/hf/index.html (+ resized evidence images)

Same rules as linkedin-intro/gen.py:
- every event that lands on a spoken word is computed from <build_dir>/words.json, never from guessed seconds;
- every script.json sound cue is checked against the picture event it belongs to (within 1.5 frames);
- caption pages can never overlap (assert), and nothing important sits under the caption band;
- the planned silence is computed from words.json + the cues (same rule as build.sh) and nothing may move in it.
Needs in <build_dir>/hf: Inter.woff2 (for measuring). Reads the evidence stills from <build_dir>/evidence.
"""
import html
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageFont

PROJECT, BUILD = Path(sys.argv[1]), Path(sys.argv[2])
HF, EV = BUILD / "hf", BUILD / "evidence"
MEDIA = PROJECT.parent.parent
spec = json.loads((PROJECT / "script.json").read_text())
words = json.loads((BUILD / "words.json").read_text())
scr = spec["on_screen"]
DUR, FPS = spec["duration"], spec["format"]["fps"]
W, H = spec["format"]["width"], spec["format"]["height"]
F = 1 / FPS
pal = spec["palette"]
GROUND, SURF, INK, MUTED, COB, WHITE = pal["ground"], pal["surface"], pal["ink"], pal["muted"], pal["accent"], pal["accent_ink"]
BORDER = "rgba(11,12,14,.15)"

# ---------------------------------------------------------------- frame geometry
SAFE_L, SAFE_R, SAFE_T, SAFE_B = round(W * .1), round(W * .9), round(H * .1), round(H * .9)  # 80% title-safe
LM = SAFE_L + 4                  # the left axis for type (plan: 96 px, moved inside title-safe)
FX, FW = SAFE_L, SAFE_R - SAFE_L  # interface fragments span the title-safe measure
TEXT_W = SAFE_R - LM - 4
HL_TOP = SAFE_T + 5
CAP_BOTTOM = SAFE_B - 15         # caption plate grows up from here
INFO_MAX = 1010                  # nothing important below this while a caption plate can show

# ---------------------------------------------------------------- type measuring (same font file the page uses)
FONT = HF / "Inter.woff2"
_fonts: dict = {}


def font(size: float, weight: int) -> ImageFont.FreeTypeFont:
    k = (round(size), weight)
    if k not in _fonts:
        f = ImageFont.truetype(str(FONT), round(size))
        f.set_variation_by_axes([weight])
        _fonts[k] = f
    return _fonts[k]


def text_w(s: str, size: float, weight: int, track: float) -> float:
    return font(size, weight).getlength(s) + track * size * len(s)


def fit(lines: list[str], cap: float, weight: int = 600, track: float = -.04, room: float = TEXT_W) -> int:
    w100 = max(text_w(s, 100, weight, track) for s in lines)
    return int(min(cap, 100 * room / w100))


def wrap_text(s: str, size: int, weight: int, room: float, track: float = -.01) -> list[str]:
    out, cur = [], ""
    for wd in s.split(" "):
        t = (cur + " " + wd) if cur else wd
        if cur and text_w(t, size, weight, track) > room:
            out.append(cur)
            cur = wd
        else:
            cur = t
    return out + [cur]


# ---------------------------------------------------------------- eases and springs (numbers from the shotcraft demos)
def bez(x1: float, y1: float, x2: float, y2: float):
    def f(x: float) -> float:
        lo, hi = 0.0, 1.0
        for _ in range(40):
            t = (lo + hi) / 2
            bx = 3 * x1 * t * (1 - t) ** 2 + 3 * x2 * t * t * (1 - t) + t ** 3
            lo, hi = (t, hi) if bx < x else (lo, t)
        t = (lo + hi) / 2
        return 3 * y1 * t * (1 - t) ** 2 + 3 * y2 * t * t * (1 - t) + t ** 3
    return f


E_OUT = bez(.22, 1, .36, 1)          # EASE.out
E_SMOOTH = bez(.65, 0, .35, 1)       # EASE.smooth
E_SNAPPY = bez(.16, 1, .3, 1)        # EASE.snappy
E_OVER = bez(.34, 1.45, .64, 1)      # EASE.overshoot
E_DEAL = bez(.3, 0, .2, 1)           # deck-deal flight
E_SINE = lambda p: -(math.cos(math.pi * p) - 1) / 2


def spring(n: int, damping: float, stiffness: float, mass: float = 1.0) -> list[float]:
    """Remotion's spring (0 -> 1, rest start) sampled at frames 0..n, by RK4 integration."""
    x, v, out, sub = 0.0, 0.0, [0.0], 40
    dt = 1 / FPS / sub
    acc = lambda x_, v_: (-stiffness * (x_ - 1) - damping * v_) / mass
    for _ in range(n):
        for _ in range(sub):
            k1x, k1v = v, acc(x, v)
            k2x, k2v = v + k1v * dt / 2, acc(x + k1x * dt / 2, v + k1v * dt / 2)
            k3x, k3v = v + k2v * dt / 2, acc(x + k2x * dt / 2, v + k2v * dt / 2)
            k4x, k4v = v + k3v * dt, acc(x + k3x * dt, v + k3v * dt)
            x += (k1x + 2 * k2x + 2 * k3x + k4x) * dt / 6
            v += (k1v + 2 * k2v + 2 * k3v + k4v) * dt / 6
        out.append(x)
    return out


mix = lambda a, b, t: a + (b - a) * t
clamp01 = lambda x: 0.0 if x < 0 else 1.0 if x > 1 else x

# ---------------------------------------------------------------- word times
def key(s: str) -> str:
    return s.lower().strip(".,!?:")


ALL = [w for ln in words.values() for w in ln["words"]]


def wt(word: str) -> float:
    """Start of the first spoken word matching `word` (same rule as mix.py, so picture and sound agree)."""
    for w in ALL:
        if key(w["w"]) == key(word):
            return w["t0"]
    raise SystemExit(f"gen.py: {word!r} is not in words.json")


def cue(note: str) -> float:
    for c in spec["sfx"]:
        if c.get("note") == note:
            return c["t"] if "t" in c else wt(c["word"]) + c.get("offset", 0.0)
    raise SystemExit(f"gen.py: no sfx cue with note {note!r} in script.json")


LINE = dict(words)
lstart = lambda lid: LINE[lid]["start"]
lend = lambda lid: LINE[lid]["start"] + LINE[lid]["dur"]

# the planned silence (same computation as build.sh): end of the line before it + 0.15 s to the next sound - 0.05 s
CUES = [c["t"] if "t" in c else wt(c["word"]) + c.get("offset", 0.0) for c in spec["sfx"]]
SILENCES = []
for s_ in spec["silence"]:
    prev = max((ln for ln in words.values() if ln["start"] < s_["to"]), key=lambda ln: ln["start"])
    a_ = prev["start"] + prev["dur"] + .15
    b_ = min([ln["start"] for ln in words.values() if ln["start"] > a_] + [t for t in CUES if t > a_ - .15]) - .05
    assert b_ - a_ >= .8, f"planned silence {a_:.2f}-{b_:.2f}s is shorter than 0.8 s"
    SILENCES.append((a_, b_))

# ---------------------------------------------------------------- timeline helpers (every motion is registered)
tw: list[str] = []
MOTION: list[tuple[float, float, str]] = []


def at(t: float) -> str:
    return f"{max(0.0, t):.3f}"


def show(sel: str, t0: float, t1: float | None = None) -> None:
    tw.append(f'tl.set("{sel}", {{autoAlpha: 1}}, {at(t0)});')
    MOTION.append((t0, t0, f"show {sel}"))
    if t1 is not None:
        tw.append(f'tl.set("{sel}", {{autoAlpha: 0}}, {at(t1)});')
        MOTION.append((t1, t1, f"hide {sel}"))


def fset(sel: str, props: str, t: float) -> None:
    tw.append(f'tl.set("{sel}", {{{props}}}, {at(t)});')
    if t > 0:
        MOTION.append((t, t, f"set {sel}"))


def to(sel: str, props: str, t: float, dur: float, ease: str) -> None:
    assert ease not in ('"none"', '"linear"'), "no linear motion"
    tw.append(f'tl.to("{sel}", {{{props}, duration: {dur:.3f}, ease: {ease}}}, {at(t)});')
    MOTION.append((t, t + dur, f"to {sel}"))


def fromto(sel: str, a: str, b: str, t: float, dur: float, ease: str, imm: bool = False) -> None:
    tw.append(f'tl.fromTo("{sel}", {{{a}}}, {{{b}, duration: {dur:.3f}, ease: {ease}, immediateRender: {str(imm).lower()}}}, {at(t)});')
    MOTION.append((t, t + dur, f"fromTo {sel}"))


def press(sel: str, t: float, s: float = .84, n: int = 4) -> None:
    """Button press: scale down for n/2 frames and back (the card's 0.84, 4 f)."""
    to(sel, f"scale: {s}", t, n / 2 * F, '"power2.out"')
    to(sel, "scale: 1", t + n / 2 * F, n / 2 * F, '"power2.out"')


# ---------------------------------------------------------------- masked headlines (Inter 600, -0.04em, leading 0.95)
HL_LEAD = .95


def headline(hid: str, lines: list[str], top: float, t_in: float | None, t_out: float | None, colour: str = INK,
             cap: int = 88, size: int | None = None) -> tuple[str, int]:
    size = size or fit(lines, cap)
    rows, k = "", 0
    for s_ in lines:
        ws = []
        for wd in s_.split():
            ws.append(f'<span class="hw" id="{hid}w{k}">{html.escape(wd)}</span>')
            k += 1
        rows += f'<div class="ln"><span>{" ".join(ws)}</span></div>'
    for i in range(len(lines)):
        if t_in is not None:
            fromto(f"#{hid} .ln:nth-child({i + 1}) > span", "yPercent: 140", "yPercent: 0", t_in + .11 * i, .9, '"power4.out"', imm=True)
        if t_out is not None:
            to(f"#{hid} .ln:nth-child({i + 1}) > span", "yPercent: -140", t_out + .04 * i, .3, '"power3.in"')
    return (f'<div id="{hid}" class="hl" style="left:{LM}px;top:{top:.0f}px;font-size:{size}px;color:{colour}">{rows}</div>', size)


def sync_words(ids: list[str], spoken: list[dict], hi_bg: str, hi_ink: str, ink: str) -> None:
    """Word sync inside type that repeats the voice: a block behind each word while it is spoken."""
    for j, (sid, w) in enumerate(zip(ids, spoken)):
        nxt = spoken[j + 1]["t0"] if j + 1 < len(spoken) else w["t1"] + .02
        to(sid, f'backgroundColor: "{hi_bg}", color: "{hi_ink}"', w["t0"], min(.06, min(nxt, w["t1"] + .02) - w["t0"] - .005), '"power1.out"')
        to(sid, f'backgroundColor: "rgba(0,0,0,0)", color: "{ink}"', min(nxt, w["t1"] + .02), .1, '"power1.out"')


# ---------------------------------------------------------------- typed text in a prompt field (frame-locked characters)
TYPE_SIZE, TYPE_LH = 44, 56
SEND = 64
FIELD_PAD_X, FIELD_PAD_Y = 28, 26
TYPE_ROOM = FW - 2 * FIELD_PAD_X - SEND - 16


def typed(pid: str, text: str, shown_upto: int) -> tuple[str, int]:
    """Lines of per-character spans (hidden ones still take their place, so nothing reflows), cursors between them.
    Returns (html, line count). Characters before `shown_upto` are visible from frame 0."""
    lines = wrap_text(text, TYPE_SIZE, 500, TYPE_ROOM)
    out, i = [], 0
    for li, ln in enumerate(lines):
        row = []
        if li:                           # the space that wrapped: an empty character slot (and its cursor) at the line start
            vis = "" if i < shown_upto else " ch"
            row.append(f'<i class="cur" id="{pid}u{i}"></i><span class="c{vis}" id="{pid}c{i}"></span>')
            i += 1
        for c in ln:
            vis = "" if i < shown_upto else " ch"
            row.append(f'<i class="cur" id="{pid}u{i}"></i><span class="c{vis}" id="{pid}c{i}">{html.escape(c) if c != " " else "&nbsp;"}</span>')
            i += 1
        if li == len(lines) - 1:
            row.append(f'<i class="cur" id="{pid}u{i}"></i>')
        out.append(f'<div class="tl">{"".join(row)}</div>')
    assert i == len(text), (i, len(text))
    return "".join(out), len(lines)


def send_key(sid: str, colour: str) -> str:
    return (f'<div id="{sid}" class="send" style="background:{colour}"><svg width="30" height="30" viewBox="0 0 30 30">'
            f'<path d="M15 25 V6 M7 13 L15 5 L23 13" fill="none" stroke="#fff" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"/></svg></div>')


def field(fid: str, top: float, inner: str, nlines: int, key_html: str, extra: str = "") -> tuple[str, float]:
    h = max(nlines * TYPE_LH + 2 * FIELD_PAD_Y, SEND + 2 * 20)
    return (f'<div id="{fid}" class="field" data-ui style="left:{FX}px;top:{top:.0f}px;width:{FW}px;height:{h:.0f}px">'
            f'{extra}<div class="typed">{inner}</div>{key_html}</div>', h)


def type_run(pid: str, start_i: int, n: int, t0: float, char_f: float = 2.0) -> float:
    """Characters start_i..n-1 appear one per char_f frames from t0; the cursor rides after the last one."""
    for k, i in enumerate(range(start_i, n)):
        t = t0 + k * char_f * F
        fset(f"#{pid}c{i}", "visibility: 'visible'", t)
        fset(f"#{pid}u{i}", "visibility: 'hidden'", t)
        fset(f"#{pid}u{i + 1}", "visibility: 'visible'", t)
    return t0 + (n - 1 - start_i) * char_f * F


def blink_twice(sel: str, t: float, half: int) -> float:
    for j, v in enumerate(["hidden", "visible", "hidden", "visible"]):
        fset(sel, f"visibility: '{v}'", t + (j + 1) * half * F)
    return t + 4 * half * F


# ================================================================ S1 hook: a typed prompt sends back a real frame
H1_OUT = cue("S2 prompt field and frame leave")
assert H1_OUT >= lend("L1"), "S1 headline leaves before the voice finishes it"
h1, s1 = headline("h1", scr["S1_headline"].split(" / "), HL_TOP, None, H1_OUT)
PROMPT, PRE = scr["S1_prompt"], scr["S1_prompt_pretyped"]
assert PROMPT.startswith(PRE)
F1_TOP = 340
p1_html, p1_lines = typed("p1", PROMPT, len(PRE))
field1, F1_H = field("f1", F1_TOP, p1_html, p1_lines, send_key("k1", COB))
TYPE1_0 = cue("S1 typing ' completely.' starts")
fset(f"#p1u{len(PRE)}", "visibility: 'visible'", 0)
TYPE1_END = type_run("p1", len(PRE), len(PROMPT), TYPE1_0)
SEND1 = blink_twice(f"#p1u{len(PROMPT)}", TYPE1_END, 3)   # solid while typing, two blinks (3 f half period), send
press("#k1", SEND1)
# the real frame flies out of the send key: 8 f flight with arc, 4 f overshoot settle, 0.996 press
HK_W, HK_H = 480, 600
HK_X, HK_Y = SAFE_R - HK_W, SAFE_B - 15 - HK_H
assert HK_Y >= F1_TOP + F1_H + 30, "S1 frame would cover the prompt field"
Image.open(EV / "li-hook.png").convert("RGB").resize((HK_W * 2, HK_H * 2), Image.LANCZOS).save(HF / "li-hook.jpg", quality=90)
frame1 = (f'<div id="hk" class="ev" style="left:{HK_X}px;top:{HK_Y}px;width:{HK_W}px;height:{HK_H}px">'
          f'<img src="li-hook.jpg" width="{HK_W}" height="{HK_H}"></div>')
key_cx, key_cy = FX + FW - 20 - SEND / 2, F1_TOP + F1_H - 20 - SEND / 2
hk_cx, hk_cy = HK_X + HK_W / 2, HK_Y + HK_H / 2
FLIGHT, SETTLE = 8, 4
LAND1 = SEND1 + FLIGHT * F
fset("#hk", f"x: {key_cx - hk_cx:.1f}, y: {key_cy - hk_cy:.1f}, scale: .25, rotation: 6, autoAlpha: 0", 0)
fset("#hk", "autoAlpha: 1, boxShadow: '0 30px 40px rgba(11,12,14,.22)'", SEND1)
for f in range(1, FLIGHT + 1):
    p = f / FLIGHT
    e = E_DEAL(p)
    fset("#hk", f"x: {(key_cx - hk_cx) * (1 - e):.1f}, y: {(key_cy - hk_cy) * (1 - e) - 70 * math.sin(math.pi * p):.1f}, "
                f"scale: {mix(.25, 1.06, e):.4f}, rotation: {mix(6, .8, e):.3f}", SEND1 + f * F)
fromto("#hk", "scale: 1.06, rotation: .8", "scale: 1, rotation: -1.2, boxShadow: '0 0px 0px rgba(11,12,14,0)'", LAND1, SETTLE * F, "B(.3, 0, .25, 1.15)")
to("#hk", "scale: .996", LAND1 + SETTLE * F, F, '"power1.out"')
to("#hk", "scale: 1", LAND1 + (SETTLE + 1) * F, F, '"power1.out"')
HK_STILL = LAND1 + (SETTLE + 2) * F
assert HK_STILL <= 2.0, f"S1 real frame still only at {HK_STILL:.2f}s (brief: a real frame by 2 s)"
T2 = cue("S2 prompt field and frame leave")
to("#f1", "y: 1100", T2, 8 * F, '"power3.in"')
to("#hk", "y: 1100", T2 + 2 * F, 8 * F, '"power3.in"')
S1_GONE = T2 + 10 * F
assert T2 - HK_STILL >= 1.0

# ================================================================ S2 the old way: a keyframe track, nudged by hand
H2_IN = lstart("L2") + .05
h2, s2 = headline("h2", scr["S2_headline"].split(" / "), HL_TOP, H2_IN, None)
TR_Y, TR_X0, TR_X1 = 660, LM, SAFE_R - 4
KF_N, KF_HOT = 8, 4
kf_x = [TR_X0 + 60 + i * (TR_X1 - TR_X0 - 120) / (KF_N - 1) for i in range(KF_N)]
dia = lambda i, fill, stroke: (f'<div id="kf{i}" class="kfw" style="left:{kf_x[i] - 16:.1f}px;top:{TR_Y - 16}px"><div class="kf" style="background:{fill};border-color:{stroke}"></div></div>')
PH_X = TR_X0 + 120
track = (f'<div id="track" class="abs0" style="left:0;top:0;width:{W}px;height:{H}px">'
         f'<div id="tline" style="position:absolute;left:{TR_X0}px;top:{TR_Y - 3}px;width:{TR_X1 - TR_X0}px;height:6px;background:{INK};border-radius:3px;transform-origin:0 50%"></div>'
         + "".join(dia(i, COB if i == KF_HOT else GROUND, COB if i == KF_HOT else INK) for i in range(KF_N))
         + f'<div id="ph" style="position:absolute;left:{PH_X - 2}px;top:{TR_Y - 120}px;width:4px;height:240px;background:{INK}">'
         f'<div style="position:absolute;left:-12px;top:-14px;width:28px;height:22px;background:{INK};border-radius:4px"></div></div>'
         f'<svg id="ptr" width="44" height="60" viewBox="-3 -3 36 50" style="position:absolute;left:{kf_x[KF_HOT] - 2:.0f}px;top:{TR_Y - 2}px;overflow:visible;transform-origin:0 0">'
         f'<path d="M0 0 L0 36 L9 28 L15 42 L22 39 L16 25 L28 25 Z" fill="{INK}" stroke="#fff" stroke-width="2.5" stroke-linejoin="round"/></svg></div>')
KEYF = wt("keyframes")
fromto("#tline", "scaleX: 0", "scaleX: 1", S1_GONE, .45, '"power3.out"', imm=True)
KF_GAPS = [.07, .06, .05, .045, .04, .035, .03]          # diamonds pop in left to right, accelerating
for i in range(KF_N):
    fromto(f"#kf{i}", "scale: 0", "scale: 1", S1_GONE + .08 + sum(KF_GAPS[:i]), .25, '"back.out(2)"', imm=True)
fromto("#ph", "opacity: 0, y: -20", "opacity: 1, y: 0", S1_GONE + .2, .3, '"power3.out"', imm=True)
TRACK_DONE = S1_GONE + .08 + sum(KF_GAPS) + .25
GRAB, REL1 = cue("S2 pointer grabs the cobalt keyframe"), cue("S2 keyframe released after the drag")
REGRAB, REL2 = REL1 + .12, REL1 + .53
assert GRAB - .5 >= TRACK_DONE - .1, "pointer arrives before the track is drawn"
fromto("#ptr", "x: 190, y: 230, autoAlpha: 0", "x: 0, y: 0, autoAlpha: 1", GRAB - .5, .5, '"power3.out"', imm=True)
to("#ptr", "scale: .9", GRAB, 3 * F, '"power2.out"')
to("#ptr, #kf4", "x: -40", GRAB + 3 * F, REL1 - GRAB - 3 * F, '"power2.inOut"')
to("#ptr", "scale: 1", REL1, 3 * F, '"power2.out"')
to("#ptr", "scale: .9", REGRAB, 3 * F, '"power2.out"')
to("#ptr, #kf4", "x: -16", REGRAB + 3 * F, REL2 - REGRAB - 3 * F, '"power2.inOut"')
to("#ptr", "scale: 1", REL2, 3 * F, '"power2.out"')
SCRUB0 = wt("checked")
assert SCRUB0 >= REL2 + 3 * F, "playhead scrub starts before the keyframe is released"
to("#ph", "x: 300", SCRUB0, .7, '"sine.inOut"')
to("#ph", "x: 120", SCRUB0 + .7, .55, '"sine.inOut"')
S2_STILL = SCRUB0 + 1.25

# ================================================================ S3 now: the slider wipes the old way away; the board
NOW = wt("Now")
THROW = cue("S3 slider thrown 8% -> 76%")
REB = cue("S3 slider rebound to 70%")
PAUSE_F, SWEEP_F = 12, 30
SW0 = THROW + (12 + 10 + PAUSE_F) * F
SW1 = SW0 + SWEEP_F * F
BAR_IN = THROW - 10 * F
assert BAR_IN >= S2_STILL - .05, f"slider appears at {BAR_IN:.2f}s while the playhead still scrubs (to {S2_STILL:.2f}s)"


def bar_pos(f: float) -> float:
    """Divider position (% of width) at frame f counted from THROW (before-after-slider-scrub demo, sweep to 100%)."""
    if f < -4:
        return 8.0
    if f < 0:
        return mix(8, 6.5, E_SMOOTH((f + 4) / 4))
    if f < 12:
        return mix(6.5, 76, E_OUT(f / 12))
    if f < 22:
        return mix(76, 70, E_SMOOTH((f - 12) / 10))
    if f < 22 + PAUSE_F:
        return 70.0
    return mix(70, 100, E_SMOOTH(clamp01((f - 22 - PAUSE_F) / SWEEP_F)))


H3_IN = THROW
h3, s3 = headline("h3", [scr["S3_headline"]], HL_TOP, H3_IN, None)
F3_TOP = HL_TOP + HL_LEAD * s3 + 40
p3_html, p3_lines = typed("p3", PROMPT, len(PROMPT))
field3, F3_H = field("f3", F3_TOP, p3_html, p3_lines, send_key("k3", INK))
ROW_H, ROW_GAP = 132, 8
ROW_TOP = F3_TOP + F3_H + 40
rows3 = []
for k, r in enumerate(scr["S3_rows"]):
    y = ROW_TOP + k * (ROW_H + ROW_GAP)
    assert text_w(r["line"], 40, 500, -.01) <= FW - 56, f"row line {r['line']!r} too wide"
    rows3.append(f'<div id="rw{k}" class="row3" data-ui style="left:{FX}px;top:{y:.0f}px;width:{FW}px;height:{ROW_H}px">'
                 f'<div class="rn">{html.escape(r["name"])}</div><div class="rl">{html.escape(r["line"])}</div>'
                 f'<div class="st" id="st{k}">{html.escape(r["status"])}</div></div>')
assert ROW_TOP + 3 * ROW_H + 2 * ROW_GAP <= INFO_MAX, "S3 board runs into the caption band"
after = (f'<div id="after" class="scene" style="background:{GROUND}">{h3}{field3}{"".join(rows3)}</div>')
divider = (f'<div id="div" class="abs" style="left:0;top:0;width:6px;height:{H}px;background:{COB}">'
           f'<div id="hdl" style="position:absolute;left:-25px;top:{H / 2 - 28:.0f}px;width:56px;height:56px;border-radius:28px;background:{COB}">'
           f'<svg width="56" height="56" viewBox="0 0 56 56"><path d="M23 19 L14 28 L23 37 M33 19 L42 28 L33 37" fill="none" stroke="#fff" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"/></svg></div></div>')
show("#div", BAR_IN, SW1 + F)
f_last = round((SW1 - THROW) / F)
prev_x = None
for f in range(-10, f_last + 1):
    p = bar_pos(f)
    x = p / 100 * W
    v = 0 if prev_x is None else abs(x - prev_x)
    prev_x = x
    sq = 1 + min(v * 1920 / W / 110, 1) * .18
    fset("#div", f"x: {x - 3:.1f}", THROW + f * F)
    fset("#hdl", f"scaleX: {sq:.3f}", THROW + f * F)
    fset("#after", f"clipPath: 'inset(0px {max(0.0, W - x):.1f}px 0px 0px)'", THROW + f * F)
fset("#after", "clipPath: 'none'", SW1 + F)
DIR, BLD, REV, FRM = wt("director"), wt("builder"), wt("reviewer"), wt("frame")
LANDS = [DIR, BLD, REV]
# the pile waits beyond the right edge; one paragraph-level anticipation (48 px press, 30 px pull-back), then each row
# is dealt: 8 f flight (bezier .3,0,.2,1, scale peak), 4 f overshoot settle, 0.996 press
PILE_CX, PILE_CY = W + 150, ROW_TOP + 140
for k in range(3):
    y = ROW_TOP + k * (ROW_H + ROW_GAP)
    dx, dy = PILE_CX - (FX + FW / 2), PILE_CY - (y + ROW_H / 2)
    fset(f"#rw{k}", f"x: {dx:.1f}, y: {dy - k * 6:.1f}, scale: .55, rotation: {4 + 2 * k}", 0)
    fset(f"#rw{k}", f"zIndex: {10 + k}", 0)
    to(f"#rw{k}", 'y: "+=48"' + (', x: "+=30"' if k == 0 else ""), DIR - (FLIGHT + 10) * F, 10 * F, '"power2.out"')
    t0 = LANDS[k] - FLIGHT * F
    to(f"#rw{k}", "x: 0, y: 0, scale: 1, rotation: -1.6", t0, FLIGHT * F, "B(.3, 0, .2, 1)")
    to(f"#rw{k}", "rotation: 0", LANDS[k], SETTLE * F, "B(.3, 0, .25, 1.15)")
    to(f"#rw{k}", "scale: .996", LANDS[k] + SETTLE * F, F, '"power1.out"')
    to(f"#rw{k}", "scale: 1", LANDS[k] + (SETTLE + 1) * F, F, '"power1.out"')
assert DIR - (FLIGHT + 10) * F >= SW1 - 1.0, "row anticipation starts long before the slider has revealed the pile"
# the active agent's status is the frame's one cobalt object; finished ones turn ink
ACT = [max(DIR + .2, SW1 + F), BLD, FRM]
to("#st0", f'backgroundColor: "{COB}", color: "{WHITE}", borderColor: "{COB}"', ACT[0], .15, '"power2.out"')
to("#st0", f'backgroundColor: "{INK}", borderColor: "{INK}"', ACT[1], .15, '"power2.out"')
to("#st1", f'backgroundColor: "{COB}", color: "{WHITE}", borderColor: "{COB}"', ACT[1], .15, '"power2.out"')
to("#st1", f'backgroundColor: "{INK}", borderColor: "{INK}"', ACT[2], .15, '"power2.out"')
to("#st2", f'backgroundColor: "{COB}", color: "{WHITE}", borderColor: "{COB}"', ACT[2], .15, '"power2.out"')
T4 = cue("S4 board leaves")
assert T4 - (FRM + .15) >= 1.0, "S3 board not held 1 s"
to("#h3 .ln > span", "yPercent: -140", T4 - .3, .3, '"power3.in"')
assert T4 - .3 >= lend("L3")
to("#f3", "y: -1300", T4, 10 * F, '"power3.in"')   # the board leaves upward, top first (nothing crosses the captions)
for k in range(3):
    to(f"#rw{k}", "y: -1300", T4 + (k + 1) * F, 10 * F, '"power3.in"')
BOARD_GONE = T4 + 13 * F

# ================================================================ S4 QA: first review, 8 problems, all 8 fixed
FIRST = wt("first")
H4_IN = max(FIRST, BOARD_GONE)            # rises once the board has cleared the headline area
assert H4_IN - FIRST <= .4
h4, s4 = headline("h4", scr["S4_headline"].split(" / "), HL_TOP, H4_IN, None)
FINDINGS = scr["S4_findings"]
assert len(FINDINGS) == 8, "FACTS.md lists exactly 8 fixes: the list must show 8 rows"
LR_H, LR_GAP, LR_TOP, DRIFT = 72, 8, 352, 40
CHK = 44
for s_ in FINDINGS:
    assert text_w(s_, 44, 500, -.01) <= FW - 28 - CHK - 22 - 24, f"finding {s_!r} does not fit its row"
assert LR_TOP + 8 * LR_H + 7 * LR_GAP <= INFO_MAX, "S4 list runs into the caption band"
assert LR_TOP >= HL_TOP + 2 * HL_LEAD * s4 + 36
lrows = []
for i, s_ in enumerate(FINDINGS):
    lrows.append(f'<div id="fr{i}" class="frow" data-ui style="left:{FX}px;top:{LR_TOP + i * (LR_H + LR_GAP)}px;width:{FW}px;height:{LR_H}px">'
                 f'<div class="chk" id="ck{i}"><svg width="{CHK}" height="{CHK}" viewBox="0 0 44 44"><path id="ckp{i}" d="M12 23 L19 30 L33 15" fill="none" '
                 f'stroke="#fff" stroke-width="4" stroke-linecap="round" stroke-linejoin="round" pathLength="1" stroke-dasharray="1 1.2" stroke-dashoffset="1.1"/></svg></div>'
                 f'<div class="ft"><span class="mk" id="mk{i}"></span><span class="fx" id="fx{i}">{html.escape(s_)}</span></div></div>')
COUNTER = scr["S4_counter"]
cnt_w = text_w(COUNTER, 56, 600, -.02)
line2_w = text_w(scr["S4_headline"].split(" / ")[1], s4, 600, -.04)
assert LM + line2_w + 40 <= SAFE_R - cnt_w, "counter would touch the headline"
cnt_top = HL_TOP + HL_LEAD * s4 + (HL_LEAD * s4 - 56 * 1.1) / 2 + 4
counter = (f'<div id="cnt" class="hl" style="left:{SAFE_R - cnt_w - 2:.0f}px;top:{cnt_top:.0f}px;font-size:56px;letter-spacing:-.02em;line-height:1.1;color:{INK}">'
           f'<div class="ln"><span>{html.escape(COUNTER)}</span></div></div>')
s4scene = f'<div id="s4" class="scene">{h4}<div id="flist" class="abs0">{"".join(lrows)}</div>{counter}</div>'
PROB = wt("problems")
STAG, WIN = 12, 26
REVEAL = [PROB + i * STAG * F for i in range(8)]
REV_END = REVEAL[-1] + WIN * F
fset("#flist", f"y: {DRIFT}", 0)
to("#flist", "y: 0", PROB, REV_END - PROB, '"sine.inOut"')
for i, t in enumerate(REVEAL):
    fromto(f"#fr{i}", "scale: .82, y: 44, filter: 'blur(8px)'", "scale: 1, y: 0, filter: 'blur(0px)'", t, WIN * F, "B(.3, 1.18, .5, 1)", imm=True)
    fromto(f"#fr{i}", "opacity: 0", "opacity: 1", t, WIN / 2.2 * F, '"power1.out"', imm=True)
# markers behind the two findings the voice names (6 f each; the first released when the second lands)
MK = [(0, cue("S4 marker behind 'Overlapping captions'")), (FINDINGS.index("Text too small for a phone"), cue("S4 marker behind 'Text too small for a phone'"))]
assert MK[0][1] >= REVEAL[MK[0][0]] + WIN * F and MK[1][1] >= REVEAL[MK[1][0]] + WIN * F, "marker lands before its row is in place"
for j, (i, t) in enumerate(MK):
    fromto(f"#mk{i}", "scaleX: 0", "scaleX: 1", t, 6 * F, '"power3.out"', imm=True)
    to(f"#fx{i}", f'color: "{WHITE}"', t, 4 * F, '"power2.out"')
i0 = MK[0][0]
fset(f"#mk{i0}", "transformOrigin: '100% 50%'", MK[1][1] + 6 * F)
to(f"#mk{i0}", "scaleX: 0", MK[1][1] + 6 * F, 6 * F, '"power3.in"')
to(f"#fx{i0}", f'color: "{INK}"', MK[1][1] + 6 * F, 4 * F, '"power2.out"')
# checks: hard-accelerating, top to bottom; each checked row's text turns muted; the counter rises with the run's end
FIXED = wt("fixed")
GAPS = [.32, .24, .18, .13, .10, .08, .07]
CHECK_T = [FIXED + .10 + sum(GAPS[:i]) for i in range(8)]
for i, t in enumerate(CHECK_T):
    to(f"#ck{i}", f'backgroundColor: "{COB}", borderColor: "{COB}"', t, 3 * F, '"power2.out"')
    to(f"#ckp{i}", "attr: {'stroke-dashoffset': 0}", t, 5 * F, '"power2.out"')
    to(f"#fx{i}", f'color: "{MUTED}"', t + (6 * F if i == MK[1][0] else 0), .2, '"power2.out"')
    if i == MK[1][0]:
        fset(f"#mk{i}", "transformOrigin: '100% 50%'", t)
        to(f"#mk{i}", "scaleX: 0", t, 6 * F, '"power3.in"')
CNT_IN = CHECK_T[5]
fromto("#cnt .ln > span", "yPercent: 140", "yPercent: 0", CNT_IN, .45, '"power4.out"', imm=True)
T5 = cue("S5 cobalt page wipes up (ends the silence)")

# ================================================================ S5 ship: the one cobalt page, the slam, the contact sheet
SHIP = cue("S5 'Ship.' lands: the only whole-frame impact")
assert abs(SHIP - wt("ship")) < 1e-9
lbl_ids = ["slw0", "slw1"]
lab_words = scr["S5_label"].split()
assert [key(w["w"]) for w in LINE["L7"]["words"][:2]] == [key(x) for x in lab_words], "S5 label must repeat the spoken words"
lab5 = (f'<div id="lab5" class="hl" style="left:{LM}px;top:{HL_TOP}px;font-size:56px;letter-spacing:-.02em;line-height:1.1;color:{WHITE}">'
        f'<div class="ln"><span>' + " ".join(f'<span class="hw" id="{i}">{html.escape(w)}</span>' for i, w in zip(lbl_ids, lab_words)) + '</span></div></div>')
fromto("#lab5 .ln > span", "yPercent: 140", "yPercent: 0", T5 + 2 * F, .9, '"power4.out"', imm=True)
sync_words(["#slw0", "#slw1"], LINE["L7"]["words"][:2], WHITE, COB, WHITE)
SHIP_SIZE = 240
SHIP_TOP = HL_TOP + 56 * 1.1 + 18
ship_w = text_w(scr["S5_word"], SHIP_SIZE, 600, -.04)
assert LM + ship_w <= SAFE_R
ship = (f'<div id="ship" class="abs0" style="left:{LM}px;top:{SHIP_TOP:.0f}px;font-size:{SHIP_SIZE}px;font-weight:600;letter-spacing:-.04em;'
        f'line-height:{HL_LEAD};color:{WHITE};white-space:nowrap;transform-origin:{ship_w / 2:.0f}px 50%">{html.escape(scr["S5_word"])}</div>')
SH_CX, SH_CY = LM + ship_w / 2, SHIP_TOP + HL_LEAD * SHIP_SIZE / 2
# score-slam: hover 9 f (2.75 -> 2.6, blur 10, half opacity), ease-in quad drop 6 f to 0.965, spring (14/260) back to 1
HOVER0, DROP0 = SHIP - 15 * F, SHIP - 6 * F
fset("#ship", "scale: 2.75, opacity: 0, filter: 'blur(10px)'", 0)
fromto("#ship", "scale: 2.75, opacity: .5, filter: 'blur(10px)'", "scale: 2.6", HOVER0, 9 * F, '"sine.inOut"')
to("#ship", "scale: .965, opacity: 1, filter: 'blur(0px)'", DROP0, 6 * F, '"power1.in"')
sp = spring(24, 14, 260)
for f in range(1, 25):
    fset("#ship", f"scale: {mix(.965, 1, sp[f]):.4f}", SHIP + f * F)
fset("#ship", "scale: 1", SHIP + 25 * F)
# one white ring: diameter 120 -> 1100 over 16 f (expansion out, fade on frame time)
ring = f'<div id="ring" class="abs0" style="left:{SH_CX:.0f}px;top:{SH_CY:.0f}px;width:0;height:0;border-radius:50%;border:0 solid {WHITE};opacity:0"></div>'
for f in range(17):
    p = f / 16
    d = mix(120, 1100, E_SNAPPY(p))
    op = mix(1, .65, p / .6) if p < .6 else mix(.65, 0, (p - .6) / .4)
    fset("#ring", f"width: {d:.1f}, height: {d:.1f}, marginLeft: {-d / 2:.1f}, marginTop: {-d / 2:.1f}, opacity: {op if f < 16 else 0:.3f}, "
                    f"borderWidth: {mix(9, 1.5, E_SNAPPY(p)):.2f}", SHIP + f * F)
# whole-frame impact 1 of 1: a 12 px shake decaying over 5 frames (mostly vertical)
SHAKE = [(4.8, 12), (-3.2, -7.5), (2.0, 4.4), (-1.0, -2.2), (.4, 1.0), (0, 0)]
for f, (sx, sy) in enumerate(SHAKE):
    fset("#stage", f"x: {sx}, y: {sy}", SHIP + f * F)
SHEET_IN = cue("S5 QA contact sheet slides up")
SHT_W = 600
cs = Image.open(EV / "qa-contact-sheet.jpg").convert("RGB")
SHT_H = round(SHT_W * cs.height / cs.width)
cs.resize((SHT_W * 2, SHT_H * 2), Image.LANCZOS).save(HF / "qa-sheet.jpg", quality=90)
SHT_TOP = SHIP_TOP + HL_LEAD * SHIP_SIZE + 44
assert SHT_TOP + SHT_H <= SAFE_B, "contact sheet leaves the title-safe box"
LAB_X = FX + SHT_W + 32
lab_lines = wrap_text(scr["S5_sheet_label"], 40, 500, SAFE_R - LAB_X)
assert all(text_w(s_, 40, 500, -.01) <= SAFE_R - LAB_X for s_ in lab_lines), "contact sheet label does not fit"
sheet = (f'<div id="sheet" class="abs0" style="left:{FX}px;top:{SHT_TOP:.0f}px;width:{SHT_W}px;height:{SHT_H}px;border:2px solid {WHITE}">'
         f'<img src="qa-sheet.jpg" width="{SHT_W - 4}" height="{SHT_H - 4}" style="display:block"></div>'
         f'<div id="shl" class="abs0" style="left:{LAB_X}px;top:{SHT_TOP - 6:.0f}px;font-size:40px;font-weight:500;line-height:1.18;letter-spacing:-.01em;color:{WHITE}">'
         + "<br>".join(html.escape(s_) for s_ in lab_lines) + '</div>')
fromto("#sheet", "y: 900", "y: 0", SHEET_IN, 8 * F, "B(.3, 0, .2, 1)", imm=True)
fromto("#shl", "y: 60, opacity: 0", "y: 0, opacity: 1", SHEET_IN + 3 * F, 10 * F, '"power3.out"', imm=True)
cpage = f'<div id="cpage" class="scene" style="background:{COB};box-shadow:0 0 0 40px {COB}">{lab5}{ship}{ring}{sheet}</div>'
fromto("#cpage", f"y: {H}", "y: 0", T5, 10 * F, '"power3.inOut"', imm=False)
fset("#cpage", f"y: {H}", 0)
T6 = cue("S6 cobalt page lifts away")
assert T6 - (SHEET_IN + 8 * F) >= 1.0, f"contact sheet held only {T6 - SHEET_IN - 8 * F:.2f}s"
to("#cpage", f"y: {-H - 40}", T6, 10 * F, '"power3.in"')
show("#cpage", T5, T6 + 12 * F)

# ================================================================ S6 results: five real stills, stacked then fanned
H8_TOP = HL_TOP
h8_lines = scr["S6_headline"].split(" / ")
h8, s8 = headline("h8", h8_lines, H8_TOP, T6 + .05, None)
spoken8 = LINE["L8"]["words"]
assert [key(w["w"]) for w in spoken8] == [key(x) for x in " ".join(h8_lines).split()], "S6 headline must repeat L8 to sync inside it"
sync_words([f"#h8w{j}" for j in range(len(spoken8))], spoken8, INK, WHITE, INK)
CW_, CH_ = 380, 475
CX_, CTOP = W / 2, HL_TOP + 2 * HL_LEAD * s8 + 160
ROT_K, TX_K, DROP = 5, 100, 820
cards = []
for i, c in enumerate(spec["evidence"]["stack"]):
    im = Image.open(MEDIA / c["file"]).convert("RGB")
    if c["crop"]:
        x0, y0, cw, ch = c["crop"]
        im = im.crop((x0, y0, x0 + cw, y0 + ch))
    assert abs(im.width / im.height - CW_ / CH_) < .01, f"{c['file']} crop is not 4:5"
    im.resize((CW_ * 2, CH_ * 2), Image.LANCZOS).save(HF / f"card{i}.jpg", quality=90)
    cards.append(f'<div id="cw{i}" class="abs0" style="left:{CX_ - CW_ / 2:.0f}px;top:{CTOP:.0f}px;width:{CW_}px;height:{CH_}px;z-index:{i}">'
                 f'<div id="cd{i}" class="card" style="transform-origin:50% 130%"><img src="card{i}.jpg" width="{CW_ - 4}" height="{CH_ - 4}"></div></div>')
CENTRE = next(i for i, c in enumerate(spec["evidence"]["stack"]) if c.get("centre"))
assert CENTRE == 2
# geometry check of the open fan: every corner inside the frame (stills are evidence texture, our type is elsewhere)
piv = (CX_, CTOP + 1.3 * CH_)
for k in (-2, 2):
    a = math.radians(k * ROT_K)
    for (px, py) in [(CX_ - CW_ / 2, CTOP), (CX_ + CW_ / 2, CTOP), (CX_ - CW_ / 2, CTOP + CH_), (CX_ + CW_ / 2, CTOP + CH_)]:
        rx, ry = px - piv[0], py - piv[1]
        qx = piv[0] + rx * math.cos(a) - ry * math.sin(a) + k * TX_K
        qy = piv[1] + rx * math.sin(a) + ry * math.cos(a)
        assert 24 <= qx <= W - 24 and qy <= SAFE_B, f"fan card corner at {qx:.0f},{qy:.0f} leaves the frame"
CS0 = T6 + 4 * F
STARTS = [CS0 + (1 - (1 - i / 4) ** 2) * 15 * F for i in range(5)]       # ease-out stagger over 15 f: gaps shrink (accelerating)
ENTRY = spring(60, 13, 150)
LANDF = next(f for f, v in enumerate(ENTRY) if v >= 1)                   # first frame the spring crosses its rest
CARD_LAND = [s_ + LANDF * F for s_ in STARTS]
LANDS_W = wt("lands")
TIGHT, FAN0 = LANDS_W, LANDS_W + .20
FANS = spring(60, 20, 95)
DRAW = wt("voice")
DRAWS = spring(40, 15, 170)
assert TIGHT >= STARTS[-1] + 14 * F, f"stack still landing ({STARTS[-1] + 14 * F:.2f}s) when it tightens at {TIGHT:.2f}s"
LEAVE6 = lend("L8")
assert LEAVE6 + 12 * F <= cue("S7 prompt field returns"), "S6 stills still leaving when the S7 field returns"
END6 = LEAVE6
assert END6 - DRAW >= 18 * F, "centre still has no time to be drawn"
nF = round((END6 - CS0) / F)
for f in range(nF + 1):
    t = CS0 + f * F
    dip = sum(math.sin(clamp01((t - s_ - 6 * F) / (9 * F)) * math.pi) * 5 for s_ in STARTS)
    squeeze = 1 - .02 * math.sin(clamp01((t - TIGHT) / (10 * F)) * math.pi)
    fan = 0.0 if t < FAN0 else FANS[min(60, round((t - FAN0) / F))]
    for i in range(5):
        k = i - 2
        fi = round((t - STARTS[i]) / F)
        s_in = 0.0 if fi < 0 else ENTRY[min(60, fi)]
        y = DROP * (1 - s_in) + dip
        tilt = (6 if i % 2 else -6) * (1 - s_in)
        rot = k * ROT_K * fan + tilt + ((i * 7) % 5 - 2) * .6 * (1 - fan)
        x = k * TX_K * fan + ((i * 5) % 3 - 1) * 8 * (1 - fan)
        sc = squeeze
        if i == CENTRE and t >= DRAW:
            dv = DRAWS[min(40, round((t - DRAW) / F))]
            y -= 72 * dv
            fset(f"#cw{i}", f"scale: {1 + .18 * dv:.4f}", t)
        fset(f"#cd{i}", f"x: {x:.2f}, y: {y:.2f}, rotation: {rot:.3f}, scale: {sc:.4f}", t)
fset(f"#cw{CENTRE}", "zIndex: 9", DRAW)
to(f"#cd{CENTRE}", f'boxShadow: "0 0 0 3px {COB}"', DRAW, 4 * F, '"power2.out"')
T7 = cue("S7 prompt field returns")
H8_OUT = lend("L8") + .05
assert H8_OUT >= lend("L8")
for i in range(5):
    fset(f"#cd{i}", f"y: {DROP}", 0)
    to(f"#cw{i}", "y: 1350", LEAVE6 + (4 - i) * F, 8 * F, '"power3.in"')
s6scene = f'<div id="s6" class="scene">{h8}{"".join(cards)}</div>'
to("#h8 .ln > span", "yPercent: -140", H8_OUT, .3, '"power3.in"')

# ================================================================ S7 my calls: the prompt field takes a real note
H7A_IN = T7 + .10
h7a, s7a = headline("h7a", scr["S7_headline_1"].split(" / "), HL_TOP, H7A_IN, None)
STILL = wt("still")
SWAP = STILL + .15
to("#h7a .ln > span", "yPercent: -140", SWAP, .3, '"power3.in"')
h7b, s7b = headline("h7b", scr["S7_headline_2"].split(" / "), HL_TOP, SWAP + .2, None)
F7_TOP = 340
NOTE = scr["S7_note"]
p7_html, p7_lines = typed("p7", NOTE, 0)
flood = f'<div id="flood" style="position:absolute;inset:-1px;border-radius:10px;background:{COB};clip-path:circle(0px at 100% 100%)"></div>'
field7, F7_H = field("f7", F7_TOP, p7_html, p7_lines, send_key("k7", COB), extra=flood)
fromto("#f7", "y: 700", "y: 0", T7, 7 * F, '"power3.out"', imm=True)
fset("#p7u0", "visibility: 'visible'", 0)
MY = wt("My")
TYPE7_0 = cue("S7 typing the user's note starts")
TYPE7_END = type_run("p7", 0, len(NOTE), TYPE7_0)
blink_twice(f"#p7u{len(NOTE)}", TYPE7_END, 4)
TAGS = scr["S7_tags"]
TAG_LAND = [cue("S7 tag 'I chose the direction' lands"), cue("S7 tag 'No paid tools' lands"), cue("S7 tag 'I approve every word' lands")]
TAG_H, TAG_GAP = 84, 16
TAG_TOP = F7_TOP + F7_H + 44
tags = []
for k, (s_, t) in enumerate(zip(TAGS, TAG_LAND)):
    tw_ = text_w(s_, 44, 500, -.01) + 2 * 28
    assert tw_ <= FW
    y = TAG_TOP + k * (TAG_H + TAG_GAP)
    tags.append(f'<div id="tg{k}" class="tag" data-ui style="left:{FX}px;top:{y:.0f}px;width:{tw_:.0f}px;height:{TAG_H}px">{html.escape(s_)}</div>')
    fset(f"#tg{k}", "x: -900, y: 120, rotation: -8, autoAlpha: 0", 0)
    fset(f"#tg{k}", "autoAlpha: 1", t - FLIGHT * F)
    for f in range(1, FLIGHT + 1):       # 8 f flight (bezier .3,0,.2,1) with a 26 px lift and a scale peak
        e, q = E_DEAL(f / FLIGHT), f / FLIGHT
        fset(f"#tg{k}", f"x: {-900 * (1 - e):.1f}, y: {120 * (1 - e) - 26 * math.sin(math.pi * q):.1f}, rotation: {mix(-8, 1.4, e):.3f}, "
                        f"scale: {1 + .06 * math.sin(math.pi * q):.4f}", t - FLIGHT * F + f * F)
    to(f"#tg{k}", "rotation: 0", t, SETTLE * F, "B(.3, 0, .25, 1.15)")
    to(f"#tg{k}", "scale: .996", t + SETTLE * F, F, '"power1.out"')
    to(f"#tg{k}", "scale: 1", t + (SETTLE + 1) * F, F, '"power1.out"')
assert TAG_TOP + 3 * TAG_H + 2 * TAG_GAP <= INFO_MAX, "S7 tags run into the caption band"
assert all(b - a >= .2 for a, b in zip(TAG_LAND, TAG_LAND[1:])) and TAG_LAND[2] - TAG_LAND[1] < TAG_LAND[1] - TAG_LAND[0], "tags must accelerate"

# ================================================================ S8 end card: the field is sent and becomes the card
SEND8 = cue("S8 send key pressed")
assert SEND8 - (TAG_LAND[-1] + (SETTLE + 2) * F) >= 1.0, "S7 tags not held 1 s"
assert SEND8 - TYPE7_END >= 1.0
press("#k7", SEND8)
to("#h7b .ln > span", "yPercent: -140", SEND8, 8 * F, '"power3.in"')
for k in range(3):
    to(f"#tg{k}", "x: -1100", SEND8 + k * F, 8 * F, '"power3.in"')
FLY = cue("S8 typed note flies off")
to("#f7 .typed", "x: 520, y: -300, rotation: -9, opacity: 0", FLY, 11 * F, "B(.5, 0, .9, .55)")
to("#k7", "opacity: 0", FLY + 2 * F, 8 * F, '"power2.out"')
FLOOD0 = FLY + 7 * F
diag = math.hypot(FW, 320)
for f in range(13):
    r = E_SNAPPY(f / 12) * diag
    fset("#flood", f"clipPath: 'circle({r:.1f}px at {FW - 20 - SEND / 2:.0f}px {F7_H - 20 - SEND / 2:.0f}px)'", FLOOD0 + f * F)
MORPH = cue("S8 cobalt flood morphs into the end-card block")
assert abs(MORPH - (FLY + 9 * F)) <= 1.5 * F
BLK_TOP, BLK_H = 520, 300
ms = spring(30, 15, 95)
for f in range(31):
    m = ms[f]
    fset("#f7", f"top: {mix(F7_TOP, BLK_TOP, m):.1f}, height: {mix(F7_H, BLK_H, m):.1f}, borderColor: 'rgba(11,12,14,{.15 * (1 - min(1, m)):.3f})'", MORPH + f * F)
END_LINES = scr["S8_card"].split(" / ")
END_SIZE = fit(END_LINES, 104, room=FW - 2 * 48)
assert END_SIZE >= 96
LET0 = MORPH + .70
glyphs, gi = [], 0
for li, s_ in enumerate(END_LINES):
    row = ""
    for c in s_:
        if c == " ":
            row += " "
            continue
        row += f'<span class="lt" id="lt{gi}">{html.escape(c)}</span>'
        gi += 1
    glyphs.append(f'<div>{row}</div>')
endcard = (f'<div id="ec" class="abs0" style="left:{FX + 48}px;top:{BLK_TOP + 44}px;font-size:{END_SIZE}px;font-weight:600;letter-spacing:-.04em;'
           f'line-height:{HL_LEAD};color:{WHITE};white-space:nowrap">{"".join(glyphs)}</div>')
assert BLK_TOP + 44 + 2 * HL_LEAD * END_SIZE <= BLK_TOP + BLK_H - 20, "end-card type does not fit its block"
for g in range(gi):
    fromto(f"#lt{g}", "yPercent: 40, scale: 1.3, opacity: 0, filter: 'blur(8px)'", "yPercent: 0, scale: 1, opacity: 1, filter: 'blur(0px)'",
           LET0 + g * F, 10 * F, '"expo.out"', imm=True)
SETTLED = LET0 + (gi - 1) * F + 10 * F
SUB = scr["S8_subline"].split(" / ")
SUB_SIZE = 44
for s_ in SUB:
    assert text_w(s_, SUB_SIZE, 500, -.01) <= TEXT_W, f"sub-line {s_!r} wider than title-safe"
SUB_IN = cue("S8 sub-line appears; then room tone only")
sub8 = (f'<div id="sub8" class="abs0" style="left:{LM}px;top:{BLK_TOP + BLK_H + 36}px;font-size:{SUB_SIZE}px;font-weight:500;line-height:1.22;letter-spacing:-.01em;color:{MUTED}">'
        + "<br>".join(html.escape(s_) for s_ in SUB) + '</div>')
fromto("#sub8", "opacity: 0, y: 14", "opacity: 1, y: 0", SUB_IN, 9 * F, '"power2.out"', imm=True)
STILL8 = SUB_IN + 9 * F
assert DUR - STILL8 >= 1.5, f"end card held only {DUR - STILL8:.2f}s"
assert SUB_IN >= SETTLED
s7scene = f'<div id="s7" class="scene">{h7a}{h7b}{"".join(tags)}{field7}{endcard}{sub8}</div>'

# ================================================================ scenes on/off
s1scene = f'<div id="s1" class="scene">{h1}{field1}{frame1}</div>'
s2scene = f'<div id="s2" class="scene">{h2}{track}</div>'
show("#s1", 0, T2 + .5)
show("#s2", T2, SW1 + F)
show("#s4", T4, T6)
show("#s6", T6 - F, T7 + .5)
show("#s7", T7 - F)
show("#after", BAR_IN, T6)

# ================================================================ captions: word-synced plate, pages of <= 2 lines
CAP_SIZE, CAP_PAD_X, CAP_PAD_Y, CAP_LH = 60, 30, 14, 1.16
CAP_MAX = SAFE_R - SAFE_L - 2 * CAP_PAD_X
cf = font(CAP_SIZE, 500)
SPACE = cf.getlength(" ")


def row_w(r: list[dict]) -> float:
    return sum(cf.getlength(w["w"]) + 16 for w in r) + SPACE * (len(r) - 1)


def wrap(ws: list[dict]) -> list[list[dict]]:
    if row_w(ws) > CAP_MAX:
        ok = [i for i in range(1, len(ws)) if row_w(ws[:i]) <= CAP_MAX and row_w(ws[i:]) <= CAP_MAX]
        if ok:
            i = min(ok, key=lambda i: max(row_w(ws[:i]), row_w(ws[i:])) - (40 if ws[i - 1]["w"][-1] in ",.;:" else 0))
            return [ws[:i], ws[i:]]
    rows, cur, cw = [], [], 0.0
    for w in ws:
        ww = cf.getlength(w["w"]) + 16
        if cur and cw + SPACE + ww > CAP_MAX:
            rows.append(cur)
            cur, cw = [], 0.0
        cw += (SPACE if cur else 0) + ww
        cur.append(w)
    return rows + [cur] if cur else rows


def pages(ws: list[dict]) -> list[list[dict]]:
    if len(wrap(ws)) <= 2:
        return [ws]
    best = None
    for i in range(1, len(ws)):
        a, b = ws[:i], ws[i:]
        if len(wrap(a)) > 2:
            continue
        la = sum(cf.getlength(w["w"]) for w in a)
        lb = sum(cf.getlength(w["w"]) for w in b)
        end = a[-1]["w"][-1]
        cost = (0 if end in ".!?" else 300 if end in ",;:" else 900) + (0 if len(wrap(b)) <= 2 else 150) + .2 * abs(la - lb)
        if best is None or cost < best[0]:
            best = (cost, i)
    if best is None:
        raise SystemExit("caption line too long for two 2-line pages: shorten it")
    return pages(ws[:best[1]]) + pages(ws[best[1]:])


NO_PLATE = {"L1", "L7", "L8", "L10"}  # L1: headline + prompt carry it; L7/L8: sync inside the type; L10: clean close
plan = []
for lid, ln in words.items():
    if lid in NO_PLATE:
        continue
    pgs = pages(ln["words"])
    for pi, pg in enumerate(pgs):
        a = (ln["start"] if pi == 0 else pg[0]["t0"]) - .15
        if lid == "L2" and pi == 0:
            a = max(a, S1_GONE)
        b = pgs[pi + 1][0]["t0"] - .15 if pi + 1 < len(pgs) else ln["start"] + ln["dur"] + .35
        for sa, sb in SILENCES:          # a page never changes inside the planned silence
            if a < sa < b:
                b = sa
        plan.append([lid, pg, a, b])
for i in range(len(plan) - 1):           # never two caption pages at once
    plan[i][3] = min(plan[i][3], plan[i + 1][2])
for (_, _, a0, b0), (_, _, a1, _) in zip(plan, plan[1:]):
    assert b0 <= a1 + 1e-9 and a0 < b0, f"caption windows overlap: {a0:.2f}-{b0:.2f} and {a1:.2f}"
for _, pg, a, b in plan:
    assert b - a >= 1.0, f"caption page {' '.join(w['w'] for w in pg)!r} shows only {b - a:.2f}s"
caps, n = [], 0
for lid, pg, a, b in plan:
    rws = wrap(pg)
    html_rows, j = "", 0
    for r in rws:
        html_rows += '<div class="row">' + "".join(f'<span class="w" id="w{n}_{j + q}">{html.escape(w["w"])}</span>' for q, w in enumerate(r)) + "</div>"
        j += len(r)
    caps.append(f'<div id="cap{n}" class="clip cap" data-start="{a:.2f}" data-duration="{b - a:.2f}" data-track-index="{20 + n % 2}">'
                f'<div class="cplate">{html_rows}</div></div>')
    fromto(f"#cap{n} .cplate", "y: 30, opacity: 0", "y: 0, opacity: 1", a, .25, '"power3.out"', imm=False)
    for q, w in enumerate(pg):
        nxt = pg[q + 1]["t0"] if q + 1 < len(pg) else w["t1"] + .02
        to(f"#w{n}_{q}", f'opacity: 1, backgroundColor: "{INK}", color: "{WHITE}"', w["t0"], min(.06, min(nxt, w["t1"] + .02) - w["t0"] - .005), '"power1.out"')
        to(f"#w{n}_{q}", f'backgroundColor: "rgba(0,0,0,0)", color: "{INK}"', min(nxt, w["t1"] + .02), .1, '"power1.out"')
    MOTION.append((b, b, f"caption {n} ends"))
    n += 1
CAP_TOP_MIN = CAP_BOTTOM - (2 * CAP_SIZE * CAP_LH + 2 * CAP_PAD_Y)
assert CAP_TOP_MIN >= INFO_MAX + 10, f"two-line captions reach up to {CAP_TOP_MIN:.0f}px, over information at {INFO_MAX}px"
# no caption plate may show while the cobalt page is up (S5) or over the end card
for _, _, a, b in plan:
    assert b <= T5 or a >= T6, "a caption plate would sit on the cobalt page"

# ---------------------------------------------------------------- the planned silence: nothing moves in it
for sa, sb in SILENCES:
    bad = [(t0, t1, lab) for t0, t1, lab in MOTION if t0 < sb - 1e-6 and t1 > sa + 1e-6]
    if bad:
        raise SystemExit("motion inside the planned silence %.2f-%.2f s: %s" % (sa, sb, "; ".join(f"{lab} {t0:.2f}-{t1:.2f}" for t0, t1, lab in bad[:6])))

# ---------------------------------------------------------------- sound and picture: every cue must sit on its picture event
KEYS7 = [0, 8, 16, 25]
picture = {
    "S1 typing ' completely.' starts": TYPE1_0,
    "S1 keystroke": None,
    "S1 send key pressed": SEND1, "S1 real frame li-hook lands": LAND1,
    "S2 prompt field and frame leave": T2,
    "S2 pointer grabs the cobalt keyframe": KEYF + .20, "S2 keyframe released after the drag": KEYF + 1.10,
    "S3 slider thrown 8% -> 76%": NOW - .10, "S3 slider rebound to 70%": THROW + 12 * F,
    "S3 Director row lands": DIR, "S3 Builder row lands": BLD, "S3 QA row lands": REV, "S3 QA status block turns cobalt": FRM,
    "S4 board leaves": lstart("L4"), "S4 findings list reveals": PROB,
    "S4 marker behind 'Overlapping captions'": wt("Overlapping"), "S4 marker behind 'Text too small for a phone'": wt("small"),
    "S4 check 1": CHECK_T[0], "S4 check 2": CHECK_T[1], "S4 check 3": CHECK_T[2],
    "S4 checks 4-8 run together; last sound before the silence": CHECK_T[3],
    "S5 cobalt page wipes up (ends the silence)": wt("Second"), "S5 'Ship.' hovers and drops": DROP0,
    "S5 'Ship.' lands: the only whole-frame impact": wt("ship"), "S5 QA contact sheet slides up": SHEET_IN,
    "S6 cobalt page lifts away": T6, "S6 first still lands on the stack": CARD_LAND[0], "S6 second still lands (rest run together, silent)": CARD_LAND[1],
    "S6 stack fans out": FAN0, "S6 centre still li-slam drawn up": DRAW,
    "S7 prompt field returns": T7, "S7 typing the user's note starts": TYPE7_0,
    "S7 tag 'I chose the direction' lands": STILL + 1.00, "S7 tag 'No paid tools' lands": STILL + 1.35, "S7 tag 'I approve every word' lands": STILL + 1.60,
    "S8 send key pressed": SEND8, "S8 typed note flies off": FLY, "S8 cobalt flood morphs into the end-card block": FLY + 9 * F,
    "S8 'Edited with Claude.' letters settled": SETTLED, "S8 sub-line appears; then room tone only": SUB_IN,
}
s1_keys = [c for c in spec["sfx"] if c.get("note") == "S1 keystroke"]
for c, i in zip(s1_keys, [4, 8]):
    if abs(c["t"] - (TYPE1_0 + i * 2 * F)) > 1.5 * F:
        raise SystemExit(f"gen.py: S1 keystroke sound at {c['t']:.3f}s but character {i} at {TYPE1_0 + i * 2 * F:.3f}s")
s7_keys = [c for c in spec["sfx"] if c.get("note") in ("S7 keystroke", "S7 typing done")]
for c, t in zip(s7_keys, [TYPE7_0 + i * 2 * F for i in KEYS7[1:]] + [TYPE7_END]):
    got = wt(c["word"]) + c.get("offset", 0.0)
    if abs(got - t) > 1.5 * F:
        raise SystemExit(f"gen.py: S7 keystroke sound at {got:.3f}s but picture at {t:.3f}s")
for c in spec["sfx"]:
    note = c.get("note")
    if note in ("S1 keystroke", "S7 keystroke", "S7 typing done"):
        continue
    if note not in picture:
        raise SystemExit(f"gen.py: sfx cue {note!r} has no picture event")
    got = c["t"] if "t" in c else wt(c["word"]) + c.get("offset", 0.0)
    if abs(got - picture[note]) > 1.5 * F:
        raise SystemExit(f"gen.py: sound {note!r} at {got:.3f}s but picture at {picture[note]:.3f}s")
assert abs(SHIP - wt("ship")) < 1e-9 and len(spec["impacts"]) == 1, "one whole-frame impact, on 'ship'"

# ---------------------------------------------------------------- the page
doc = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="UTF-8" /><meta name="viewport" content="width={W}, height={H}" />
<script src="gsap.min.js"></script>
<style>
@font-face{{font-family:"Inter";src:url(Inter.woff2) format('woff2');font-weight:100 900}}
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:{W}px;height:{H}px;overflow:hidden;background:{GROUND};font-family:"Inter",sans-serif;color:{INK}}}
.scene{{position:absolute;left:0;top:0;width:{W}px;height:{H}px;visibility:hidden;opacity:0}}
.abs{{position:absolute;visibility:hidden;opacity:0}}
.abs0{{position:absolute}}
.hl{{position:absolute;font-weight:600;letter-spacing:-.04em;line-height:{HL_LEAD};white-space:nowrap}}
.ln{{overflow:hidden;padding:.12em .2em .22em 0;margin:-.12em -.2em -.22em 0}}
.ln > span{{display:inline-block}}
.hw{{padding:0 .06em;margin:0 -.06em;border-radius:.06em}}
.field{{position:absolute;background:{SURF};border:1px solid {BORDER};border-radius:10px}}
.typed{{position:absolute;left:{FIELD_PAD_X}px;top:{FIELD_PAD_Y}px;font-weight:500;font-size:{TYPE_SIZE}px;line-height:{TYPE_LH}px;letter-spacing:-.01em;color:{INK};white-space:nowrap;transform-origin:0 50%}}
.tl{{height:{TYPE_LH}px}}
.ch{{visibility:hidden}}
.cur{{display:inline-block;width:0;height:{TYPE_LH}px;position:relative;visibility:hidden;vertical-align:top}}
.cur::after{{content:"";position:absolute;left:1px;top:6px;width:3px;height:{TYPE_LH - 12}px;background:{INK}}}
.send{{position:absolute;right:20px;bottom:20px;width:{SEND}px;height:{SEND}px;border-radius:10px;display:flex;align-items:center;justify-content:center}}
.ev{{position:absolute;border:2px solid rgba(11,12,14,.10);background:#fff}}
.ev img,.card img{{display:block}}
.kfw{{position:absolute;width:32px;height:32px}}
.kf{{position:absolute;inset:0;border:3px solid;transform:rotate(45deg)}}
.row3{{position:absolute;background:{SURF};border:1px solid {BORDER};border-radius:10px}}
.rn{{position:absolute;left:28px;top:12px;font-weight:600;font-size:56px;line-height:66px;letter-spacing:-.03em}}
.rl{{position:absolute;left:28px;top:78px;font-weight:500;font-size:40px;line-height:44px;letter-spacing:-.01em;color:{MUTED};white-space:nowrap}}
.st{{position:absolute;right:20px;top:16px;height:58px;padding:0 20px;border:1px solid {BORDER};border-radius:10px;background:{GROUND};
  font-weight:500;font-size:40px;line-height:56px;letter-spacing:-.01em;color:{INK}}}
.abs0#flist{{left:0;top:0}}
.frow{{position:absolute;background:{SURF};border:1px solid {BORDER};border-radius:10px;opacity:0}}
.chk{{position:absolute;left:24px;top:{(LR_H - CHK) / 2 - 1:.0f}px;width:{CHK}px;height:{CHK}px;border:3px solid rgba(11,12,14,.45);border-radius:10px;overflow:hidden}}
.chk svg{{position:absolute;left:-3px;top:-3px}}
.ft{{position:absolute;left:{24 + CHK + 22}px;top:0;height:{LR_H - 2}px;display:flex;align-items:center}}
.fx{{position:relative;font-weight:500;font-size:44px;letter-spacing:-.01em;white-space:nowrap;color:{INK}}}
.mk{{position:absolute;left:-10px;right:-12px;top:{(LR_H - 60) / 2 - 1:.0f}px;height:60px;background:{INK};border-radius:6px;transform:scaleX(0);transform-origin:0 50%}}
.card{{position:absolute;inset:0;border:2px solid rgba(11,12,14,.10);background:#fff}}
.tag{{position:absolute;background:{SURF};border:1px solid {BORDER};border-radius:10px;padding:0 28px;font-weight:500;font-size:44px;line-height:{TAG_H - 2}px;letter-spacing:-.01em;white-space:nowrap}}
.lt{{display:inline-block;transform-origin:50% 100%}}
.cap{{position:absolute;left:0;right:0;bottom:{H - CAP_BOTTOM}px;display:flex;justify-content:center}}
.cplate{{background:{SURF};color:{INK};border-radius:10px;padding:{CAP_PAD_Y}px {CAP_PAD_X}px;font-weight:500;font-size:{CAP_SIZE}px;line-height:{CAP_LH};
  letter-spacing:-.01em;text-align:center;max-width:{SAFE_R - SAFE_L}px}}
.row{{white-space:nowrap}}
.w{{opacity:.38;padding:0 8px;border-radius:6px}}
</style>
</head>
<body>
<div id="root" data-composition-id="main" data-start="0" data-duration="{DUR}" data-width="{W}" data-height="{H}">
  <audio id="mix" src="mix.wav" data-start="0" data-duration="{DUR}" data-track-index="9" data-volume="1"></audio>
  <div id="stage" class="clip" data-start="0" data-duration="{DUR}" data-track-index="0" style="position:absolute;inset:0;background:{GROUND}">
    {s1scene}
    {s2scene}
    {after}
    {divider}
    {s4scene}
    {s6scene}
    {s7scene}
    {cpage}
  </div>
  {"".join(caps)}
</div>
<script>
const B = (x1, y1, x2, y2) => {{
  const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx, cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
  return x => {{ let t = x; for (let i = 0; i < 8; i++) {{ const d = (3 * ax * t + 2 * bx) * t + cx; if (Math.abs(d) < 1e-6) break; t -= (((ax * t + bx) * t + cx) * t - x) / d; }}
    t = Math.min(1, Math.max(0, t)); return ((ay * t + by) * t + cy) * t; }};
}};
const tl = gsap.timeline({{ paused: true }});
{chr(10).join(tw)}
window.__timelines["main"] = tl;
</script>
</body>
</html>
'''
(HF / "index.html").write_text(doc)
print(f"ok: headlines {s1}/{s2}/{s3}/{s4}/{s8}/{s7a}/{s7b}px, end card {END_SIZE}px, {n} caption pages; "
      f"frame lands {LAND1:.2f}s (still {HK_STILL:.2f}s); sweep ends {SW1:.2f}s; checks {CHECK_T[0]:.2f}-{CHECK_T[-1]:.2f}s; "
      f"silence {', '.join(f'{a:.2f}-{b:.2f}' for a, b in SILENCES)}s; ship {SHIP:.2f}s; cards land {', '.join(f'{t:.2f}' for t in CARD_LAND)}; "
      f"typing {TYPE7_0:.2f}-{TYPE7_END:.2f}s; letters settled {SETTLED:.2f}s; end card still {STILL8:.2f}-{DUR}s")
print("caption pages: " + " | ".join(f"{a:.2f}-{b:.2f} {' '.join(w['w'] for w in pg)}" for _, pg, a, b in plan))
