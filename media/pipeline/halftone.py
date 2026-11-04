"""Halftone a transparent cut-out (keeps its alpha) and add a cream die-cut keyline, gbro-collage style."""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageOps
src, out = sys.argv[1], sys.argv[2]
CELL, INK, PAPER, KEY = 9, (38, 36, 31, 255), (246, 241, 228, 255), (252, 248, 237, 255)
im = Image.open(src).convert("RGBA")
alpha = im.getchannel("A").point(lambda a: 255 if a > 128 else 0)
gray = ImageOps.autocontrast(ImageOps.grayscale(im), cutoff=1)
W, H = im.size
dots = Image.new("RGBA", (W, H), PAPER)
d = ImageDraw.Draw(dots)
for y in range(0, H, CELL):
    for x in range(0, W, CELL):
        g = gray.getpixel((min(W - 1, x + CELL // 2), min(H - 1, y + CELL // 2)))
        r = (1 - g / 255) ** 0.9 * CELL * 0.72
        if r > .4: d.ellipse([x + CELL / 2 - r, y + CELL / 2 - r, x + CELL / 2 + r, y + CELL / 2 + r], fill=INK)
body = Image.new("RGBA", (W, H), (0, 0, 0, 0)); body.paste(dots, (0, 0), alpha)
key = alpha.filter(ImageFilter.MaxFilter(17)).filter(ImageFilter.GaussianBlur(1))
pad = 24
canvas = Image.new("RGBA", (W + 2 * pad, H + 2 * pad), (0, 0, 0, 0))
canvas.paste(Image.new("RGBA", (W, H), KEY), (pad, pad), key)
canvas.alpha_composite(body, (pad, pad))
canvas = canvas.crop(canvas.getbbox())
canvas.save(out); print(out, canvas.size)
