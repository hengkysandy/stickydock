#!/usr/bin/env python3
"""Draws AppIcon.icns: a yellow note with the dock's coloured tabs on its edge.

The whole idea of the app in one shape, so it still reads at 16 points where
anything more detailed turns to mush.
"""
from PIL import Image, ImageDraw
import pathlib, subprocess, sys, math

S = 1024
# Apple's grid: the shape sits inside the canvas rather than filling it.
PAD = 100
BOX = (PAD, PAD, S - PAD, S - PAD)
R = 200          # squircle-ish corner
TAB_W = 78
INK = (48, 44, 34)

def squircle(size, radius, fill):
    """Rounded rect on a 4x supersampled canvas, for clean edges."""
    k = 4
    img = Image.new("RGBA", (size[0] * k, size[1] * k), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle(
        [0, 0, size[0] * k - 1, size[1] * k - 1], radius=radius * k, fill=fill
    )
    return img.resize(size, Image.LANCZOS)

def vertical_gradient(size, top, bottom):
    img = Image.new("RGBA", size)
    d = ImageDraw.Draw(img)
    for y in range(size[1]):
        t = y / max(size[1] - 1, 1)
        d.line([(0, y), (size[0], y)],
               fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img

canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))

w = BOX[2] - BOX[0]
h = BOX[3] - BOX[1]

# The tabs first, so the note sits on top of them and they read as behind it.
tabs = [((252, 176, 196), 0.14), ((150, 200, 246), 0.40), ((196, 176, 250), 0.66)]
for colour, at in tabs:
    ty = BOX[1] + int(h * at)
    th = int(h * 0.20)
    tab = squircle((TAB_W + R // 2, th), R // 3, colour + (255,))
    canvas.alpha_composite(tab, (BOX[2] - R // 2, ty))

# The note itself: a warm yellow with a soft top-to-bottom shift.
note_grad = vertical_gradient((w, h), (255, 219, 112, 255), (247, 191, 61, 255))
mask = squircle((w, h), R, (255, 255, 255, 255))
note = Image.new("RGBA", (w, h), (0, 0, 0, 0))
note.paste(note_grad, (0, 0), mask)
canvas.alpha_composite(note, (BOX[0], BOX[1]))

d = ImageDraw.Draw(canvas)

# Four written lines. Shortening the last one is what makes it read as text.
line_x = BOX[0] + int(w * 0.17)
line_w = [0.52, 0.60, 0.44, 0.30]
top = BOX[1] + int(h * 0.30)
gap = int(h * 0.135)
for i, frac in enumerate(line_w):
    y = top + i * gap
    d.rounded_rectangle(
        [line_x, y, line_x + int(w * frac), y + int(h * 0.052)],
        radius=int(h * 0.026), fill=INK + (92,)
    )

out = pathlib.Path("build/AppIcon.iconset")
out.mkdir(parents=True, exist_ok=True)
for size in (16, 32, 64, 128, 256, 512, 1024):
    for scale in (1, 2):
        px = size * scale
        if px > 1024:
            continue
        name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
        canvas.resize((px, px), Image.LANCZOS).save(out / name)

canvas.save("build/icon-preview.png")
subprocess.run(["iconutil", "-c", "icns", str(out), "-o", "Resources/AppIcon.icns"], check=True)
print("wrote Resources/AppIcon.icns")
