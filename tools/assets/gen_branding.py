#!/usr/bin/env python3
"""Generate OpenSaberQ3's branding: app icon, backgrounds, promo images.

Everything is drawn from primitives - no third-party artwork, no Beat Saber assets.

Why a "Q" and not two crossed sabers: the first draft was cyan and amber blades crossing in an X.
It was legible, but two angled, colour-split sabers is precisely Beat Saber's visual shorthand, so
it advertised "a Beat Saber clone" rather than this project. The mark is now the game's own initial:
a bold Q whose tail is a blade, over the perspective grid of the play space. It survives being
shrunk to a launcher icon and it cannot be confused with the genre's logos.

Outputs:
  icon.png                                  512x512 app icon (transparent outside the badge)
  icon_192.png                              192x192 Android launcher icon
  icon_adaptive_fg_432.png / _bg_432.png    Android adaptive icon layers
  game/data/background/bg_base.png          1920x1080 menu/sky backdrop
  game/data/background/bg_0..3.png          600x338 event panels, one tint each
  game/data/beepsaber_logo.png              placeholder map cover -> our mark
  docs/images/cover.png                     1280x640 GitHub social preview / itch banner
  docs/images/itch-cover.png                630x500 itch.io cover

Usage:  python tools/assets/gen_branding.py
"""
from __future__ import annotations

import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

INK = (5, 8, 14)
DEEP = (14, 24, 42)
CYAN = (56, 225, 255)
AMBER = (255, 179, 64)
WHITE = (240, 248, 255)

TINTS = {
    "0": (56, 225, 255),   # cyan
    "1": (255, 86, 160),   # magenta
    "2": (255, 179, 64),   # amber
    "3": (150, 120, 255),  # violet
}


def vertical_gradient(size, top, bottom):
    w, h = size
    img = Image.new("RGB", size, top)
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        d.line([(0, y), (w, y)], fill=c)
    return img


def radial_glow(size, centre, radius, colour, strength=1.0):
    """Additive glow with a real alpha channel.

    This used to return an opaque RGB field, which alpha_composite treats as a full-canvas
    replacement - it wiped the badge, the gradient and the grid underneath, and every output came
    out as a flat black square with a blob on it. Alpha now carries the falloff, so compositing adds
    light instead of overwriting.
    """
    w, h = size
    small = (max(2, w // 4), max(2, h // 4))
    layer = Image.new("RGBA", small, colour + (0,))
    d = ImageDraw.Draw(layer)
    cx, cy = centre[0] / 4, centre[1] / 4
    r = max(1, radius / 4)
    for i in range(16, 0, -1):
        f = i / 16.0
        rr = r * f
        a = int(255 * (1.0 - f) ** 1.8 * min(1.0, strength))
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=colour + (a,))
    return layer.resize(size, Image.LANCZOS).filter(ImageFilter.GaussianBlur(radius / 14))


def perspective_grid(img, horizon_y, colour, alpha=60, vanish=None, spacing=90, fade=True):
    """Grid floor with the far lines faded out, so they do not alias into a shimmer at 120 Hz."""
    w, h = img.size
    vx, vy = vanish if vanish else (w // 2, horizon_y)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    top = horizon_y

    def line_alpha(y):
        if not fade:
            return alpha
        # fade over the first third of the floor, so distant lines dissolve instead of moiring
        t = (y - top) / max(1.0, (h - top) * 0.35)
        return int(alpha * min(1.0, max(0.0, t)) ** 0.7)

    for x in range(-w, 2 * w, spacing):
        steps = 12
        for s in range(steps):
            y0 = top + (h - top) * (s / steps)
            y1 = top + (h - top) * ((s + 1) / steps)
            x0 = vx + (x - vx) * (s / steps)
            x1 = vx + (x - vx) * ((s + 1) / steps)
            a = line_alpha(y0)
            if a > 2:
                d.line([(x0, y0), (x1, y1)], fill=colour + (a,), width=2)

    y = horizon_y + 6
    step = 12.0
    while y < h:
        a = line_alpha(y)
        if a > 2:
            d.line([(0, y), (w, y)], fill=colour + (a,), width=2)
        step *= 1.32
        y += step
    return Image.alpha_composite(img.convert("RGBA"), layer)


def draw_q(img, cx, cy, radius, thickness, colour, tail_colour):
    """A bold Q whose tail is a saber blade: ring, overlapping hilt, tapered blade, emitter."""
    d = ImageDraw.Draw(img)
    d.ellipse([cx - radius, cy - radius, cx + radius, cy + radius],
              outline=colour + (255,), width=thickness)

    ang = math.radians(50)                      # steeper than a magnifier's handle
    inner = radius - thickness * 0.15           # start inside the stroke: no gap
    start = (cx + math.cos(ang) * inner, cy + math.sin(ang) * inner)
    length = radius * 1.05
    end = (start[0] + math.cos(ang) * length, start[1] + math.sin(ang) * length)

    width = thickness * 1.15
    nx, ny = -math.sin(ang) * width / 2, math.cos(ang) * width / 2
    d.polygon([
        (start[0] + nx, start[1] + ny), (end[0] + nx * 0.45, end[1] + ny * 0.45),
        (end[0] - nx * 0.45, end[1] - ny * 0.45), (start[0] - nx, start[1] - ny),
    ], fill=tail_colour + (255,))

    # crossguard, perpendicular to the blade at the ring
    hx, hy = cx + math.cos(ang) * (radius * 1.02), cy + math.sin(ang) * (radius * 1.02)
    gx, gy = -math.sin(ang) * thickness * 1.15, math.cos(ang) * thickness * 1.15
    d.line([(hx - gx, hy - gy), (hx + gx, hy + gy)], fill=colour + (255,), width=int(thickness * 0.8))

    # emitter: a small bright cap at the tip
    r = thickness * 0.62
    d.ellipse([end[0] - r, end[1] - r, end[0] + r, end[1] + r], fill=(255, 255, 255, 255))


def make_icon(size=512, badge=True):
    """badge=True -> app icon (rounded plate, grid, glow).
    badge=False -> the mark alone on transparency, for compositing onto other artwork. It must not
    carry its own grid or glow: pasted onto the banner that read as a second, non-converging grid
    inside a soft square."""
    ss = 4
    S = size * ss
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    if badge:
        bg = vertical_gradient((S, S), DEEP, INK).convert("RGBA")
        img.paste(bg, (0, 0))
        horizon = int(S * 0.68)
        img = perspective_grid(img, horizon, CYAN, alpha=28, spacing=int(S * 0.22))
        img = Image.alpha_composite(img, radial_glow((S, S), (S * 0.5, S * 0.52), S * 0.44, CYAN, 0.26))
        img = Image.alpha_composite(img, radial_glow((S, S), (S * 0.70, S * 0.70), S * 0.22, AMBER, 0.18))

    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # radius 0.26 leaves room for the blade tip and its emitter inside the rounded corner
    draw_q(layer, S * 0.50, S * 0.47, S * 0.260, int(S * 0.078), CYAN, AMBER)
    bloom = layer.filter(ImageFilter.GaussianBlur(S * 0.028))
    img = Image.alpha_composite(img, bloom)
    img = Image.alpha_composite(img, layer)

    if badge:
        # trim everything - grid, glow, bloom - to the rounded square
        mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.23), fill=255)
        img.putalpha(Image.composite(img.getchannel("A"), Image.new("L", (S, S), 0), mask))

    return img.resize((size, size), Image.LANCZOS)


def make_background(size=(1920, 1080), tint=CYAN):
    w, h = size
    img = vertical_gradient(size, DEEP, (2, 4, 8)).convert("RGBA")
    horizon = int(h * 0.58)

    glow = radial_glow(size, (w * 0.5, horizon), h * 0.75, tint, 0.28).convert("RGBA")
    img = Image.alpha_composite(img, glow)
    # a little warmth so the backdrop shares the icon's palette instead of being cyan-only
    warm = radial_glow(size, (w * 0.78, horizon * 0.92), h * 0.30, AMBER, 0.12).convert("RGBA")
    img = Image.alpha_composite(img, warm)

    img = perspective_grid(img, horizon, tint, alpha=46, spacing=int(w * 0.07))

    vig = Image.new("L", size, 0)
    ImageDraw.Draw(vig).ellipse([-w * 0.25, -h * 0.35, w * 1.25, h * 1.35], fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(w * 0.06))
    dark = Image.new("RGBA", size, (0, 0, 0, 235))
    img = Image.composite(img, dark, vig)
    return img.convert("RGB")


def load_font(px):
    p = os.path.join(REPO, "OQ_Toolkit", "OQ_UI2D", "theme", "Roboto-Medium.ttf")
    return ImageFont.truetype(p, px) if os.path.exists(p) else ImageFont.load_default()


def make_cover(size=(1280, 640)):
    w, h = size
    img = make_background(size).convert("RGBA")

    icon = make_icon(260, badge=False)   # mark only: no plate, no baked grid
    img.alpha_composite(icon, (92, 84))

    d = ImageDraw.Draw(img)
    x = 436
    d.text((x, int(h * 0.26)), "OpenSaberQ3", font=load_font(72), fill=WHITE)
    d.text((x, int(h * 0.43)), "Beat-saber style rhythm game for Quest 3",
           font=load_font(29), fill=(196, 214, 232))
    d.text((x, int(h * 0.50)), "120 Hz", font=load_font(27), fill=CYAN)
    d.text((x + 132, int(h * 0.50)), "v2/v3/v4 maps", font=load_font(27), fill=(196, 214, 232))
    d.text((x + 356, int(h * 0.50)), "MIT", font=load_font(27), fill=(196, 214, 232))
    return img.convert("RGB")


def main() -> int:
    make_icon(512).save(os.path.join(REPO, "icon.png"))
    make_icon(192).save(os.path.join(REPO, "icon_192.png"))
    fg = make_icon(300, badge=False)
    canvas = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    canvas.alpha_composite(fg, (66, 66))
    canvas.save(os.path.join(REPO, "icon_adaptive_fg_432.png"))
    Image.new("RGB", (432, 432), INK).save(os.path.join(REPO, "icon_adaptive_bg_432.png"))

    # The map-browser placeholder was the upstream logo; ours replaces it.
    make_icon(256).convert("RGBA").save(os.path.join(REPO, "game", "data", "beepsaber_logo.png"))
    print("wrote icons and placeholder")

    bg_dir = os.path.join(REPO, "game", "data", "background")
    make_background((2048, 1024), CYAN).save(os.path.join(bg_dir, "bg_base.png"))
    for key, tint in TINTS.items():
        make_background((600, 338), tint).save(os.path.join(bg_dir, f"bg_{key}.png"))
    print("wrote backgrounds")

    docs = os.path.join(REPO, "docs", "images")
    os.makedirs(docs, exist_ok=True)
    make_cover((1280, 640)).save(os.path.join(docs, "cover.png"))
    make_cover((630, 500)).save(os.path.join(docs, "itch-cover.png"))
    print("wrote covers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())





