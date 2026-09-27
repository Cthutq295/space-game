"""Procedural pixel-art generator for the game.

Requires: numpy, pillow.   Run:  python tools/gen_assets.py
Writes PNGs into assets/sprites and assets/bg.
"""
import math
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SPR = os.path.join(HERE, "..", "assets", "sprites")
BG = os.path.join(HERE, "..", "assets", "bg")
os.makedirs(SPR, exist_ok=True)
os.makedirs(BG, exist_ok=True)

BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32) / 16.0 + 1.0 / 32.0


def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32) / 255.0


def bayer(h, w):
    return np.tile(BAYER4, (h // 4 + 1, w // 4 + 1))[:h, :w]


def save(arr, path):
    img = Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
    img.save(path)


def ramp_idx(v, n, dith, strength=1.0):
    return np.clip(np.floor(v * (n - 1) + 0.5 + (dith - 0.5) * strength), 0, n - 1).astype(int)


def ramp_pick(ramp, v, dith, strength=1.0):
    cols = np.stack([hexc(c) for c in ramp])
    return cols[ramp_idx(np.clip(v, 0, 1), len(ramp), dith, strength)]


def smooth(t):
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- noise
def vnoise2(h, w, period, rng):
    """Value noise, tileable over the whole image."""
    g = rng.random((period, period)).astype(np.float32)
    ys = np.arange(h) / h * period
    xs = np.arange(w) / w * period
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    fy = smooth(ys - y0)[:, None]
    fx = smooth(xs - x0)[None, :]
    y1 = (y0 + 1) % period
    x1 = (x0 + 1) % period
    a = g[y0[:, None], x0[None, :]]
    b = g[y0[:, None], x1[None, :]]
    c = g[y1[:, None], x0[None, :]]
    d = g[y1[:, None], x1[None, :]]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm2(h, w, period, octaves, rng, gain=0.5):
    total = np.zeros((h, w), np.float32)
    amp, norm = 1.0, 0.0
    for _ in range(octaves):
        total += vnoise2(h, w, period, rng) * amp
        norm += amp
        amp *= gain
        period *= 2
    return total / norm


class Noise3:
    def __init__(self, rng, n=64):
        self.n = n
        self.g = rng.random((n, n, n)).astype(np.float32)

    def __call__(self, x, y, z):
        n = self.n
        x = x + 1000.0
        y = y + 1000.0
        z = z + 1000.0
        xi, yi, zi = np.floor(x).astype(int), np.floor(y).astype(int), np.floor(z).astype(int)
        fx, fy, fz = smooth(x - xi), smooth(y - yi), smooth(z - zi)
        x0, y0, z0 = xi % n, yi % n, zi % n
        x1, y1, z1 = (x0 + 1) % n, (y0 + 1) % n, (z0 + 1) % n
        g = self.g

        def lerp(a, b, t):
            return a + (b - a) * t

        c00 = lerp(g[x0, y0, z0], g[x1, y0, z0], fx)
        c10 = lerp(g[x0, y1, z0], g[x1, y1, z0], fx)
        c01 = lerp(g[x0, y0, z1], g[x1, y0, z1], fx)
        c11 = lerp(g[x0, y1, z1], g[x1, y1, z1], fx)
        return lerp(lerp(c00, c10, fy), lerp(c01, c11, fy), fz)

    def fbm(self, x, y, z, octaves=5, gain=0.5):
        total, amp, norm, f = 0.0, 1.0, 0.0, 1.0
        for _ in range(octaves):
            total = total + self(x * f, y * f, z * f) * amp
            norm += amp
            amp *= gain
            f *= 2.0
        return total / norm


def outline(alpha_mask, col, rgba):
    """Paint 1px outline on the inner border of mask."""
    m = alpha_mask
    edge = np.zeros_like(m)
    edge[1:, :] |= ~m[:-1, :]
    edge[:-1, :] |= ~m[1:, :]
    edge[:, 1:] |= ~m[:, :-1]
    edge[:, :-1] |= ~m[:, 1:]
    edge[0, :] = True
    edge[-1, :] = True
    edge[:, 0] = True
    edge[:, -1] = True
    edge &= m
    rgba[edge, :3] = hexc(col)
    return edge


# ---------------------------------------------------------------- ship
SHIP_PAL = {
    "o": "#10121c", "d": "#2b3350", "m": "#4a5a7c", "l": "#7d93b5", "W": "#d8e4f0",
    "c": "#1f6fb5", "C": "#5ed0f5", "r": "#a8323e", "R": "#e05a3a", "e": "#3a2440",
    "g": "#ffb347", "y": "#fff2a8",
}

SHIP_HALF = [
    "............o",
    "...........oW",
    "..........olW",
    "..........olW",
    ".........omlW",
    ".........omcC",
    "........omcCC",
    "........omcCW",
    "........omccC",
    "........odmcc",
    ".......odmmll",
    ".......odmlWl",
    "..o....odmlll",
    ".olo..odmmlml",
    ".oro..odmmlmm",
    ".oro.oddmmrmm",
    ".omlodddmmrrm",
    ".omllodmmmmrr",
    "oomlllodmmmmm",
    "odmmllldmmlmm",
    "oddmmmmlddmdd",
    "odddddmmmddmd",
    ".oooddddddodd",
    "....ooodoeeod",
    ".......oeggeo",
    "........oooo.",
]


def ascii_to_rgba(rows, pal):
    h, w = len(rows), len(rows[0])
    arr = np.zeros((h, w, 4), np.float32)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != ".":
                arr[y, x, :3] = hexc(pal[ch])
                arr[y, x, 3] = 1
    return arr


def gen_ship():
    rows = [r + r[:-1][::-1] for r in SHIP_HALF]
    up = ascii_to_rgba(rows, SHIP_PAL)
    right = np.rot90(up, k=-1).copy()  # nose points +X
    save(right, os.path.join(SPR, "ship.png"))
    # engine flame: 3 frames 12x5, white core -> tinted at runtime
    frames = []
    for length in (7, 10, 8):
        f = np.zeros((5, 12, 4), np.float32)
        for x in range(12):
            t = x / max(length, 1)
            dist = 11 - x  # distance from nozzle (right side is nozzle)
            if dist > length:
                continue
            half = 2.0 * (1 - dist / (length + 1)) + 0.3
            for y in range(5):
                if abs(y - 2) <= half:
                    core = abs(y - 2) < half * 0.45 and dist < length * 0.6
                    col = hexc("#fffbe0") if core else (hexc("#ffc24a") if dist < length * 0.55 else hexc("#ff6a2a"))
                    f[y, x, :3] = col
                    f[y, x, 3] = 1
        frames.append(f)
    save(np.concatenate(frames, axis=1), os.path.join(SPR, "flame.png"))


# ---------------------------------------------------------------- projectiles / fx
def gen_fx():
    bolt = ascii_to_rgba([
        "..ccCCCC..",
        "cCCCWWWWWW",
        "..ccCCCC..",
    ], {"c": "#1b6f9a", "C": "#6fd8ff", "W": "#ffffff"})
    save(bolt, os.path.join(SPR, "bolt.png"))

    s = 11
    orb = np.zeros((s, s, 4), np.float32)
    yy, xx = np.mgrid[0:s, 0:s]
    d = np.sqrt((xx - 5) ** 2 + (yy - 5) ** 2)
    orb[d <= 5.2] = [*hexc("#8a2be2"), 1]
    orb[d <= 3.9] = [*hexc("#e070ff"), 1]
    orb[d <= 2.3] = [*hexc("#ffe0ff"), 1]
    save(orb, os.path.join(SPR, "plasma.png"))

    # shockwave ring
    s = 48
    ring = np.zeros((s, s, 4), np.float32)
    yy, xx = np.mgrid[0:s, 0:s]
    d = np.sqrt((xx - 23.5) ** 2 + (yy - 23.5) ** 2)
    ring[(d <= 23.5) & (d >= 21)] = [1, 1, 1, 1]
    ring[(d < 21) & (d >= 19.5) & ((xx + yy) % 2 == 0)] = [1, 1, 1, 1]
    save(ring, os.path.join(SPR, "ring.png"))

    # flash blob (dithered radial)
    s = 32
    blob = np.zeros((s, s, 4), np.float32)
    yy, xx = np.mgrid[0:s, 0:s]
    d = np.sqrt((xx - 15.5) ** 2 + (yy - 15.5) ** 2) / 16
    v = np.clip(1 - d, 0, 1) ** 1.5
    lv = ramp_idx(v, 5, bayer(s, s))
    blob[..., :3] = 1
    blob[..., 3] = lv / 4.0
    save(blob, os.path.join(SPR, "glow.png"))

    # crosshair (11x11 design, doubled)
    c = np.zeros((11, 11, 4), np.float32)
    white = [1, 1, 1, 1]
    dark = [*hexc("#10121c"), 1]
    pts = [(5, 0), (5, 1), (5, 9), (5, 10), (0, 5), (1, 5), (9, 5), (10, 5)]
    for (x, y) in pts:
        c[y, x] = white
    for (x, y) in [(2, 2), (8, 2), (2, 8), (8, 8), (3, 2), (2, 3), (7, 2), (8, 3), (2, 7), (3, 8), (8, 7), (7, 8)]:
        c[y, x] = white
    c[5, 5] = white
    big = np.repeat(np.repeat(c, 2, axis=0), 2, axis=1)
    out = np.zeros((24, 24, 4), np.float32)
    out[1:23, 1:23] = big
    # dark outline around white pixels
    a = out[..., 3] > 0
    ol = np.zeros_like(a)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            ol |= np.roll(np.roll(a, dy, 0), dx, 1)
    ol &= ~a
    out[ol] = dark
    save(out, os.path.join(SPR, "crosshair.png"))


# ---------------------------------------------------------------- asteroids
ROCK_KINDS = {
    "rock": ["#1b1520", "#35282f", "#523e40", "#735a52", "#957a66", "#b89f82", "#d8c6a4"],
    "iron": ["#141724", "#262c40", "#3c465e", "#58647e", "#7b88a0", "#a4b0c3", "#d2d9e4"],
    "ice": ["#111a33", "#1e3561", "#2e5a8f", "#4687bb", "#6fb4d9", "#a6dcef", "#e8fbff"],
    "crystal": ["#150f22", "#2a1f3c", "#3f3055", "#57466f", "#73608a", "#9582a8", "#bcaacb"],
}
ASTEROID_SIZES = {"s": 14, "m": 24, "l": 40}


def gen_asteroid(size, kind, seed):
    rng = np.random.default_rng(seed)
    S = size
    ramp = ROCK_KINDS[kind]
    c = (S - 1) / 2
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    dx, dy = xx - c, yy - c
    ang = np.arctan2(dy, dx)
    dist = np.sqrt(dx * dx + dy * dy)
    r0 = S / 2 - 1.0
    rad = np.ones_like(ang)
    for k in range(2, 7):
        rad += rng.uniform(0.03, 0.11) / (k * 0.6) * np.sin(k * ang + rng.uniform(0, 6.28))
    rad = r0 * (rad / (1 + 0.18))
    mask = dist <= rad
    rn = np.clip(dist / np.maximum(rad, 0.1), 0, 1)
    nx, ny = dx / np.maximum(rad, 0.1), dy / np.maximum(rad, 0.1)
    nz = np.sqrt(np.clip(1 - rn * rn, 0, 1))
    # craters -> concave normals
    ncr = {14: 1, 24: 3, 40: 5}[S]
    shade_add = np.zeros_like(nx)
    for _ in range(ncr):
        a = rng.uniform(0, 6.28)
        rr = rng.uniform(0, r0 * 0.55)
        cx, cy = c + math.cos(a) * rr, c + math.sin(a) * rr
        cr = rng.uniform(S * 0.1, S * 0.2)
        ddx, ddy = xx - cx, yy - cy
        dd = np.sqrt(ddx * ddx + ddy * ddy)
        inside = dd < cr
        # concave: light comes from the opposite side
        cl = (-(-ddx) * -0.6 + -(-ddy) * -0.55) / cr  # rim facing light brighter
        shade_add[inside] += (-(ddx[inside] * -0.6 + ddy[inside] * -0.55) / cr) * -0.45 - 0.12
        rim = (dd >= cr) & (dd < cr + 1.2)
        shade_add[rim] += 0.1 * ((ddx[rim] * -0.6 + ddy[rim] * -0.55) / cr > 0)
    L = np.array([-0.6, -0.55, 0.58])
    L = L / np.linalg.norm(L)
    lam = np.clip(nx * L[0] + ny * L[1] + nz * L[2], 0, 1)
    tex = vnoise2(S, S, max(2, S // 5), rng) * 0.25
    v = np.clip(lam * 0.85 + 0.1 + tex - 0.1 + shade_add, 0, 1)
    rgba = np.zeros((S, S, 4), np.float32)
    rgba[..., :3] = ramp_pick(ramp[1:], v, bayer(S, S), 0.8)
    rgba[..., 3] = mask
    if kind == "crystal":
        vein = fbm2(S, S, 3, 3, rng)
        vein = 1 - np.abs(vein * 2 - 1)
        cry = mask & (vein > 0.82) & (rn < 0.9)
        cols = np.stack([hexc(x) for x in ["#6a2fb8", "#b659ff", "#f2b8ff", "#6ff3ff"]])
        idx = np.clip(((vein - 0.82) / 0.18 * 3.5 + lam * 0.8).astype(int), 0, 3)
        rgba[cry, :3] = cols[idx[cry]]
    if kind == "ice":
        sparkle = mask & (rng.random((S, S)) > 0.97) & (lam > 0.5)
        rgba[sparkle, :3] = 1
    rgba[~mask] = 0
    outline(mask, ramp[0], rgba)
    return rgba


def gen_asteroids():
    seed = 100
    for kind in ROCK_KINDS:
        for sname, S in ASTEROID_SIZES.items():
            for i in range(3):
                seed += 1
                save(gen_asteroid(S, kind, seed), os.path.join(SPR, f"asteroid_{kind}_{sname}{i}.png"))


# ---------------------------------------------------------------- planets
def sphere_grid(D, margin=2):
    S = D + margin * 2
    c = S / 2
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    dx = (xx + 0.5 - c) / (D / 2)
    dy = (yy + 0.5 - c) / (D / 2)
    d2 = dx * dx + dy * dy
    mask = d2 <= 1.0
    nz = np.sqrt(np.clip(1 - d2, 0, 1))
    return S, dx, dy, nz, d2, mask


def light_levels(dx, dy, nz, S, levels=(0.28, 0.45, 0.65, 0.85, 1.0)):
    L = np.array([-0.62, -0.5, 0.6])
    L = L / np.linalg.norm(L)
    lam = np.clip(dx * L[0] + dy * L[1] + nz * L[2], 0, 1)
    lam = np.clip(lam * 1.35 - 0.12, 0, 1)
    idx = ramp_idx(lam, len(levels), bayer(S, S), 1.0)
    return np.array(levels, np.float32)[idx], lam


def finish_planet(rgba_rgb, mask, dx, dy, nz, S, shadow="#120f2a", emissive=None):
    lv, lam = light_levels(dx, dy, nz, S)
    sh = hexc(shadow)
    col = sh + (rgba_rgb - sh) * lv[..., None]
    if emissive is not None:
        em_mask, em_col = emissive
        col[em_mask] = em_col[em_mask]
    rgba = np.zeros((S, S, 4), np.float32)
    rgba[..., :3] = col
    rgba[..., 3] = mask
    # rim light on lit edge
    d2 = dx * dx + dy * dy
    rim = mask & (d2 > 0.93) & (lam > 0.5)
    rgba[rim, :3] = np.clip(rgba[rim, :3] * 1.25 + 0.05, 0, 1)
    rgba[~mask] = 0
    outline(mask, "#0a0814", rgba)
    return rgba


def colors_from(ramp, idx):
    cols = np.stack([hexc(c) for c in ramp])
    return cols[np.clip(idx, 0, len(ramp) - 1)]


def planet_terra(D, seed):
    rng = np.random.default_rng(seed)
    n = Noise3(rng)
    S, dx, dy, nz, d2, mask = sphere_grid(D)
    px, py, pz = dx * 2.3, dy * 2.3, nz * 2.3
    h = n.fbm(px, py, pz, 6)
    h = (h - h[mask].min()) / (h[mask].max() - h[mask].min())
    b = bayer(S, S)
    rgb = np.zeros((S, S, 3), np.float32)
    ocean = h < 0.55
    oi = ramp_idx(h / 0.55, 4, b)
    rgb[ocean] = colors_from(["#10265a", "#173a7a", "#1f5aa0", "#2f82c0"], oi)[ocean]
    land = ~ocean
    li = ramp_idx((h - 0.55) / 0.45, 6, b)
    land_cols = colors_from(["#d8c47a", "#5a9a3c", "#3f7d33", "#2d5e2a", "#6b5a45", "#e8eef5"], li)
    rgb[land] = land_cols[land]
    polar = np.abs(dy) + (n(px * 3, py * 3, pz * 3) - 0.5) * 0.25 > 0.82
    rgb[polar] = hexc("#e6f0f8")
    cl = n.fbm(px * 1.7 + 5, py * 3.5 + 3, pz * 1.7, 5)
    clouds = cl > 0.58
    rgb[clouds] = rgb[clouds] * 0.25 + hexc("#f4f8ff") * 0.75
    thick = cl > 0.64
    rgb[thick] = hexc("#ffffff")
    return finish_planet(rgb, mask, dx, dy, nz, S, "#0d1030"), "#6ab8ff"


def planet_lava(D, seed):
    rng = np.random.default_rng(seed)
    n = Noise3(rng)
    S, dx, dy, nz, d2, mask = sphere_grid(D)
    px, py, pz = dx * 2.0, dy * 2.0, nz * 2.0
    b = bayer(S, S)
    base = n.fbm(px * 1.5, py * 1.5, pz * 1.5, 5)
    rgb = colors_from(["#1a1216", "#2a1c20", "#3c2826", "#54362d"], ramp_idx(base, 4, b))
    ridge = 1 - np.abs(n.fbm(px, py, pz, 5) * 2 - 1)
    ridge2 = 1 - np.abs(n.fbm(px * 2 + 7, py * 2, pz * 2, 4) * 2 - 1)
    crack = mask & ((ridge > 0.9) | (ridge2 > 0.93))
    lake = n.fbm(px * 0.8 + 3, py * 0.8, pz * 0.8, 4) > 0.64
    em = crack | (lake & mask)
    heat = np.clip(np.maximum((ridge - 0.9) / 0.1, (ridge2 - 0.93) / 0.07), 0, 1)
    heat = np.where(lake, 0.6 + 0.4 * n(px * 4, py * 4, pz * 4), heat)
    emc = colors_from(["#a8200e", "#ff4a1c", "#ff9a2a", "#ffe066"], ramp_idx(heat, 4, b))
    # dim emissive slightly on night side for readability
    return finish_planet(rgb, mask, dx, dy, nz, S, "#0a0608", (em, emc)), "#ff6a30"


def planet_ice(D, seed):
    rng = np.random.default_rng(seed)
    n = Noise3(rng)
    S, dx, dy, nz, d2, mask = sphere_grid(D)
    px, py, pz = dx * 2.2, dy * 2.2, nz * 2.2
    b = bayer(S, S)
    base = n.fbm(px, py, pz, 5)
    rgb = colors_from(["#6fa8cf", "#94c9e6", "#bfe3f3", "#e3f5fb", "#ffffff"], ramp_idx(base, 5, b))
    ridge = 1 - np.abs(n.fbm(px * 1.5 + 2, py * 1.5, pz * 1.5, 5) * 2 - 1)
    crev = ridge > 0.9
    rgb[crev] = hexc("#2c5d9a")
    rgb[ridge > 0.96] = hexc("#173a70")
    return finish_planet(rgb, mask, dx, dy, nz, S, "#141c3e"), "#9ff0ff"


def planet_toxic(D, seed):
    rng = np.random.default_rng(seed)
    n = Noise3(rng)
    S, dx, dy, nz, d2, mask = sphere_grid(D)
    px, py, pz = dx * 2.0, dy * 2.0, nz * 2.0
    b = bayer(S, S)
    turb = n.fbm(px * 1.2, py * 3.0, pz * 1.2, 5)
    t = dy * 3.2 + turb * 2.2
    band = (np.floor(t * 2.0).astype(int)) % 6
    ramp = ["#3b1d5e", "#5c2a7e", "#8a3f9c", "#c46bb5", "#6a3c8c", "#2f7a78"]
    rgb = colors_from(ramp, band)
    fine = n(px * 6, py * 14, pz * 6)
    lighter = fine > 0.62
    rgb[lighter] = np.clip(rgb[lighter] * 1.25, 0, 1)
    # a storm eye
    ex, ey = 0.25, 0.3
    de = np.sqrt(((dx - ex) * 1.0) ** 2 + ((dy - ey) * 1.8) ** 2)
    rgb[de < 0.16] = hexc("#e8a0d0")
    rgb[de < 0.10] = hexc("#b0508c")
    rgb[de < 0.05] = hexc("#f5d0ea")
    return finish_planet(rgb, mask, dx, dy, nz, S, "#120a22"), "#b6ff7a"


def planet_mars(D, seed):
    rng = np.random.default_rng(seed)
    n = Noise3(rng)
    S, dx, dy, nz, d2, mask = sphere_grid(D)
    px, py, pz = dx * 2.4, dy * 2.4, nz * 2.4
    b = bayer(S, S)
    base = n.fbm(px, py, pz, 6)
    v = np.clip((base - 0.3) / 0.45, 0, 1)
    rgb = colors_from(["#5e2418", "#8a3a22", "#b4562e", "#d27a45", "#e8a468", "#f3c998"], ramp_idx(v, 6, b))
    # craters on the sphere
    for _ in range(26):
        u = rng.normal(size=3)
        u /= np.linalg.norm(u)
        if u[2] < 0:
            u[2] = -u[2]
        cr = rng.uniform(0.05, 0.16)
        dot = dx * u[0] + dy * u[1] + nz * u[2]
        ang = np.arccos(np.clip(dot, -1, 1))
        inner = mask & (ang < cr * 0.8)
        rim = mask & (ang >= cr * 0.8) & (ang < cr)
        rgb[inner] *= 0.72
        rgb[rim] = np.clip(rgb[rim] * 1.2, 0, 1)
    polar = dy + (n(px * 3, py * 3, pz * 3) - 0.5) * 0.2 < -0.86
    rgb[polar] = hexc("#f6efe6")
    return finish_planet(rgb, mask, dx, dy, nz, S, "#1c0c14"), "#ffb48a"


def gen_planets():
    specs = [("terra", planet_terra, 240, 11), ("lava", planet_lava, 200, 22), ("ice", planet_ice, 216, 33),
             ("toxic", planet_toxic, 260, 44), ("mars", planet_mars, 208, 55)]
    for name, fn, D, seed in specs:
        rgba, _atmo = fn(D, seed)  # atmosphere is drawn by shaders/planet_atmo.gdshader
        save(rgba, os.path.join(SPR, f"planet_{name}.png"))


# ---------------------------------------------------------------- background
def gen_nebula(S, period, seed, ramp, alpha_max, name, ridged=False, contrast=1.0):
    rng = np.random.default_rng(seed)
    dens = fbm2(S, S, period, 5, rng, 0.55)
    warp = fbm2(S, S, period, 4, rng, 0.5)
    dens = dens * 0.6 + warp * 0.4
    if ridged:
        dens = 1 - np.abs(dens * 2 - 1)
        dens = dens ** 3
    lo, hi = np.percentile(dens, 35), np.percentile(dens, 99.5)
    dens = np.clip((dens - lo) / (hi - lo), 0, 1) ** contrast
    hue = fbm2(S, S, max(2, period // 2), 3, rng)
    hue = (hue - hue.min()) / (hue.max() - hue.min())
    b = bayer(S, S)
    n = len(ramp)
    ci = ramp_idx(np.clip(dens * 0.7 + hue * 0.3, 0, 1), n, b)
    rgba = np.zeros((S, S, 4), np.float32)
    rgba[..., :3] = colors_from(ramp, ci)
    al = ramp_idx(dens, 6, np.roll(b, 1, axis=0)) / 5.0
    rgba[..., 3] = al * alpha_max
    save(rgba, os.path.join(BG, name))


def star_color(rng):
    return hexc(rng.choice(["#ffffff", "#cfe3ff", "#9fc4ff", "#fff1c9", "#ffd2a8", "#ffb0b0", "#e0d0ff"]))


def gen_stars(S, count, seed, name, bright=(0.25, 0.8), big=0, cross=0):
    rng = np.random.default_rng(seed)
    rgba = np.zeros((S, S, 4), np.float32)
    for _ in range(count):
        x, y = rng.integers(0, S, 2)
        c = star_color(rng)
        a = rng.uniform(*bright)
        rgba[y, x] = [*c, a]
    for _ in range(cross):
        x, y = rng.integers(2, S - 2, 2)
        c = star_color(rng)
        rgba[y, x] = [1, 1, 1, 1]
        for (ox, oy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            rgba[y + oy, x + ox] = [*c, 0.75]
    for _ in range(big):
        x, y = rng.integers(3, S - 3, 2)
        c = star_color(rng)
        rgba[y, x] = [1, 1, 1, 1]
        for (ox, oy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            rgba[y + oy, x + ox] = [*c, 0.95]
        for (ox, oy) in ((2, 0), (-2, 0), (0, 2), (0, -2)):
            rgba[y + oy, x + ox] = [*c, 0.45]
        for (ox, oy) in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
            rgba[y + oy, x + ox] = [*c, 0.25]
    save(rgba, os.path.join(BG, name))


def gen_galaxy(S, seed, name, arms=2, tilt=0.5, rot=0.6, ramp=None):
    rng = np.random.default_rng(seed)
    ramp = ramp or ["#1a1440", "#35287a", "#5a4ab0", "#8f86e0", "#d0ccff", "#ffffff"]
    c = (S - 1) / 2
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    x, y = xx - c, yy - c
    cr, sr = math.cos(rot), math.sin(rot)
    xr, yr = x * cr - y * sr, (x * sr + y * cr) / tilt
    r = np.sqrt(xr * xr + yr * yr) / (S / 2)
    th = np.arctan2(yr, xr)
    spiral = 0.5 + 0.5 * np.cos(arms * (th - 3.2 * np.log(r + 0.05)))
    noise = vnoise2(S, S, 8, rng)
    v = np.exp(-r * 3.2) * (0.35 + 0.65 * spiral ** 2) * (0.75 + 0.5 * noise)
    v += np.exp(-(r / 0.09) ** 2) * 0.9
    v = np.clip(v * 1.4, 0, 1)
    b = bayer(S, S)
    idx = ramp_idx(v, len(ramp) + 1, b) - 1
    rgba = np.zeros((S, S, 4), np.float32)
    on = idx >= 0
    rgba[on, :3] = colors_from(ramp, idx)[on]
    rgba[on, 3] = np.clip(0.35 + idx[on] / len(ramp), 0, 1)
    save(rgba, os.path.join(BG, name))


def gen_far_planet(S, seed, name, base, shadow, ring=True):
    rng = np.random.default_rng(seed)
    D = int(S * 0.55)
    rgba = np.zeros((S, S, 4), np.float32)
    off = (S - D - 4) // 2
    Sg, dx, dy, nz, d2, mask = sphere_grid(D)
    band = (np.floor((dy * 4 + vnoise2(Sg, Sg, 4, rng) * 1.2) * 1.5).astype(int)) % 3
    cols = np.stack([hexc(base[i]) for i in range(3)])
    body = finish_planet(cols[band], mask, dx, dy, nz, Sg, shadow)
    rgba[off:off + Sg, off:off + Sg] = body
    if ring:
        c = (S - 1) / 2
        yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
        x, y = xx - c, (yy - c) / 0.32
        rot = -0.35
        xr = x * math.cos(rot) - (yy - c) * math.sin(rot)
        yr = (x * math.sin(rot) + (yy - c) * math.cos(rot)) / 0.3
        rr = np.sqrt(xr * xr + yr * yr)
        rmask = (rr > D * 0.62) & (rr < D * 0.92) & (((rr / 2).astype(int)) % 3 != 0)
        front = yr > 0
        draw = rmask & (front | (rgba[..., 3] == 0))
        rc = hexc("#d8c8a8")
        rgba[draw] = [*rc, 0.9]
    save(rgba, os.path.join(BG, name))


def gen_bigstar(S, name, color):
    c = (S - 1) / 2
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    x, y = xx - c, yy - c
    d = np.sqrt(x * x + y * y)
    v = np.exp(-d / 2.2) + np.exp(-np.abs(y) / 0.7) * np.exp(-np.abs(x) / (S * 0.18)) \
        + np.exp(-np.abs(x) / 0.7) * np.exp(-np.abs(y) / (S * 0.18)) + np.exp(-d / 5) * 0.3
    v = np.clip((v - 0.12) / 0.88, 0, 1)
    v[d > S / 2 - 1] = 0
    idx = ramp_idx(v, 6, bayer(S, S))
    rgba = np.zeros((S, S, 4), np.float32)
    col = hexc(color)
    rgba[..., :3] = np.where((idx >= 4)[..., None], 1.0, col)
    rgba[..., 3] = idx / 5.0
    save(rgba, os.path.join(BG, name))


def gen_cluster(S, seed, name):
    rng = np.random.default_rng(seed)
    rgba = np.zeros((S, S, 4), np.float32)
    c = S / 2
    for _ in range(90):
        r = abs(rng.normal(0, S * 0.18))
        a = rng.uniform(0, 6.28)
        x, y = int(c + math.cos(a) * r), int(c + math.sin(a) * r)
        if 0 <= x < S and 0 <= y < S:
            rgba[y, x] = [*star_color(rng), rng.uniform(0.5, 1)]
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    d = np.sqrt((xx - c) ** 2 + (yy - c) ** 2) / (S / 2)
    haze = ramp_idx(np.clip(0.75 - d, 0, 1) ** 2, 4, bayer(S, S))
    hz = (haze > 0) & (rgba[..., 3] == 0)
    rgba[hz] = [*hexc("#8fb0ff"), 0]
    rgba[hz, 3] = haze[hz] * 0.12
    save(rgba, os.path.join(BG, name))


def gen_background():
    gen_nebula(320, 4, 7, ["#0c0822", "#140e34", "#1e1248", "#1a2052", "#18305e", "#34184e"], 1.0, "nebula_far.png",
               contrast=0.9)
    gen_nebula(256, 4, 8, ["#100a26", "#1a1036", "#26144a", "#32185c", "#3e2270", "#1c3050"], 0.7, "nebula_near.png",
               ridged=True)
    gen_nebula(256, 3, 9, ["#08141e", "#0c222e", "#10323c", "#164448", "#1e5654"], 0.55, "nebula_teal.png",
               ridged=True, contrast=1.3)
    gen_stars(256, 420, 1, "stars_far.png", (0.15, 0.5))
    gen_stars(256, 160, 2, "stars_mid.png", (0.35, 0.8), cross=10)
    gen_stars(256, 50, 3, "stars_near.png", (0.6, 1.0), big=4, cross=10)
    gen_stars(256, 40, 4, "dust.png", (0.08, 0.22))
    gen_galaxy(72, 1, "galaxy_blue.png")
    gen_galaxy(56, 2, "galaxy_pink.png", arms=3, tilt=0.45, rot=-0.4,
               ramp=["#3a0f2e", "#6e1e4e", "#b0406e", "#f080a0", "#ffd0e0", "#ffffff"])
    gen_galaxy(48, 3, "galaxy_gold.png", arms=2, tilt=0.8, rot=1.2,
               ramp=["#2e1a0a", "#5e3a14", "#a06a28", "#e0a850", "#fff0c0", "#ffffff"])
    gen_far_planet(64, 5, "far_planet_ringed.png", ["#c8a070", "#a07850", "#e0c090"], "#1a1020")
    gen_far_planet(40, 6, "far_planet_blue.png", ["#3a6ab0", "#5a8ad0", "#2a4a90"], "#0a0a20", ring=False)
    gen_bigstar(33, "bigstar_blue.png", "#8fc8ff")
    gen_bigstar(25, "bigstar_red.png", "#ff9a7a")
    gen_cluster(64, 12, "star_cluster.png")


if __name__ == "__main__":
    gen_ship()
    gen_fx()
    gen_asteroids()
    gen_planets()
    gen_background()
    print("done")
