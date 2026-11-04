# Decisions

## 2026-11-03 — Image/video automation tooling
- Claude Code plugins live in `.claude/settings.json` (project scope, pinned to reviewed commits): ECC (subagents), HyperFrames, Ponytail, Matt Pocock skills, Lemo-Opuscar, opus-video-skills (painted-animation, kinetic-reel). They install when a session trusts the project.
- Everything else goes through `scripts/setup-media-tools.sh` into gitignored `/tools`: OpenMontage, Graphify (project skill), onetake (user skill), Earshot + real-sound (`--with-earshot`), ClaudeAnimationBase (`--with-animation`), plus two reference-only collections.
- Openverse is used through its public API (HyperFrames media-use already does this for SFX). We don't self-host the monorepo.
- Not installed: "collage B-rolls" (no credible repo found), clipwing.pro real-SFX (not on GitHub; Earshot's real-sound covers the same job).
- Risk accepted: ECC and Ponytail ship hooks that run on every session. Review them before trusting the project.

## 2026-11-04 — Media pipeline consolidated into `/media`, video team of three agents
- Supersedes the 2026-11-03 layout: `scripts/setup-media-tools.sh` -> `media/setup.sh`; tools in gitignored `media/.tools` (core by default, the rest behind `--with-*` flags).
- Plugins trimmed to the video ones (HyperFrames, Lemo-Opuscar, opus-video-skills). ECC, Ponytail and Matt Pocock skills removed: coding tools, ECC adds 27 hooks, and our own agents replace ECC's subagents for video work.
- Three agents, not more: `video-director` (plan + script.json), `video-builder` (render), `video-qa` (read-only checks, SHIP/FIX). The recurring failures were environmental, so fixes live in `media/env.sh` rather than in more agents.
- Sync rule: anything that must land on a spoken word is computed from Whisper word times (words.json), never from fixed seconds; a different voice take cannot break it.
- `voice.py` re-takes a line up to 4 times (Piper sometimes slurs words) and fails loudly if no take is intelligible or lines overlap; `heard_as` maps known mishearings of names ("writer" -> "rider").
- The repo is public: licensed stock never committed (`media/assets/` gitignored), every asset/sound/voice/font/engine recorded in `media/rights.md`. Remotion (via OpenMontage) may need a company licence; the default pipeline does not use it.
- Python + shell here (not TypeScript) because the speech/audio tools are Python; it sits outside `src/` and the TS build.
- Verified 2026-11-04 by running everything from the repo: setup from scratch, both projects end to end, join, and the video-qa agent. QA caught, and we fixed: an unsupported "Automated" product claim on a map label, sources hidden under captions, dead digital silence (now a room tone in mix.py + a dead-air check in check.py), and clipping in join.py (+5.3 dBTP; now two-pass loudness + limiter).

## 2026-11-04 — Design system, better voice, Blender
- Voice: `voice.py` now has providers. ElevenLabs (user's choice; paid Starter+ for commercial use) is used when `ELEVENLABS_API_KEY` is set and a `voice_id` is configured, with ElevenLabs' character alignment as the timing source. Kokoro-82M (free, Apache-2.0) is the default otherwise; Piper is the last fallback. Every take is still checked with Whisper. Kokoro's q8f16 model segfaults onnxruntime here; the int8 `model_quantized.onnx` is used.
- Design: taste-skill (art direction) and video-shotcraft (shot recipe cards, aesthetic rules, final review) are built into the director and QA agents. Shotcraft's demos render with its pinned Remotion template; this machine has no GPU, so `--gl=swangle` is required and 3D shots cost ~11 s per frame.
- Both tools converge on one finding: the strongest product video shows the real product UI. Yourider has no UI yet, so the biggest design jump comes once there are real screens to capture.
- Blender: headless `bpy` 5.2.3 for 3D stills (~140 s per 1080p frame on CPU). Real 3D animation and Blender MCP (needs the desktop app) belong on a machine with a GPU.
- VoiceStudio (local ElevenLabs alternative, AGPL) not installed: desktop/Docker app, GPU-oriented; an option for a local machine later.

## 2026-11-04 — No paid voice services
- The user decided against ElevenLabs because it is paid. Kokoro (free, Apache-2.0) is the voice; Piper is the fallback. The optional ElevenLabs code in `voice.py` stays dormant (it runs only if `ELEVENLABS_API_KEY` is set) and the agents are told not to set it up.

## 2026-11-04 — Anti-slop gates
- User asked for no AI slop. Added two automatic gates: `plancheck.py` (Humanizer writing patterns, headline/caption repeats, facts, learned rules) before any build, and `motionlint.py` (Emil Kowalski's motion standards) after the composition is generated. Impeccable's craft floor and taste-skill guide the director and QA. `LEARNINGS.md` turns every QA finding into a rule.
- Tested on our own work: plancheck finds the six headline repeats QA found by hand in the paused 40 s video; motionlint finds scale-from-zero entrances in both 4:5 videos. Ease-in on entrances is a warning, not a failure, because slams into an impact accelerate on purpose.
