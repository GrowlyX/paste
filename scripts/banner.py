#!/usr/bin/env python3
"""Renders docs/banner.svg: the app icon, the "paste" wordmark and a tagline,
above a screenshot of the shelf.

The wordmark is set in Macintosh Skeletal Filled and the tagline in SF Pro.
Both are converted to outlines, so the SVG needs no font at view time and
neither font file is redistributed.

usage: uv run --with fonttools scripts/banner.py \
         --skeletal assets/MacintoshSkeletalFilled.otf \
         [--sf /System/Library/Fonts/SFNS.ttf] [--shot docs/shelf.png] \
         [--icon docs/icon.png] [--out docs/banner.svg]
"""

import argparse
import base64
import struct

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

W, H = 1280, 640
BG = "#0f1116"
BLUE = "#1a5cf2"


def load(path, **axes):
    font = TTFont(path)
    if axes and "fvar" in font:
        font = instantiateVariableFont(font, axes)
    return font


def text_path(font, text, size, x, baseline, tracking=0.0):
    """Returns (svg path data, advance width, (ymin, ymax) above baseline) for text set in font."""
    scale = size / font["head"].unitsPerEm
    cmap, glyphs, hmtx = font.getBestCmap(), font.getGlyphSet(), font["hmtx"]
    pen, bounds = SVGPathPen(glyphs), BoundsPen(glyphs)
    cursor = x
    for ch in text:
        name = cmap[ord(ch)]
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, cursor, baseline)))
        glyphs[name].draw(TransformPen(bounds, (scale, 0, 0, scale, cursor, 0)))
        cursor += hmtx[name][0] * scale + tracking
    b = bounds.bounds or (0, 0, 0, 0)
    return pen.getCommands(), cursor - x, (b[1], b[3])


def png(path):
    with open(path, "rb") as f:
        data = f.read()
    w, h = struct.unpack(">II", data[16:24])
    return w, h, base64.b64encode(data).decode()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skeletal", required=True)
    ap.add_argument("--sf", default="/System/Library/Fonts/SFNS.ttf")
    ap.add_argument("--shot", default="docs/shelf.png")
    ap.add_argument("--icon", default="docs/icon.png")
    ap.add_argument("--out", default="docs/banner.svg")
    a = ap.parse_args()

    skeletal = load(a.skeletal)
    sf = load(a.sf, wght=500, opsz=28, wdth=100, GRAD=400)

    # Top row: icon, then the wordmark optically centred on it, tagline under both.
    left, top, icon = 88, 66, 128
    _, _, (lo, hi) = text_path(skeletal, "paste", 150, 0, 0)
    word_x = left + icon + 30
    word_base = top + icon / 2 + (hi + lo) / 2
    word, word_w, _ = text_path(skeletal, "paste", 150, word_x, word_base, tracking=-2)
    tag, _, _ = text_path(sf, "Everything you copy, one shortcut away.", 30, left + 2, top + icon + 62)

    # Bottom: the shelf, bleeding off the right and bottom edges.
    sw, sh, shot_b64 = png(a.shot)
    shot_w = 1420
    shot_h = round(shot_w * sh / sw)
    shot_x, shot_y = 56, H - shot_h + 26
    _, _, icon_b64 = png(a.icon)

    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{W}" height="{H}" viewBox="0 0 {W} {H}" role="img" aria-label="paste: everything you copy, one shortcut away">
  <defs>
    <clipPath id="card"><rect width="{W}" height="{H}" rx="28"/></clipPath>
    <radialGradient id="glow" cx="0.22" cy="0.05" r="0.9">
      <stop offset="0" stop-color="{BLUE}" stop-opacity="0.55"/>
      <stop offset="0.55" stop-color="{BLUE}" stop-opacity="0.08"/>
      <stop offset="1" stop-color="{BLUE}" stop-opacity="0"/>
    </radialGradient>
    <filter id="shadow" x="-10%" y="-30%" width="120%" height="160%">
      <feDropShadow dx="0" dy="16" stdDeviation="20" flood-color="#000" flood-opacity="0.55"/>
    </filter>
  </defs>
  <g clip-path="url(#card)">
    <rect width="{W}" height="{H}" fill="{BG}"/>
    <rect width="{W}" height="{H}" fill="url(#glow)"/>
    <image x="{left}" y="{top}" width="{icon}" height="{icon}" filter="url(#shadow)" xlink:href="data:image/png;base64,{icon_b64}"/>
    <path d="{word}" fill="#fff"/>
    <path d="{tag}" fill="#b4bac6"/>
    <image x="{shot_x}" y="{shot_y}" width="{shot_w}" height="{shot_h}" filter="url(#shadow)" preserveAspectRatio="xMinYMin meet" xlink:href="data:image/png;base64,{shot_b64}"/>
  </g>
</svg>
"""
    with open(a.out, "w") as f:
        f.write(svg)
    print(f"wrote {a.out} ({len(svg) // 1024} KB)")


if __name__ == "__main__":
    main()
