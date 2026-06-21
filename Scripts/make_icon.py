#!/usr/bin/env python3
"""Pith icon — minimal waveform on warm gradient, inspired by Claude's aesthetic."""

import os
import subprocess
from PIL import Image, ImageDraw, ImageFilter

def lerp_color(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def draw_icon(size: int) -> Image.Image:
    s = size
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    # --- Gradient background (warm sand → coral, like Claude palette) ---
    bg = Image.new("RGB", (s, s))
    top    = (210, 140, 100)   # warm terra cotta
    bottom = (165,  85,  60)   # deeper rust
    for y in range(s):
        t = y / (s - 1)
        row_color = lerp_color(top, bottom, t)
        ImageDraw.Draw(bg).line([(0, y), (s, y)], fill=row_color)

    # Apply rounded rect mask
    radius = s * 0.22
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([(0, 0), (s - 1, s - 1)], radius=radius, fill=255)
    img.paste(bg, (0, 0))
    img.putalpha(mask)

    draw = ImageDraw.Draw(img)

    # --- "Core": the pith — a solid center radiating two rings ---
    cx = cy = s * 0.5
    # Radiating rings (outer fainter, like sound emanating from the core)
    for r_norm, alpha in [(0.30, 150), (0.42, 80)]:
        r = s * r_norm
        draw.ellipse(
            [(cx - r, cy - r), (cx + r, cy + r)],
            outline=(255, 255, 255, alpha),
            width=max(1, int(s * 0.016)),
        )
    # The core itself
    r = s * 0.155
    draw.ellipse([(cx - r, cy - r), (cx + r, cy + r)], fill=(255, 255, 255, 255))

    return img


def main():
    assets = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")
    iconset = os.path.join(assets, "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)

    specs = [
        ("icon_16x16.png",        16),
        ("icon_16x16@2x.png",     32),
        ("icon_32x32.png",        32),
        ("icon_32x32@2x.png",     64),
        ("icon_128x128.png",     128),
        ("icon_128x128@2x.png",  256),
        ("icon_256x256.png",     256),
        ("icon_256x256@2x.png",  512),
        ("icon_512x512.png",     512),
        ("icon_512x512@2x.png", 1024),
    ]

    for filename, px in specs:
        img = draw_icon(px)
        path = os.path.join(iconset, filename)
        img.save(path, "PNG")
        print(f"  {path}")

    icns = os.path.join(assets, "AppIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", icns], check=True)
    print(f"\n{icns} generated.")


if __name__ == "__main__":
    main()
