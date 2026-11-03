# Decisions

## 2026-11-03 — Image/video automation tooling
- Claude Code plugins live in `.claude/settings.json` (project scope, pinned to reviewed commits): ECC (subagents), HyperFrames, Ponytail, Matt Pocock skills, Lemo-Opuscar, opus-video-skills (painted-animation, kinetic-reel). They install when a session trusts the project.
- Everything else goes through `scripts/setup-media-tools.sh` into gitignored `/tools`: OpenMontage, Graphify (project skill), onetake (user skill), Earshot + real-sound (`--with-earshot`), ClaudeAnimationBase (`--with-animation`), plus two reference-only collections.
- Openverse is used through its public API (HyperFrames media-use already does this for SFX). We don't self-host the monorepo.
- Not installed: "collage B-rolls" (no credible repo found), clipwing.pro real-SFX (not on GitHub; Earshot's real-sound covers the same job).
- Risk accepted: ECC and Ponytail ship hooks that run on every session. Review them before trusting the project.
