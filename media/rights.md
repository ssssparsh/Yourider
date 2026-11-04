# Rights ledger

Every image, clip, sound, voice, font and render engine a Yourider video uses is listed here before it is used.
The video-qa agent fails any video that uses something missing from this file.

**This repository is public.** Licensed stock files are never committed: they live in `media/assets/` (gitignored) and
each entry says how to get the file again. Verify licence terms yourself before a paid campaign; this ledger records
what we checked, it is not legal advice.

## Images and footage

| File in `media/assets/` | Source | Licence | Used in | How to get it again |
|---|---|---|---|---|
| `AdobeStock_524285853-cutout.png` | Adobe Stock #524285853 "Two businessmen shake hands on white background", background removed with Photoshop (Adobe connector) | Adobe Stock free tier, licensed 2026-11-03 to the account connected to Claude; Adobe Stock licence terms apply | `collage-handshake`, `linkedin-intro` | Adobe connector: `asset_license_and_download_stock` 524285853 -> `image_remove_background` -> `asset_inline_preview` (size 2000) |

## Sound

| Item | Source | Licence | Used in |
|---|---|---|---|
| Narration voice `en_US-ljspeech-medium` | Piper voice trained on the LJ Speech dataset | Dataset: public domain (voice model card) | fallback voice |
| Narration voice Kokoro-82M (`am_michael` default) | onnx-community/Kokoro-82M-v1.0-ONNX, run with kokoro-onnx | Model Apache-2.0 | default free voice |
| Narration voice ElevenLabs | not used (decision 2026-11-04: no paid voice services) | its free plan forbids commercial use | none |
| 10 effects in `gbro-collage-info/assets/sfx` | [pyang5166/gbro-collage-info](https://github.com/pyang5166/gbro-collage-info) @ 0b97a81, sourced from Mixkit | Repo MIT; the repo states the Mixkit sounds are royalty-free for commercial use | `collage-handshake`, `linkedin-intro` |
| Score and foley of `one-map` | Synthesised by our `audio.py` with Lemo-Opuscar `core/audio` (plucked-string and procedural synthesis) | Our own composition; library MIT | `one-map` |

## Fonts

| Font | Source | Licence |
|---|---|---|
| Inter | npm `@fontsource-variable/inter@5.2.5` | SIL Open Font License 1.1 |
| Schibsted Grotesk (variable, latin) | npm `@fontsource-variable/schibsted-grotesk@5.3.0` (package licence OFL-1.1, checked 2026-11-04) | SIL Open Font License 1.1 |

## Engines and libraries (what renders the video)

| Tool | Licence | Note |
|---|---|---|
| Lemo-Opuscar @ bebbbe1 (transit-map engine, audio synthesis) | MIT | engine files are copied into `.tools` at build time, not into this repo |
| HyperFrames 0.9.8 | Apache-2.0 | telemetry switched off in `env.sh` |
| GSAP 3.15.0 | GreenSock Standard License (gsap.com/standard-license), not open source | read the terms before shipping a product built on it |
| Remotion 4.0.484 (via video-shotcraft `--with-shotcraft`, and OpenMontage `--with-openmontage`) | Remotion licence: free for individuals and companies of **up to 3 people**; larger companies need a company licence (from $25/month per seat, checked 2026-11-04 on remotion.dev/license) | HyperFrames and Lemo shots do not use Remotion |
| video-shotcraft @ 1266a3e (shot recipes, demos, Remotion template) | Apache-2.0 | demos carry its own brand (Brand.tsx); replace it with Yourider before anything ships |
| taste-skill @ 12af471 (art direction) | MIT | — |
| Blender / bpy 5.2.3 | GPL-3.0 (the program); renders are ours | stills only on this CPU machine |
| kokoro-onnx 0.6.1 | MIT (project repository; package metadata does not state it) | — |
| Piper TTS, faster-whisper, ffmpeg | open source tools; their output (our audio, timings) is ours | — |

## Not allowed
- Images from arbitrary websites, other creators' videos or music, even "for a test" in a public repo.
- yt-dlp downloads of anything except our own uploads or Creative Commons material with attribution recorded here.
