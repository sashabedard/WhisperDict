#!/usr/bin/env python3
"""
Render docs/demo.gif entirely in code (no screen capture) — a stylized demo of
the WhisperDict flow: hold the key, the recording overlay shows live equalizer
bars, it transcribes, and clean text appears in the editor. On-brand (warm/copper
accents, the app's dark overlay pill).

Usage: python3 Scripts/make_demo_gif.py
"""
import math
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

# ── Config ────────────────────────────────────────────────
SS = 2                      # supersample factor (rendered then downscaled = crisp)
W, H = 860, 500
FPS = 20
OUT = os.path.join(os.path.dirname(__file__), "..", "docs", "demo.gif")

SENTENCE = "So I basically want to ship this feature today."

# Phase timeline (seconds). Shared by frame() and main().
T_IDLE, T_REC, T_SPIN, T_TYPE = 0.35, 2.4, 0.7, 1.7
P_REC = T_IDLE
P_SPIN = P_REC + T_REC
P_TYPE = P_SPIN + T_SPIN
P_HOLD = P_TYPE + T_TYPE
TOTAL = P_HOLD + 0.2

# Colors
BG_TOP = (247, 243, 238)
BG_BOT = (238, 230, 222)
WIN = (255, 255, 255)
WIN_BORDER = (0, 0, 0, 18)
TEXT = (38, 38, 40)
DIM = (150, 146, 142)
ACCENT = (198, 104, 64)        # copper/terracotta (brand)
PILL = (24, 24, 26)
BAR = (255, 255, 255)

FONT = "/System/Library/Fonts/SFNS.ttf"


def font(sz):
    return ImageFont.truetype(FONT, sz * SS)


def lerp(a, b, t):
    return a + (b - a) * max(0.0, min(1.0, t))


def ease(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)   # smoothstep


def rounded(draw, box, r, fill=None, outline=None, width=1):
    draw.rounded_rectangle([c * SS for c in box], radius=r * SS, fill=fill,
                           outline=outline, width=width * SS)


def vgradient():
    img = Image.new("RGB", (W * SS, H * SS))
    px = img.load()
    for y in range(H * SS):
        t = y / (H * SS)
        c = tuple(int(lerp(BG_TOP[i], BG_BOT[i], t)) for i in range(3))
        for x in range(W * SS):
            px[x, y] = c
    return img


GRADIENT = vgradient()


def bar_height(i, t):
    """Per-bar equalizer fraction [0.12, 1] for an 8-band 'speaking' look."""
    phase = i * 0.7
    env = 0.55 + 0.45 * math.sin(t * 5.0 + i)           # talking envelope
    wob = 0.5 + 0.5 * math.sin(t * 11.0 + phase) * math.cos(t * 7.0 + phase * 1.7)
    return 0.12 + 0.88 * max(0.0, min(1.0, env * wob))


def draw_pill(img, cx, cy, alpha, mode, t):
    """The app's overlay: a dark pill with equalizer bars (mode='rec') or a
    rotating arc spinner (mode='spin'). `alpha` 0..1 fades it in/out."""
    if alpha <= 0.01:
        return
    pw, ph = 168, 58
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    box = [cx - pw / 2, cy - ph / 2, cx + pw / 2, cy + ph / 2]
    a = int(216 * alpha)
    rounded(d, box, ph / 2, fill=(PILL[0], PILL[1], PILL[2], a))

    if mode == "rec":
        n, bw, gap = 8, 6, 8
        total = n * bw + (n - 1) * gap
        x = cx - total / 2
        for i in range(n):
            hgt = 8 + bar_height(i, t) * 34
            bx = [x, cy - hgt / 2, x + bw, cy + hgt / 2]
            rounded(d, bx, bw / 2, fill=(BAR[0], BAR[1], BAR[2], int(235 * alpha)))
            x += bw + gap
    else:  # spinner
        r = 11
        bb = [(cx - r) * SS, (cy - r) * SS, (cx + r) * SS, (cy + r) * SS]
        start = (t * 360) % 360
        d.arc(bb, start, start + 270, fill=(255, 255, 255, int(235 * alpha)), width=3 * SS)

    img.alpha_composite(layer)


def draw_cursor(d, x, y, h, on):
    if on:
        d.rectangle([x * SS, y * SS, (x + 2) * SS, (y + h) * SS], fill=ACCENT)


def frame(t, total_t):
    """Render one frame at time t (seconds)."""
    img = GRADIENT.copy().convert("RGBA")
    d = ImageDraw.Draw(img)

    # menu-bar hint (top-right): a copper dot + name
    d.ellipse([(W - 170) * SS, 21 * SS, (W - 162) * SS, 29 * SS], fill=ACCENT)
    d.text(((W - 154) * SS, 18 * SS), "WhisperDict", font=font(13), fill=(120, 116, 112))

    # editor window
    wx, wy, ww, wh = 90, 70, W - 180, H - 185
    # soft blurred shadow
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        [wx * SS, (wy + 10) * SS, (wx + ww) * SS, (wy + wh + 10) * SS],
        radius=18 * SS, fill=(0, 0, 0, 50))
    sh = sh.filter(ImageFilter.GaussianBlur(9 * SS))
    img.alpha_composite(sh)
    rounded(d, [wx, wy, wx + ww, wy + wh], 16, fill=WIN, outline=(180, 174, 168, 90), width=1)
    # title bar dots
    for i, col in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        d.ellipse([(wx + 20 + i * 20) * SS, (wy + 18) * SS,
                   (wx + 32 + i * 20) * SS, (wy + 30) * SS], fill=col)

    # ── timeline (module constants) ─────────────────────
    p_rec, p_spin, p_type, p_hold = P_REC, P_SPIN, P_TYPE, P_HOLD

    tx, ty = wx + 34, wy + 70           # text origin in the editor
    fnt = font(22)
    line_h = 30

    # caption + state
    pill_cx, pill_cy = W / 2, wy + wh + 30
    cap_y = wy + wh + 70

    if t < p_rec:
        caption, ccol = "Hold  ⌥  to dictate", DIM
        draw_cursor(d, tx, ty, 26, (int(t * 2) % 2 == 0))
    elif t < p_spin:
        caption, ccol = "Listening…", ACCENT
        a = ease((t - p_rec) / 0.18)
        draw_pill(img, pill_cx, pill_cy, a, "rec", t)
        draw_cursor(d, tx, ty, 26, True)
    elif t < p_type:
        caption, ccol = "Transcribing…", ACCENT
        draw_pill(img, pill_cx, pill_cy, 1.0, "spin", t)
        draw_cursor(d, tx, ty, 26, True)
    else:
        caption, ccol = "Cleaned on-device — nothing left your Mac", (110, 150, 100)
        # fade the pill out at the start of typing
        a = 1.0 - ease((t - p_type) / 0.2)
        draw_pill(img, pill_cx, pill_cy, a, "spin", t)

    # word-by-word reveal during type + hold
    words = SENTENCE.split(" ")
    if t >= p_type:
        prog = (t - p_type) / T_TYPE
        shown = max(1, min(len(words), int(math.ceil(ease(prog) * len(words)))))
        # wrap text inside the window
        line, lines = "", []
        for w in words[:shown]:
            test = (line + " " + w).strip()
            if d.textlength(test, font=fnt) / SS > ww - 70 and line:
                lines.append(line)
                line = w
            else:
                line = test
        lines.append(line)
        for i, ln in enumerate(lines):
            d.text((tx * SS, (ty + i * line_h) * SS), ln, font=fnt, fill=TEXT)
        # caret after last word
        if shown < len(words) or t < p_hold:
            cw = d.textlength(lines[-1], font=fnt) / SS
            draw_cursor(d, tx + cw + 3, ty + (len(lines) - 1) * line_h, 26,
                        (int(t * 3) % 2 == 0))

    d.text((W / 2 * SS, cap_y * SS), caption, font=font(14), fill=ccol, anchor="ma")

    return img.convert("RGB").resize((W, H), Image.LANCZOS)


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    n = int(P_HOLD * FPS)                        # animate idle → end of typing
    frames = [frame(i / FPS, TOTAL) for i in range(n)]
    durs = [int(1000 / FPS)] * n
    frames.append(frame(P_HOLD + 0.1, TOTAL))    # final result, held before loop
    durs.append(1700)
    # Per-frame adaptive palettes: vivid colors AND every frame distinct, so the
    # encoder doesn't merge/drop frames (which would scramble the timing).
    qframes = [f.quantize(colors=256, method=Image.MEDIANCUT, dither=Image.NONE) for f in frames]
    qframes[0].save(OUT, save_all=True, append_images=qframes[1:],
                    duration=durs, loop=0, disposal=1)
    size = os.path.getsize(OUT) / 1024
    print(f"wrote {OUT}  ({len(qframes)} frames, {size:.0f} KB)")


if __name__ == "__main__":
    main()
