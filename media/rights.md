# Rights ledger

Every image, clip, sound, voice, font and render engine a Yourider video uses is listed here before it is used.
The video-qa agent fails any video that uses something missing from this file.

**This repository is public.** Licensed stock files are never committed: they live in `media/assets/` (gitignored) and
each entry says how to get the file again. Verify licence terms yourself before a paid campaign; this ledger records
what we checked, it is not legal advice.

## Images and footage

| File in `media/assets/` | Source | Licence | Used in | How to get it again |
|---|---|---|---|---|
| `AdobeStock_524285853-cutout.png` | Adobe Stock #524285853 "Two businessmen shake hands on white background", background removed with Photoshop (Adobe connector) | Adobe Stock free tier, licensed 2026-11-03 to the account connected to Claude; Adobe Stock licence terms apply | `collage-handshake` | Adobe connector: `asset_license_and_download_stock` 524285853 -> `image_remove_background` -> `asset_inline_preview` (size 2000) |

## Sound

| Item | Source | Licence | Used in |
|---|---|---|---|
| Narration voice `en_US-ljspeech-medium` | Piper voice trained on the LJ Speech dataset | Dataset: public domain (voice model card) | all projects |
| 10 effects in `gbro-collage-info/assets/sfx` | [pyang5166/gbro-collage-info](https://github.com/pyang5166/gbro-collage-info) @ 0b97a81, sourced from Mixkit | Repo MIT; the repo states the Mixkit sounds are royalty-free for commercial use | `collage-handshake` |
| Score and foley of `one-map` | Synthesised by our `audio.py` with Lemo-Opuscar `core/audio` (plucked-string and procedural synthesis) | Our own composition; library MIT | `one-map` |

## Fonts

| Font | Source | Licence |
|---|---|---|
| Inter | npm `@fontsource-variable/inter@5.2.5` | SIL Open Font License 1.1 |

## Engines and libraries (what renders the video)

| Tool | Licence | Note |
|---|---|---|
| Lemo-Opuscar @ bebbbe1 (transit-map engine, audio synthesis) | MIT | engine files are copied into `.tools` at build time, not into this repo |
| HyperFrames 0.9.8 | Apache-2.0 | telemetry switched off in `env.sh` |
| GSAP 3.15.0 | GreenSock Standard License (gsap.com/standard-license), not open source | read the terms before shipping a product built on it |
| Remotion (only via OpenMontage, `setup.sh --with-openmontage`) | Remotion licence: **companies may need a paid company licence** | check remotion.dev/license before commercial use; our default pipeline does not use it |
| Piper TTS, faster-whisper, ffmpeg | open source tools; their output (our audio, timings) is ours | — |

## Not allowed
- Images from arbitrary websites, other creators' videos or music, even "for a test" in a public repo.
- yt-dlp downloads of anything except our own uploads or Creative Commons material with attribution recorded here.
