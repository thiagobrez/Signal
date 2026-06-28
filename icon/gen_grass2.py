#!/usr/bin/env python3
"""Grass field v2: thicker blades with BLUNT rounded tips (so they don't look
razor-sharp / pixelated at small icon sizes), and SOLID dark->light vertical
gradient per blade (works on light OR dark backgrounds, unlike the old
opacity-based shading). Same palette / depth model / draw-order as GrassBlade."""
import random, math, sys

random.seed(11)
W = H = 1024

palette = [
    (0.16, 0.46, 0.18),
    (0.22, 0.55, 0.22),
    (0.30, 0.64, 0.26),
    (0.40, 0.72, 0.30),
    (0.50, 0.80, 0.36),
]
def hexc(c):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(x*255))) for x in c)
def darker(c, f=0.6):
    return tuple(x*f for x in c)

BLADES = 70

blades = []
for _ in range(BLADES):
    depth = random.random()
    # Sit at the bottom; tallest few just kiss the notch's rounded base.
    height = (150 + 200*depth) * random.uniform(0.85, 1.15)
    width = 24 + 30*depth          # thicker than v1 (was 15+22)
    bend = random.uniform(-55, 55) * (0.4 + 0.6*depth)
    shade = palette[min(len(palette)-1, int(depth*len(palette)))]
    blades.append(dict(baseX=random.uniform(-0.02, 1.02), height=height,
                       width=width, bend=bend, shade=shade))

blades.sort(key=lambda b: b["height"])  # far/short first

defs = []
for i, c in enumerate(palette):
    defs.append(
        f'<linearGradient id="g{i}" x1="0" y1="1" x2="0" y2="0">'
        f'<stop offset="0" stop-color="{hexc(darker(c))}"/>'
        f'<stop offset="1" stop-color="{hexc(c)}"/>'
        f'</linearGradient>')

paths = []
for b in blades:
    baseY = H
    bx = b["baseX"] * W
    h = b["height"]
    half = b["width"]/2
    tipX = bx + b["bend"]
    tipY = baseY - h
    tipHalf = max(5.0, b["width"]*0.24)   # blunt tip half-width
    gi = palette.index(b["shade"])
    cL = (bx - half + (tipX-bx)*0.45, baseY - h*0.60)
    cR = (bx + half + (tipX-bx)*0.55, baseY - h*0.50)
    d = (f'M {bx-half:.1f} {baseY:.1f} '
         f'Q {cL[0]:.1f} {cL[1]:.1f} {tipX-tipHalf:.1f} {tipY:.1f} '          # left edge to left of tip
         f'Q {tipX:.1f} {tipY-tipHalf*0.9:.1f} {tipX+tipHalf:.1f} {tipY:.1f} '# rounded blunt cap
         f'Q {cR[0]:.1f} {cR[1]:.1f} {bx+half:.1f} {baseY:.1f} Z')            # right edge down
    paths.append(f'<path d="{d}" fill="url(#g{gi})"/>')

svg = (f'<svg viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg">\n'
       f'<defs>\n' + "\n".join(defs) + "\n</defs>\n"
       + "\n".join(paths) + "\n</svg>\n")
sys.stdout.write(svg)
