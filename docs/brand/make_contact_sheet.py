#!/usr/bin/env python3
"""Build docs/brand/contact-sheet.png from the rendered icon exports.

Requires Pillow. Run after tools/brand/render_brand.gd.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONT = ROOT / "OQ_Toolkit/OQ_UI2D/theme/Roboto-Medium.ttf"
OUT = ROOT / "docs/brand/contact-sheet.png"

BG = (10, 15, 24)
CARD = (16, 24, 38)
WHITE = (244, 248, 255)
MUTED = (170, 186, 205)
CYAN = (49, 215, 245)


def font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT), size)


def label(draw, xy, text, size=18, fill=MUTED):
    draw.text(xy, text, font=font(size), fill=fill)


def rounded_mask(size: int, radius: float) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def main() -> None:
    w, h = 1400, 1140
    sheet = Image.new("RGB", (w, h), BG)
    d = ImageDraw.Draw(sheet)
    d.text((60, 42), "OpenSaberQ3 — brand assets", font=font(38), fill=WHITE)
    d.text((60, 90), "AI-generated vector artwork · sources and render script in docs/brand",
           font=font(19), fill=MUTED)

    icon = Image.open(ROOT / "icon.png").convert("RGBA")
    icon192 = Image.open(ROOT / "icon_192.png").convert("RGBA")
    banner = Image.open(ROOT / "docs/images/banner.png").convert("RGB")
    cover = Image.open(ROOT / "docs/images/itch-cover.png").convert("RGB")
    fg = Image.open(ROOT / "icon_adaptive_fg_432.png").convert("RGBA")
    bg = Image.open(ROOT / "icon_adaptive_bg_432.png").convert("RGBA")
    adaptive = Image.alpha_composite(bg, fg)

    # Row 1: icon at its real sizes.
    sheet.paste(icon, (60, 140), icon)
    label(d, (60, 660), "512 px app icon")
    sheet.paste(icon192, (700, 140), icon192)
    label(d, (700, 344), "192 px")
    small48 = icon.resize((48, 48), Image.LANCZOS)
    small32 = icon.resize((32, 32), Image.LANCZOS)
    sheet.paste(small48, (960, 150), small48)
    label(d, (960, 208), "48 px")
    sheet.paste(small32, (960, 260), small32)
    label(d, (960, 300), "32 px")
    zoom48 = small48.resize((192, 192), Image.NEAREST)
    sheet.paste(zoom48, (1040, 140))
    label(d, (1040, 344), "48 px, 4× nearest")

    # Row 2: adaptive masks.
    circle = Image.new("L", (200, 200), 0)
    ImageDraw.Draw(circle).ellipse((0, 0, 199, 199), fill=255)
    squircle = rounded_mask(200, 56)
    ac = adaptive.resize((200, 200), Image.LANCZOS)
    card = Image.new("RGB", (200, 200), CARD)
    card.paste(ac, (0, 0), circle)
    sheet.paste(card, (700, 400))
    label(d, (700, 610), "Adaptive icon, circle mask")
    card2 = Image.new("RGB", (200, 200), CARD)
    card2.paste(ac, (0, 0), squircle)
    sheet.paste(card2, (960, 400))
    label(d, (960, 610), "Adaptive icon, squircle mask")

    # Row 3: banner, cover, wordmark.
    sheet.paste(banner.resize((640, 320), Image.LANCZOS), (60, 700))
    label(d, (60, 1026), "Banner 1280×640 (shown 640×320)")
    sheet.paste(cover.resize((315, 250), Image.LANCZOS), (760, 700))
    label(d, (760, 956), "itch cover 630×500 (shown 315×250)")
    word = Image.open(ROOT / "docs/brand/wordmark-horizontal.png").convert("RGB")
    sheet.paste(word.resize((420, 112), Image.LANCZOS), (760, 980))
    label(d, (760, 1096), "Wordmark", size=16)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT, optimize=True)
    print("wrote", OUT, sheet.size)


if __name__ == "__main__":
    main()
