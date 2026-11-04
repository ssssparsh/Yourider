"""Paper materials for collage shots: a grainy coloured field and torn-edge cards. Deterministic (fixed seeds).

usage: $MEDIA_PY media/pipeline/paper.py <out_dir> [--field "#B8432F"]
Writes field.png (1920x1080), card.png, mapcard.png, brand.png.
"""
import argparse
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

rng = np.random.default_rng(3)
random.seed(3)


def grain(w: int, h: int, rgb: tuple[int, int, int], amt: float) -> Image.Image:
    n = rng.normal(0, 1, (h // 2, w // 2))
    n = np.array(Image.fromarray(((n + 3) * 40).clip(0, 255).astype("uint8")).resize((w, h)).filter(ImageFilter.GaussianBlur(.6))) / 255 - .5
    fib = np.array(Image.fromarray((rng.random((h // 8, w // 8)) * 255).astype("uint8")).resize((w, h), Image.BICUBIC)) / 255 - .5
    base = np.array(rgb, float)[None, None, :] * (1 + amt * n[..., None] + amt * .8 * fib[..., None])
    return Image.fromarray(base.clip(0, 255).astype("uint8"))


def torn(w: int, h: int, rgb: tuple[int, int, int], out: Path, jag: float = 7) -> None:
    pts = []
    for side in range(4):
        for i in range(60):
            f = i / 60
            x, y = [(f * w, 0), (w, f * h), (w - f * w, h), (0, h - f * h)][side]
            j = random.uniform(-jag, jag)
            pts.append((x + (j if side in (1, 3) else 0), y + (j if side in (0, 2) else 0)))
    pad = 20
    mask = Image.new("L", (w + 2 * pad, h + 2 * pad), 0)
    ImageDraw.Draw(mask).polygon([(x + pad, y + pad) for x, y in pts], fill=255)
    tex = grain(w + 2 * pad, h + 2 * pad, rgb, .05).convert("RGBA")
    tex.putalpha(mask.filter(ImageFilter.GaussianBlur(.7)))
    tex.save(out)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir")
    ap.add_argument("--field", default="#B8432F")
    a = ap.parse_args()
    d = Path(a.out_dir)
    d.mkdir(parents=True, exist_ok=True)
    rgb = tuple(int(a.field[i:i + 2], 16) for i in (1, 3, 5))
    grain(1920, 1080, rgb, .10).save(d / "field.png")
    torn(1180, 760, (246, 241, 228), d / "card.png")
    torn(560, 300, (234, 225, 204), d / "mapcard.png", 5)
    torn(470, 150, (38, 36, 31), d / "brand.png", 5)
    print(f"paper materials in {d}")
