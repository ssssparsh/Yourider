# linkedin-intro: plan

30.0 s Yourider introduction for the LinkedIn feed. 1080x1350 (4:5), 30 fps, one HyperFrames (GSAP) composition, 2D
only. Audience: founders and sales leaders scrolling with the sound off. Status: plan only, nothing rendered.

## 1. Subject inventory (what belongs to Yourider and no competitor)

1. **The name.** "Your" + "rider": the one who rides along with you; a deal that rides a pipeline. (Also a contract
   rider, the clause attached to a deal; not used on screen, too clever for 30 s.)
2. **The build target, verbatim:** "CRM MVP: Leads, Pipelines, Deals". Three nouns, nothing more.
3. **AI chat agents on top**, modular and multi-agent (several agents, one chat surface).
4. **It is being built now.** No UI, no customers, no metrics. The honest status is itself the material.
5. **A domain-agnostic engine underneath**, CRM first. (True, but not said in this film: one subject only.)
6. **The licensed handshake cut-out** already in our first collage film ("every deal ends with a handshake"):
   continuity with what Yourider has published.
7. **The deal route** vocabulary of our earlier films (route, stages, Closed Won), which is why `heard_as` maps
   "root" to "route".
8. **Printed things of the sales world:** the index card a lead is written on, the stage bar, the proof sheet a
   printer pulls before the run.
9. **No numbers exist.** Every figure slot in the dealt direction stays empty or becomes a word.

Idea sentence (direction step 1): *In this film, Yourider's three-noun build target and its "being built now"
status become a two-colour proof print: a lead card rides the pipeline bar, the name slams on and snaps into
register, and the handshake prints in strip by strip.* Competitor test: "HubSpot's status becomes a proof print
that is still being registered" does not work for a shipped product; the "rider" riding the bar only works for this
name.

## 2. Art direction (taste-skill)

Drawn with `draw.mjs --sector saas --sections intro,how-it-works,features,cta --options 3`
(dealt: `editorial-report`, `dense-tiles`, `product-performs`). Full sheet: `media/.build/linkedin-intro/taste/direction.json`
(seed 952702228).

- **Chosen: `editorial-report`, "The printed annual".** A two-colour print job in solid blocks is the same medium
  as the gbro paper collage (halftone, cardstock, one accent), and "a proof sheet still being registered" carries
  item 4 honestly.
- Rejected: `product-performs` needs a working product fragment; there is no UI and we must not fake one (Q1).
  `dense-tiles` (a board of tiles) would read as a kanban screenshot we do not have.
- **Palette (record of the deal, "Bottle ink, yellow"):** ground `#f7f7f7` (paper grey, with fibre grain from
  `paper.py`), cardstock `#ebebeb` (`--surface`), ink `#0d2a1c` (bottle green; all type, never black), muted
  `#5f6b64`, accent `#f6e016` (yellow; one object per frame, and one whole page turns yellow in S5). Colour pages:
  yellow `#f6e016` (S5) and inverted bottle green `#0d2a1c` (S7 CTA, paper-coloured type).
  Die-cut keyline on cut paper: gbro cream `#FCF8ED` at 2 px (a print edge, not a palette colour).
- **Type: Schibsted Grotesk.** Display 800, tracking -0.05em, leading 0.88, sentence case. Captions and small text
  600, tracking -0.01em. Sizes on this 1080 x 1350 frame: headline 112 px, giant wordmark 220 px, card labels
  64 px, captions 60 px, small lines 40 px (nothing that must be read below 40 px; Q11).
  Font file is not installed yet: see Open items.
- **Composition:** a vertical axis at 42% of the width is replaced, for a portrait frame, by an axis at 96 px
  (left margin) for headlines and 454 px (42%) for small side lines; all headlines two lines, flush left on the
  margin. Masthead band = top 45% (0-608 px) in S1. Captions live in the bottom band y 1110-1290; information
  stays at y <= 1060.
- **Direction motion:** "Masked headline": each headline line rises from behind its own baseline, 0.9 s, strong
  ease-out, second line +0.11 s. Used for every headline change; it is the film's typographic signature.
- **Collage rules kept:** flat paper field (no gradients), cardstock cut-outs with the cream keyline and hand rotation
  of 0.3-1.6 degrees, one accent per frame, halftone on the only photograph (the handshake), one paper shadow
  direction (down-right, soft). Paper moves are stop-motion on a 10 fps grid (see R2 for how this squares with
  acceleration).
- **Deviation from the sheet, on purpose:** the "Stages as one bar" blueprint sizes segments by true stage durations
  and labels them with durations. We have no durations, so the four segments are equal and unlabelled except
  "Lead" under the first and "Deal" under the last (no invented data). The direction's photograph floor and picsum
  atmosphere photos do not apply to a video with one licensed picture; we use none of them.

## 3. Story

- **Logline:** Every deal starts as a lead and rides a pipeline; Yourider is the CRM being built for that ride, with
  AI agents you work with in chat.
- **Setup (0-6.6 s):** a lead card is dealt onto the page and rides the pipeline bar, stage by stage.
- **Turn (6.6-15.2 s):** it stalls ("keeping it moving is the hard part"), a beat of true silence, then the name
  Yourider slams on as a misregistered two-plate print and snaps into register; Leads, Pipelines, Deals are dealt
  under it.
- **Ending (15.2-30 s):** AI agents dealt as slips on a yellow page; the handshake prints in strip by strip
  ("being built right now"); the page inverts to the CTA "Follow along"; the wordmark locks up and holds 3.4 s.

## 4. Benchmark

- **Our own `collage-handshake` (6.8 s):** keep its word-synced caption plate, the stamp landing on a spoken word,
  the halftone handshake. Do not copy its red field or "Closed Won" stamp (would claim an outcome).
- **The direction's references** (`aww-ai-in-design-report-2026`, `opl-applied-imagination`): learn the colour
  blocks and fixed column line of a print annual, and halftone as atmosphere. Copy nothing of theirs (names, copy,
  images).
- **LinkedIn muted autoplay:** learn from feed kinetic-type posts that the headline must be readable in the first
  second with no sound; do not copy anyone's footage or music.

## 5. Narration (Kokoro `am_michael`, 56 words, ~2.6 w/s budget)

| id | start | say | est. end | gap to next |
|---|---|---|---|---|
| L1 | 0.50 | Every deal starts as a lead. (6) | 2.8 | 0.4 |
| L2 | 3.20 | Then it rides a pipeline, stage by stage. (8) | 6.3 | 0.4 |
| L3 | 6.70 | Keeping it moving is the hard part. (7) | 9.4 | **1.2 s silence** |
| L4 | 10.60 | Your Rider is a CRM built around leads, pipelines and deals. (11) | 14.8 | 0.5 |
| L5 | 15.30 | And on top, AI agents you work with in chat. (10) | 19.1 | 0.5 |
| L6 | 19.60 | We're building it right now, piece by piece. (8) | 22.7 | 0.4 |
| L7 | 23.10 | Follow along as it comes together. (6) | 25.4 | tail 4.6 s |

Every claim maps to the brief: a CRM for leads, pipelines, deals; AI chat agents on top; being built now; a soft
follow-along. No numbers, customers, integrations or URLs. If Kokoro runs longer than 2.6 w/s, `voice.py` will say
which start to move; move the later line and the shots anchored to it, never shorten the gaps below 0.3 s.

## 6. Shot list (one HyperFrames composition; all times in seconds)

Anchors written as `word+offset` follow `words.json` (the visual and its sound both key off the spoken word).

| # | time | card adapted (2D) | framing / composition | motion and camera | why |
|---|---|---|---|---|---|
| S1 hook | 0.00-3.00 | `typography/paper-title-card.md` (letterpress-in, one accent per line) + direction "Masked headline" | Frame 0 is not empty: bottle-green masthead block over the top 608 px with halftone dot texture, crop marks at the four corners. Headline below it on the left margin, ink: "Every deal / starts as a lead." | 0.10 line 1 rises from its baseline (0.9 s, power4.out), line 2 at +0.11; settled 1.11. A cardstock card "Lead" (380x230, `#ebebeb`, keyline, -1.2 deg, small yellow tab = the frame's accent) is dealt onto the masthead from top right, 3 stepped frames, landing at `lead+0.00`. Static camera. | Hook readable muted by 1.1 s; the card lands before 2.5 s. |
| S2 ride | 3.00-6.60 | `ui-entrance/draw-svg-trace.md` (pen nib drawing a line, closure darken; crop marks preface reused in S1) | Masthead lifts out of frame (steps(4)). Headline swaps: "It rides / a pipeline." The bar: 960 x 120 px at y 760, drawn as one ink outline, then filled as four equal segments with 6 px gaps; "Lead" under the first, "Deal" under the last (40 px, muted). | Pen draw starts at `pipeline-0.05`, 48 frames (one notch slower than the card's 40), inOut cubic, visible nib; 2-frame darken on closure. The Lead card shrinks to 0.45 and sits on segment 1, then steps to segment 2 at `stage+0.00` and segment 3 at `stage+0.45` (stepped 3-frame hops, the second hop shorter). | "rides" made literal: the rider. |
| S3 stall | 6.60-10.60 | none (a hold) | Headline swaps: "Keeping it moving / is the hard part." Bar and card unchanged. | At `hard+0.00` the card nudges 24 px toward segment 4 and slips back (2 stepped frames each way). 9.4-10.3: nothing moves, no sound. 10.30-10.60: anticipation, the card pulls back 48 px (amplitude from deck-deal's "must pass the eye threshold" rule), silent. | Real silence before the peak; the stall is the problem statement without a claim about competitors. |
| S4 turn | 10.60-15.20 | `effects/riso-print-hits.md` (misregistration hit, single shot) + `ui-entrance/deck-deal-flyin.md` (dealing with uneven intervals, landing press) | Bar and card drop out of frame (steps(3)). Giant "Yourider" 220 px across the width at y 300-520. Under it "A CRM built around" (40 px, muted) and three cardstock tags dealt into one row: "Leads" "Pipelines" "Deals" (64 px). | Slam: 8-frame ease-in from below, lands at `Yourider+0.00`; same frame splits into two plates, bottle green and yellow, `mix-blend-mode: multiply`, opposite offsets A=(22,9) px, envelope A*cos(2*pi*t/18f)*exp(-t/60f); hard snap to register at `Yourider+1.47` with a 4-frame scale pulse 1.03 -> 1 and a 1.2% whole-page nudge over 10 frames (**whole-frame impact 1 of 1**). Tags land on their spoken words (`leads`, `pipelines`, `deals`), each with an 8-frame flight, small overshoot settle and 0.996 press; intervals follow speech, so they are uneven. Hold from the "Deals" landing to 15.2. | The turn: name + the three nouns, the film's peak and the only impact. |
| S5 agents | 15.20-19.40 | `ui-entrance/deck-deal-flyin.md` (pile, anticipation press, hard-accelerating deal) + `typography/typewriter-moves.md` (character-locked typing, cursor states) | A yellow sheet pushes up from the bottom (steps(4)) and the whole page turns yellow (the direction's one yellow page; on this page the accent role passes to bottle-green cardstock). "Yourider" demotes to a 64 px label top-left. Headline: "AI agents / on top." Right column: a stack of four bottle-green slips; the top slip is paper-coloured and holds one typed line. | At `agents+0.00` the slip pile presses down 48 px, the top slip pulls back 30 px (anticipation), then four slips are dealt with intervals 0.36, 0.22, 0.12 s and settle in a fanned stack (rotations -1.4, 0.6, -0.4, 1.1 deg). Typing on the top slip from `agents+0.90`: "AI agents, in chat." at 2.5 frames per character (one notch slower than the card's 2), fixed-width span per character, cursor solid while typing, blinks twice, then removed. Hold >= 1.2 s to 19.4. | Multi-agent shown as a dealt hand, the claim typed out verbatim: no invented capability. |
| S6 building | 19.40-23.00 | `typography/marker-underline-title.md` (one marker stroke under one word) + draw-svg-trace's crop-mark preface | Yellow sheet pulled away upward; paper ground; crop marks at the corners again (proof sheet). Headline: "Being built / right now." Handshake halftone (licensed cut-out, `halftone.py`) on a cardstock panel, 900 px wide, y 520-1040. | Headline rises 19.6. Yellow marker stroke under "now" drawn in 12 frames, rising left-to-right, 6 frames after the headline settles. From `building+0.00` the handshake prints in six horizontal strips bottom to top with intervals 0.50, 0.42, 0.36, 0.30, 0.26 s (accelerating), each strip a 2-frame step; complete at `piece+0.2` (stretch the five intervals proportionally if the voice puts "piece" elsewhere). Hold >= 1 s. | "piece by piece" made literal; honest about status. |
| S7 CTA | 23.00-25.80 | none from shotcraft; the direction's "cta: the idea again, inverted" | Field inverts to bottle green by a paper wipe from the top (steps(4)); type turns paper-coloured. Headline: "Follow along / as it comes together." Handshake panel shrinks to the top right (stepped). One yellow rectangle (the accent) bottom right, 56 px tall, blank. | Headline rises at 23.15; hold 24.2-25.8 (1.6 s). | Soft call to action, no URL. |
| S8 lockup | 25.80-30.00 | `outro/logo-shrink-wordmark-lockup.md` | The yellow rectangle grows to fill the frame centre and collapses into a 120 px yellow square; the square slides left; "Yourider" (800, 150 px, paper `#f7f7f7` on the bottle-green field) letters slide in; sub-line at 40 px: "A CRM for leads, pipelines and deals. Coming soon." | Collapse 25.8-26.25 with +6% overshoot brake (element level, not whole frame); slide-left 26.25-26.45; 8 letters at 0.035 s stagger, 8 px slide, 0.3 s each, settled by 26.85; sub-line fades in 27.10-27.40. **Wordmark held still 26.85-30.00 = 3.15 s** (>= 1.5 s). | End on the wordmark. |

Captions (all shots): the word-synced plate from `collage-handshake/gen.py`, re-coloured: plate `#ebebeb` with the
cream keyline, words `#0d2a1c` at 0.38 opacity, each spoken word at full opacity with a yellow highlighter block
behind it; 60 px, 600 weight, max two lines, centred in the bottom band. On the yellow page the highlighter turns
bottle green with paper text; on the green page the plate is paper and the highlighter yellow. No caption in the
lockup tail (C1: the brand close stays clean).

## 7. Shotcraft aesthetic rules: how each is met

- **R1 hold >= 1 s:** S1 headline still 1.11-3.0; S2 bar complete ~4.9-6.6; S3 still 7.6-10.3; S4 "Deals" tag lands
  ~14.4, hold to 15.2 (0.8 s) but the wordmark itself is still from 12.1 to 15.2 (3.1 s); S5 typing done ~18.1, hold
  to 19.4; S6 handshake complete ~22.0, hold to 23.0; S7 hold 24.2-25.8; wordmark 26.85-30.0.
- **R2 acceleration, uneven stagger, no linear moves:** headlines on power4.out; paper moves are stop-motion
  (gbro) but each one samples an ease on the 10 fps grid instead of linear steps: builder uses
  `ease: p => Math.round(gsap.parseEase("power3.out")(p) * n) / n`. Group entrances accelerate: slips 0.36/0.22/0.12 s,
  print strips 0.50 -> 0.26 s, stage hops 0.45 then shorter; tags follow speech. Every group ends in a still.
- **R3 one notch slower:** pen draw 48 f (card 40), typing 2.5 f/char (card 2), marker 12 f (card 10), headline rises
  0.9 s; hero arc (the lead card's ride, 3.0-10.6) is 7.6 s; the turn arc 10.6-15.2 is 4.6 s.
- **R4 <= 3 whole-frame impacts:** one (the riso register snap, 1.2% page nudge at `Yourider+1.47`). The field colour
  changes at 15.2, 19.4 and 23.0 are paper wipes (transitions), not scale/shake impacts; the lockup brake is element
  level.
- Also: Q1 no faked product UI (cards carry words only, no fake fields or buttons); Q5 one subject per opening (the
  Lead card); Q11 readable sizes listed in section 2; S2 every cue below is tied to a named action.

## 8. Sound plan (no music)

- **Effects** only from `$MEDIA_TOOLS/gbro-collage-info/assets/sfx` (click, flip, focus, grow, pop-land, pop-soft,
  reveal, tick, whoosh-in, whoosh-soft); 25 cues in `script.json`, all <= 0.5 gain, >= 0.25 s apart, anchored to the
  spoken word where they land on one. `mix.py` adds its quiet paper room tone under everything.
- **Silence:** 9.4-10.6 s, no voice and no effect (room tone only), right before the slam. The cue list has nothing
  between `hard` (~8.5) and the whoosh-in at `Yourider-0.27`; if L3 runs long the gap only shrinks, so QA must confirm
  >= 0.8 s of real silence there.
- **Tail:** after the lockup reveal (~26.25) only the sub-line pop; 27.5-30.0 is room tone, so the loop restarts clean.
- **Music bed: follow-up.** No licensed music file exists. Options for a later pass: synthesise a soft bed with
  Lemo `core/audio` as `one-map` did (our own composition), or license one track; either goes into `rights.md` first.
  This plan stands on its own without it.

## 9. Engine per shot

All eight shots: **HyperFrames 0.9.8 + GSAP 3.15**, one composition `index.html` at 1080x1350, 30 fps, 30.0 s
(no Remotion, no Blender, no WebGL; no GPU on this machine). The shotcraft cards are Remotion demos; the builder reads
each named demo for its numbers and re-implements them as GSAP tweens at absolute times:

| card file | demo the builder reads | what is adapted |
|---|---|---|
| `typography/paper-title-card.md` | `demos/typography/paper-title-card/PaperTitleCard.tsx` | one-sentence title card rhythm, exactly one accent per frame, held ~1.8 s+ |
| `ui-entrance/draw-svg-trace.md` | `demos/ui-entrance/draw-svg-trace/DrawSvgTrace.tsx` | `pathLength=1` dash draw, three-dash pen nib, closure darken, crop-mark preface |
| `effects/riso-print-hits.md` | `demos/effects/riso-print-hits/RisoMisregistrationHit.tsx` | two multiply plates, decaying cos offset, hard snap to register, 1.2% page nudge (no "ON REGISTER" stamp) |
| `ui-entrance/deck-deal-flyin.md` | `demos/ui-entrance/deck-deal-flyin/DeckDealFlyin.tsx` | 2D only: anticipation press, hard-accelerating deal intervals, 8 f flight + settle + press; no orbit, no 3D camera |
| `typography/typewriter-moves.md` | `demos/typography/typewriter-moves/TypewriterErrorRetype.tsx` | frame-locked characters, fixed-width spans, cursor states; **not** the error-retype act (a retype would need a false "before" claim) |
| `typography/marker-underline-title.md` | `demos/typography/marker-underline-title/MarkerUnderlineTitle.tsx` | one rising variable-width marker stroke with dry-brush filter, in yellow |
| `outro/logo-shrink-wordmark-lockup.md` | `demos/outro/logo-shrink-wordmark-lockup/LogoShrinkWordmarkLockup.tsx` | collapse with +6% brake, make room, letter stagger, sub-line fade; a yellow square stands in for the icon (no logo is invented) |

Builder inputs: `halftone.py` on the handshake cut-out; `paper.py` for the field and cardstock (see Open items);
`mix.py`; `voice.py`; captions pattern from `media/projects/collage-handshake/gen.py`.

## 10. Open items (not decided here)

1. **Font:** Schibsted Grotesk (SIL OFL) is not installed. Getting it means a new npm package
   (`@fontsource/schibsted-grotesk`), which needs the user's go-ahead under CLAUDE.md, plus a `rights.md` entry.
   Fallback if not approved: Inter (already licensed) at 800, tracking -0.04em; the plan works with either.
2. **`paper.py`** is hard-wired to 1920x1080, a red field and cream cards. The builder needs a size and colour option
   (1080x1350, `#f7f7f7`, `#ebebeb`, `#f6e016`, `#0d2a1c`); that edit touches a shared pipeline file and should be
   flagged before it is made.
3. **Music bed:** follow-up (section 8).
4. **Copy sign-off:** "AI agents you work with in chat" and "piece by piece" are the plan's wording of the brief's
   facts; the user may want to approve them before a public post.
