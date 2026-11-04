# Yourider media pipeline

Narrated, word-synced videos for Yourider marketing, built from code. Self-contained: nothing here touches the app code
in `src/`. Python and shell (not TypeScript) because the speech and audio tools are Python.

## Quick start

```bash
media/setup.sh --with-shotcraft --with-taste --with-blender   # once per machine/session: tools into media/.tools
media/projects/collage-handshake/build.sh       # 6.8 s paper-collage shot   -> media/out/collage-handshake.mp4
media/projects/one-map/build.sh                 # 33.5 s transit-map film    -> media/out/one-map.mp4 (~10 min render)
```
Every build ends with `pipeline/check.py` and fails loudly; read its output before sharing a video.

## Voice
The voice is **Kokoro** (free, local, Apache-2.0, default `am_michael`); Piper is the fallback. Every take is
checked with Whisper. Decision 2026-11-04: no paid voice services. `voice.py` still contains an optional ElevenLabs
provider, but it only runs if someone deliberately sets `ELEVENLABS_API_KEY`, which we do not.

## Design system
- **taste-skill** deals a researched art direction (palette, type, composition) from a short brief; the director uses it before any shot.
- **video-shotcraft** gives 124 shot recipe cards with tuned Remotion demos, written aesthetic rules (rhythm, texture, sound, copy) and a final review; the director picks cards, the builder adapts the exact demo, QA checks every rule.
- **Blender** renders real 3D stills (about 2 min per 1080p frame on CPU here); animate them with camera moves in the other engines.

## Anti-slop gates (every build runs them; the build stops on FAIL)
| Gate | When | Checks |
|---|---|---|
| `pipeline/plancheck.py` | before any build | copy (Humanizer patterns: AI words, sales language, "not X but Y", dashes, fragments), headline repeating a caption, numbers not in FACTS.md, rules learned in `LEARNINGS.md`, timing |
| `pipeline/motionlint.py` | after the composition is generated | Emil Kowalski's motion standards: no scale-from-zero, no linear easing, transform/opacity only, ease-in only for slams |
| stills gate | before the full render | frames at every beat and across every transition, looked at by the builder |
| `pipeline/check.py` + QA agent | after the render | technical checks, then Humanizer / Emil Kowalski / Impeccable / shotcraft judgment |
`LEARNINGS.md` records every mistake QA has caught; `setup.sh --with-design` installs the three skills.

## The team (Claude Code agents in `.claude/agents/`)

| Agent | Does | Never |
|---|---|---|
| `writer` | brief -> `BRIEF.md` (audience, one message, proof, cut list), `FACTS.md`, the spoken lines and on-screen words | plans shots or renders |
| `video-director` | brief -> `PLAN.md` + `script.json` (story, narration timings, shots, sounds, engine per shot) | renders |
| `designer` | plan -> `DESIGN.md` + 3 style frames (art direction, type, colour, grid, motion language); reviews the stills gate | writes narration or the final film |
| `video-builder` | `script.json` -> composition, narration, mix, render, master, join | commits licensed assets |
| `video-qa` | independent check: format, loudness, silences, word-sync frames, framing, rights, repo hygiene | edits anything |

Ask for a video in plain words: the writer decides what it says, the director plans how it is shot, the designer sets the look, the builder builds, QA signs off with SHIP or FIX.

## Layout

```
media/
  env.sh            every environment fix (local Chromium, telemetry off, HF downloads); source it first
  setup.sh          pinned installs; core by default, --with-openmontage/earshot/animation/onetake/graphify/ytdlp
  requirements.txt  Python versions for media/.tools/venv
  rights.md         every asset, sound, voice, font and engine with its licence (QA enforces it)
  pipeline/
    voice.py        script.json -> narration (Piper, re-takes unclear lines) + words.json (Whisper word times)
    mix.py          narration + SFX, ducking, -14 LUFS; SFX can be anchored to a spoken word
    master.sh       picture + mix, two-pass loudness
    join.py         chapters -> one long video with crossfades (normalises size, fps, loudness)
    halftone.py     transparent cut-out -> halftone print with cream die-cut edge
    paper.py        paper field and torn cards
    check.py        QA checks + contact sheet of frames at word times
  projects/<name>/  script.json (contract), PLAN.md, composition sources, build.sh
  assets/           licensed inputs, gitignored (the repo is public)
  .tools/ .build/ out/   installed tools, intermediates, finished videos (all gitignored)
```

## `script.json`

```json
{"duration": 6.8, "voice": "en_US-ljspeech-medium", "length_scale": 1.05,
 "lines": [{"id": "L1", "start": 0.6, "say": "Your Rider gets you there.", "show": "Yourider gets you there."}],
 "assets": {"cutout": "AdobeStock_524285853-cutout.png"},
 "sfx": [{"file": "whoosh-in", "t": 0.0, "gain": 0.35}, {"file": "focus", "word": "handshake", "offset": 0.02}]}
```
`say` is spoken, `show` is captioned. Anything that must land on a word is anchored to the word, not to seconds.

## Limits (measured 2026-11-03/04, CPU only)

| | |
|---|---|
| Transit-map film (WebGL) | ~17 s render per film second |
| Remotion 3D shot (shotcraft deck-deal, software GL `--gl=swangle`) | ~11-40 s per frame: ~1.5 h for 5 s; use a GPU machine for 3D cards |
| Blender Cycles still, 1080p, 48 samples | ~140 s per frame |
| HyperFrames shot | ~2 min for 7 s, including narration and QA |
| Join | ~2 min per minute of output |
| Sweet spot | 30-60 s pieces; 5-6 min = 10-12 chapters joined with `join.py` |
| Resolution | 1080p tested; 4K supported by the engines, ~4x render time, untested |

## Environment notes (cloud sessions)
- Allowed domains needed: `huggingface.co`, `us.aws.cdn.hf.co` (voice, Whisper), `api.openverse.org`. GitHub file
  downloads and CDNs (jsdelivr) are blocked; `setup.sh` gets GSAP and Inter from npm instead.
- `photoshop-api.adobe.io` is blocked: Adobe results are pulled through the connector's preview (max 2000 px).
- Freesound refuses this cloud machine's downloads; all current sounds are bundled or synthesised.
- yt-dlp (`--with-ytdlp`) needs YouTube domains allowed, and is only for our own uploads or CC material (see `rights.md`).
