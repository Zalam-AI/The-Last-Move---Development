#!/usr/bin/env python3
"""Bake the surface texture set for THE LAST MOVE.

Everything here is generated from scratch with numpy: no third-party art, no scanned
materials, nothing with unclear licensing. Each surface produces an albedo (greyscale-ish
detail that gets tinted by vertex colour in the shader) and a normal map derived from a
height field by Sobel filtering.

Surfaces are tileable: noise is generated in frequency space or with wrapped lattices so the
seams do not show when the shader repeats them triplanar over world space.

    python3 tools/generate_textures.py            # writes assets/textures/*.png
    python3 tools/generate_textures.py --list     # what it would write
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

SIZE = 512
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "textures")
RNG = np.random.default_rng(20261109)


# ------------------------------------------------------------------ noise ---

def periodic_noise(size, cells, octaves=4, persistence=0.5, seed=0):
    """Tileable value noise: a lattice of `cells` samples wrapped in both axes."""
    rng = np.random.default_rng(seed)
    total = np.zeros((size, size), dtype=np.float32)
    amp = 1.0
    norm = 0.0
    c = cells
    for _ in range(octaves):
        if c < 2:
            break
        lattice = rng.random((c, c)).astype(np.float32)
        # bilinear upsample with wrap
        ys = np.linspace(0, c, size, endpoint=False, dtype=np.float32)
        xs = np.linspace(0, c, size, endpoint=False, dtype=np.float32)
        y0 = np.floor(ys).astype(np.int32)
        x0 = np.floor(xs).astype(np.int32)
        fy = (ys - y0)[:, None]
        fx = (xs - x0)[None, :]
        fy = fy * fy * (3 - 2 * fy)
        fx = fx * fx * (3 - 2 * fx)
        y1 = (y0 + 1) % c
        x1 = (x0 + 1) % c
        a = lattice[np.ix_(y0, x0)]
        b = lattice[np.ix_(y0, x1)]
        cc = lattice[np.ix_(y1, x0)]
        d = lattice[np.ix_(y1, x1)]
        layer = (a * (1 - fx) + b * fx) * (1 - fy) + (cc * (1 - fx) + d * fx) * fy
        total += layer * amp
        norm += amp
        amp *= persistence
        c *= 2
    return total / max(norm, 1e-6)


def fbm(size=SIZE, cells=6, octaves=5, seed=1):
    return periodic_noise(size, cells, octaves, 0.55, seed)


def normal_from_height(height, strength=2.0):
    """Sobel-ish normals with wrapped edges so the tile stays seamless."""
    h = height.astype(np.float32)
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * strength
    nz = np.ones_like(h)
    length = np.sqrt(dx * dx + dy * dy + nz * nz)
    nx = -dx / length
    ny = -dy / length
    nzv = nz / length
    rgb = np.stack([nx * 0.5 + 0.5, ny * 0.5 + 0.5, nzv * 0.5 + 0.5], axis=-1)
    return (np.clip(rgb, 0, 1) * 255).astype(np.uint8)


def save(name, arr):
    path = os.path.join(OUT, name + ".png")
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    img.save(path, optimize=True)
    return path


def grey(v):
    v = np.clip(v, 0, 1)
    return (v * 255).astype(np.uint8)


# --------------------------------------------------------------- surfaces ---

def plaster():
    base = fbm(SIZE, 8, 5, 11)
    fine = fbm(SIZE, 64, 3, 12)
    speck = (RNG.random((SIZE, SIZE)) > 0.995).astype(np.float32)
    h = base * 0.55 + fine * 0.2 + speck * 0.15
    v = 0.72 + base * 0.16 + fine * 0.08 - speck * 0.25
    return grey(v), normal_from_height(h, 1.6)


def paint():
    """Rolled interior emulsion: very fine orange-peel texture, faint brush drag, no pattern.

    Kept almost flat so walls read as clean painted plaster instead of noisy geometry, but with
    enough tooth that a raking light shows the roll marks.
    """
    peel = fbm(SIZE, 96, 2, 31)
    drag = fbm(SIZE, 3, 2, 32)
    fine = fbm(SIZE, 160, 2, 33)
    h = peel * 0.5 + fine * 0.3
    v = 0.82 + peel * 0.06 + fine * 0.05 + (drag - 0.5) * 0.05
    return grey(v), normal_from_height(h, 0.7)


def wallpaper():
    x = np.arange(SIZE)[None, :] / SIZE
    stripes = 0.5 + 0.5 * np.sign(np.sin(x * np.pi * 14))
    damask = fbm(SIZE, 24, 4, 21)
    damask = np.abs(np.sin(damask * 18.0)) ** 3
    v = 0.70 + stripes * 0.05 + damask * 0.12
    h = stripes * 0.25 + damask * 0.5
    return grey(v), normal_from_height(h, 1.2)


def wood_floor():
    y = np.arange(SIZE)[:, None] / SIZE
    x = np.arange(SIZE)[None, :] / SIZE
    plank = np.floor(y * 7.0)
    plank_off = (plank % 2) * 0.37
    seam_y = ((y * 7.0) % 1.0 < 0.035).astype(np.float32)
    seam_x = (((x + plank_off) * 3.0) % 1.0 < 0.006).astype(np.float32)
    grain = fbm(SIZE, 4, 5, 31)
    grain = 0.5 + 0.5 * np.sin((y * 70.0 + grain * 5.0))
    grain = grain * (0.55 + 0.45 * fbm(SIZE, 6, 3, 33))
    v = 0.68 + grain * 0.10 + (plank % 3) * 0.02
    v = v * (1.0 - seam_y * 0.55) * (1.0 - seam_x * 0.4)
    h = grain * 0.5 - seam_y * 0.9 - seam_x * 0.5
    return grey(v), normal_from_height(h, 2.2)


def wood_dark():
    y = np.arange(SIZE)[:, None] / SIZE
    warp = fbm(SIZE, 5, 4, 43)
    grain = fbm(SIZE, 4, 5, 41)
    streak = 0.5 + 0.5 * np.sin((y * 46.0 + grain * 5.0 + warp * 9.0))
    blotch = fbm(SIZE, 7, 4, 44)
    knots = (fbm(SIZE, 12, 3, 42) > 0.8).astype(np.float32)
    v = 0.62 + streak * 0.10 + blotch * 0.20 + knots * 0.10
    h = streak * 0.5 + blotch * 0.6 + knots * 0.8
    return grey(v), normal_from_height(h, 1.8)


def fabric():
    x = np.arange(SIZE)[None, :] / SIZE
    y = np.arange(SIZE)[:, None] / SIZE
    warp_t = 0.5 + 0.5 * np.sin(x * np.pi * 150)
    weft_t = 0.5 + 0.5 * np.sin(y * np.pi * 150)
    weave = np.maximum(warp_t, weft_t) * 0.6 + warp_t * weft_t * 0.4
    slub = fbm(SIZE, 70, 3, 51)
    v = 0.58 + weave * 0.3 + slub * 0.18
    h = weave * 0.7 + slub * 0.3
    return grey(v), normal_from_height(h, 2.6)


def carpet():
    pile = fbm(SIZE, 96, 4, 61)
    coarse = fbm(SIZE, 16, 3, 62)
    v = 0.58 + pile * 0.3 + coarse * 0.1
    return grey(v), normal_from_height(pile * 1.2 + coarse * 0.4, 2.4)


def metal_brushed():
    x = np.arange(SIZE)[None, :] / SIZE
    streak = fbm(SIZE, 128, 4, 71)
    lines = 0.5 + 0.5 * np.sin(x * np.pi * 900 + streak * 40)
    v = 0.72 + lines * 0.12 + streak * 0.1
    h = lines * 0.25 + streak * 0.2
    return grey(v), normal_from_height(h, 1.4)


def tile():
    x = np.arange(SIZE)[None, :] / SIZE
    y = np.arange(SIZE)[:, None] / SIZE
    gx = ((x * 8.0) % 1.0 < 0.04).astype(np.float32)
    gy = ((y * 8.0) % 1.0 < 0.04).astype(np.float32)
    grout = np.maximum(gx, gy)
    grit = fbm(SIZE, 40, 4, 81)
    v = (0.78 + grit * 0.12) * (1.0 - grout * 0.45)
    h = -grout * 0.8 + grit * 0.15
    return grey(v), normal_from_height(h, 2.0)


def brick():
    y = np.arange(SIZE)[:, None] / SIZE
    x = np.arange(SIZE)[None, :] / SIZE
    rows = 12.0
    row = np.floor(y * rows)
    off = (row % 2) * 0.5
    mortar_y = ((y * rows) % 1.0 < 0.09).astype(np.float32)
    mortar_x = (((x + off) * 5.0) % 1.0 < 0.045).astype(np.float32)
    mortar = np.maximum(mortar_y, mortar_x)
    grit = fbm(SIZE, 48, 4, 91)
    tone = fbm(SIZE, 8, 3, 92)
    v = 0.5 + tone * 0.3 + grit * 0.1
    v = np.where(mortar > 0.5, 0.72 + grit * 0.08, v)
    h = -mortar * 1.0 + grit * 0.12
    return grey(v), normal_from_height(h, 2.4)


def concrete():
    base = fbm(SIZE, 10, 5, 101)
    pits = (fbm(SIZE, 70, 3, 102) > 0.72).astype(np.float32)
    v = 0.66 + base * 0.2 - pits * 0.12
    h = base * 0.5 - pits * 0.4
    return grey(v), normal_from_height(h, 1.6)


def ground_dirt():
    base = fbm(SIZE, 8, 5, 111)
    pebbles = (fbm(SIZE, 60, 2, 112) > 0.8).astype(np.float32)
    v = 0.45 + base * 0.3 + pebbles * 0.15
    h = base * 0.6 + pebbles * 0.8
    return grey(v), normal_from_height(h, 2.0)


def grass():
    blades = fbm(SIZE, 120, 3, 121)
    clumps = fbm(SIZE, 20, 4, 122)
    v = 0.42 + blades * 0.35 + clumps * 0.15
    h = blades * 0.8 + clumps * 0.3
    return grey(v), normal_from_height(h, 2.2)


def grime():
    """A multiply/overlay map: dark organic streaks that break up flat surfaces."""
    smudge = fbm(SIZE, 12, 5, 131)
    drip = fbm(SIZE, 40, 4, 132)
    v = 0.55 + smudge * 0.3 - drip * 0.2
    return grey(v), normal_from_height(smudge * 0.4, 1.0)


SURFACES = {
    "plaster": plaster,
    "paint": paint,
    "wallpaper": wallpaper,
    "wood_floor": wood_floor,
    "wood_dark": wood_dark,
    "fabric": fabric,
    "carpet": carpet,
    "metal": metal_brushed,
    "tile": tile,
    "brick": brick,
    "concrete": concrete,
    "ground": ground_dirt,
    "grass": grass,
    "grime": grime,
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    manifest = {}
    for name, fn in SURFACES.items():
        if args.list:
            print(name)
            continue
        albedo, normal = fn()
        a = save(name + "_alb", albedo)
        n = save(name + "_nrm", normal)
        manifest[name] = {"albedo": os.path.basename(a), "normal": os.path.basename(n)}
        print("baked %-12s %s %s" % (name, os.path.basename(a), os.path.basename(n)))
    if not args.list:
        with open(os.path.join(OUT, "manifest.json"), "w") as f:
            json.dump(manifest, f, indent=1, sort_keys=True)
        total = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT))
        print("\n%d surfaces, %.1f KB total" % (len(manifest), total / 1024.0))


if __name__ == "__main__":
    main()
