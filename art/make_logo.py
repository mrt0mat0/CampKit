"""Render the CampKit logo (logo.png, 400x400) with Pillow.

Drawn at 4x and downsampled for smooth edges. Run: python3 art/make_logo.py
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

OUT = 400
S = 4
W = OUT * S


def px(v):
    return v * S


def flame(cx, base, width, height, lean=0.0, steps=120):
    """Teardrop flame outline: round bottom, pointed tip that can lean sideways."""
    pts = []
    for i in range(steps + 1):
        t = i / steps * 2 * math.pi
        # x: sin gives the width; narrowing toward the top makes the tip
        y = -math.cos(t)  # -1 bottom .. 1 top
        up = (y + 1) / 2
        half = width / 2 * math.sin(t) * (1 - up) ** 0.55 * (1 + 0.6 * up)
        x = cx + half + lean * up ** 2 * width
        yy = base - up * height
        pts.append((px(x), px(yy)))
    return pts


def log(draw, cx, cy, length, thick, angle, fill, end):
    a = math.radians(angle)
    dx, dy = math.cos(a) * length / 2, math.sin(a) * length / 2
    nx, ny = -math.sin(a) * thick / 2, math.cos(a) * thick / 2
    poly = [(cx - dx + nx, cy - dy + ny), (cx + dx + nx, cy + dy + ny),
            (cx + dx - nx, cy + dy - ny), (cx - dx - nx, cy - dy - ny)]
    draw.polygon([(px(x), px(y)) for x, y in poly], fill=fill)
    for sx in (-1, 1):
        ex, ey = cx + sx * dx, cy + sx * dy
        r = thick / 2
        draw.ellipse([px(ex - r), px(ey - r), px(ex + r), px(ey + r)], fill=end)
        r2 = r * 0.45
        draw.ellipse([px(ex - r2), px(ey - r2), px(ex + r2), px(ey + r2)], fill=fill)


img = Image.new("RGBA", (W, W), (0, 0, 0, 0))

# Background: rounded night-sky square
bg = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ImageDraw.Draw(bg).rounded_rectangle([0, 0, W - 1, W - 1], radius=px(72), fill=(22, 27, 48, 255))
img.alpha_composite(bg)

# Warm glow behind the fire
glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([px(80), px(110), px(320), px(350)], fill=(255, 140, 40, 120))
glow = glow.filter(ImageFilter.GaussianBlur(px(45)))
mask = Image.new("L", (W, W), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, W - 1], radius=px(72), fill=255)
glow.putalpha(Image.composite(glow.getchannel("A"), Image.new("L", (W, W), 0), mask))
img.alpha_composite(glow)

d = ImageDraw.Draw(img)

# Stars
for x, y, r in [(70, 70, 3), (118, 48, 2), (300, 62, 3), (340, 118, 2), (52, 150, 2), (258, 40, 2)]:
    d.ellipse([px(x - r), px(y - r), px(x + r), px(y + r)], fill=(230, 232, 255, 220))

# Crossed logs
log(d, 200, 318, 230, 36, 16, (122, 74, 42, 255), (196, 150, 104, 255))
log(d, 200, 318, 230, 36, -16, (140, 86, 50, 255), (214, 168, 120, 255))

# Flames, back to front
d.polygon(flame(200, 318, 170, 250, lean=-0.10), fill=(226, 72, 38, 255))
d.polygon(flame(203, 316, 124, 196, lean=0.12), fill=(250, 140, 40, 255))
d.polygon(flame(200, 314, 74, 128, lean=-0.08), fill=(255, 214, 90, 255))

# Sparks
for x, y, r in [(132, 132, 5), (276, 104, 4), (254, 62, 3)]:
    d.ellipse([px(x - r), px(y - r), px(x + r), px(y + r)], fill=(255, 196, 80, 255))

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logo.png")
img.resize((OUT, OUT), Image.LANCZOS).save(out)
print(out)
