#!/usr/bin/env python3
"""Build the OpenSaberQ3 brand SVGs.

The artwork is original vector geometry written for this project. Text is converted to paths with
Roboto Medium (Apache-2.0) so the SVGs render identically in a browser and in Godot's ThorVG
importer. Run this file, then render the PNGs with:

    godot --headless --path . -s res://tools/brand/render_brand.gd

The generated files are committed; this script exists so the marks can be regenerated and audited.
"""

from pathlib import Path
from math import cos, sin, radians

from matplotlib.font_manager import FontProperties
from matplotlib.textpath import TextPath

ROOT = Path(__file__).resolve().parent
FONT = ROOT.parents[1] / "OQ_Toolkit/OQ_UI2D/theme/Roboto-Medium.ttf"

NAVY_IN = "#0E1A2B"
NAVY_OUT = "#050A12"
CYAN = "#31D7F5"
ORANGE = "#FFA53A"
RED = "#E8364F"
BLUE = "#2F7BFF"
WHITE = "#F4F8FF"
MUTED = "#BFCEE0"

CENTER = (256.0, 256.0)
ANGLE = radians(35.0)
U = (cos(ANGLE), -sin(ANGLE))          # bottom-left -> top-right, SVG y down
N = (sin(ANGLE), cos(ANGLE))           # perpendicular, down-right
CUBE = (131.0, 131.0, 250.0, 250.0, 40.0)  # x, y, w, h, r


def font_props() -> FontProperties:
    return FontProperties(fname=str(FONT))


def text_width(text: str, size: float) -> float:
    return TextPath((0, 0), text, size=size, prop=font_props()).get_extents().x1


def text_path(text: str, size: float, x: float, y: float, fill: str) -> str:
    """Roboto text as an SVG path, baseline at (x, y), SVG coordinates."""
    tp = TextPath((0, 0), text, size=size, prop=font_props())
    verts, codes = tp.vertices, tp.codes
    parts = []
    i = 0
    while i < len(verts):
        c = codes[i]
        if c == 1:
            parts.append("M%.2f %.2f" % (x + verts[i][0], y - verts[i][1]))
            i += 1
        elif c == 2:
            parts.append("L%.2f %.2f" % (x + verts[i][0], y - verts[i][1]))
            i += 1
        elif c == 3:
            parts.append("Q%.2f %.2f %.2f %.2f" % (
                x + verts[i][0], y - verts[i][1],
                x + verts[i + 1][0], y - verts[i + 1][1]))
            i += 2
        elif c == 4:
            parts.append("C%.2f %.2f %.2f %.2f %.2f %.2f" % (
                x + verts[i][0], y - verts[i][1],
                x + verts[i + 1][0], y - verts[i + 1][1],
                x + verts[i + 2][0], y - verts[i + 2][1]))
            i += 3
        elif c == 79:
            parts.append("Z")
            i += 1
        else:
            i += 1
    return '<path d="%s" fill="%s"/>' % (" ".join(parts), fill)


def point(base, direction, distance):
    return (base[0] + direction[0] * distance, base[1] + direction[1] * distance)


def fmt(p):
    return "%.2f,%.2f" % p


def cut_polygon(center, normal_sign: int, along: float, gap: float) -> str:
    """Half-plane polygon on the `normal_sign` side of the cut line."""
    p = (center[0] + U[0] * along + N[0] * gap * normal_sign,
         center[1] + U[1] * along + N[1] * gap * normal_sign)
    a = point(p, U, 700)
    b = point(p, U, -700)
    off = (N[0] * 700 * normal_sign, N[1] * 700 * normal_sign)
    return " ".join([fmt(a), fmt(b), fmt((b[0] + off[0], b[1] + off[1])),
                     fmt((a[0] + off[0], a[1] + off[1]))])


def floor_grid(width: int, height: int, top: float, vp_x: float, opacity: float,
               color: str = CYAN) -> str:
    parts = []
    for x in range(-600, width + 601, 120):
        parts.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%d" stroke="%s" stroke-width="1.4" opacity="%.2f"/>'
                     % (vp_x, top, x, height, color, opacity))
    y = top + 30
    step = 34
    while y < height:
        parts.append('<line x1="0" y1="%.1f" x2="%d" y2="%.1f" stroke="%s" stroke-width="1.4" opacity="%.2f"/>'
                     % (y, width, y, color, opacity))
        step *= 1.35
        y += step
    return "\n".join(parts)


def sliced_cube(mark: str, cx: float, cy: float, size: float, small: bool, with_glow: bool,
                tile: bool = True) -> str:
    """The mark inside a 512 canvas: optional background tile, cube, blade, hilt."""
    x, y, w, h, r = CUBE
    gap = 13.0
    along = 8.0
    blade_len = 230.0
    blade_center = point(CENTER, U, 4.0)

    defs = []
    defs.append('<clipPath id="red%s"><polygon points="%s"/></clipPath>'
                % (mark, cut_polygon(CENTER, -1, -along, gap)))
    defs.append('<clipPath id="blue%s"><polygon points="%s"/></clipPath>'
                % (mark, cut_polygon(CENTER, 1, along, gap)))
    if tile:
        defs.insert(0, '<radialGradient id="bg%s" cx="50%%" cy="42%%" r="72%%">'
                       '<stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/>'
                       '</radialGradient>' % (mark, NAVY_IN, NAVY_OUT))
        defs.insert(1, '<clipPath id="tile%s"><rect x="0" y="0" width="512" height="512" rx="112"/>'
                       '</clipPath>' % mark)
    out = ["<defs>", "\n".join(defs), "</defs>"]
    if tile:
        out.append('<g clip-path="url(#tile%s)">' % mark)
        out.append('<rect width="512" height="512" fill="url(#bg%s)"/>' % mark)
        if not small:
            out.append(floor_grid(512, 512, 350, 256, 0.10))
    # Halves of the cube, clipped by their own cut lines.
    out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%.1f" fill="%s" clip-path="url(#red%s)"/>'
               % (x, y, w, h, r, RED, mark))
    out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%.1f" fill="%s" clip-path="url(#blue%s)"/>'
               % (x, y, w, h, r, BLUE, mark))
    start = point(blade_center, U, -blade_len)
    end = point(blade_center, U, blade_len)
    if with_glow:
        out.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="30" '
                   'stroke-linecap="round" opacity="0.06"/>' % (start[0], start[1], end[0], end[1], CYAN))
        out.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="18" '
                   'stroke-linecap="round" opacity="0.12"/>' % (start[0], start[1], end[0], end[1], CYAN))
    # Hilt at the lower-left end, then the blade, so the cyan cleanly leaves the orange.
    hilt_end = point(start, U, 46)
    out.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="18" '
               'stroke-linecap="round"/>' % (start[0], start[1], hilt_end[0], hilt_end[1], ORANGE))
    out.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="11" '
               'stroke-linecap="round"/>' % (hilt_end[0], hilt_end[1], end[0], end[1], CYAN))
    if tile:
        out.append("</g>")
    return "\n".join(out)


def logo_svg(small: bool = False) -> str:
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">\n'
            + sliced_cube("s" if small else "l", 0, 0, 512, small, True) + "\n</svg>\n")


def adaptive_svg(background: bool) -> str:
    if background:
        body = ['<rect width="432" height="432" fill="url(#abg)"/>']
        defs = ('<defs><radialGradient id="abg" cx="50%%" cy="42%%" r="72%%">'
                '<stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></radialGradient></defs>'
                % (NAVY_IN, NAVY_OUT))
        return ('<svg xmlns="http://www.w3.org/2000/svg" width="432" height="432" viewBox="0 0 432 432">\n'
                + defs + "\n" + "\n".join(body) + "\n</svg>\n")
    # Foreground: cube, blade and hilt, fitted to Android's 264 px safe circle.
    inner = sliced_cube("f", 0, 0, 512, True, False, tile=False)
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="432" height="432" viewBox="0 0 432 432">\n'
            '<g transform="translate(216 216) scale(0.70) translate(-256 -262)">\n%s\n</g>\n</svg>\n'
            % inner)


def name_paths(x: float, baseline: float, size: float) -> str:
    first = "OpenSaber"
    return (text_path(first, size, x, baseline, WHITE)
            + text_path("Q3", size, x + text_width(first, size), baseline, CYAN))


BANNER_W, BANNER_H = 1280, 640


def banner_svg() -> str:
    logo_scale = 340.0 / 512.0
    logo = sliced_cube("b", 0, 0, 512, False, True)
    # The banner embeds the tile with its own gradient ids; prefix avoids collisions.
    logo = logo.replace('id="bgb"', 'id="bannerbg"').replace('url(#bgb)', 'url(#bannerbg)')
    logo = logo.replace('id="tileb"', 'id="bannertile"').replace('url(#tileb)', 'url(#bannertile)')
    logo = logo.replace('id="redb"', 'id="bannerred"').replace('url(#redb)', 'url(#bannerred)')
    logo = logo.replace('id="blueb"', 'id="bannerblue"').replace('url(#blueb)', 'url(#bannerblue)')

    x_name, name_size = 460.0, 96.0
    tagline = "Open-source rhythm game for Meta Quest 3"
    chips = ["BeatSaver maps v2\u00b7v3\u00b7v4", "120 Hz", "Free \u00b7 GPLv3"]
    chip_size = 26.0
    chip_y, chip_h, chip_pad, chip_gap = 386.0, 44.0, 18.0, 12.0
    widths = [text_width(c, chip_size) + chip_pad * 2 for c in chips]
    if sum(widths) + chip_gap * 2 > 760:
        chip_size = 23.0
        widths = [text_width(c, chip_size) + chip_pad * 2 for c in chips]
    chip_parts = []
    cx = x_name
    for text, w in zip(chips, widths):
        chip_parts.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%.1f" '
                          'fill="%s" fill-opacity="0.06" stroke="%s" stroke-opacity="0.35"/>'
                          % (cx, chip_y, w, chip_h, chip_h / 2, CYAN, CYAN))
        chip_parts.append(text_path(text, chip_size, cx + chip_pad, chip_y + 29, CYAN))
        cx += w + chip_gap

    cubes = []
    for (ccx, ccy, cs, sliced) in ((1168, 352, 40, False), (1100, 432, 60, False), (1012, 520, 90, True)):
        cubes.append(note(ccx, ccy, cs, sliced, "c%d" % len(cubes)))

    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{BANNER_W}" height="{BANNER_H}" viewBox="0 0 {BANNER_W} {BANNER_H}">
<defs>
  <linearGradient id="bbg" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#07101E"/><stop offset="1" stop-color="#040810"/>
  </linearGradient>
  <radialGradient id="bglow" cx="34%" cy="48%" r="42%">
    <stop offset="0" stop-color="{CYAN}" stop-opacity="0.09"/>
    <stop offset="1" stop-color="{CYAN}" stop-opacity="0"/>
  </radialGradient>
</defs>
<rect width="{BANNER_W}" height="{BANNER_H}" fill="url(#bbg)"/>
<rect width="{BANNER_W}" height="{BANNER_H}" fill="url(#bglow)"/>
{floor_grid(BANNER_W, BANNER_H, 360, 640, 0.07)}
{''.join(cubes)}
<g transform="translate(64 150) scale({logo_scale:.6f})">
{logo}
</g>
{name_paths(x_name, 282, name_size)}
{text_path(tagline, 34, x_name + 2, 334, MUTED)}
{''.join(chip_parts)}
</svg>
'''


def note(cx: float, cy: float, size: float, sliced: bool, ident: str) -> str:
    x, y = cx - size / 2, cy - size / 2
    r = size * 0.16
    color = RED if sliced else (BLUE if size > 50 else RED)
    if not sliced:
        return ('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%.1f" fill="%s" '
                'opacity="0.30" transform="rotate(-8 %.1f %.1f)"/>'
                % (x, y, size, size, r, color, cx, cy))
    u = (cos(radians(32)), -sin(radians(32)))
    n = (sin(radians(32)), cos(radians(32)))
    gap = size * 0.14
    def poly(sign):
        p = (cx + n[0] * gap * sign, cy + n[1] * gap * sign)
        a = (p[0] - u[0] * 500, p[1] - u[1] * 500)
        b = (p[0] + u[0] * 500, p[1] + u[1] * 500)
        off = (n[0] * 500 * sign, n[1] * 500 * sign)
        return " ".join([fmt(a), fmt(b), fmt((b[0] + off[0], b[1] + off[1])),
                         fmt((a[0] + off[0], a[1] + off[1]))])
    start = (cx - u[0] * size * 0.8, cy - u[1] * size * 0.8)
    end = (cx + u[0] * size * 0.8, cy + u[1] * size * 0.8)
    return ('<defs><clipPath id="nr{ident}"><polygon points="{pread}"/></clipPath>'
            '<clipPath id="nb{ident}"><polygon points="{pblue}"/></clipPath></defs>'
            '<rect x="{x:.1f}" y="{y:.1f}" width="{size:.1f}" height="{size:.1f}" rx="{r:.1f}" '
            'fill="{red}" opacity="0.35" clip-path="url(#nr{ident})"/>'
            '<rect x="{x:.1f}" y="{y:.1f}" width="{size:.1f}" height="{size:.1f}" rx="{r:.1f}" '
            'fill="{blue}" opacity="0.35" clip-path="url(#nb{ident})"/>'
            '<line x1="{sx:.1f}" y1="{sy:.1f}" x2="{ex:.1f}" y2="{ey:.1f}" '
            'stroke="{cyan}" stroke-width="3" stroke-linecap="round" opacity="0.55"/>').format(
                ident=ident, pread=poly(-1), pblue=poly(1),
                x=x, y=y, size=size, r=r, red=RED, blue=BLUE, cyan=CYAN,
                sx=start[0], sy=start[1], ex=end[0], ey=end[1])


def itch_cover_svg() -> str:
    logo_scale = 230.0 / 512.0
    logo = sliced_cube("i", 0, 0, 512, False, True)
    for src, dst in (("bgi", "ibg2"), ("tilei", "itile"), ("redi", "ired"), ("bluei", "iblue")):
        logo = logo.replace('id="%s"' % src, 'id="%s"' % dst).replace("url(#%s)" % src, "url(#%s)" % dst)
    name = "OpenSaberQ3"
    name_size = 64.0
    name_x = (630 - text_width(name, name_size)) / 2
    tagline = "Rhythm game for Quest 3"
    tag_size = 28.0
    tag_x = (630 - text_width(tagline, tag_size)) / 2
    small = "Free \u00b7 GPLv3 \u00b7 Open source"
    small_size = 25.0
    small_x = (630 - text_width(small, small_size)) / 2
    name_path = text_path("OpenSaber", name_size, name_x, 356, WHITE)
    name_path += text_path("Q3", name_size, name_x + text_width("OpenSaber", name_size), 356, CYAN)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="630" height="500" viewBox="0 0 630 500">
<defs>
  <linearGradient id="ibg" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#07101E"/><stop offset="1" stop-color="#040810"/>
  </linearGradient>
</defs>
<rect width="630" height="500" fill="url(#ibg)"/>
{floor_grid(630, 500, 300, 315, 0.06)}
<g transform="translate(200 42) scale({logo_scale:.6f})">
{logo}
</g>
{name_path}
{text_path(tagline, tag_size, tag_x, 404, MUTED)}
{text_path(small, small_size, small_x, 446, CYAN)}
</svg>
'''


def wordmark_svg(stacked: bool) -> str:
    if stacked:
        logo_scale = 260.0 / 512.0
        logo = sliced_cube("ws", 0, 0, 512, False, True)
        for src, dst in (("bgws", "wsbg"), ("tilews", "wstile"), ("redws", "wsred"), ("bluews", "wsblue")):
            logo = logo.replace('id="%s"' % src, 'id="%s"' % dst).replace("url(#%s)" % src, "url(#%s)" % dst)
        name, size = "OpenSaberQ3", 64.0
        nx = (600 - text_width(name, size)) / 2
        sub, sub_size = "Quest 3 rhythm game", 26.0
        sx = (600 - text_width(sub, sub_size)) / 2
        return f'''<svg xmlns="http://www.w3.org/2000/svg" width="600" height="600" viewBox="0 0 600 600">
<rect width="600" height="600" rx="28" fill="#07101E"/>
<g transform="translate(170 50) scale({logo_scale:.6f})">
{logo}
</g>
{text_path("OpenSaber", size, nx, 412, WHITE)}
{text_path("Q3", size, nx + text_width("OpenSaber", size), 412, CYAN)}
{text_path(sub, sub_size, sx, 458, MUTED)}
</svg>
'''
    logo_scale = 220.0 / 512.0
    logo = sliced_cube("wh", 0, 0, 512, False, True)
    for src, dst in (("bgwh", "whbg"), ("tilewh", "whtile"), ("redwh", "whred"), ("bluewh", "whblue")):
        logo = logo.replace('id="%s"' % src, 'id="%s"' % dst).replace("url(#%s)" % src, "url(#%s)" % dst)
    name, size = "OpenSaberQ3", 96.0
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="320" viewBox="0 0 1200 320">
<rect width="1200" height="320" rx="28" fill="#07101E"/>
<g transform="translate(175 50) scale({logo_scale:.6f})">
{logo}
</g>
{text_path("OpenSaber", size, 435, 178, WHITE)}
{text_path("Q3", size, 435 + text_width("OpenSaber", size), 178, CYAN)}
{text_path("Quest 3 rhythm game", 36, 437, 238, MUTED)}
</svg>
'''


def main() -> None:
    (ROOT / "logo.svg").write_text(logo_svg(False), encoding="utf-8")
    (ROOT / "logo-small.svg").write_text(logo_svg(True), encoding="utf-8")
    (ROOT / "icon-adaptive-fg.svg").write_text(adaptive_svg(False), encoding="utf-8")
    (ROOT / "icon-adaptive-bg.svg").write_text(adaptive_svg(True), encoding="utf-8")
    (ROOT / "banner.svg").write_text(banner_svg(), encoding="utf-8")
    (ROOT / "itch-cover.svg").write_text(itch_cover_svg(), encoding="utf-8")
    (ROOT / "wordmark-horizontal.svg").write_text(wordmark_svg(False), encoding="utf-8")
    (ROOT / "wordmark-stacked.svg").write_text(wordmark_svg(True), encoding="utf-8")
    print("brand SVGs written to", ROOT)


if __name__ == "__main__":
    main()
