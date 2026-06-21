#!/usr/bin/env python3
"""DMG background — warm gradient with a drag-to-Applications hint and arrow.
Rendered at 2x (1200x800) for Retina; the Finder window is 600x400 points."""

import os.path

from PIL import Image, ImageDraw, ImageFont

S = 1                      # 1:1 with the Finder window (600x400 points) so the
                            # art aligns with the icon slots; dmgbuild maps it 1:1
W, H = 600 * S, 400 * S
img = Image.new("RGB", (W, H))
px = img.load()

# Vertical warm gradient: cream -> soft peach (matches the app's aesthetic).
top, bot = (250, 246, 240), (243, 231, 220)
for y in range(H):
    t = y / (H - 1)
    row = tuple(int(top[i] * (1 - t) + bot[i] * t) for i in range(3))
    for x in range(W):
        px[x, y] = row

draw = ImageDraw.Draw(img)


def font(size, weight="Regular"):
    for path in (f"/System/Library/Fonts/SFNS.ttf",
                 "/System/Library/Fonts/Helvetica.ttc",
                 "/Library/Fonts/Arial.ttf"):
        try:
            return ImageFont.truetype(path, size * S)
        except OSError:
            continue
    return ImageFont.load_default()


def centered(text, y, fnt, fill):
    w = draw.textlength(text, font=fnt)
    draw.text(((W - w) / 2, y * S), text, font=fnt, fill=fill)


centered("Pith", 42, font(30), (44, 36, 30))
centered("Drag the app onto the Applications folder", 82, font(14), (130, 114, 102))

# Arrow between the two icon slots (app at x=150, Applications at x=450, y=210).
y = 210 * S
x0, x1 = 234 * S, 366 * S
accent = (200, 120, 84)
draw.line([(x0, y), (x1, y)], fill=accent, width=5 * S)
head = 14 * S
draw.polygon([(x1, y), (x1 - head, y - head * 0.7), (x1 - head, y + head * 0.7)], fill=accent)

_out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "dmg_background.png")
img.save(_out)
print(f"OK {_out}")
