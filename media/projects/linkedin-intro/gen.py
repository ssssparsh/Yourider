"""HyperFrames composition for the LinkedIn intro (1080x1350, 30 fps, 30 s). See PLAN.md.

usage: python gen.py <project_dir> <build_dir>   -> <build_dir>/hf/index.html

Every event that lands on a spoken word is computed here from <build_dir>/words.json (never guessed seconds);
page transitions take their time from the matching script.json sound cue, so picture and sound share one source.
At the end every script.json cue is checked against the picture event it belongs to (fails loudly if out of sync).
Needs in <build_dir>/hf: SchibstedGrotesk.woff2 (for measuring), handshake-ht.png and the paper pieces.
"""
import html
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageFont

PROJECT, BUILD = Path(sys.argv[1]), Path(sys.argv[2])
HF = BUILD / "hf"
spec = json.loads((PROJECT / "script.json").read_text())
words = json.loads((BUILD / "words.json").read_text())
DUR, FPS = spec["duration"], spec["format"]["fps"]
W, H = spec["format"]["width"], spec["format"]["height"]
F = 1 / FPS
pal = spec["palette"]
PAPER, CARD, INK, MUTED, YEL, KEY = pal["ground"], pal["cardstock"], pal["ink"], pal["muted"], pal["accent"], pal["keyline"]

# ---------------------------------------------------------------- frame geometry
SAFE_L, SAFE_R, SAFE_T, SAFE_B = round(W * .1), round(W * .9), round(H * .1), round(H * .9)  # 80% title-safe
LM = SAFE_L + 4                  # the headline axis (plan: 96 px, moved inside title-safe)
TEXT_W = SAFE_R - LM - 4         # widest a text line may be
CAP_BOTTOM = SAFE_B - 15         # caption plate grows up from here
INFO_MAX = 1010                  # nothing important below this (captions live under it)

# ---------------------------------------------------------------- type measuring (same font file the page uses)
FONT = HF / "SchibstedGrotesk.woff2"


def font(size: float, weight: int) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(FONT), round(size))
    f.set_variation_by_axes([weight])
    return f


def text_w(s: str, size: float, weight: int, track: float) -> float:
    return font(size, weight).getlength(s) + track * size * len(s)


def fit(lines: list[str], cap: float, weight: int = 800, track: float = -.05, room: float = TEXT_W) -> int:
    """Largest size <= cap at which every line fits the title-safe measure."""
    w100 = max(text_w(s, 100, weight, track) for s in lines)
    return int(min(cap, 100 * room / w100))


# ---------------------------------------------------------------- word times
def key(s: str) -> str:
    return s.lower().strip(".,!?")


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


LINE = {lid: ln for lid, ln in words.items()}
lstart = lambda lid: LINE[lid]["start"]
lend = lambda lid: LINE[lid]["start"] + LINE[lid]["dur"]

# ---------------------------------------------------------------- the beat sheet (all seconds derive from words / cues)
H1_IN = None                            # S1 headline is set on frame 0 (LinkedIn may use frame 0 as the cover)
LEAD = wt("lead")                       # S1 card lands
T2 = cue("S2 masthead lifts out")       # transition
H2_IN = lstart("L2")
PEN0 = wt("rides") - .05                # S2 pen starts on "rides"
PEN_F = 40                              # the card's tuned 40 f (48 would print the segments after "stage by")
PEN1 = PEN0 + PEN_F * F                 # outline closes
SEG_D = [0, 2, 3, 4]                    # segments print in, uneven, frames after closure + 2
SEGS_DONE = PEN1 + 2 * F + SEG_D[-1] * F
HOP1 = wt("by") + .12                   # hops start only after every segment is printed
HOP2 = HOP1 + .45
assert HOP1 - 3 * F >= SEGS_DONE, f"S2 hop at {HOP1:.2f}s starts before the segments are printed ({SEGS_DONE:.2f}s)"
H3_IN = lstart("L3") - .10
HARD = wt("hard")                       # S3 nudge
YR = wt("Yourider")                     # S4 slam lands
SLAM0 = YR - 8 * F
ANT0 = YR - .62                         # silent anticipation: card pulls back
DROP0 = YR - .30                        # bar + card drop out, gone before the name lands
SNAP = YR + 44 * F                      # plates snap into register (= Yourider+1.47)
CRM = wt("CRM")
TAGS = [("Leads", wt("leads")), ("Pipelines", wt("pipelines")), ("Deals", wt("deals"))]
T5 = cue("S5 yellow sheet pushes up")
TOP = wt("top")                         # the yellow sheet lands on "top" (holds the tag row >= 1 s first)
DEAL_GAPS = [.30, .18, .10]             # hard-accelerating deal
DEALS = [TOP + .45 + sum(DEAL_GAPS[:k]) for k in range(4)]
FLIGHT, SETTLE = 8 * F, 4 * F
AGENTS = wt("agents")
TYPED = "AI agents, in chat."
CHAR_F = 2.0                            # the card's 2 f/char, so the finished line holds >= 1 s
TYPE0 = TOP + 1.5                       # after the paper slip has landed and settled
KEYS = list(range(0, len(TYPED) - 2, 4))  # soft keystroke sound every 4th character
TYPE1 = TYPE0 + len(TYPED) * CHAR_F * F
CURSOR_OFF = TYPE1 + 20 * F             # solid, blinks twice (4 f half period), removed
T6 = cue("S6 yellow sheet pulled away")
BUILDING = wt("building")
PIECE = wt("piece") + .2                # last print strip lands
MARK0 = wt("now") + .25                 # marker stroke under "now"
MARK_F = 12
H6_IN = MARK0 - 6 * F - 1.01            # headline settles 6 frames before the stroke
T7 = cue("S7 page inverts to bottle green")
T8 = cue("S8 yellow block collapses")
PANEL_SHRINK = .35
H7_IN = T7 + .1 + PANEL_SHRINK + .05     # headline rises once the panel has finished shrinking
H7_OUT = T8 - .42                       # cleared before the yellow block grows
BRAKE = cue("S8 lockup brake, square settles")
SUB_IN = cue("S8 sub-line appears") - .05

assert H6_IN >= T6 - .15, f"S6 headline would start at {H6_IN:.2f}, before the sheet lifts at {T6:.2f}"
assert TYPE0 >= DEALS[3] + FLIGHT + SETTLE + F, "typing starts before the paper slip has settled"
assert H7_OUT >= lend("L7"), "S7 headline leaves before the voice finishes it"
assert TYPE1 + 1.0 <= T6, f"S5 typed line done at {TYPE1:.2f}: less than 1 s before {T6:.2f}"

# ---------------------------------------------------------------- timeline helpers
tw: list[str] = []


def at(t: float) -> str:
    return f"{max(0.0, t):.3f}"


def show(sel: str, t0: float, t1: float | None = None) -> None:
    tw.append(f'tl.set("{sel}", {{autoAlpha: 1}}, {at(t0)});')
    if t1 is not None:
        tw.append(f'tl.set("{sel}", {{autoAlpha: 0}}, {at(t1)});')


def to(sel: str, props: str, t: float, dur: float, ease: str) -> None:
    tw.append(f'tl.to("{sel}", {{{props}, duration: {dur:.3f}, ease: {ease}}}, {at(t)});')


def paper_ease(name: str, dur: float) -> str:
    """Stop-motion on the 10 fps grid, sampling an ease (never linear steps)."""
    return f'S("{name}", {max(2, round(dur * 10))})'


# ---------------------------------------------------------------- masked headlines
heads: list[str] = []


def headline(hid: str, lines: list[str], top: float, t_in: float | None, t_out: float | None, colour: str = INK,
             cap: int = 112, parent: list[str] | None = None, sync: str | None = None) -> int:
    """Masked two-line headline. sync=<line id>: the voice's word sync runs inside the headline (yellow block behind
    each spoken word, times from words.json) instead of a caption plate."""
    size = fit(lines, cap)
    k = 0
    rows = ""
    for s_ in lines:
        ws = []
        for wd in s_.split():
            ws.append(f'<span class="hw" id="{hid}w{k}">{html.escape(wd)}</span>')
            k += 1
        rows += f'<div class="ln"><span>{" ".join(ws)}</span></div>'
    if sync:
        spoken = LINE[sync]["words"]
        if [w["w"] for w in spoken] != " ".join(lines).split():
            raise SystemExit(f"{hid}: headline words differ from spoken {sync}: cannot sync inside the headline")
        for j, w in enumerate(spoken):
            nxt = spoken[j + 1]["t0"] if j + 1 < len(spoken) else w["t1"] + .02
            tw.append(f'tl.to("#{hid}w{j}", {{backgroundColor: "{YEL}", color: "{INK}", duration: .06, ease: "power1.out"}}, {at(w["t0"])});')
            tw.append(f'tl.to("#{hid}w{j}", {{backgroundColor: "rgba(0,0,0,0)", color: "{colour}", duration: .1, ease: "power1.out"}}, {at(min(nxt, w["t1"] + .02))});')
    (parent if parent is not None else heads).append(
        f'<div id="{hid}" class="hl" style="left:{LM}px;top:{top:.0f}px;font-size:{size}px;color:{colour}">{rows}</div>')
    for i in range(len(lines)):
        if t_in is not None:
            tw.append(f'tl.fromTo("#{hid} .ln:nth-child({i + 1}) > span", {{yPercent: 140}}, '
                      f'{{yPercent: 0, duration: .9, ease: "power4.out", immediateRender: true}}, {at(t_in + .11 * i)});')
        if t_out is not None:
            to(f"#{hid} .ln:nth-child({i + 1}) > span", "yPercent: -140", t_out + .04 * i, .3, '"power3.in"')
    return size


def baseline(top: float, size: int, row: int) -> float:
    """y of the text baseline of headline row `row` (CSS line box 0.88em, half-leading split)."""
    asc, desc = font(size, 800).getmetrics()
    return top + row * .88 * size + (.88 * size - (asc + desc)) / 2 + asc


# ================================================================ S1 hook
HL1_TOP = 652
H1_OUT = T2 - .3                        # S1 headline clears before the card drops past it
assert H1_OUT >= lend("L1"), "S1 headline leaves before the voice finishes it"
s1 = headline("h1", ["Every deal", "starts as a lead."], HL1_TOP, H1_IN, H1_OUT, sync="L1")
MAST_H = 608
dots = []
STEP = 18
for iy in range(MAST_H // STEP + 1):
    for ix in range(W // STEP + 2):
        x = ix * STEP + (STEP / 2 if iy % 2 else 0)
        y = iy * STEP
        g = (y / MAST_H) ** 1.6 * .85 + .15 * (1 - abs(x / W - .7))       # denser toward the foot of the band
        r = STEP / 2 * .95 * math.sqrt(max(0.0, min(1.0, g)))
        if r > .6:
            dots.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{r:.1f}"/>')
masthead = (f'<div id="mast" class="abs" style="left:0;top:0;width:{W}px;height:{MAST_H}px;background:url(green.png);overflow:hidden">'
            f'<svg width="{W}" height="{MAST_H}" style="position:absolute;inset:0"><g fill="#1c4532">{"".join(dots)}</g></svg>'
            f'<div style="position:absolute;left:{LM}px;top:{SAFE_T + 10}px;font-weight:800;font-size:56px;letter-spacing:-.05em;color:{PAPER}">Yourider</div></div>')
tw.append(f'tl.to("#mast", {{y: -{MAST_H + 40}, duration: .4, ease: {paper_ease("power3.in", .4)}}}, {at(T2)});')


def crop_marks(cid: str, colour_top: str, colour_bot: str, inset: int = 44, arm: int = 40) -> str:
    """Printer's crop marks at the four corners (one full-frame SVG each, scaled from its corner)."""
    out = []
    for k, (x, y, sx, sy) in enumerate([(inset, inset, 1, 1), (W - inset, inset, -1, 1), (inset, H - inset, 1, -1), (W - inset, H - inset, -1, -1)]):
        c = colour_top if y < H / 2 else colour_bot
        out.append(f'<svg id="{cid}{k}" class="abs" width="{W}" height="{H}" style="left:0;top:0;transform-origin:{x}px {y}px">'
                   f'<path d="M{x} {y + sy * arm} L{x} {y} L{x + sx * arm} {y}" fill="none" stroke="{c}" stroke-width="3"/></svg>')
    return "".join(out)


marks1 = crop_marks("cm1_", PAPER, INK)
for k in range(4):
    tw.append(f'tl.fromTo("#cm1_{k}", {{scale: 0}}, {{scale: 1, duration: .2, ease: {paper_ease("back.out(2)", .2)}, immediateRender: true}}, {at(k * 2 * F)});')
    tw.append(f'tl.to("#cm1_{k}", {{autoAlpha: 0, duration: .2, ease: "power2.in"}}, {at(T2 + k * 2 * F)});')

# the Lead card: dealt onto the masthead from the top right, 3 stepped frames, lands on "lead"
LC_W, LC_H = Image.open(HF / "leadcard.png").size
LC_W, LC_H = LC_W - 40, LC_H - 40
LC_X, LC_Y = 560, 214
lead_card = (f'<div id="lead" class="abs shadow" style="left:{LC_X}px;top:{LC_Y}px;width:{LC_W}px;height:{LC_H}px;transform:rotate(-1.2deg)">'
             f'<img src="leadcard.png" style="position:absolute;left:-20px;top:-20px">'
             f'<div style="position:absolute;right:30px;top:-8px;width:70px;height:26px;background:{YEL}"></div>'
             f'<div style="position:absolute;left:34px;right:34px;top:70px;height:2px;background:{INK};opacity:.18"></div>'
             f'<div style="position:absolute;left:34px;bottom:22px;font-weight:800;font-size:92px;line-height:1;letter-spacing:-.03em;color:{INK}">Lead</div></div>')
tw.append(f'tl.fromTo("#lead", {{x: 620, y: -520, rotation: 16}}, {{x: 0, y: 0, rotation: -1.2, duration: {3 * F:.3f}, '
          f'ease: S("power3.out", 3), immediateRender: true}}, {at(LEAD - 3 * F)});')
tw.append(f'tl.to("#lead", {{scale: .985, duration: {F:.3f}, ease: "power2.out", yoyo: true, repeat: 1}}, {at(LEAD)});')

# ================================================================ S2 ride: the pipeline bar
BAR_X, BAR_Y, BAR_W, BAR_H, GAP = SAFE_L, 742, SAFE_R - SAFE_L, 120, 6
SEG_W = (BAR_W - 3 * GAP) / 4
seg_cx = [BAR_X + SEG_W / 2 + k * (SEG_W + GAP) for k in range(4)]
s2 = headline("h2", ["It rides", "a pipeline."], 168, H2_IN, H3_IN - .32)
segs = "".join(f'<rect id="seg{k}" x="{k * (SEG_W + GAP):.1f}" y="0" width="{SEG_W:.1f}" height="{BAR_H}" fill="{INK}"/>' for k in range(4))
outline = f'M0 0 H{BAR_W} V{BAR_H} H0 Z'


def perim(p: float) -> tuple[float, float]:
    L = 2 * (BAR_W + BAR_H)
    d = p * L
    if d <= BAR_W:
        return d, 0
    d -= BAR_W
    if d <= BAR_H:
        return BAR_W, d
    d -= BAR_H
    if d <= BAR_W:
        return BAR_W - d, BAR_H
    return 0, BAR_H - (d - BAR_W)


NIB = [(.04, 6.4), (.024, 8), (.011, 9.6)]
bar = (f'<div id="bar" class="abs" style="left:{BAR_X}px;top:{BAR_Y}px;width:{BAR_W}px;height:{BAR_H}px">'
       f'<svg width="{BAR_W}" height="{BAR_H}" style="position:absolute;inset:0;overflow:visible">'
       f'<g id="segs">{segs}</g>'
       f'<path id="ol" d="{outline}" fill="none" stroke="{INK}" stroke-width="6" stroke-linejoin="miter" pathLength="1" stroke-dasharray="1" stroke-dashoffset="1"/>'
       + "".join(f'<path id="nib{i}" d="{outline}" fill="none" stroke="{INK}" stroke-width="{wd}" stroke-linecap="round" pathLength="1" '
                 f'stroke-dasharray="{ln} {1 - ln}" stroke-dashoffset="{ln}" opacity="0"/>' for i, (ln, wd) in enumerate(NIB))
       + f'<circle id="tip" r="7.5" fill="{INK}" opacity="0" style="filter:drop-shadow(2px 3px 2px rgba(13,42,28,.35))"/></svg>'
       f'<div class="lbl" id="lbl0" style="left:0;top:{BAR_H + 18}px">Lead</div>'
       f'<div class="lbl" id="lbl3" style="right:0;top:{BAR_H + 18}px;text-align:right">Deal</div></div>')
for k in range(4):
    tw.append(f'tl.set("#seg{k}", {{opacity: 0}}, 0);')
show("#bar", T2 + .2)
tw.append(f'tl.set(["#nib0", "#nib1", "#nib2", "#tip"], {{opacity: 1}}, {at(PEN0)});')
for f in range(PEN_F + 1):
    p = f / PEN_F
    e = 4 * p ** 3 if p < .5 else 1 - (-2 * p + 2) ** 3 / 2          # inOut cubic (card: Easing.inOut(cubic))
    x, y = perim(e)
    nibs = ", ".join(f'"#nib{i}"' for i in range(3))
    tw.append(f'tl.set("#ol", {{attr: {{"stroke-dashoffset": {1 - e:.4f}}}}}, {at(PEN0 + f * F)});'
              + "".join(f'tl.set("#nib{i}", {{attr: {{"stroke-dashoffset": {ln - e:.4f}}}}}, {at(PEN0 + f * F)});' for i, (ln, _) in enumerate(NIB))
              + f'tl.set("#tip", {{attr: {{cx: {x:.1f}, cy: {y:.1f}}}}}, {at(PEN0 + f * F)});')
tw.append(f'tl.set(["#nib0", "#nib1", "#nib2", "#tip"], {{opacity: 0}}, {at(PEN1 + F)});')
# closure: 2-frame darken + thicken, 6-frame release, then the four segments print in (uneven, accelerating)
tw.append(f'tl.to("#ol", {{attr: {{"stroke-width": 11}}, stroke: "#03100a", duration: {2 * F:.3f}, ease: "power2.out"}}, {at(PEN1)});')
tw.append(f'tl.to("#ol", {{attr: {{"stroke-width": 6}}, stroke: "{INK}", duration: {6 * F:.3f}, ease: "power2.out"}}, {at(PEN1 + 2 * F)});')
tw.append('tl.set(["#lbl0", "#lbl3"], {opacity: 0}, 0);')
for k, d in enumerate(SEG_D):
    tw.append(f'tl.set("#seg{k}", {{opacity: 1}}, {at(PEN1 + 2 * F + d * F)});')
    if k in (0, 3):
        tw.append(f'tl.fromTo("#lbl{k}", {{opacity: 0, y: 8}}, {{opacity: 1, y: 0, duration: .25, ease: "power3.out", immediateRender: false}}, {at(PEN1 + 2 * F + d * F)});')
tw.append(f'tl.to("#ol", {{opacity: 0, duration: .3, ease: "power2.out"}}, {at(PEN1 + 12 * F)});')

# the card rides: shrink onto segment 1 when the masthead lifts, hop on "stage" and 0.45 s later
CARD_S = .45
cx0, cy0 = LC_X + LC_W / 2, LC_Y + LC_H / 2
ride_y = BAR_Y - LC_H * CARD_S / 2 - 4
pos = [(seg_cx[k] - cx0, ride_y - cy0) for k in range(4)]
to("#lead", f"y: {pos[0][1]:.1f}, scale: {CARD_S}, rotation: 1.5", T2, .3, paper_ease("power3.inOut", .3))
to("#lead", f"x: {pos[0][0]:.1f}, rotation: -2.5", T2 + .35, .5, paper_ease("power3.inOut", .5))
for t_hop, k, nf in [(HOP1, 1, 3), (HOP2, 2, 2)]:
    to("#lead", f"x: {pos[k][0]:.1f}, rotation: {[-2.5, 1.2, -1.8][k]}", t_hop - nf * F, nf * F, f'S("power2.inOut", {nf})')
    to("#lead", "y: \"-=26\"", t_hop - nf * F, nf * F / 2, '"power2.out"')
    to("#lead", "y: \"+=26\"", t_hop - nf * F / 2, nf * F / 2, '"power2.in"')

# ================================================================ S3 stall + silence
s3 = headline("h3", ["Keeping it moving", "is the hard part."], 168, H3_IN, YR - .32, sync="L3")
to("#lead", f"x: {pos[2][0] + 24:.1f}", HARD, 2 * F, 'S("power2.out", 2)')
to("#lead", f"x: {pos[2][0]:.1f}", HARD + 2 * F, 2 * F, 'S("power2.in", 2)')
to("#lead", f"x: {pos[2][0] - 48:.1f}, rotation: -4", ANT0, .3, paper_ease("power2.out", .3))      # silent anticipation
to("#lead", "y: \"+=900\", rotation: 9", DROP0, .2, 'S("power2.in", 2)')
to("#bar", "y: 700", DROP0, .2, 'S("power2.in", 2)')
show("#lead", 0, DROP0 + .4)
show("#bar", T2 + .2, DROP0 + .4)

# ================================================================ S4 turn: the riso slam
WM_SIZE = fit(["Yourider"], 220, room=TEXT_W - 2 * 22)
WM_TOP = 286
plates = "".join(f'<div id="pl{c}" class="plate-t" style="color:{col}">Yourider</div>' for c, col in (("Y", YEL), ("G", INK)))
wm = f'<div id="wm" class="abs" style="left:{LM}px;top:{WM_TOP}px;font-size:{WM_SIZE}px">{plates}</div>'
show("#wm", SLAM0, T5 + .5)
tw.append(f'tl.fromTo("#wm", {{y: 1100}}, {{y: 0, duration: {8 * F:.3f}, ease: "power3.in", immediateRender: false}}, {at(SLAM0)});')
for f in range(44):
    m = math.cos(2 * math.pi * f / 18) * math.exp(-f / 60)
    tw.append(f'tl.set("#plG", {{x: {22 * m:.2f}, y: {9 * m:.2f}}}, {at(YR + f * F)});tl.set("#plY", {{x: {-22 * m:.2f}, y: {-9 * m:.2f}}}, {at(YR + f * F)});')
tw.append(f'tl.set(["#plG", "#plY"], {{x: 0, y: 0}}, {at(SNAP)});')
for f in range(5):
    tw.append(f'tl.set("#wm", {{scale: {1 + .03 * (1 - f / 4):.4f}}}, {at(SNAP + f * F)});')
for f in range(11):                     # whole-frame impact 1 of 1: a 1.2% page nudge, 10 frames
    tw.append(f'tl.set("#stage", {{scale: {1 + .012 * math.exp(-f / 2.5) if f < 10 else 1:.5f}}}, {at(SNAP + f * F)});')

sub4_top = WM_TOP + WM_SIZE * .95 + 40
sub4 = f'<div id="sub4" class="hl small" style="left:{LM}px;top:{sub4_top:.0f}px;font-size:40px;color:{MUTED}"><div class="ln"><span>A CRM built around</span></div></div>'
tw.append(f'tl.fromTo("#sub4 .ln > span", {{yPercent: 140}}, {{yPercent: 0, duration: .7, ease: "power4.out", immediateRender: true}}, {at(CRM)});')
show("#sub4", CRM, T5 + .5)
TAG_TOP = sub4_top + 84
tags_html, x = [], LM
for k, (label, t_land) in enumerate(TAGS):
    tw_, th_ = Image.open(HF / f"tag{k}.png").size
    tw_, th_ = tw_ - 40, th_ - 40
    if text_w(label, 64, 700, -.01) > tw_ - 40:
        raise SystemExit(f"tag {label!r} does not fit its {tw_}px cardstock: widen it in build.sh")
    rot = [-.8, .6, -1.3][k]
    tags_html.append(f'<div id="tag{k}" class="abs shadow tag" style="left:{x}px;top:{TAG_TOP:.0f}px;width:{tw_}px;height:{th_}px">'
                     f'<img src="tag{k}.png" style="position:absolute;left:-20px;top:-20px"><span>{label}</span></div>')
    x += tw_ + 18
    t0 = t_land - FLIGHT
    show(f"#tag{k}", t0, T5 + .5)
    # 8 f flight (bezier .3,0,.2,1 on the 10 fps grid) with a lift, overshoot settle, 0.996 press
    tw.append(f'tl.fromTo("#tag{k}", {{x: {420 - 120 * k}, y: 760, rotation: {14 - 6 * k}, scale: 1}}, {{x: 0, y: 0, rotation: {rot}, duration: {FLIGHT:.3f}, '
              f'ease: SB(.3, 0, .2, 1, 3), immediateRender: false}}, {at(t0)});')
    tw.append(f'tl.to("#tag{k}", {{scale: 1.06, duration: {FLIGHT / 2:.3f}, ease: "sine.out", yoyo: true, repeat: 1}}, {at(t0)});')
    tw.append(f'tl.fromTo("#tag{k}", {{rotation: {rot + 2.2}}}, {{rotation: {rot}, duration: {SETTLE:.3f}, ease: B(.3, 0, .25, 1.15)}}, {at(t_land)});')
    tw.append(f'tl.to("#tag{k}", {{scale: .996, duration: {F:.3f}, ease: "power1.out", yoyo: true, repeat: 1}}, {at(t_land + SETTLE)});')
assert x - 18 <= SAFE_R + 2, f"tag row ends at {x - 18}px, past title-safe {SAFE_R}px"

# ================================================================ S5 agents (the yellow page)
y_inner: list[str] = []
s5 = headline("h5", ["AI agents", "on top."], 252, T5 + .3, None, parent=y_inner)
SL_W, SL_H = Image.open(HF / "slip0.png").size
SL_W, SL_H = SL_W - 40, SL_H - 40
fan = [(LM + 196, 556, -1.4), (LM + 222, 630, .6), (LM + 186, 704, -.4), (LM + 206, 790, 1.1)]
PILE = (W - SL_W * .55 / 2 - 40, 430, 8)          # a compact pile at the right edge, waiting
slips = []
for k in range(4):
    fx, fy, frot = fan[k]
    inner = ""
    if k == 3:
        chars = "".join(f'<span class="ch" id="ch{i}">{html.escape(c) if c != " " else "&nbsp;"}</span><i class="cur" id="cu{i + 1}"></i>'
                        for i, c in enumerate(TYPED))
        inner = f'<div class="typed"><i class="cur" id="cu0"></i>{chars}</div>'
    slips.append(f'<div id="sl{k}" class="abs shadow" style="left:{fx}px;top:{fy}px;width:{SL_W}px;height:{SL_H}px;z-index:{8 - k}">'
                 f'<img src="slip{k}.png" style="position:absolute;left:-20px;top:-20px">{inner}</div>')
    dx, dy = PILE[0] - (fx + SL_W / 2), PILE[1] - (fy + SL_H / 2)
    tw.append(f'tl.set("#sl{k}", {{x: {dx:.1f}, y: {dy + (3 - k) * -5:.1f}, rotation: {PILE[2] + (k % 2) * 2 - 1}, scale: .55}}, 0);')
    t0 = DEALS[k]
    tw.append(f'tl.set("#sl{k}", {{zIndex: {10 + k}}}, {at(t0)});')
    # anticipation (once, for the whole pile): press down 48 px, the top slip pulls back 30 px
    to(f"#sl{k}", 'y: "+=48"' if k else 'y: "+=48", x: "+=30"', DEALS[0] - 10 * F, 10 * F, '"power2.out"')
    tw.append(f'tl.to("#sl{k}", {{x: 0, y: 0, scale: 1, rotation: {frot + (1.8 if k % 2 else -1.8)}, duration: {FLIGHT:.3f}, ease: SB(.3, 0, .2, 1, 3)}}, {at(t0)});')
    tw.append(f'tl.to("#sl{k}", {{rotation: {frot}, duration: {SETTLE:.3f}, ease: B(.3, 0, .25, 1.15)}}, {at(t0 + FLIGHT)});')
    tw.append(f'tl.to("#sl{k}", {{scale: .996, duration: {F:.3f}, ease: "power1.out", yoyo: true, repeat: 1}}, {at(t0 + FLIGHT + SETTLE)});')
assert fan[3][1] + SL_H + 12 <= INFO_MAX, "S5 slips run into the caption band"
# typing: frame-locked characters, cursor solid while typing, blinks twice, then removed
tw.append(f'tl.set("#cu0", {{autoAlpha: 1}}, {at(TYPE0 - 6 * F)});')
for i in range(len(TYPED)):
    t = TYPE0 + i * CHAR_F * F
    tw.append(f'tl.set("#ch{i}", {{autoAlpha: 1}}, {at(t)});tl.set("#cu{i}", {{autoAlpha: 0}}, {at(t)});tl.set("#cu{i + 1}", {{autoAlpha: 1}}, {at(t)});')
last = f"#cu{len(TYPED)}"
for j, v in enumerate([0, 1, 0, 1, 0]):
    tw.append(f'tl.set("{last}", {{autoAlpha: {v}}}, {at(TYPE1 + (j + 1) * 4 * F)});')
assert abs(TYPE1 + 20 * F - CURSOR_OFF) < 1e-6
label5 = f'<div style="position:absolute;left:{LM}px;top:{SAFE_T + 14}px;font-weight:800;font-size:64px;letter-spacing:-.05em;color:{INK}">Yourider</div>'
ypage = (f'<div id="ypage" class="abs" style="left:0;top:0;width:{W}px;height:{H}px;background:url(yellow.png)">'
         f'{label5}{"".join(y_inner)}{"".join(slips)}</div>')
show("#ypage", T5, T6 + .5)
show("#h5", T5)
show("#sl0, #sl1, #sl2, #sl3", T5)
tw.append(f'tl.fromTo("#ypage", {{y: {H}}}, {{y: 0, duration: .4, ease: {paper_ease("power3.out", .4)}, immediateRender: false}}, {at(T5)});')
tw.append(f'tl.to("#ypage", {{y: {-H - 40}, duration: .4, ease: {paper_ease("power3.in", .4)}}}, {at(T6)});')

# ================================================================ S6 building: proof sheet, marker, the handshake prints
marks6 = crop_marks("cm6_", INK, INK)
for k in range(4):
    show(f"#cm6_{k}", T6 + .25 + [0, 2, 3, 5][k] * F, T7 + .4)
    tw.append(f'tl.fromTo("#cm6_{k}", {{scale: 0}}, {{scale: 1, duration: .2, ease: {paper_ease("back.out(2)", .2)}, immediateRender: false}}, {at(T6 + .25 + [0, 2, 3, 5][k] * F)});')
H6_TOP = 168
s6 = headline("h6", ["Being built", "right now."], H6_TOP, H6_IN, None)
show("#h6", T6 - .2, T7 + .4)


def mulberry32(a: int):
    def r() -> float:
        nonlocal a
        a = (a + 0x6D2B79F5) & 0xFFFFFFFF
        t = a
        t = ((t ^ (t >> 15)) * (t | 1)) & 0xFFFFFFFF
        t ^= (t + (((t ^ (t >> 7)) * (t | 61)) & 0xFFFFFFFF)) & 0xFFFFFFFF
        return ((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296
    return r


def marker_path(length: float, seed: int, k: float) -> str:
    """Variable-width marker stroke (marker-underline-title demo), scaled by k for a larger headline."""
    rand = mulberry32(seed)
    N = 40
    wob = [rand() - .5 for _ in range(N + 1)]
    top, bot = [], []
    for i in range(N + 1):
        t = i / N
        mid = (19 - t * 9 + math.sin(t * math.pi * 1.6 + .4) * 2.6 + wob[i] * 1.6) * k
        wb = 14 + math.sin(t * math.pi) * 6 - max(0, t - .86) * 46 - max(0, .06 - t) * 70
        w = max(2.2, wb + wob[i] * 3) * k
        top.append(f"{t * length:.1f},{mid - w / 2:.1f}")
        bot.append(f"{t * length:.1f},{mid + w / 2:.1f}")
    return "M" + "L".join(top) + "L" + "L".join(reversed(bot)) + "Z"


now_x = LM + text_w("right ", s6, 800, -.05)
now_w = text_w("now", s6, 800, -.05)
MK_K = s6 / 118
MK_LEN = now_w + 26
mk_top = baseline(H6_TOP, s6, 1) + .04 * s6 - 15 * MK_K
marker = (f'<svg id="mk" class="abs" width="{MK_LEN:.0f}" height="{44 * MK_K:.0f}" style="left:{now_x - 12:.0f}px;top:{mk_top:.0f}px;overflow:visible;mix-blend-mode:multiply">'
          f'<defs><clipPath id="mkc"><rect id="mkr" x="0" y="-30" width="0" height="{44 * MK_K + 60:.0f}"/></clipPath>'
          f'<filter id="dry" x="-5%" y="-40%" width="110%" height="180%" color-interpolation-filters="sRGB">'
          f'<feTurbulence type="fractalNoise" baseFrequency="0.09 0.5" numOctaves="2" seed="7" result="warp"/>'
          f'<feDisplacementMap in="SourceGraphic" in2="warp" scale="1.8" xChannelSelector="R" yChannelSelector="G" result="rough"/>'
          f'<feTurbulence type="fractalNoise" baseFrequency="0.035 0.9" numOctaves="2" seed="19" result="grain"/>'
          f'<feColorMatrix in="grain" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 -16 11.4" result="holes"/>'
          f'<feComposite in="rough" in2="holes" operator="in"/></filter></defs>'
          f'<g clip-path="url(#mkc)"><path d="{marker_path(MK_LEN, 77, MK_K)}" fill="{YEL}" filter="url(#dry)"/></g></svg>')
show("#mk", MARK0, T7 + .4)
for f in range(MARK_F + 1):          # 12 frames, ease-out (1-(1-x)^2.2), left to right
    p = f / MARK_F
    tw.append(f'tl.set("#mkr", {{attr: {{width: {(1 - (1 - p) ** 2.2) * (MK_LEN + 6):.1f}}}}}, {at(MARK0 + f * F)});')

# handshake panel and the six print strips (bottom to top, accelerating, complete on "piece"+0.2)
PN_W, PN_H = Image.open(HF / "panel.png").size
PN_W, PN_H = PN_W - 40, PN_H - 40
PN_X, PN_Y = (W - PN_W) // 2, 520
assert PN_Y + PN_H <= INFO_MAX, "S6 panel runs into the caption band"
hs_w, hs_h = Image.open(HF / "handshake-ht.png").size
HS_W = PN_W - 60
HS_H = HS_W * hs_h / hs_w
if HS_H > PN_H - 60:
    HS_H = PN_H - 60
    HS_W = HS_H * hs_w / hs_h
panel = (f'<div id="panel" class="abs shadow" style="left:{PN_X}px;top:{PN_Y}px;width:{PN_W}px;height:{PN_H}px;transform:rotate(.6deg)">'
         f'<img src="panel.png" style="position:absolute;left:-20px;top:-20px">'
         f'<img id="hs" src="handshake-ht.png" style="position:absolute;left:{(PN_W - HS_W) / 2:.0f}px;top:{(PN_H - HS_H) / 2:.0f}px;width:{HS_W:.0f}px;height:{HS_H:.0f}px;clip-path:inset(100% 0 0 0)"></div>')
show("#panel", T6, None)
gaps = [.50, .42, .36, .30, .26]
k_stretch = (PIECE - BUILDING) / sum(gaps)
strip_t = [BUILDING + k_stretch * sum(gaps[:i]) for i in range(6)]
assert abs(strip_t[-1] - PIECE) < 1e-6
for i, t in enumerate(strip_t):       # each strip a 2-frame step: half, then whole
    tw.append(f'tl.set("#hs", {{clipPath: "inset({100 - (i + .5) / 6 * 100:.2f}% 0 0 0)"}}, {at(t - F)});')
    tw.append(f'tl.set("#hs", {{clipPath: "inset({100 - (i + 1) / 6 * 100:.2f}% 0 0 0)"}}, {at(t)});')

# ================================================================ S7 CTA: the page inverts
gpage = f'<div id="gpage" class="abs" style="left:0;top:0;width:{W}px;height:{H}px;background:url(green.png)"></div>'
show("#gpage", T7, None)
tw.append(f'tl.fromTo("#gpage", {{y: {-H}}}, {{y: 0, duration: .4, ease: {paper_ease("power3.out", .4)}, immediateRender: false}}, {at(T7)});')
PANEL_S = .42
p_cx, p_cy = PN_X + PN_W / 2, PN_Y + PN_H / 2
tgt_cx, tgt_cy = SAFE_R - PN_W * PANEL_S / 2, SAFE_T + 20 + PN_H * PANEL_S / 2
to("#panel", f"x: {tgt_cx - p_cx:.1f}, y: {tgt_cy - p_cy:.1f}, scale: {PANEL_S}, rotation: 2.2", T7 + .1, PANEL_SHRINK, paper_ease("power3.inOut", PANEL_SHRINK))
to("#panel", 'y: "-=520", rotation: -6', H7_OUT, .3, 'S("power3.in", 3)')
show("#panel", T6, H7_OUT + .35)
H7_TOP = tgt_cy + PN_H * PANEL_S / 2 + 90
s7 = headline("h7", ["Follow along", "as it comes together."], H7_TOP, H7_IN, H7_OUT, colour=PAPER, sync="L7")
show("#h7", T7, H7_OUT + .4)
# the accent: a blank yellow block, bottom right. Built as the lockup's 120 px square at the frame centre and carried
# by transforms only (x, y, scale), so the S8 collapse interpolates sub-pixel.
LK_SQ, LK_GAP = 120, 28
WM8 = 150
wm8_w = text_w("Yourider", WM8, 800, -.05)
LK_W = LK_SQ + LK_GAP + wm8_w
LK_X = (W - LK_W) / 2
LK_CY = 600
YB_W, YB_H = 260, 56
YB_X, YB_Y = SAFE_R - YB_W, min(INFO_MAX - YB_H, H7_TOP + 2 * .88 * s7 + 150)
SQ_X, SQ_Y = (W - LK_SQ) / 2, LK_CY - LK_SQ / 2
yb_x, yb_y = YB_X + YB_W / 2 - W / 2, YB_Y + YB_H / 2 - LK_CY
yb = f'<div id="yb" class="abs" style="left:{SQ_X:.0f}px;top:{SQ_Y:.0f}px;width:{LK_SQ}px;height:{LK_SQ}px;background:{YEL}"></div>'
show("#yb", T7 + .5, None)
tw.append(f'tl.fromTo("#yb", {{x: {yb_x:.1f}, y: {yb_y:.1f}, scaleX: 0, scaleY: {YB_H / LK_SQ:.4f}}}, {{scaleX: {YB_W / LK_SQ:.4f}, duration: .3, '
          f'ease: S("power3.out", 3), immediateRender: false}}, {at(T7 + .5)});')

# ================================================================ S8 lockup
# grow (bottom-right block -> centre square 5.4x), collapse with a +6% brake, slide left, letters, sub-line
tw.append(f'tl.to("#yb", {{x: 0, y: 0, scaleX: 5.4, scaleY: 5.4, duration: .16, ease: "power2.in"}}, {at(T8)});')
COLL0 = T8 + .16
tw.append(f'tl.to("#yb", {{scaleX: 1, scaleY: 1, duration: {BRAKE - COLL0:.3f}, ease: "power2.inOut"}}, {at(COLL0)});')
tw.append(f'tl.to("#yb", {{scaleX: 1.06, scaleY: 1.06, duration: .06, ease: "sine.out", yoyo: true, repeat: 1}}, {at(BRAKE)});')
SLIDE0 = BRAKE + .05
tw.append(f'tl.to("#yb", {{x: {LK_X - SQ_X:.1f}, duration: .2, ease: "power2.inOut"}}, {at(SLIDE0)});')
letters = "".join(f'<span class="lt" id="lt{i}">{c}</span>' for i, c in enumerate("Yourider"))
wm8 = (f'<div id="wm8" class="abs" style="left:{LK_X + LK_SQ + LK_GAP:.0f}px;top:{LK_CY - WM8 * .5:.0f}px;font-size:{WM8}px;'
       f'line-height:1;font-weight:800;letter-spacing:-.05em;color:{PAPER}">{letters}</div>')
LET0 = SLIDE0 + .14
show("#wm8", LET0 - .05)
for i in range(8):
    tw.append(f'tl.fromTo("#lt{i}", {{autoAlpha: 0, x: 8}}, {{autoAlpha: 1, x: 0, duration: .3, ease: "power3.out", immediateRender: true}}, {at(LET0 + i * .035)});')
SETTLED = LET0 + 7 * .035 + .3
sub8 = (f'<div id="sub8" class="abs" style="left:{SAFE_L}px;width:{SAFE_R - SAFE_L}px;top:{LK_CY + 130}px;text-align:center;font-weight:600;'
        f'font-size:48px;line-height:1.22;letter-spacing:-.01em;color:{PAPER}">A CRM for leads, pipelines and deals.<br>Coming soon.</div>')
tw.append(f'tl.fromTo("#sub8", {{autoAlpha: 0}}, {{autoAlpha: 1, duration: .3, ease: "power2.out", immediateRender: true}}, {at(SUB_IN)});')
assert DUR - SETTLED >= 1.5, f"wordmark held only {DUR - SETTLED:.2f}s"

# ================================================================ captions: word-synced plate, pages of <= 2 lines
CAP_SIZE, CAP_PAD_X, CAP_PAD_Y, CAP_LH = 60, 30, 14, 1.16
CAP_MAX = SAFE_R - SAFE_L - 2 * CAP_PAD_X
cf = font(CAP_SIZE, 600)
SPACE = cf.getlength(" ")


def row_w(r: list[dict]) -> float:
    return sum(cf.getlength(w["w"]) + 16 for w in r) + SPACE * (len(r) - 1)


def wrap(ws: list[dict]) -> list[list[dict]]:
    """Rows of a caption page; two rows are balanced (no lone word on the second row)."""
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
        if len(wrap(a)) > 2 or len(wrap(b)) > 2:
            continue
        la = sum(cf.getlength(w["w"]) for w in a)
        lb = sum(cf.getlength(w["w"]) for w in b)
        cost = abs(la - lb) - (400 if a[-1]["w"][-1] in ",.;:" else 0)
        if best is None or cost < best[0]:
            best = (cost, i)
    if best is None:
        raise SystemExit("caption line too long for two 2-line pages: shorten it")
    return pages(ws[:best[1]]) + pages(ws[best[1]:])


THEMES = {"paper": (CARD, INK, YEL, INK), "yellow": (CARD, INK, INK, PAPER), "green": (PAPER, INK, YEL, INK)}
IN_HEADLINE = {"L1", "L3", "L7"}       # headline repeats the voice: word sync runs inside the headline
LINE_THEME = {"L5": "yellow", "L7": "green"}
plan = []
for lid, ln in words.items():
    if lid in IN_HEADLINE:
        continue
    pgs = pages(ln["words"])
    for pi, pg in enumerate(pgs):
        a = (ln["start"] if pi == 0 else pg[0]["t0"]) - .15
        b = pgs[pi + 1][0]["t0"] - .15 if pi + 1 < len(pgs) else ln["start"] + ln["dur"] + .35
        plan.append([lid, pg, a, b])
for i in range(len(plan) - 1):           # never two caption pages at once
    plan[i][3] = min(plan[i][3], plan[i + 1][2])
for (_, _, a0, b0), (_, _, a1, _) in zip(plan, plan[1:]):
    assert b0 <= a1 + 1e-9 and a0 < b0, f"caption windows overlap: {a0:.2f}-{b0:.2f} and {a1:.2f}"
caps = []
n = 0
for lid, pg, a, b in plan:
    if True:
        theme = LINE_THEME.get(lid, "paper")
        plate, ink, hi, hi_ink = THEMES[theme]
        rows = "".join('<div class="row">' + "".join(f'<span class="w" id="w{n}_{j + sum(len(r) for r in wrap(pg)[:ri])}">{html.escape(w["w"])}</span>'
                                                     for j, w in enumerate(r)) + "</div>" for ri, r in enumerate(wrap(pg)))
        caps.append(f'<div id="cap{n}" class="clip cap" data-start="{a:.2f}" data-duration="{b - a:.2f}" data-track-index="{20 + n % 2}">'
                    f'<div class="cplate" style="background:{plate};color:{ink}">{rows}</div></div>')
        tw.append(f'tl.from("#cap{n} .cplate", {{y: 30, opacity: 0, duration: .25, ease: "power3.out"}}, {at(a)});')
        for j, w in enumerate(pg):
            nxt = pg[j + 1]["t0"] if j + 1 < len(pg) else w["t1"] + .02
            tw.append(f'tl.to("#w{n}_{j}", {{opacity: 1, backgroundColor: "{hi}", color: "{hi_ink}", duration: .06, ease: "power1.out"}}, {at(w["t0"])});')
            tw.append(f'tl.to("#w{n}_{j}", {{backgroundColor: "rgba(0,0,0,0)", color: "{ink}", duration: .1, ease: "power1.out"}}, {at(min(nxt, w["t1"] + .02))});')
        n += 1
CAP_TOP_MIN = CAP_BOTTOM - (2 * CAP_SIZE * CAP_LH + 2 * CAP_PAD_Y + 4)
assert CAP_TOP_MIN >= INFO_MAX + 10, f"two-line captions reach up to {CAP_TOP_MIN:.0f}px, over information at {INFO_MAX}px"

# ---------------------------------------------------------------- sound and picture: every cue must sit on its picture event
picture = {
    "S1 crop marks print in": .05, "S1 Lead card lands": LEAD, "S2 masthead lifts out": T2, "S2 pen draws the bar": PEN0,
    "S2 card hops to segment 2": HOP1, "S2 card hops to segment 3": HOP2, "S3 card nudges and slips back": HARD,
    "S4 name slams in (8 frames)": SLAM0, "S4 plates snap into register (only whole-frame impact)": SNAP,
    "S4 tag Leads lands": TAGS[0][1], "S4 tag Pipelines lands": TAGS[1][1], "S4 tag Deals lands": TAGS[2][1],
    "S5 yellow sheet pushes up": T5, "S5 first slip dealt": DEALS[0],
    "S5 typing starts": TYPE0, "S5 typing done, cursor removed": CURSOR_OFF,
    **{f"S5 keystroke {i + 1}": TYPE0 + c * CHAR_F * F for i, c in enumerate(KEYS[1:])}, "S6 yellow sheet pulled away": T6,
    "S6 handshake starts printing": BUILDING, "S6 marker stroke under now": MARK0, "S6 last print strip lands": PIECE,
    "S7 page inverts to bottle green": T7, "S8 yellow block collapses": T8, "S8 lockup brake, square settles": BRAKE,
    "S8 sub-line appears": SUB_IN + .05,
}
for c in spec["sfx"]:
    want = picture.get(c.get("note"))
    if want is None:
        raise SystemExit(f"gen.py: sfx cue {c.get('note')!r} has no picture event")
    got = cue(c["note"])
    if abs(got - want) > 1.5 * F:
        raise SystemExit(f"gen.py: sound {c['note']!r} at {got:.3f}s but picture at {want:.3f}s")

# ---------------------------------------------------------------- the page
doc = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="UTF-8" /><meta name="viewport" content="width={W}, height={H}" />
<script src="gsap.min.js"></script>
<style>
@font-face{{font-family:"Schibsted Grotesk";src:url(SchibstedGrotesk.woff2) format('woff2');font-weight:400 900}}
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:{W}px;height:{H}px;overflow:hidden;background:{PAPER};font-family:"Schibsted Grotesk",sans-serif}}
.abs{{position:absolute}}
#stage .abs,#stage .hl{{visibility:hidden;opacity:0}}
#field{{position:absolute;inset:0;background:url(field.png)}}
.shadow{{filter:drop-shadow(10px 14px 14px rgba(13,42,28,.22)) drop-shadow(2px 3px 3px rgba(13,42,28,.16))}}
.hl{{position:absolute;font-weight:800;letter-spacing:-.05em;line-height:.88;white-space:nowrap}}
.hl.small{{font-weight:600;letter-spacing:-.01em;line-height:1.1}}
.ln{{overflow:hidden;padding:.12em .2em .2em 0;margin:-.12em -.2em -.2em 0}}
.ln > span{{display:inline-block}}
.hw{{padding:0 .05em;margin:0 -.05em;border-radius:.04em}}
.lbl{{position:absolute;font-weight:600;font-size:40px;letter-spacing:-.01em;color:{MUTED}}}
.plate-t{{position:absolute;left:0;top:0;font-weight:800;letter-spacing:-.05em;line-height:1;white-space:nowrap;mix-blend-mode:multiply}}
.tag span{{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:64px;letter-spacing:-.01em;color:{INK};padding-bottom:4px}}
.typed{{position:absolute;left:44px;top:0;bottom:0;display:flex;align-items:center;font-weight:700;font-size:56px;letter-spacing:-.02em;color:{INK};white-space:nowrap}}
.ch{{visibility:hidden}}
.cur{{display:inline-block;width:0;height:64px;position:relative;visibility:hidden}}
.cur::after{{content:"";position:absolute;left:1px;top:0;width:5px;height:64px;background:{INK}}}
.cap{{position:absolute;left:0;right:0;bottom:{H - CAP_BOTTOM}px;display:flex;justify-content:center}}
.cplate{{border:2px solid {KEY};border-radius:14px;padding:{CAP_PAD_Y}px {CAP_PAD_X}px;font-weight:600;font-size:{CAP_SIZE}px;line-height:{CAP_LH};
  letter-spacing:-.01em;box-shadow:8px 12px 18px rgba(13,42,28,.20);text-align:center;max-width:{SAFE_R - SAFE_L}px}}
.row{{white-space:nowrap}}
.w{{opacity:.38;padding:0 8px;border-radius:4px}}
.lt{{display:inline-block}}
</style>
</head>
<body>
<div id="root" data-composition-id="main" data-start="0" data-duration="{DUR}" data-width="{W}" data-height="{H}">
  <audio id="mix" src="mix.wav" data-start="0" data-duration="{DUR}" data-track-index="9" data-volume="1"></audio>
  <div id="stage" class="clip" data-start="0" data-duration="{DUR}" data-track-index="0" style="position:absolute;inset:0;transform-origin:50% 45%">
    <div id="field"></div>
    {masthead}{marks1}
    {heads[0]}{heads[1]}{heads[2]}
    {bar}{lead_card}
    {wm}{sub4}{"".join(tags_html)}
    {marks6}{heads[3]}{marker}
    {gpage}
    {panel}{heads[4]}{yb}{wm8}{sub8}
    {ypage}
  </div>
  {"".join(caps)}
</div>
<script>
const S = (name, n) => {{ const e = gsap.parseEase(name); return p => Math.round(e(p) * n) / n; }};
const B = (x1, y1, x2, y2) => {{
  const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx, cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
  return x => {{ let t = x; for (let i = 0; i < 8; i++) {{ const d = (3 * ax * t + 2 * bx) * t + cx; if (Math.abs(d) < 1e-6) break; t -= (((ax * t + bx) * t + cx) * t - x) / d; }}
    t = Math.min(1, Math.max(0, t)); return ((ay * t + by) * t + cy) * t; }};
}};
const SB = (x1, y1, x2, y2, n) => {{ const e = B(x1, y1, x2, y2); return p => Math.round(e(p) * n) / n; }};
const tl = gsap.timeline({{ paused: true }});
tl.set(["#mast", "#field"], {{autoAlpha: 1}}, 0);
tl.set(["#h1", "#lead"], {{autoAlpha: 1}}, 0);
tl.set("#cm1_0, #cm1_1, #cm1_2, #cm1_3", {{autoAlpha: 1}}, 0);
tl.set("#h2", {{autoAlpha: 1}}, {at(H2_IN - .05)});
tl.set("#h3", {{autoAlpha: 1}}, {at(H3_IN - .05)});
tl.set("#h1", {{autoAlpha: 0}}, {at(T2 + .4)});
tl.set("#h2", {{autoAlpha: 0}}, {at(H3_IN)});
tl.set("#h3", {{autoAlpha: 0}}, {at(YR)});
tl.set("#mast", {{autoAlpha: 0}}, {at(T2 + .5)});
{chr(10).join(tw)}
window.__timelines["main"] = tl;
</script>
</body>
</html>
'''
(HF / "index.html").write_text(doc)
print(f"ok: headlines {s1}/{s2}/{s3}/{s5}/{s6}/{s7}px, wordmark {WM_SIZE}px, {n} caption pages, slam {YR:.2f}s, snap {SNAP:.2f}s, "
      f"typed {TYPE0:.2f}-{TYPE1:.2f}s, strips {', '.join(f'{t:.2f}' for t in strip_t)}, wordmark still {SETTLED:.2f}-{DUR}s")
