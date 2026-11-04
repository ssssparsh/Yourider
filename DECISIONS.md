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
