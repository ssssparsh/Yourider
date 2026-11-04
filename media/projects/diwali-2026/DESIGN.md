# DESIGN: Diwali 2026 greeting (1080x1350, 30 fps, 20 s)

Direction in one line: **a sikku kolam drawn in rice flour over its own dot grid on a new-moon floor, lit only by five clay lamps that take their flame one from the next; the camera tilts down to the threshold and the greeting sits on the step below the lamps.**

Style frames (reference implementation, generator code included):
`media/.build/diwali-2026/style/01-dotgrid-3s.png`, `02-lit-12_5s.png`, `03-lockup-17s.png`;
source `media/.build/diwali-2026/style/frame.html` (state as a pure function of `?t=`) and `kolam.js` (geometry). The builder ports `kolam.js` as is and re-anchors the timeline to words.json.

This film is a greeting only. No product, no feature, no claim. Yourider appears once, as the sender, in the sign.

## 1. Subject inventory (refined from PLAN.md)
Every frame below traces to one of these.
1. **Amavasya**: the new-moon night. No moon, no sky, no stars drawn. Darkness is the starting material.
2. **Pulli (dot) grid**: the guide a person puts down first, dot by dot, before any line. Here: 7 x 7, set on the diagonal (a diamond), the usual doorstep orientation.
3. **Sikku kolam line**: one continuous rice-flour line that loops around every dot and never touches one. Constructed in code as a mirror curve (below), not drawn freehand by us.
4. **Powder, not ink**: grain, ragged edge, slight wobble; colour is poured into the loops after the white line.
5. **Turmeric, vermilion, marigold, rice white**: the four powders. Nothing else is coloured.
6. **Clay diya**: open bowl with a pinched spout, cotton wick, oil; unglazed, terracotta.
7. **One lamp lights the next**: light passes along the row; the first flame keeps its size.
8. **The threshold**: the stone step at the door. It is the stage and, at the end, the page.
9. **Light that falls**: the only light source is the flames; the floor and the rangoli are lit from the lamps' side, darker away from them.
10. **The sender**: "from all of us at Yourider", once, last.

## 2. References (not browsed this session)
Per the brief's time limit, no gallery sites were opened; nothing was copied, nothing goes into rights.md from this step.
- **Mirror-curve construction of sikku kolam / Lunda designs (Paulus Gerdes' mathematical description)**: taken: the rule that a line moving diagonally between dots reflects at the grid border and so wraps the outer dots. Not taken: any specific published pattern.
- **Tegaki (stroke-by-stroke handwriting) in our library**: taken: the idea that a drawn line should arrive at hand speed with a slow start and a slow end per stroke, not as one wipe. Not used as code.
- **Real doorstep practice** (subject, FACTS.md): dots first, white line second, colour third, lamps last. The film's order follows it exactly.

## 3. Tokens

### Palette (hex, role)
| Token | Hex | Role |
|---|---|---|
| floor | `#0E0B09` | the night floor, page background everywhere |
| stone | turbulence tint `rgb(64,46,33)` at 0.28 | floor texture only (see Texture) |
| veil | `#050302` | darkness laid over floor + rangoli: gradient 0.60 (top) -> 0.55 (62%) -> 0.30 (75%) -> 0.20 (bottom) |
| step | `#17110D` | threshold step face (y >= 1168) |
| step-edge | `#2B211A` | 2 px top edge of the step |
| rice | `#EFE6D6` | dots and the kolam line |
| turmeric | `#E8B21A` | powder, ring 0 (the centre dot) |
| vermilion | `#D23A26` | powder, ring 1 (8 dots) |
| marigold | `#F28C1B` | powder, ring 2 (16 dots); also the ONE accent: lamp light |
| clay | `#9A4F27 -> #4A2210` | diya body, vertical gradient |
| clay-rim | `#D07A3C` | lit rim, 2.5 px |
| wick | `#1E120B` | |
| flame | `#FFF6DC` (base) -> `#FFD27A` (35%) -> `#FF9F2E` (80%) -> `#F2801E` 0.85 (tip) | flame body, gradient bottom to top |
| flame-core | `#FFFBEF` | inner ellipse, rx 5, ry 0.17 h |
| pool | `#FF9A3C` 0.34 -> `#E06A1E` 0.12 (45%) -> 0 | radial light pool on the floor per lamp |
| halo | `#FFC56B` 0.55 -> `#FF9A3C` 0.18 (35%) -> 0 | radial halo around each flame, r 170 |
| ink | `#F3E9DA` | captions and headline (16:1 on floor) |
| ink-2 | `#CDBDA6` | the sign (about 10:1 on step) |

Colour is material: the four powders appear only in the rangoli; marigold light is the only accent. No other hue enters the film.

### Type (one family)
Schibsted Grotesk variable (repo copy `$MEDIA_TOOLS/web/SchibstedGrotesk.woff2`, OFL, already in the repo; no new font).
| Role | Size / line-height | Weight | Tracking | Colour |
|---|---|---|---|---|
| Caption (L1-L4) | 50 / 58 px | 500 | -0.012em | ink |
| End headline "Happy Diwali" | 140 / 133 px, one line | 700 | -0.04em | ink |
| Sign "from all of us at Yourider" | 46 / 53 px | 450 | -0.01em | ink-2 |
Nothing on screen below 46 px. No eyebrow, no second family, no script face, no gradient text.

### Grid and safe areas
- Frame 1080 x 1350. Margins 108 px left/right (title-safe 80%: x 108-972, y 135-1215).
- **Caption zone**: x 108, top 128, width 820, max 3 lines (bottom <= 310). Left-aligned, ragged right, `text-wrap: balance`.
- **Rangoli**: centre (540, 700), pitch P = 72 px, grid rotated 45 deg. Outer loop extent: y 344-1056, x 184-896. Never under the caption zone (gap >= 34 px at the top tip).
- **Lamps**: 5 bowls on the step, bowl centres x = 176, 356, 536, 716, 896, y = 1214, scale 1.25 of the drawn bowl (about 145 px wide). Flame base at (x + 72, y - 38), flame height 78 px.
- **Step**: rect from y 1168 down, 2 px edge.
- **End (after the camera tilt of -400 px)**: rangoli centre at y 300 (top cropped by the frame on purpose), lamps at y 814, step edge at 768. Headline block left 108, top 880. Sign 22 px under the headline, indented 6 px to sit on the H's stem optically.
- No radius, no shadows, no cards, no plates anywhere in the film.

### Texture
- **Powder line**: SVG filter on the rangoli group: feTurbulence fractalNoise 0.9, 2 octaves, seed 3 -> feDisplacementMap scale 3.2, plus a speckle layer (noise alpha table `0 0 1 1`) merged on top. Seed fixed, never animated.
- **Powder fill**: filter `powderFill`: displacement scale 7 (noise 0.7, seed 9) then an alpha mask of noise 1.6 (`discrete 0 1 1 1 1`) so about 20% of the fill is missing grains.
- **Stone**: feTurbulence 0.02 x 0.035, 2 octaves, seed 5, tinted, opacity 0.28. Static.
- **Grain**: whole frame, opacity 0.07. In the build, generate one 1080x1350 noise canvas at load (seeded), and per frame offset it by a seeded random (dx, dy) in 0-64 px. Do not re-run feTurbulence per frame (CPU cost).

## 4. Rangoli construction (exact; `kolam.js`)
1. Dots: n = 7, grid points (i, j), i, j in 0..6. Screen transform `T(x,y)`: u = (x-3)P, v = (y-3)P; screen = (540 + (u - v)/sqrt2, 700 + (u + v)/sqrt2). Dot radius 7 px, rice.
2. **Kolam line (mirror curve)**: points live on the half-lattice (exactly one coordinate is a half-integer), including the border points x or y = -0.5 / 6.5. A strand moves in diagonal steps of (+-0.5, +-0.5); on reaching x = -0.5 or 6.5 it flips dx, on y = -0.5 or 6.5 it flips dy. No interior mirrors. Result: 7 closed loops of 28 points each (`kolamLoops(7)`).
3. **Curve**: each step between two consecutive points wraps exactly one dot D (its integer x from one endpoint, integer y from the other). Draw it as a quadratic Bezier whose midpoint sits at distance `BULGE = 0.43` grid units from D (0.354 = straight, 0.5 = circle; 0.43 keeps true crossings and still reads as loops). `arcPath(loop, T, 0.43)`.
4. Line: rice, stroke-width 7 px, round caps and joins, `pathLength=1000`, drawn by `stroke-dashoffset` 1000 -> 0.
5. **Loop order**: sort loops by their minimum ring distance from the centre (ring = max(|i-3|, |j-3|)), centre first; each loop starts at its first generated point.
6. **Powder**: ring 0 (1 dot) turmeric, ring 1 (8 dots) vermilion, ring 2 (16 dots) marigold, ring 3 (24 dots) left unfilled: white loops with their dots only. Each fill is a disc centred on the dot, r = P x (0.29 + 0.03 x (((7i + 3j) mod 5)/4 - 0.5)) (slightly uneven, as poured), filter `powderFill`, painted under the line.
7. Light: one veil rect over floor + rangoli (gradient above), opacity `1 - 0.85 x lightUp`. Light pools: one ellipse per lit lamp centred (x, 1154), rx 300 + 260 lightUp, ry 260 + 300 lightUp, opacity lit x (0.8 + 0.4 lightUp), painted under the powder.

## 5. Motion language
Personality: **a hand at a doorstep**. Unhurried, exact, accelerating as it gains confidence; nothing floats, nothing bounces.

| Role | Curve | Duration |
|---|---|---|
| Arrive (dots, powder, words) | `cubic-bezier(0.23, 1, 0.32, 1)` (strong ease-out) | dot 220 ms, powder disc 320 ms, word 90 ms (3 frames) |
| Draw (kolam loop) | `cubic-bezier(0.45, 0, 0.55, 1)` per loop (hand starts and stops) | 900 ms per loop, next loop starts 520 ms after the previous |
| Carry (light passing lamp to lamp) | `cubic-bezier(0.77, 0, 0.175, 1)` | 420 / 300 / 220 / 160 ms (accelerating) |
| Catch (a flame takes) | `cubic-bezier(0.23, 1, 0.32, 1)` | 500 ms, scaleY 0.55 -> 1, opacity 0 -> 1, origin flame base |
| Light comes up (L4) | `cubic-bezier(0.23, 1, 0.32, 1)` | 1800 ms |
| Camera tilt (end) | `cubic-bezier(0.65, 0, 0.35, 1)` (in-out, moving on screen) | 1100 ms, world y 0 -> -400 |
| Caption line exit | ease-out | 200 ms opacity only |

- Never scale from 0: dots 0.9 -> 1, powder 0.9 -> 1, flames 0.55 -> 1 in height. Animate transform, opacity, stroke-dashoffset and the veil opacity only.
- Stagger: dots 120 ms gap at the start shrinking to 45 ms at dot 49, +-15 ms seeded jitter (the hand speeds up). Powder within a ring: 0-210 ms by `((3i + 5j) mod 7) x 35 ms`, never even.
- Flicker (all lit flames, always on): scaleY = 1 + 0.035 (sin(2 pi 1.3 t + a) + 0.6 sin(2 pi 2.9 t + b) + 0.3 sin(2 pi 5.3 t + c)), skewX +-1.5 deg from the same signal, a/b/c seeded per lamp so no two lamps match and nothing loops within 20 s. Halo opacity follows 0.92-1.0. No flicker on the pools (they would read as strobing).
- **Lamp 1 never changes**: no dip, no shrink, no brightness change when it gives its light. That is L4's meaning; the builder asserts flame-1 height is identical at 9.0, 11.0 and 14.0 s.
- Whole-frame impacts: exactly two. (1) L4 light-up, (2) the camera tilt in the silence. No shakes, no flashes, no zooms elsewhere.
- Holds: dot grid complete and still >= 0.25 s before the first line starts; full rangoli + all five flames held still (flicker only) 13.8-14.35; lockup held >= 2.5 s complete (sign last word at about 17.7, film ends 20.0).

## 6. Captions
- Word-synced, from words.json. The whole line is laid out at its final wrap from the start (no reflow); each word goes opacity 0 -> 1 over 90 ms at its spoken start. Unspoken words are invisible, not dimmed.
- Position: caption zone only (x 108, top 128, width 820, <= 3 lines). No plate, no pill, no shadow; ink on the dark floor is 16:1.
- A line clears (200 ms fade) 0.25 s after its last word ends, or when the next line starts, whichever is first. Never two lines on screen.
- The caption zone never overlaps the rangoli (top tip y 344) or the lamps; builder asserts bounding boxes per line at every word.
- **L5 has no caption plate and no caption**: its words sync inside the end lockup. "Happy" and "Diwali" appear in the headline on their spoken starts; "from all of us at" word by word in the sign; the sign word "Yourider" appears on the start of the spoken "Your" (voice says "Your Rider").

## 7. Per-scene frames (times re-anchored to words.json by the builder)
**S1, L1 0.0-4.4 "Diwali comes on the darkest night of the month."** Frame 01.
Near-black floor, stone barely visible, unlit lamps as dark clay shapes on the step (veil 0.82 over each body). From 0.7 s the 49 dots arrive row by row from the top tip down, the hand speeding up; last dot about 4.3 s. Caption top-left. The authored moment: the grid completing on "month". Nothing else moves.

**S2, L2 4.6-8.4 "We draw a rangoli at the door, and light one lamp."**
On "draw": loop 1 starts; seven loops follow at 520 ms intervals (last loop ends about 8.6). On "rangoli": powder ring 0, then ring 1 (+0.25 s), ring 2 (+0.55 s). On "lamp": lamp 1 catches (catch curve), its halo and pool come up over 900 ms; its rim lights. The authored moment: the first flame catching; everything else in the frame is still.

**S3, L3 8.6-11.1 "Then the next one, from the first."**
On "first": a spark (7 px disc `#FFE3A3`, quadratic arc peaking 40 px above the wicks) carries from flame 1 to wick 2 (420 ms), lamp 2 catches; then lamps 3, 4, 5 at +0.33, +0.57, +0.75 s from lamp 2's catch, carries 300/220/160 ms. Each pool adds to the floor light. Lamp 1 does not change.

**S4, L4 11.4-14.3 "A flame gives its light, and loses nothing."** Frame 02.
On "gives": lightUp 0 -> 1 over 1.8 s: the veil lifts to 0.15, pools widen; the rangoli's powders come to full colour from the lamp side upward. Five flames, equal height. On "nothing": no new event; hold.

**Silence 14.3-15.4**: only drone and flames. At 14.35 the camera tilts down (world y -400, 1.1 s): the rangoli rises and is cropped by the top edge, the lamps settle at y 814, the step becomes the page.

**S5, L5 15.4-20.0 "Happy Diwali, from all of us at Yourider."** Frame 03.
Headline at (108, 880), words on their spoken starts, no movement other than the 90 ms opacity; sign below. Hold to 20.0 with flicker only. The bell (sound plan) on "Diwali".

## 8. Refused defaults (this project)
- Fireworks, glitter, bokeh, sparkles, lens flares, particle dust "magic".
- A script or "Devanagari-style" display face for "Happy Diwali"; gradient or gold-foil text.
- Centred headline over a soft gradient; an eyebrow label; a caption plate or pill.
- Emoji or icon-font diyas; stock photos; any video asset.
- A freehand-looking rangoli traced from a template, or a mandala generator: the pattern is the constructed sikku kolam and nothing is added to it (no petal ring, no outer border).
- Moon, stars or sky: it is the new-moon night, the darkness is the point.
- Fade-up-20-px entrances on text; everything appearing at once; any bounce or overshoot.
- Lamp 1 dimming or shrinking when it lights the next one.
- Any mention of the product or what Yourider does. The film says nothing about the company except its name in the sign.

## 9. Rights
No new material. Font: Schibsted Grotesk (OFL), already recorded for the repo. Rangoli, lamps, flames, textures: generated in code in this repo. Sounds: per PLAN.md, recorded by the builder in rights.md.

## 10. Open items for the director
- **Cover frame**: LEARNINGS says frame 0 must show the headline and brand. This film opens on darkness by design. Proposal: set the post's cover/thumbnail to the 17 s lockup frame (both LinkedIn and Instagram allow a custom cover). If a custom cover is not possible on the target platform, the director decides whether frame 0 may stay dark.
- Word times in this file and in the style frames are estimates; the builder anchors every event to words.json and re-checks the caption/rangoli clearance at every word.
