#!/usr/bin/env python3
"""Generate a static grass field SVG matching Signal's GrassBlade animation
(at rest: growth=1, sway=0). Same palette, depth model, tapered quad-curve
blade shape, and far-to-near draw order."""
import random, math, sys

random.seed(7)  # reproducible

W = H = 1024

# Palette from GrassBlade.palette (RGB 0..1 -> hex), dark base -> bright tip.
palette = [
    (0.16, 0.46, 0.18),
    (0.22, 0.55, 0.22),
    (0.30, 0.64, 0.26),
    (0.40, 0.72, 0.30),
    (0.50, 0.80, 0.36),
]
def hexc(c):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(x*255))) for x in c)

BLADES = 90

blades = []
for _ in range(BLADES):
    depth = random.random()
    # Tuned so tallest blades just kiss the bottom of the S (~y=620) and most
    # sit lower; full-bleed roots at the bottom edge.
    height = (150 + 280*depth) * random.uniform(0.85, 1.15)
    width = 15 + 22*depth
    bend = random.uniform(-60, 60) * (0.4 + 0.6*depth)
    shade = palette[min(len(palette)-1, int(depth*len(palette)))]
    blades.append(dict(
        baseX=random.uniform(-0.02, 1.02),
        height=height, width=width, bend=bend,
        shade=shade, depth=depth,
    ))

# far (short) first so taller/brighter overlap in front
blades.sort(key=lambda b: b["height"])

# One vertical gradient per palette shade: darker (0.65 a) at root -> full at tip.
defs = []
for i, c in enumerate(palette):
    defs.append(
        f'<linearGradient id="g{i}" x1="0" y1="1" x2="0" y2="0">'
        f'<stop offset="0" stop-color="{hexc(c)}" stop-opacity="0.65"/>'
        f'<stop offset="1" stop-color="{hexc(c)}" stop-opacity="1"/>'
        f'</linearGradient>'
    )

paths = []
for b in blades:
    baseY = H
    bx = b["baseX"] * W
    h = b["height"]
    half = b["width"] / 2
    tipX = bx + b["bend"]
    tipY = baseY - h
    gi = palette.index(b["shade"])
    d = (
        f'M {bx-half:.1f} {baseY:.1f} '
        f'Q {bx-half + (tipX-bx)*0.5:.1f} {baseY - h*0.6:.1f} {tipX:.1f} {tipY:.1f} '
        f'Q {bx+half + (tipX-bx)*0.5:.1f} {baseY - h*0.5:.1f} {bx+half:.1f} {baseY:.1f} Z'
    )
    paths.append(f'<path d="{d}" fill="url(#g{gi})"/>')

svg = (
    f'<svg viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg">\n'
    f'<defs>\n' + "\n".join(defs) + "\n</defs>\n"
    + "\n".join(paths) + "\n</svg>\n"
)
sys.stdout.write(svg)
