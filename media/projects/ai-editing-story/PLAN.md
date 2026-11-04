# ai-editing-story: plan

"How I edit video with Claude". 40.0 s, 1080x1350 (4:5, LinkedIn feed), 30 fps, one HyperFrames (GSAP) composition,
2D only. Posted by the user about their own workflow, so the narrator is the user ("I"). Muted autoplay: the
on-screen text carries the story on its own. Status: plan only, nothing rendered.

Source of truth for every word on screen or in the voice: `FACTS.md` in this folder. Nothing else is claimed.

## 1. Subject inventory (what belongs to this story and to nobody else)

1. **The user's own requests, verbatim** (FACTS): "Make a 30 second Yourider intro video for LinkedIn, and do check
   completely." / "Currently the designs are not better." / "Can you make a video in which the audio goes along with
   the lines rendered in the video?" / "Create an automation for images and videos."
2. **The team of three agents:** director (plans story, script, shots), builder (renders), QA (checks every frame and
   rule, never edits).
3. **The pipeline chain:** narration -> word timings -> composition -> mix -> render -> automated checks.
4. **The real QA contact sheet** (`evidence/qa-contact-sheet.jpg`): frames pulled at the spoken words.
5. **The first QA review of the intro found 8 problems; the builder fixed all 8; the second review said SHIP.**
6. **Word-synced captions**: every caption word timed to the voice by Whisper; the highlighted word is visible in the
   real stills (`li-slam.png`, `li-agents.png`, `map-route.png`).
7. **Three real films of ours:** the transit map ("One Map"), the paper collage, the LinkedIn intro.
8. **The human's calls:** the user chose the direction, rejected paid tools, approves the wording before posting.
9. **Notes in plain words** instead of keyframes ("Currently the designs are not better.").
10. QA caught "Automated" on a One Map label (true, but a second story; not used: one subject).
11. 55 words / 126 s build, -14 LUFS (true; not used: numbers on a "how editing changed" post invite a time-saved
    reading, which FACTS forbids, and loudness is meaningless on a muted feed).

**Idea sentence:** *In this film, the user's own typed sentences become the product fragment: one prompt field, the
same one all film, that sends back a real frame, is checked by an agent, takes the user's notes, and finally turns into
the end card.* Competitor test: put any other editor in the sentence and it fails, because the prompts, the eight QA
findings and the frames are this repo's. The one live thing the viewer watches: a sentence being typed and something
real coming back.

## 2. Art direction (taste-skill)

Drawn with `draw.mjs --sector ai-product --brief "A founder shows how he now edits video by typing sentences to Claude:
a director, builder and QA agent plan, render and check real films" --sections intro,how-it-works,proof,showcase,cta
--have video,product-ui --options` (dealt: `one-motif`, `borrowed-category`, `product-performs`), then dealt in full with
`--direction product-performs`. Sheet: `media/.build/ai-editing-story/taste/direction.json` (seed 143353812).

- **Chosen: `product-performs`, "The product performs".** "Show the product doing its job in front of you, small true
  fragments at real size" is exactly "a typed prompt turns into a real frame". Here it is honest, because the outputs
  exist (FACTS evidence stills); the LinkedIn intro had to reject this same direction because it had no product to show.
- Rejected: `one-motif` (one shape running the system; the frame rectangle would work but says nothing about agents or
  checking); `borrowed-category` (dressing this up as another category hides the real outputs, the point of the post).
- **Palette (sheet "Cool grey, cobalt"):** ground `#eef0f3`, surface `#e2e5ea` (fields, rows, caption plate), ink
  `#0b0c0e` (all type), muted `#5d6470`, accent cobalt `#1f2de6` with white type `#ffffff`. Cobalt is the send key
  and one object per frame; it takes **one whole page** (S5, "Ship.") and returns at the end **as a single block**
  (S8), exactly the sheet's colour story. No gradients, no shadows at rest (one soft shadow only under a dealt card
  while it is in the air), no paper grain: these are clean interface fragments, not print.
- **Type: Switzer is dealt; we use Inter** (already licensed, `media/.tools/web/Inter.woff2`). Switzer comes from the
  Fontshare CDN under the ITF Free Font License: a new download and a new licence entry for no gain; Inter is the
  nearest licensed neo-grotesk. Set by the sheet's rules: display 600, tracking -0.04em, leading 0.95, sentence case,
  no capitals, no monospace, one face only. Sizes on 1080x1350: headline 88 px, end-card line 104 px, "Ship." 240 px,
  row names 56 px, captions 60 px (500), row text / tags / typed text 44 px, smallest text 40 px (Q11 and the brief's
  40 px floor).
- **Composition:** one left axis at x = 96 px, right margin 96 px (measure 888 px). Headlines top-left from y 96,
  two lines at most. Fragments (prompt field, agent rows, findings list) are cropped interface pieces at true size, flat
  on the ground, 1 px borders and 10 px radius inside them only (`data-ui` rule). Caption band y 1130-1290; information
  stays at y <= 1090 wherever a caption plate shows.
- **Direction motion: "Masked headline":** each headline line rises from behind its own baseline, 0.9 s, power4.out,
  second line +0.11 s. Same signature as the LinkedIn intro on purpose: that is the family resemblance.
- **Related to, distinct from the LinkedIn intro:** same 4:5 frame, same left-axis grid, same masked headline and
  word-synced caption plate. Different everything else: cool grey and cobalt instead of bottle green and yellow, Inter
  instead of Schibsted Grotesk, clean UI fragments instead of torn cardstock and halftone, real frames as the pictures.
  The intro's own frames appear inside this film as evidence, which reads as "sequel", not "copy".
- **Deviations from the sheet, on purpose:** the "proof: one quiet logo row" section is replaced by the QA contact
  sheet (FACTS forbids other logos; the proof we have is a QA sheet). The sheet's picsum atmosphere photos are not used:
  our pictures are our own renders. The CTA "dialog already open" becomes the prompt field that turns into the end card.

## 3. Story

- **Logline:** I used to move keyframes by hand; now I type a sentence, three agents plan, render and check the video,
  and I still make the calls.
- **Setup (0-8.7 s):** a typed prompt sends back a real frame (hook), then the old way: keyframes nudged by hand.
- **Turn (8.7-26.4 s):** a slider wipes the keyframes away; the sentence goes to a director, a builder and a reviewer;
  the first review finds eight problems, all fixed; a beat of silence; "Ship."
- **Ending (27.4-40 s):** the real results; my notes are plain words, I still make the calls; the prompt field becomes
  the end card "Edited with Claude." held 1.95 s.

## 4. Benchmark

- **Our own `linkedin-intro`:** learn its headline-on-frame-0 cover, word sync inside the headline, caption pages that
  never overlap, sounds anchored to words (all lessons from its first QA review). Do not copy its paper, palette, riso
  slam or wordmark lockup.
- **The direction's references** (`opl-berd`: type the headline into an empty window; `opl-dabbit`: the tool proves
  itself on the page): learn "open on the premise being performed". Copy nothing of theirs.
- **AI-product launch films** (the before/after slider is their grammar): learn the fast-throw / slow-sweep rhythm.
  Not copied: no comparison to any named editor, no "x times faster", no logos (FACTS).

## 5. Narration (Kokoro `am_michael`, 79 spoken words, ~2.6 w/s budget)

| id | start | say (show identical unless noted) | words | est. end | gap |
|---|---|---|---|---|---|
| L1 | 0.30 | I asked Claude for a LinkedIn intro. One sentence. | 9 | 3.9 | 0.4 |
| L2 | 4.30 | Editing used to mean key frames by hand, checked by eye. (show: "keyframes") | 10 | 8.3 | 0.4 |
| L3 | 8.70 | Now I describe it. A director plans, a builder renders, and a reviewer checks every frame. | 16 | 15.25 | 0.35 |
| L4 | 15.60 | The first review found eight problems. | 6 | 17.9 | 0.35 |
| L5 | 18.25 | Overlapping captions. Text too small for a phone. | 8 | 21.6 | 0.35 |
| L6 | 21.95 | The builder fixed all eight. | 5 | 23.85 | **1.2 s silence** |
| L7 | 25.05 | Second review: ship. | 3 | 26.35 | 1.05 |
| L8 | 27.40 | Every caption word lands on the voice. | 7 | 30.1 | 0.4 |
| L9 | 30.50 | My notes are plain words. And I still make the calls. | 11 | 35.0 | 1.6 |
| L10 | 36.60 | Edited with Claude. | 3 | 37.8 | tail 2.2 |

Every line maps to FACTS: the user's LinkedIn request (L1); the "before" framing (L2); the three agents (L3: "reviewer"
is spoken because Kokoro/Whisper handle "QA" badly; the screen says QA); the first review's 8 problems, two of them
named verbatim (L4-L5); all 8 fixed, second review SHIP (L6-L7); Whisper-timed captions (L8); notes in plain words and
the human decides (L9). No percentages, no savings, no other editors, no industry claims.
"key frames" is spoken as two words because Whisper writes it that way; `show` joins them ("keyframes").
If Kokoro runs long, `voice.py` names the start to move: move the later line and the shots anchored to it, never cut a
gap below 0.3 s, and keep >= 0.8 s of the L6-L7 silence.

## 6. Shot list (one HyperFrames composition; times in seconds, estimates; the builder computes every anchored time from `words.json`)

`word+offset` = anchored to the spoken word's start in `words.json` (first occurrence; all anchor words below are
unique in the script).

| # | time | card adapted (2D) | framing / composition | motion | why |
|---|---|---|---|---|---|
| S1 hook | 0.00-4.30 | `typography/typewriter-moves.md` (frame-locked characters, fixed-width spans, cursor states; **not** the error-retype act) + `ui-entrance/deck-deal-flyin.md` (8 f flight with arc, overshoot settle, press) | **Frame 0 is the cover:** headline "How I edit video / with Claude." (88 px, ink, axis 96, y 96-290). Prompt field (`data-ui`: surface `#e2e5ea`, 1 px ink border at 15%, radius 10, 888x220 at y 330-550), typed text 44 px ink, already showing "Make a 30 second Yourider intro video for LinkedIn, and do check" with a solid cursor; a 64 px cobalt send key in its bottom-right corner (the frame's accent). | 0.10-0.90 types " completely." at 2 f/char (character-locked, no easing). Cursor blinks twice (4 f half-periods) 0.90-1.10. 1.10 send key presses (scale 0.84, 4 f). The real frame **`li-hook.png`** (520x650, x 464-984, y 600-1250, rotation -1.2 deg) flies out of the send key: 8 f flight (bezier .3,0,.2,1, scale 0.25 -> 1.06 peak -> 1, small upward arc), 4 f overshoot settle, 0.996 press; lands 1.43, still by 1.6. Hold to 4.3. No caption plate (headline + prompt carry the meaning; the voice repeats it). | A real typed prompt turns into a real frame inside 1.6 s: the hook and the film's thesis at once. |
| S2 old way | 4.30-8.70 | none for the diagram; the direction's masked headline | Prompt field and frame leave downward (10 f, power3.in). Headline: "Editing used to be / keyframes by hand." A plain keyframe track (diagram, not any app's interface): 888 px ink line 6 px at y 640, eight outline diamonds (32 px, 3 px ink), one filled cobalt; a vertical ink playhead 4 px. Caption plate on. | Headline rises at 4.35. At `keyframes+0.20` an ink arrow pointer grabs the cobalt diamond and drags it 40 px left (0.9 s, power2.inOut), then back 24 px (0.7 s); at `eye+0.00` the playhead scrubs right 300 px and back 180 px (1.0 s + 0.8 s, sine.inOut). Still 7.6-8.7. | The "before" from FACTS, shown as a generic diagram (no other editor's UI, no logos). Slow, fiddly motion = "by hand". |
| S3 now | 8.70-15.60 | `data/before-after-slider-scrub.md` (fast throw, rebound, pause, slow sweep) + `ui-entrance/deck-deal-flyin.md` (2D: one paragraph-level anticipation, 8 f flight, settle, press) | Before layer = S2 frame. After layer (same layout and axis): headline "Now I describe it." (one line), the prompt field again at y 330-550 holding the full S1 sentence (cursor off), and below it the board: three rows (`data-ui`, 888x132, surface, 8 px gaps, radius 10, y 600-1010): name 56 px ink left; one line 40 px muted under it: **Director** "story, script, shots" / **Builder** "voice, word timings, picture, mix" / **QA** "every frame, every rule. Never edits." Right end of each row: a status block 40 px ("plans" / "renders" / "checks"); only the active row's block is cobalt, earlier ones turn ink. | Divider: 6 px cobalt bar with a 56 px handle. Anchored to `Now`: rests at 8% (0-4 f), anticipation pull to 6.5%, **throw 8% -> 76% in 12 f** (power3.out) at `Now+0.00`, rebound to 70% in 10 f, pause 12 f, **slow sweep 70% -> 100% in 30 f** (sine.inOut); handle scaleX stretch up to 1.18 from velocity. After layer clip-path follows the bar exactly. Board: the three rows wait as a pile off the right edge; at `director-0.33` the pile presses 48 px and the top row pulls back 30 px (anticipation, the card's measured amplitude); rows land on `director`, `builder`, `reviewer` (speech-spaced, so uneven), each 8 f flight + 4 f settle + press. Status word of row 3 turns cobalt at `frame+0.00`. Board still ~12.9-15.6. | The turn from method to method, in one wipe. Three agents shown as true, labelled rows, no invented features. |
| S4 QA | 15.60-25.05 | `ui-entrance/list-reveal.md` (staggered scale-into-place, soft overshoot; drift eased, not linear) + deck-deal's accelerating cadence for the ticks | Board leaves upward (10 f, power3.in). Headline "First review: / 8 problems." Findings list (`data-ui`, 7 rows 888x84, 8 px gaps, y 330-970), text 44 px ink, verbatim from FACTS: "Overlapping captions" / "Brand not named until 10.6 s" / "Empty first frame" / "Headline and caption duplicated" / "Three transition overlaps" / "A row held under 1 s" / "Text too small for a phone". A 44 px check square at each row's left (empty outline). | Headline rises at `first+0.00`. Rows reveal from `problems+0.00` at **12 f stagger** (card's 10 f, one notch slower), 26 f window, scale 0.82 -> 1, y 44 -> 0, blur 8 -> 0, soft back overshoot ~1.5%; container drifts 40 px up over the reveal with sine.inOut (not the card's linear drift: R2). At `Overlapping+0.00` and `small+0.00` an ink marker block slides behind that row's text (white text), 6 f each, the first released when the second lands. At `fixed+0.10` checks fill cobalt top to bottom with **hard-accelerating intervals 0.32, 0.24, 0.18, 0.13, 0.10, 0.08 s**; each checked row's text turns muted; with the last check a counter "8 of 8 fixed" (56 px ink) rises at top right. **Then nothing moves 23.5-25.05** (the silence). | The proof that the agents check each other, from the real review. The ticks are the deck-deal metaphor applied to a checklist. |
| S5 ship | 25.05-27.35 | `effects/slam-entrance-moves.md` B "score-slam" (hover, ease-in drop, single ring, short shake; no sparks or gold) | At `Second+0.00` a cobalt field wipes up from the bottom (10 f, power3.inOut): **the direction's one cobalt page**. "Second review" 56 px white top-left at y 120. "Ship." 240 px white on the axis, y 260-500. Then the **QA contact sheet** (`qa-contact-sheet.jpg`, 760x713, x 96-856, y 560-1273, 2 px white border) with a 40 px white label right of it: "QA contact sheet: frames at the spoken words". No caption plate after the slam (the word is the frame). | "Ship." hovers from `ship-0.30` at scale 2.6, 10 px blur, 0.5 opacity (9 f), drops with ease-in quad in 6 f to land on `ship+0.00` at 0.965, spring back to 1 (damping 14). Same frame: one white ring 120 -> 1100 px over 16 f (expansion out-cubic, fade linear), and a **12 px whole-frame shake decaying over 5 f (whole-frame impact 1 of 1)**. Sheet slides up 8 f from `ship+0.40`, settled ~26.4; hold to 27.35. | The payoff after the silence: the reviewer, not the narrator, decides it ships. |
| S6 results | 27.35-30.50 | `ui-entrance/card-stack.md` (spring in from below with EASE.out stagger, stack weight dip, anticipation tighten, one fan spring, centre card drawn) | Cobalt page lifts away upward (10 f). Ground grey. Headline "Every caption word / lands on the voice." Five real stills as cards 440x550, 2 px ink border at 10%, centred x 540, y 470-1020: k = -2 `collage.png` (crop x 800-1664), -1 `map-whole.png` (crop x 280-1144), 0 `li-slam.png` (full), +1 `map-drop.png` (crop x 820-1684), +2 `li-agents.png` (full). | Cards spring up from y +820 (damping 13, stiffness 150) with EASE.out stagger over 30 f from 27.45 (gaps shrink: accelerating), +-6 deg alternating tilt in flight; stack dips 5 px per landing. Anticipation: stack tightens 2% at `word+0.00`; fan at `word+0.20`: one spring (damping 20, stiffness 95), rot k*6 deg, tx k*118 px, origin 50% 130%. At `voice+0.00` the centre card (li-slam, its real caption with the highlighted word "is") is drawn up 72 px and to scale 1.18 with a 3 px cobalt outline (no glint, Q4). Hold ~29.4-30.5. | Real outputs only (Q1). The centre card visibly shows a word highlighted in time with speech, which is what L8 says. |
| S7 my calls | 30.50-35.60 | `typography/typewriter-moves.md` (straight typing, 2 f/char, cursor states) + deck-deal 2D for the three tags | The prompt field returns at y 330-550 (empty, cursor blinking). Headline "My notes: / plain words." Field types the user's real note **"Currently the designs are not better."** (44 px). Then the headline swaps to "I still make / the calls." Three tags (`data-ui`, surface, 44 px ink, left-aligned on the axis, stacked y 640-940): "I chose the direction" / "No paid tools" / "I approve every word". | Headline rises 30.55. Typing from `My+0.20` at 2 f/char (38 chars, ~2.5 s), cursor solid while typing, blinks twice, stays (the field is sent in S8). Headline swap at `still+0.15` (masked rise). Tags dealt from the left at `still+1.00`, `+1.35`, `+1.60` (intervals 0.35, 0.25: accelerating), 8 f flight, settle, press. Hold ~34.6-35.6. | The human half of the workflow, from FACTS: plain-word notes (a real one), direction, no paid tools, approval. |
| S8 end card | 35.60-40.00 | `outro/ui-to-brand-morph.md` B "input-morph-assemble" (send press, text flies off accelerating, colour floods from the send key, five-quantity spring morph); no logo pieces are assembled (no logo is invented) | Headline and tags clear upward (8 f). The prompt field becomes a cobalt block 888x300 at y 520-820, radius 10. In it, white, 104 px, 600, two lines on the axis + 48 px padding: "Edited with / Claude." Under the block, 44 px muted: "Planned, rendered and checked by agents. / Approved by me." No caption plate (C1: the close stays clean). No other brand logo. | 35.60 send key pressed (scale 0.84, 4 f); typed note flies up-right with ease-in 11 f; cobalt floods the field from the send key (circle clip-path, 12 f, solid colour, no opacity fade) 35.75-36.15; one spring (damping 15, stiffness 95) drives x/y/w/h/radius from the field to the block 36.15-36.70. Letters rise from the baseline at 1 f stagger, 10 f each, scale 1.3 -> 1 with 8 -> 0 px blur, from 36.70 (L10 starts 36.60), settled ~37.65; sub-line fades up 37.75-38.05. **Held still 38.05-40.00 = 1.95 s.** | The input you watched all film is the signature. |

Captions (S2, S3, S4, S6, S7, and S5 only before the slam): the word-synced plate pattern of
`media/projects/collage-handshake/gen.py` as adapted in `linkedin-intro/gen.py`: plate `#e2e5ea`, radius 10, no shadow;
words 60 px Inter 500, ink at 0.38 opacity, the spoken word full ink on an ink block with white text (cobalt stays the
single accent object of each frame); max two lines, centred in y 1130-1290; caption pages never overlap. On the cobalt
page the plate is white. Where a headline repeats the spoken line exactly (none in this plan), sync runs inside the
headline instead.

## 7. Shotcraft aesthetic rules: how each is met

- **R1 hold >= 1 s:** S1 frame 1.6-4.3; S2 7.6-8.7; S3 board ~12.9-15.6; S4 list 20.2-22.0, checked list 23.5-25.05;
  S5 sheet ~26.4-27.35 ("Ship." itself still from ~26.1); S6 fan ~29.4-30.5; S7 tags ~34.6-35.6; end card
  38.05-40.0 (1.95 s, >= 1.5 s required).
- **R2 acceleration, uneven stagger, no linear motion:** every move has an ease (power/sine/spring); typing is
  frame-locked by design (the card's rule: eased typing reads as a loader). Groups accelerate: checks 0.32 -> 0.08 s,
  cards EASE.out stagger, tags 0.35/0.25 s; speech-anchored rows are uneven by nature. list-reveal's linear drift is
  replaced by sine.inOut. Every group ends in a still.
- **R3 one notch slower:** typing 2 f/char (human speed), list stagger 12 f (card 10 f), slider sweep 30 f. The hook
  is deliberately fast (the brief demands a frame by 2 s), so the **hero arc is the prompt field itself**: it types
  (S1), returns (S3), takes notes (S7) and becomes the end card (S8), one object across 40 s.
- **R4 <= 3 whole-frame impacts:** one, the "Ship." slam shake at `ship+0.00`. The cobalt wipes and the slider are
  transitions; the end-card morph is element level.
- **Q1:** every picture of a product output is a real render (evidence stills). The prompt field, rows, findings list
  and tags are hand-built fragments with real content only (verbatim prompts, FACTS wording); the keyframe track is a
  labelled-free generic diagram of "the old way", not a copy of any editor's interface.
- **Q5:** one subject opens the film (the prompt field, then the frame it returns).
- **Q11 / brief's 40 px floor:** captions 60 px, all read text >= 40 px. Text inside the real stills (their own
  captions, map labels) is evidence texture; the headline carries the meaning.
- **P4:** each trick is the hero once: typing (S1, S7 is the same field taking a note), slider once, slam once, card
  fan once, list once, morph once.
- **S2/S4:** each sound below is tied to a named action; repeated sounds alternate samples at falling gain.
- **C1:** captions on every narrated shot; the end card has none.

## 8. Sound plan (no music)

- **Effects** only from `$MEDIA_TOOLS/gbro-collage-info/assets/sfx` (click, flip, focus, grow, pop-land, pop-soft,
  reveal, tick, whoosh-in, whoosh-soft): 45 cues in `script.json`, all <= 0.5 gain, anchored to the spoken word
  wherever they land on one (anchor words are unique in the script; `mix.py` takes the first match). `mix.py` adds its
  quiet room tone under everything.
- **Silence:** from the end of L6 (~23.85) to L7 (~25.05): no voice, no effect, no motion. The last cue before it is
  the check-run whoosh at `fixed+0.70` (0.68 s long, ends ~23.6); the next is the cobalt wipe on `Second`. If L6 runs
  long the gap shrinks: QA must confirm >= 0.8 s of real silence.
- **Peak:** whoosh-in at `ship-0.20` for the drop, reveal at `ship+0.00` for the landing (the only whole-frame impact).
- **Typing** (S1 and S7): alternating click/tick every 3rd-4th character at falling gain (0.18 -> 0.09), not one per
  character (machine-gun rule S2).
- **Tail:** after the end-card sub-line (~37.75) only room tone, so the loop restarts clean.
- **Music bed: follow-up** (no licensed track; option: synthesise with Lemo `core/audio` as `one-map` did, logged in
  `rights.md` first).

## 9. Engine per shot

All eight shots: **HyperFrames 0.9.8 + GSAP 3.15**, one `index.html` at 1080x1350, 30 fps, 40.0 s. No Remotion, no
WebGL, no Blender (no GPU). Font: `media/.tools/web/Inter.woff2`. The builder reads each named demo for its numbers
and re-implements them as GSAP tweens at absolute times:

| card | demo the builder reads | what is adapted |
|---|---|---|
| `typography/typewriter-moves.md` | `demos/typography/typewriter-moves/TypewriterErrorRetype.tsx` | frame-locked substring typing, fixed-width spans per character, cursor solid/blink/removed; not the retype act (would need a false "before" text) |
| `ui-entrance/deck-deal-flyin.md` | `demos/ui-entrance/deck-deal-flyin/DeckDealFlyin.tsx` | 2D only: 48/30 px anticipation, 8 f flight with arc, 4 f overshoot settle, 0.996 press; no orbit, no camera |
| `data/before-after-slider-scrub.md` | `demos/data/before-after-slider-scrub/BeforeAfterSliderScrub.tsx` | throw/rebound/pause/sweep timing, clip-path locked to the bar, velocity stretch on the handle; sweep ends at 100% (see section 11) |
| `ui-entrance/list-reveal.md` | `demos/ui-entrance/list-reveal/ListReveal.tsx` | scale-into-place with focus blur, soft back overshoot, window/stagger ratio; drift eased |
| `effects/slam-entrance-moves.md` | `demos/effects/slam-entrance-moves/ScoreSlam.tsx` | hover -> ease-in drop -> spring, one ring, 5 f decaying shake; no shards, sparks, gold or white flash |
| `ui-entrance/card-stack.md` | `demos/ui-entrance/card-stack/CardStack.tsx` | EASE.out stagger springs, landing dip, 2% tighten, single fan spring with origin 50% 130%, centre-card draw; 5 cards not 9 |
| `outro/ui-to-brand-morph.md` | `demos/outro/ui-to-brand-morph/InputMorphsIntoLogo.tsx` | send press, accelerating fly-off, flood from the send key, single-spring five-quantity morph; letters instead of logo pieces |

Builder inputs: the evidence stills in `media/.build/ai-editing-story/evidence/` (paths in `script.json`
`evidence`); `voice.py`; `mix.py`; caption pattern from `linkedin-intro/gen.py`. `paper.py` is not needed (flat fields).

## 10. Open items (for the user / caller)

1. **"8 problems" vs seven descriptions.** FACTS names the 8 problems in seven phrases ("three transition overlaps" is
   one phrase). The list shows those seven rows verbatim and the counter says "8 of 8 fixed". Please confirm how the 8
   break down (from the QA transcript); if needed, the builder splits a row so the list has exactly 8.
2. **Contact sheet timing.** The sheet shows the fixed intro (word sync inside the headline), so S5 places it with the
   second review. Confirm it came from the second (SHIP) review; if not, its label stays generic as written.
3. **rights.md** needs, before the build: rows for our own evidence stills (own renders, used in `ai-editing-story`),
   and `ai-editing-story` added to the "Used in" column of the Adobe Stock cut-out (it appears inside `collage.png`)
   and of the gbro SFX row. Not edited here (scope of this task: PLAN.md and script.json).
4. **Copy sign-off:** the user approves the wording before posting (FACTS); especially "I chose the direction",
   "No paid tools", "I approve every word" and the end-card sub-line.
5. **Music bed:** follow-up.

## 11. Deliberate rule breaks

- **before-after-slider-scrub ends at 100%, not 40%:** the card keeps both states to compare outputs. Here the
  comparison is of methods, and the "before" is a diagram, not a product state; the story needs the old way gone.
  The fast/slow 12 f : 30 f contrast (2.5:1, near the card's 3:1 floor) is kept short so "Now I describe it" is not
  stretched; if QA finds the contrast unreadable, lengthen the sweep to 36 f.
- **Typewriter is frame-locked (stepped), not eased:** the card's own rule; it is not linear motion in R2's sense.
- **Hook arc under 3 s (R3):** the brief requires a real frame within 2 s; the landed frame then holds 2.7 s, and the
  prompt field carries the long arc across the film.
- **Q8 (energy at the close):** the end is a quiet morph and a 1.95 s hold, not a launch-style group shot: this is a
  personal workflow post, the peak is "Ship." at 25.95 s.
