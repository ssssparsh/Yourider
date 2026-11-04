# Learnings: mistakes QA has caught, so they are not repeated

Every QA FIX finding ends up here. If a finding can be checked automatically, it becomes a rule in
`pipeline/plancheck.py` (copy and plan) or `pipeline/motionlint.py` (motion), or a `check:` line below
(a phrase that must never appear in spoken or on-screen text, with the reason). The director reads this file
before planning; QA adds to it after every review.

## Automatic `check:` rules (read by plancheck.py)
- check: automated | unsupported product claim (One Map label, 2026-11-04); Yourider automation is not a fact
- check: game changer | sales language (humanizer §16)

## Caught by QA and now enforced by a script
| Finding | Videos | Enforced by |
|---|---|---|
| Headline repeats the caption (same sentence twice on screen) | linkedin-intro, ai-editing-story | plancheck.py (headline vs caption, sentence level) |
| Unsupported claim on screen ("Automated") | one-map | plancheck.py (`check:` rule) + numbers vs FACTS.md |
| Two caption pages overlapping | linkedin-intro | gen.py assert pattern (to move into the component library) |
| Dead digital silence | collage-handshake | mix.py room tone + check.py dead-air check |
| Clipping in joined videos (+5.3 dBTP) | join test | join.py two-pass loudness + limiter, check.py true peak |
| Scale-from-zero entrances | linkedin-intro, ai-editing-story | motionlint.py |
| Linear motion | (rule from shotcraft R2) | motionlint.py |

## Caught by QA, still checked by eye (candidates for automation)
- Music/drone bed louder than the voice (diwali-2026: 2-6 dB above voice after ducking). Measure voice and bed stems per line; bed should sit >= 10 dB under the voice. Candidate check for check.py.
- A tween that starts exactly on a sound cue becomes visible 1-2 frames late (diwali-2026 lamps). Start sync-critical entrances one frame before the cue.
- Captions under 56 px (shotcraft Q11) passed because our floor was 40 px. Use 56 px for captions, 40 px only for secondary text.
- A hold written in DESIGN.md contradicted the built timing. Assert holds in gen.py from words.json, not in prose.
- A film that opens dark needs a custom cover: decide it in PLAN.md before the build.
- Elements overlapping during transitions (both 4:5 videos): render frame strips across every transition before the full render.
- Key information held under 1 s (tag row; S6 stills): hold timing should be declared per beat and asserted.
- Brand not named early; empty first frame (LinkedIn may use frame 0 as the cover): frame 0 must show the headline and the brand.
- Text too small on a phone (< 40 px at 1080 wide), including text inside evidence stills that the voice points at.
- Cluttered proof montage (five tilted, cropped stills that never hold still): fewer, larger, held.
- Elements waiting just off-frame poke into view (S3 agent rows): keep off-frame elements fully outside.
- Layering errors during page wipes (stills drawn over the cobalt page).
- Lower case word-by-word highlight colour inconsistent with the page it sits on.
