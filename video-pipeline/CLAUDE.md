This file governs the `video-pipeline/` directory only. It is separate from the
root `Yourider` CLAUDE.md (the CRM product) — nothing here changes how Claude
Code behaves outside this directory.

# 1. What this is

A video/audio generation pipeline for producing YouTube videos. Publishing is
manual — I upload to YouTube myself. No YouTube API / upload automation is in
scope here.

# 2. Primary tool

Pipeline: `digitalsamba/claude-code-video-toolkit`.

- I clone it as a sibling directory to this repo (not nested inside
  `Yourider`) and run its `/setup` separately, outside this session.
- Claude Code should treat that toolkit as the actual video/audio generation
  engine — use its commands/workflow as documented in its own repo, don't
  reinvent scene generation, TTS, or rendering steps here.
- Do not invent a parallel custom pipeline in this directory. This CLAUDE.md
  exists to record how the toolkit is used for this project, not to replace it.

# 3. Scope right now

Goal: get one real test video produced end to end and manually uploaded to
YouTube. Nothing beyond that yet.

Out of scope for now (add later, only once the toolkit is confirmed working):
- Any additional generation tool (e.g. Higgsfield, Runway, or similar).
- YouTube API / automated publishing.
- Batch/scheduled video production.

# 4. Guardrails

Same spirit as the root CLAUDE.md:
- No secrets (API keys for whatever model/TTS providers the toolkit uses) in
  code, commits, or prompts — use environment variables / a gitignored `.env`
  referenced by name only.
- No destructive action (deleting rendered assets, overwriting source clips,
  force-push) without explicit confirmation.
- If the toolkit's setup or a generation step fails or behaves unexpectedly,
  say so plainly — don't fabricate a "done" video or invented output.

# 5. Workflow for the first test video

1. Clone `digitalsamba/claude-code-video-toolkit` as a sibling directory and
   run its `/setup` (done outside this session).
2. Follow the toolkit's own instructions to generate one short test video
   (script/scenes → audio → render), keeping any project-specific inputs
   (footage, scripts, assets) inside this `video-pipeline/` directory.
3. Review the rendered output locally.
4. Manual step (not automated): upload to YouTube myself.

# 6. Notes

Once the toolkit is actually working end to end, extend this file with
what was learned (useful settings, recurring gotchas) rather than
speculating ahead of time.
