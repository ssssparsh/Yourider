"""HyperFrames composition for the Diwali 2026 greeting (1080x1350, 30 fps, 20 s). See PLAN.md and DESIGN.md.

usage: python gen.py <project_dir> <build_dir>   -> <build_dir>/hf/index.html

Every event is anchored to a spoken word from <build_dir>/words.json (never guessed seconds). Lamp ignitions are
read from the script.json catch cues (sfx[].lamp), and the spark carries from script.json "lamp_carry", so the
sound of a lamp catching and the picture of it catching come from the same numbers.
The sikku kolam geometry is a Python port of media/.build/diwali-2026/style/kolam.js (mirror curve on a 7x7 grid).
Needs SchibstedGrotesk.woff2 in <build_dir>/hf (for measuring type).
"""
import html
import json
import math
import random
import sys
from pathlib import Path

from PIL import ImageFont

PROJECT, BUILD = Path(sys.argv[1]), Path(sys.argv[2])
HF = BUILD / "hf"
spec = json.loads((PROJECT / "script.json").read_text())
words = json.loads((BUILD / "words.json").read_text())
DUR, FPS = spec["duration"], spec["format"]["fps"]
W, H = spec["format"]["width"], spec["format"]["height"]
F = 1 / FPS
MARGIN = 108

# ---------------------------------------------------------------- palette (DESIGN.md section 3)
FLOOR, STEP, STEP_EDGE, RICE = "#0E0B09", "#17110D", "#2B211A", "#EFE6D6"
RING_COL = ["#E8B21A", "#D23A26", "#F28C1B"]          # turmeric, vermilion, marigold
INK, INK2 = "#F3E9DA", "#CDBDA6"

# ---------------------------------------------------------------- word times
def key(s: str) -> str:
    return s.lower().strip(".,!?")


ALL = [w for ln in words.values() for w in ln["words"]]
LINE = dict(words)


def wt(word: str) -> float:
    """Start of the first spoken word matching `word` (same rule as mix.py, so picture and sound agree)."""
    for w in ALL:
        if key(w["w"]) == key(word):
            return w["t0"]
    raise SystemExit(f"gen.py: {word!r} is not in words.json")


def wend(word: str) -> float:
    for w in ALL:
        if key(w["w"]) == key(word):
            return w["t1"]
    raise SystemExit(f"gen.py: {word!r} is not in words.json")


def cue_t(c: dict) -> float:
    return c["t"] if "t" in c else wt(c["word"]) + c.get("offset", 0.0)


lend = lambda lid: LINE[lid]["start"] + LINE[lid]["dur"]

# ---------------------------------------------------------------- kolam (port of kolam.js)
N, P, CX, CY = 7, 72, 540, 700
C = (N - 1) / 2
BULGE, THETA = 0.56, 28  # changed after style-frame review (was a quadratic at 0.43): round loops around each dot, real X crossings


def T(p):
    u, v = (p[0] - C) * P, (p[1] - C) * P
    return (CX + (u - v) * math.sqrt(.5), CY + (u + v) * math.sqrt(.5))


def kolam_loops(n: int) -> list[list[tuple[float, float]]]:
    """Mirror curve: strands move in diagonal half steps and reflect on the grid border; returns closed loops."""
    seen, loops, mids = set(), [], []
    xs = [i / 2 for i in range(-1, 2 * n)]
    for x in xs:
        for y in xs:
            if (x % 1 != 0) != (y % 1 != 0):
                mids.append((x, y))
    edge = lambda v: v in (-0.5, n - 0.5)
    for sx, sy in mids:
        for sd in (1, -1):
            if (sx, sy, sd) in seen or edge(sx) or edge(sy):
                continue
            x, y, dx, dy = sx, sy, 1, sd
            pts, guard = [], 0
            while True:
                pts.append((x, y))
                seen.add((x, y, dx * dy))
                x, y = x + dx * .5, y + dy * .5
                if edge(x):
                    dx = -dx
                elif edge(y):
                    dy = -dy
                guard += 1
                if guard > 10000:
                    raise SystemExit("kolam loop did not close")
                if x == sx and y == sy and dx == 1 and dy == sd:
                    break
            loops.append(pts)
    return loops


def seg_dot(a, b):
    return (a[0] if float(a[0]).is_integer() else b[0], a[1] if float(a[1]).is_integer() else b[1])


def arc_segments(loop, bulge, theta):
    """Each step wraps one dot D as a cubic arc. The line leaves a crossing at `theta` degrees off the strand's
    diagonal (so two strands meet in a real X, crossing angle about 90 - 2 theta) and its midpoint sits `bulge`
    grid units from D (0.354 = straight chord, 0.5 = circle). A quadratic arc (kolam.js) ties the two together:
    at 0.6-0.75 it either kisses its neighbour or loses the crossings, so the review change uses this cubic."""
    segs = []
    m = len(loop)
    th = math.radians(theta)
    for i in range(m):
        a, b = loop[i], loop[(i + 1) % m]
        D = seg_dot(a, b)
        M = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        nx, ny = M[0] - D[0], M[1] - D[1]
        ln = math.hypot(nx, ny)
        nx, ny = nx / ln, ny / ln
        ux, uy = b[0] - a[0], b[1] - a[1]
        lu = math.hypot(ux, uy)
        ux, uy = ux / lu, uy / lu
        h = (bulge - ln) / (.75 * math.sin(th))          # cubic midpoint = M + 3/4 h sin(theta) n
        ta = (math.cos(th) * ux + math.sin(th) * nx, math.cos(th) * uy + math.sin(th) * ny)
        tb = (math.cos(th) * ux - math.sin(th) * nx, math.cos(th) * uy - math.sin(th) * ny)
        c1 = (a[0] + h * ta[0], a[1] + h * ta[1])
        c2 = (b[0] - h * tb[0], b[1] - h * tb[1])
        segs.append((T(a), T(c1), T(c2), T(b)))
    return segs


def seg_path(segs) -> str:
    d = f"M{segs[0][0][0]:.1f},{segs[0][0][1]:.1f}"
    for _, c1, c2, b in segs:
        d += f"C{c1[0]:.1f},{c1[1]:.1f} {c2[0]:.1f},{c2[1]:.1f} {b[0]:.1f},{b[1]:.1f}"
    return d + "Z"


def seg_bbox(segs):
    xs, ys = [], []
    for a, c1, c2, b in segs:
        for k in range(21):
            s = k / 20
            w = ((1 - s) ** 3, 3 * s * (1 - s) ** 2, 3 * s * s * (1 - s), s ** 3)
            xs.append(w[0] * a[0] + w[1] * c1[0] + w[2] * c2[0] + w[3] * b[0])
            ys.append(w[0] * a[1] + w[1] * c1[1] + w[2] * c2[1] + w[3] * b[1])
    return min(xs), min(ys), max(xs), max(ys)


ring_of = lambda p: max(abs(p[0] - C), abs(p[1] - C))
loops = kolam_loops(N)
assert len(loops) == 7 and all(len(lp) == 28 for lp in loops), f"kolam: {len(loops)} loops of {[len(l) for l in loops]}"
loops.sort(key=lambda lp: min(ring_of(p) for p in lp))      # centre first (stable, like Array.sort)
LOOP_SEGS = [arc_segments(lp, BULGE, THETA) for lp in loops]
bbs = [seg_bbox(s) for s in LOOP_SEGS]
LINE_W = 7
KOLAM_TOP = min(b[1] for b in bbs) - LINE_W / 2 - 3       # 3 px: powder displacement
KOLAM_BOT = max(b[3] for b in bbs) + LINE_W / 2 + 3
KOLAM_L, KOLAM_R = min(b[0] for b in bbs) - 7, max(b[2] for b in bbs) + 7

dots = [(i, j) for i in range(N) for j in range(N)]
dots.sort(key=lambda d: (T(d)[1], T(d)[0]))                # the hand works top row to bottom row

# ---------------------------------------------------------------- type measuring
FONT = HF / "SchibstedGrotesk.woff2"


def text_w(s: str, size: float, weight: int, track: float) -> float:
    f = ImageFont.truetype(str(FONT), round(size))
    f.set_variation_by_axes([weight])
    return f.getlength(s) + track * size * len(s)


# ---------------------------------------------------------------- captions (L1-L4)
CAP_SIZE, CAP_LH, CAP_W, CAP_TOP = 50, 58, 820, 128


def wrap_count(txt: str) -> int:
    rows, cur = 1, ""
    for wd in txt.split():
        t = (cur + " " + wd).strip()
        if text_w(t, CAP_SIZE, 500, -.012) > CAP_W and cur:
            rows, cur = rows + 1, wd
        else:
            cur = t
    return rows


cap_lines = [ln for ln in spec["lines"] if ln.get("plate", True)]
for ln in cap_lines:
    spoken = [key(w["w"]) for w in LINE[ln["id"]]["words"]]
    if spoken != [key(w) for w in ln["show"].split()]:
        raise SystemExit(f"{ln['id']}: caption words differ from the spoken words")
    rows = wrap_count(ln["show"])
    bottom = CAP_TOP + rows * CAP_LH
    assert rows <= 3, f"{ln['id']}: {rows} caption lines"
    assert KOLAM_TOP - bottom >= 34, f"{ln['id']}: caption bottom {bottom} is {KOLAM_TOP - bottom:.0f}px above the rangoli tip"

# ---------------------------------------------------------------- lamps (geometry, per-lamp variation, ignitions)
LAMP_Y, LAMP_K = 1214, 1.25
LAMP_X = [174, 351, 528, 705, 882]
LAMP_S = [1.0, 1.02, 0.985, 1.025, 0.99]                   # size, +-1-3 % (hand-made bowls)
LAMP_R = [-1.4, 1.0, -0.6, 1.8, -1.1]                      # tilt in degrees
WICK = (57.0, -31.0)                                       # wick tip in bowl units
FLAME_H = 78


def lamp_pt(i: int, p) -> tuple[float, float]:
    k, r = LAMP_K * LAMP_S[i], math.radians(LAMP_R[i])
    x, y = p[0] * k, p[1] * k
    return (LAMP_X[i] + x * math.cos(r) - y * math.sin(r), LAMP_Y + x * math.sin(r) + y * math.cos(r))


FLAME = [lamp_pt(i, WICK) for i in range(5)]
for i in range(5):                                          # bowl inside the side margins
    l, r = lamp_pt(i, (-50, 0))[0], lamp_pt(i, (66, -28))[0]
    assert l >= MARGIN and r <= W - MARGIN, f"lamp {i + 1} spans {l:.0f}-{r:.0f}px, outside the 108 px margins"

catches = sorted((c for c in spec["sfx"] if "lamp" in c), key=lambda c: c["lamp"])
assert [c["lamp"] for c in catches] == [1, 2, 3, 4, 5], f"need exactly one catch cue per lamp, got {[c['lamp'] for c in catches]}"
IGN = [cue_t(c) for c in catches]
assert all(b > a for a, b in zip(IGN, IGN[1:])), "lamps must light in order"
CARRY = {int(k): v for k, v in spec["lamp_carry"].items() if not k.startswith("_")}
for n in range(2, 6):
    assert IGN[n - 1] - CARRY[n] >= IGN[n - 2] + .05, f"spark to lamp {n} leaves before lamp {n - 1} is lit"
gaps = [b - a for a, b in zip(IGN[1:], IGN[2:])]
assert all(b < a for a, b in zip(gaps, gaps[1:])), f"lamp gaps should accelerate: {gaps}"

# ---------------------------------------------------------------- timeline (all from words.json)
DOT0 = wt("Diwali") + .1                    # the hand starts with the first word
DOT_END = lend("L1")                        # the grid completes as L1 ends
LOOP0 = wt("draw")                          # first kolam loop on "draw"
LOOP_GAP, LOOP_D, DOT_D = .52, .9, .22
POWDER0 = wt("rangoli")
RING_DT = [0, .25, .55]
LIGHT_UP, LIGHT_D = wt("gives"), 1.8
TILT0, TILT_D = wend("nothing") + .2, 1.1
HAPPY = wt("Happy")

rng = random.Random(7)
gaps_raw = [.12 - .075 * (i / 47) + (rng.random() - .5) * .03 for i in range(48)]
scale = (DOT_END - DOT_D - DOT0) / sum(gaps_raw)
DOT_T = [DOT0]
for g in gaps_raw:
    DOT_T.append(DOT_T[-1] + g * scale)
assert LOOP0 - (DOT_T[-1] + DOT_D) >= .25, "dot grid must hold still >= 0.25 s before the first line"
assert TILT0 + TILT_D <= HAPPY - F, f"camera tilt ends {TILT0 + TILT_D:.2f}s, after 'Happy' {HAPPY:.2f}s"
assert TILT0 >= IGN[-1] + .5 and TILT0 >= wend("nothing") + .15, "tilt starts before the scene is complete"
assert LOOP0 + 6 * LOOP_GAP + LOOP_D < IGN[0] + 1.5, "kolam still drawing long after lamp 1"

# ---------------------------------------------------------------- end lockup (rebalanced after review)
HEAD_W = 700
size_fit = (W - 2 * MARGIN) / text_w("Happy Diwali", 100, HEAD_W, -.04) * 100
HEAD_SIZE = int(min(156, size_fit - 2))
HEAD_BOX = round(HEAD_SIZE * .95)
SIGN_SIZE, SIGN_LH, SIGN_GAP = 46, 53, 22
SIGN_BOTTOM = H - MARGIN - 8                                 # sign line box ends inside the bottom margin
HEAD_TOP = SIGN_BOTTOM - SIGN_LH - SIGN_GAP - HEAD_BOX
BOWL_BOTTOM_LOCAL = 24 * LAMP_K * max(LAMP_S) + 4
TILT = math.ceil(LAMP_Y + BOWL_BOTTOM_LOCAL + 48 - HEAD_TOP)  # bowls sit 48 px above the headline box
assert text_w("from all of us at Yourider", SIGN_SIZE, 450, -.01) + 6 <= W - 2 * MARGIN
assert KOLAM_TOP - TILT >= 0, f"rangoli tip cut by the frame at the end ({KOLAM_TOP - TILT:.0f}px)"

# ---------------------------------------------------------------- tweens
tw: list[str] = []
at = lambda t: f"{max(0.0, t):.3f}"

# dots: 0.9 -> 1 with opacity, accelerating hand
for n, d in enumerate(dots):
    x, y = T(d)
    tw.append(f'tl.fromTo("#d{n}", {{opacity: 0, scale: 0.9, svgOrigin: "{x:.1f} {y:.1f}"}}, '
              f'{{opacity: 1, scale: 1, duration: {DOT_D}, ease: "arrive"}}, {at(DOT_T[n])});')

# powder fills (rings 0-2), poured unevenly
fills_html = []
grng = random.Random(11)
for d in dots:
    r = ring_of(d)
    if r > 2:
        continue
    r = int(r)
    x, y = T(d)
    rr = P * (.31 + .03 * (((d[0] * 7 + d[1] * 3) % 5) / 4 - .5))
    pts = []
    k = 18
    ph = grng.random() * 6.28
    for q in range(k):
        a = q / k * 2 * math.pi
        rad = rr * (1 + .07 * math.sin(3 * a + ph) + .05 * math.sin(5 * a + 2 * ph) + (grng.random() - .5) * .08)
        pts.append((x + rad * math.cos(a), y + rad * math.sin(a)))
    dd = f"M{pts[0][0]:.1f},{pts[0][1]:.1f}"
    for q in range(k):
        p0, p1, p2, p3 = pts[q - 1], pts[q], pts[(q + 1) % k], pts[(q + 2) % k]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        dd += f"C{c1[0]:.1f},{c1[1]:.1f} {c2[0]:.1f},{c2[1]:.1f} {p2[0]:.1f},{p2[1]:.1f}"
    grains = ""
    for _ in range(46):                                    # sprinkled grains past the edge
        a = grng.random() * 2 * math.pi
        rad = rr * (.88 + .42 * grng.random() ** 1.6)
        grains += (f'<circle cx="{x + rad * math.cos(a):.1f}" cy="{y + rad * math.sin(a):.1f}" '
                   f'r="{.9 + 1.3 * grng.random():.1f}" opacity="{.45 + .55 * grng.random():.2f}"/>')
    fid = f"f{d[0]}_{d[1]}"
    fills_html.append(f'<g id="{fid}" fill="{RING_COL[r]}" opacity="0"><path d="{dd}" fill="url(#pw{r})" filter="url(#powderFill)"/>{grains}</g>')
    t0 = POWDER0 + RING_DT[r] + .035 * ((d[0] * 3 + d[1] * 5) % 7)
    tw.append(f'tl.fromTo("#{fid}", {{opacity: 0, scale: 0.9, svgOrigin: "{x:.1f} {y:.1f}"}}, '
              f'{{opacity: 1, scale: 1, duration: 0.32, ease: "arrive"}}, {at(t0)});')

# kolam line: one stroke per loop, drawn by dash offset; hidden until its stroke starts (no round-cap dot)
loop_html = []
for i, segs in enumerate(LOOP_SEGS):
    loop_html.append(f'<path id="k{i}" d="{seg_path(segs)}" pathLength="1000" stroke-dasharray="1000 1000" '
                     f'style="stroke-dashoffset:1000;visibility:hidden"/>')
    t0 = LOOP0 + i * LOOP_GAP
    tw.append(f'tl.set("#k{i}", {{visibility: "visible"}}, {at(t0)});')
    tw.append(f'tl.fromTo("#k{i}", {{strokeDashoffset: 1000}}, {{strokeDashoffset: 0, duration: {LOOP_D}, ease: "draw"}}, {at(t0)});')


# lamps
def bowl(i: int) -> str:
    """Clay diya in bowl units: darker lower half, lighter lip, dark oil with a thin highlight near the wick."""
    body = "M-50,-18 Q-46,22 0,24 Q44,22 50,-18 Q60,-22 66,-28 Q46,-12 0,-12 Q-30,-12 -50,-18Z"
    opening = "M-50,-18 Q-30,-12 0,-12 Q46,-12 66,-28 Q56,-25 46,-23 Q2,-25 -50,-18Z"
    g = f'<path d="{body}" fill="url(#clay)"/>'
    g += f'<path d="{body}" fill="url(#clayside)"/>'                                       # form: away from the flame is darker
    g += f'<path d="{body}" fill="url(#claylit)" class="lit{i}" opacity="0"/>'           # its own flame lights it
    g += f'<path d="{opening}" fill="url(#oil)"/>'
    g += f'<path d="M-49,-18.5 Q2,-25 46,-23 Q56,-25 65,-28" fill="none" stroke="#7A3D1C" stroke-width="1.4"/>'  # back lip
    g += (f'<path d="M-50,-18 Q-30,-12 0,-12 Q46,-12 66,-28" fill="none" stroke="#D07A3C" stroke-width="2.5" '
          f'stroke-linecap="round" id="rim{i}" opacity="0.15"/>')                         # lit front lip
    g += f'<path d="M33,-19.6 Q41,-21.4 48,-21.6" fill="none" stroke="#FFE3A8" stroke-width="1" stroke-linecap="round" class="lit{i}" opacity="0"/>'  # oil highlight
    g += f'<path d="M52,-22 L57,-31" stroke="#1E120B" stroke-width="3" stroke-linecap="round"/>'
    g += f'<path d="{body}" fill="#070403" id="dark{i}" opacity="0.82"/>'
    return (f'<g transform="translate({LAMP_X[i]},{LAMP_Y}) rotate({LAMP_R[i]}) scale({LAMP_K * LAMP_S[i]:.4f})">{g}</g>')


def flame(i: int) -> str:
    fx, fy = FLAME[i]
    h, w = FLAME_H, 21
    return (f'<g id="fc{i}" opacity="0"><g id="fk{i}">'
            f'<path d="M{fx:.1f},{fy:.1f} C{fx - w:.1f},{fy - h * .25:.1f} {fx - w * .5:.1f},{fy - h * .72:.1f} {fx + 2:.1f},{fy - h:.1f} '
            f'C{fx + w * .55:.1f},{fy - h * .7:.1f} {fx + w:.1f},{fy - h * .25:.1f} {fx:.1f},{fy:.1f}Z" fill="url(#flame)"/>'
            f'<ellipse cx="{fx:.1f}" cy="{fy - h * .22:.1f}" rx="5" ry="{h * .17:.1f}" fill="#FFFBEF"/></g></g>')


pools_html, halos_html, bowls_html, flames_html, sparks_html = [], [], [], [], []
for i in range(5):
    x = LAMP_X[i]
    fx, fy = FLAME[i]
    pools_html.append(f'<ellipse id="pl{i}" cx="{x}" cy="{LAMP_Y - 60}" rx="300" ry="260" fill="url(#pool)" opacity="0"/>')
    halos_html.append(f'<g id="hc{i}" opacity="0"><circle id="hk{i}" cx="{fx:.1f}" cy="{fy - 40:.1f}" r="170" fill="url(#halo)"/></g>')
    bowls_html.append(bowl(i))
    flames_html.append(flame(i))
    t = IGN[i]
    tw.append(f'tl.fromTo("#fc{i}", {{opacity: 0, scaleY: 0.55, svgOrigin: "{fx:.1f} {fy:.1f}"}}, '
              f'{{opacity: 1, scaleY: 1, duration: 0.5, ease: "arrive"}}, {at(t)});')
    tw.append(f'tl.fromTo("#hc{i}", {{opacity: 0}}, {{opacity: 1, duration: 0.9, ease: "arrive"}}, {at(t)});')
    tw.append(f'tl.fromTo("#pl{i}", {{opacity: 0}}, {{opacity: 0.8, duration: 0.9, ease: "arrive"}}, {at(t + .1)});')
    tw.append(f'tl.fromTo("#rim{i}", {{opacity: 0.15}}, {{opacity: 1, duration: 0.5, ease: "arrive"}}, {at(t)});')
    tw.append(f'tl.fromTo("#dark{i}", {{opacity: 0.82}}, {{opacity: 0, duration: 0.5, ease: "arrive"}}, {at(t)});')
    tw.append(f'tl.fromTo("#lamp{i} .lit{i}", {{opacity: 0}}, {{opacity: 1, duration: 0.5, ease: "arrive"}}, {at(t)});')
    # light up on "gives": pools widen (300x260 -> 560x560) and brighten
    tw.append(f'tl.to("#pl{i}", {{scaleX: {560 / 300:.4f}, scaleY: {560 / 260:.4f}, opacity: 1, svgOrigin: "{x} {LAMP_Y - 60}", '
              f'duration: {LIGHT_D}, ease: "arrive"}}, {at(LIGHT_UP)});')
    if i > 0:                                   # spark carried from flame i-1 to wick i, arcing 40 px above the wicks
        n = i + 1
        sx, sy = FLAME[i - 1][0], FLAME[i - 1][1] - 22
        t0 = IGN[i] - CARRY[n]
        sparks_html.append(f'<g id="sp{i}" style="visibility:hidden" transform="translate({sx:.1f},{sy:.1f})"><g id="sq{i}">'
                           f'<circle r="11" fill="#FFC56B" opacity="0.35"/><circle r="3.5" fill="#FFE3A3"/></g></g>')
        tw.append(f'tl.set("#sp{i}", {{visibility: "visible"}}, {at(t0)});')
        tw.append(f'tl.fromTo("#sp{i}", {{x: {sx:.1f}, y: {sy:.1f}}}, {{x: {fx:.1f}, y: {fy:.1f}, duration: {CARRY[n]}, ease: "carry"}}, {at(t0)});')
        tw.append(f'tl.fromTo("#sq{i}", {{y: 0}}, {{y: -40, duration: {CARRY[n]}, ease: "arc"}}, {at(t0)});')
        tw.append(f'tl.set("#sp{i}", {{visibility: "hidden"}}, {at(IGN[i])});')

# light comes up across the floor (whole-frame impact 1)
tw.append(f'tl.fromTo("#veil", {{opacity: 1}}, {{opacity: 0.15, duration: {LIGHT_D}, ease: "arrive"}}, {at(LIGHT_UP)});')
# camera tilts down to the threshold in the voice silence (whole-frame impact 2)
tw.append(f'tl.fromTo("#world", {{y: 0}}, {{y: {-TILT}, duration: {TILT_D}, ease: "tilt"}}, {at(TILT0)});')

# captions: word by word, laid out at their final wrap from the start
caps_html = []
for n, ln in enumerate(cap_lines):
    lw = LINE[ln["id"]]["words"]
    nxt = next((l2["start"] for l2 in spec["lines"] if l2["start"] > ln["start"]), DUR)
    nxt = min(nxt, LINE[cap_lines[n + 1]["id"]]["start"]) if n + 1 < len(cap_lines) else nxt
    clear = min(lw[-1]["t1"] + .25, nxt - .2)
    a, b = lw[0]["t0"] - .1, clear + .2
    spans = " ".join(f'<span class="w" id="c{n}w{j}">{html.escape(w)}</span>' for j, w in enumerate(ln["show"].split()))
    caps_html.append(f'<div id="cap{n}" class="clip cap" data-start="{a:.2f}" data-duration="{b - a:.2f}" data-track-index="{20 + n % 2}">{spans}</div>')
    for j, w in enumerate(lw):
        tw.append(f'tl.fromTo("#c{n}w{j}", {{opacity: 0}}, {{opacity: 1, duration: 0.09, ease: "arrive"}}, {at(w["t0"])});')
    tw.append(f'tl.to("#cap{n}", {{opacity: 0, duration: 0.2, ease: "power2.out"}}, {at(clear)});')

# end lockup: L5 sync inside the headline and the sign
l5 = [ln for ln in spec["lines"] if not ln.get("plate", True)][0]
l5w = LINE[l5["id"]]["words"]
head_words = spec["on_screen"]["end_headline"].split()
sign_words = spec["on_screen"]["end_sign"].split()
if [key(w["w"]) for w in l5w] != [key(w) for w in head_words + sign_words]:
    raise SystemExit("L5 words differ from headline + sign: cannot sync inside the lockup")
end_spans_h, end_spans_s = [], []
for j, w in enumerate(head_words + sign_words):
    (end_spans_h if j < len(head_words) else end_spans_s).append(f'<span class="w" id="e{j}">{html.escape(w)}</span>')
    tw.append(f'tl.fromTo("#e{j}", {{opacity: 0}}, {{opacity: 1, duration: 0.09, ease: "arrive"}}, {at(l5w[j]["t0"])});')
lock_html = (f'<div id="end" class="clip" data-start="{HAPPY - .1:.2f}" data-duration="{DUR - HAPPY + .1:.2f}" data-track-index="30">'
             f'<h1>{" ".join(end_spans_h)}</h1><p>{" ".join(end_spans_s)}</p></div>')

# ---------------------------------------------------------------- sound and picture: every lamp cue on its ignition
for c in spec["sfx"]:
    if "lamp" in c:
        assert abs(cue_t(c) - IGN[c["lamp"] - 1]) <= F, f"{c['note']}: sound off its lamp"
bell = next(c for c in spec["sfx"] if c["file"] == "bell")
assert l5w[0]["t0"] <= cue_t(bell) <= l5w[1]["t1"], "bell is off the greeting"

# flicker phases (seeded per lamp)
frng = random.Random(23)
PH = [[round(frng.random() * 6.283, 3) for _ in range(3)] for _ in range(5)]

# ---------------------------------------------------------------- the page
WORLD_H = H + TILT + 20
defs = f'''<defs>
<filter id="powder" x="-5%" y="-5%" width="110%" height="110%"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="3" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="3.2" xChannelSelector="R" yChannelSelector="G" result="d"/><feComponentTransfer in="n" result="m"><feFuncA type="table" tableValues="0 0 1 1"/></feComponentTransfer><feComposite in="d" in2="m" operator="in" result="g"/><feMerge><feMergeNode in="d"/><feMergeNode in="g"/></feMerge></filter>
<filter id="powderFill" x="-25%" y="-25%" width="150%" height="150%"><feTurbulence type="fractalNoise" baseFrequency="0.55" numOctaves="2" seed="9" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="11" xChannelSelector="R" yChannelSelector="G" result="d"/><feTurbulence type="fractalNoise" baseFrequency="1.7" numOctaves="1" seed="2" result="n2"/><feComponentTransfer in="n2" result="m"><feFuncA type="linear" slope="2.2" intercept="-0.55"/></feComponentTransfer><feComposite in="d" in2="m" operator="in" result="g"/><feComponentTransfer in="g"><feFuncA type="discrete" tableValues="0 0 1 1 1 1 1 1"/></feComponentTransfer></filter>
<filter id="stone"><feTurbulence type="fractalNoise" baseFrequency="0.02 0.035" numOctaves="2" seed="5"/><feColorMatrix values="0 0 0 0 0.25  0 0 0 0 0.18  0 0 0 0 0.13  0 0 0 0.5 -0.1"/></filter>
{"".join(f'<radialGradient id="pw{r}"><stop offset="0" stop-color="{c}"/><stop offset="0.62" stop-color="{c}"/><stop offset="0.86" stop-color="{c}" stop-opacity="0.6"/><stop offset="1" stop-color="{c}" stop-opacity="0.15"/></radialGradient>' for r, c in enumerate(RING_COL))}
<radialGradient id="pool" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#FF9A3C" stop-opacity="0.34"/><stop offset="0.45" stop-color="#E06A1E" stop-opacity="0.12"/><stop offset="1" stop-color="#E06A1E" stop-opacity="0"/></radialGradient>
<radialGradient id="halo" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#FFC56B" stop-opacity="0.55"/><stop offset="0.35" stop-color="#FF9A3C" stop-opacity="0.18"/><stop offset="1" stop-color="#FF9A3C" stop-opacity="0"/></radialGradient>
<linearGradient id="flame" x1="0" y1="1" x2="0" y2="0"><stop offset="0" stop-color="#FFF6DC"/><stop offset="0.35" stop-color="#FFD27A"/><stop offset="0.8" stop-color="#FF9F2E"/><stop offset="1" stop-color="#F2801E" stop-opacity="0.85"/></linearGradient>
<linearGradient id="clay" gradientUnits="userSpaceOnUse" x1="0" y1="-16" x2="0" y2="24"><stop offset="0" stop-color="#9A4F27"/><stop offset="0.35" stop-color="#8A4520"/><stop offset="0.55" stop-color="#5E2C13"/><stop offset="0.8" stop-color="#3A190A"/><stop offset="1" stop-color="#24100A"/></linearGradient>
<linearGradient id="clayside" gradientUnits="userSpaceOnUse" x1="-50" y1="0" x2="50" y2="0"><stop offset="0" stop-color="#0A0503" stop-opacity="0.38"/><stop offset="0.6" stop-color="#0A0503" stop-opacity="0"/></linearGradient>
<radialGradient id="claylit" gradientUnits="userSpaceOnUse" cx="44" cy="-20" r="52"><stop offset="0" stop-color="#E08A4A" stop-opacity="0.45"/><stop offset="0.55" stop-color="#C46A33" stop-opacity="0.12"/><stop offset="1" stop-color="#C46A33" stop-opacity="0"/></radialGradient>
<linearGradient id="oil" gradientUnits="userSpaceOnUse" x1="-50" y1="0" x2="66" y2="0"><stop offset="0" stop-color="#140904"/><stop offset="1" stop-color="#2A160A"/></linearGradient>
<linearGradient id="veilg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#050302" stop-opacity="0.6"/><stop offset="0.62" stop-color="#050302" stop-opacity="0.55"/><stop offset="0.75" stop-color="#050302" stop-opacity="0.3"/><stop offset="1" stop-color="#050302" stop-opacity="0.2"/></linearGradient>
</defs>'''

art = (f'<svg id="art" width="{W}" height="{WORLD_H}" viewBox="0 0 {W} {WORLD_H}" xmlns="http://www.w3.org/2000/svg">{defs}'
       f'<rect width="{W}" height="{WORLD_H}" fill="{FLOOR}"/><rect width="{W}" height="{WORLD_H}" filter="url(#stone)" opacity="0.28"/>'
       f'{"".join(pools_html)}'
       f'<g filter="url(#powder)">'
       + "".join(f'<circle id="d{n}" cx="{T(d)[0]:.1f}" cy="{T(d)[1]:.1f}" r="7" fill="{RICE}" opacity="0"/>' for n, d in enumerate(dots))
       + "".join(fills_html)
       + f'<g fill="none" stroke="{RICE}" stroke-width="{LINE_W}" stroke-linecap="round" stroke-linejoin="round">{"".join(loop_html)}</g>'
       f'</g>'
       f'<rect id="veil" y="-400" width="{W}" height="2150" fill="url(#veilg)"/>'
       f'<rect x="0" y="1168" width="{W}" height="{WORLD_H - 1168}" fill="{STEP}"/><rect x="0" y="1168" width="{W}" height="2" fill="{STEP_EDGE}"/>'
       f'{"".join(halos_html)}'
       + "".join(f'<g id="lamp{i}">{b}</g>' for i, b in enumerate(bowls_html))
       + "".join(flames_html) + "".join(sparks_html) + '</svg>')

doc = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="UTF-8" /><meta name="viewport" content="width={W}, height={H}" />
<script src="gsap.min.js"></script>
<style>
@font-face{{font-family:"Schibsted Grotesk";src:url(SchibstedGrotesk.woff2) format('woff2');font-weight:400 900}}
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:{W}px;height:{H}px;overflow:hidden;background:{FLOOR};font-family:"Schibsted Grotesk",sans-serif}}
#world{{position:absolute;left:0;top:0;width:{W}px;height:{WORLD_H}px}}
#art{{position:absolute;left:0;top:0}}
#grain{{position:absolute;left:0;top:0;opacity:0.07;pointer-events:none}}
.cap{{position:absolute;left:{MARGIN}px;top:{CAP_TOP}px;width:{CAP_W}px;font-size:{CAP_SIZE}px;line-height:{CAP_LH}px;font-weight:500;
  letter-spacing:-0.012em;color:{INK};text-wrap:balance}}
.w{{opacity:0}}
#end{{position:absolute;left:{MARGIN}px;top:{HEAD_TOP}px;width:{W - 2 * MARGIN}px}}
#end h1{{font-size:{HEAD_SIZE}px;line-height:{HEAD_BOX}px;font-weight:{HEAD_W};letter-spacing:-0.04em;color:{INK};white-space:nowrap}}
#end p{{margin:{SIGN_GAP}px 0 0 6px;font-size:{SIGN_SIZE}px;line-height:{SIGN_LH}px;font-weight:450;letter-spacing:-0.01em;color:{INK2};white-space:nowrap}}
</style>
</head>
<body>
<div id="root" data-composition-id="main" data-start="0" data-duration="{DUR}" data-width="{W}" data-height="{H}">
  <audio id="mix" src="mix.wav" data-start="0" data-duration="{DUR}" data-track-index="9" data-volume="1"></audio>
  <div id="stage" class="clip" data-start="0" data-duration="{DUR}" data-track-index="0" style="position:absolute;inset:0;overflow:hidden">
    <div id="world">{art}</div>
    <canvas id="grain" width="{W + 64}" height="{H + 64}"></canvas>
  </div>
  {"".join(caps_html)}
  {lock_html}
</div>
<script>
const B = (x1, y1, x2, y2) => {{
  const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx, cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
  return x => {{ let t = x; for (let i = 0; i < 8; i++) {{ const d = (3 * ax * t + 2 * bx) * t + cx; if (Math.abs(d) < 1e-6) break; t -= (((ax * t + bx) * t + cx) * t - x) / d; }}
    t = Math.min(1, Math.max(0, t)); return ((ay * t + by) * t + cy) * t; }};
}};
// DESIGN.md motion language: one curve per role
gsap.registerEase("arrive", B(0.23, 1, 0.32, 1));
gsap.registerEase("draw", B(0.45, 0, 0.55, 1));
const carry = B(0.77, 0, 0.175, 1);
gsap.registerEase("carry", carry);
gsap.registerEase("arc", p => {{ const s = carry(p); return 4 * s * (1 - s); }});   // the spark's lift, on the carry's clock
gsap.registerEase("tilt", B(0.65, 0, 0.35, 1));

// film grain: one seeded noise canvas, offset per frame (no per-frame feTurbulence)
let seed = 1234567;
const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
(() => {{
  const c = document.getElementById("grain"), g = c.getContext("2d"), im = g.createImageData(c.width, c.height);
  for (let i = 0; i < im.data.length; i += 4) {{ const v = rnd() * 255; im.data[i] = im.data[i + 1] = im.data[i + 2] = v; im.data[i + 3] = 255; }}
  g.putImageData(im, 0, 0);
}})();

const tl = gsap.timeline({{ paused: true }});
{chr(10).join(tw)}

// per-frame samples (exact at every rendered frame): grain offset, and the flame flicker, a sum of three
// sines per lamp with seeded phases (never repeats within the film). Lamp scale/skew live on the inner group,
// so the catch (outer group) and the flicker never fight; lamp 1's outer group stays at scale 1 once lit.
const PH = {json.dumps(PH)}, FPS = {FPS}, NF = {round(DUR * FPS)};
for (let i = 0; i < 5; i++) {{
  const b = document.querySelector("#fc" + i + " path").getAttribute("d").match(/^M([\\d.]+),([\\d.]+)/);
  gsap.set("#fk" + i, {{svgOrigin: b[1] + " " + b[2]}});
}}
for (let f = 0; f <= NF; f++) {{
  const t = f / FPS;
  tl.set("#grain", {{x: -Math.floor(rnd() * 64), y: -Math.floor(rnd() * 64)}}, t);
  for (let i = 0; i < 5; i++) {{
    const [a, b, c] = PH[i];
    const s = Math.sin(2 * Math.PI * 1.3 * t + a) + 0.6 * Math.sin(2 * Math.PI * 2.9 * t + b) + 0.3 * Math.sin(2 * Math.PI * 5.3 * t + c);
    tl.set("#fk" + i, {{scaleY: 1 + 0.035 * s, skewX: 1.5 * s / 1.9}}, t);
    tl.set("#hk" + i, {{opacity: 0.96 + 0.04 * s / 1.9}}, t);
  }}
}}
window.__timelines = window.__timelines || {{}};
window.__timelines["main"] = tl;
</script>
</body>
</html>
'''
(HF / "index.html").write_text(doc)
print(f"ok: bulge {BULGE} theta {THETA}, rangoli y {KOLAM_TOP:.0f}-{KOLAM_BOT:.0f} x {KOLAM_L:.0f}-{KOLAM_R:.0f}; dots {DOT_T[0]:.2f}-{DOT_T[-1]:.2f}s; "
      f"loops {LOOP0:.2f}-{LOOP0 + 6 * LOOP_GAP + LOOP_D:.2f}s; lamps {', '.join(f'{t:.2f}' for t in IGN)}s; "
      f"light-up {LIGHT_UP:.2f}s; tilt {TILT0:.2f}-{TILT0 + TILT_D:.2f}s by {TILT}px; headline {HEAD_SIZE}px at {HEAD_TOP}, "
      f"sign bottom {SIGN_BOTTOM}")
