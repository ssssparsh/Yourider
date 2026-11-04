# Facts for "How I edit video with Claude" (verified from this repo and session, 2026-11-03/04)

Only these facts may appear in the video. Anything else must be cut or confirmed with the user first.

## The user's own requests to Claude (quoted; typos tidied, meaning unchanged)
- "Create an automation for images and videos."
- "Can you make a video in which the audio goes along with the lines rendered in the video?"
- "Currently the designs are not better."
- "Make a 30 second Yourider intro video for LinkedIn, and do check completely."

## What Claude did (true, checkable in git history and media/)
- Researched and installed open-source video tools: OpenMontage, HyperFrames, Lemo-Opuscar, video-shotcraft, taste-skill, Blender (headless), Whisper, the Kokoro voice.
- Built a pipeline in `media/`: narration -> word timings -> composition -> mix -> render -> automated checks.
- Built a team of three AI agents: a director (plans the story, script and shots), a builder (renders), a QA reviewer (checks every frame and rule, never edits).
- Every caption word is timed to the voice by Whisper; on-screen events land on the spoken word.
- The 30-second LinkedIn intro: 55 spoken words, 1080x1350, built end to end by one script in about 2 minutes (126 s measured).
- The first QA review of that intro found 8 problems (overlapping captions, brand not named until 10.6 s, empty first frame, duplicated headline and caption, three transition overlaps, a row held under 1 s, text too small for a phone). The builder fixed all 8; the second review said SHIP.
- QA also caught an unsupported product claim ("Automated") on a map label in the "One Map" film; it was removed.
- Loudness is mastered to -14 LUFS for every video.
- Real stills from those videos are in `media/.build/ai-editing-story/evidence/` (all our own renders; the collage frame contains the licensed Adobe Stock cut-out listed in rights.md).

## How the editing changed (framing that is true for this session; no statistics)
- Before: a person moves keyframes on a timeline, by hand, and checks by eye.
- Here: the user describes the video in a sentence; agents plan, render and check; the user gives notes in plain words.
- The human still decides: the user chose the direction, rejected paid tools, and approves the wording before posting.

## Not allowed
- No time-saved percentages, cost savings, comparisons to other editors, or claims about the industry.
- No logos of other companies or tools on screen (names in plain text are fine).
