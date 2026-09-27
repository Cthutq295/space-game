"""Pixel-art for ships, structures, missiles and pickups.

Team-coloured sprites are painted in neutral greys: the team_tint shader turns
grey pixels into red (enemies) or blue (allies). Saturated pixels (cockpits,
engines) and the slightly bluish outline keep their colour.

Requires: numpy, pillow.   Run:  python tools/gen_units.py
"""
import os

import numpy as np
from PIL import Image, ImageDraw

from gen_assets import SPR, ascii_to_rgba, hexc, save

OUTLINE = "#0e0e18"
GREYS = ["#262626", "#3c3c3c", "#585858", "#7a7a7a", "#a2a2a2", "#cdcdcd", "#f2f2f2"]  # levels 1..7
ACCENTS = {  # index >= 20
    20: "#ffd35a",  # cockpit / window warm
    21: "#ff8a3a",  # engine
    22: "#6fe6ff",  # lights cyan
    23: "#ff4a3a",  # warning red
    24: "#1a1420",  # hangar dark (saturated-ish, not tinted)
}


class Canvas:
    """Index-map painter with automatic bevel shading and outline."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.img = Image.new("L", (w, h), 0)
        self.draw = ImageDraw.Draw(self.img)

    def poly(self, pts, level, mirror_y=True):
        self.draw.polygon(pts, fill=level)
        if mirror_y:
            self.draw.polygon([(x, self.h - 1 - y) for x, y in pts], fill=level)

    def rect(self, x0, y0, x1, y1, level, mirror_y=True):
        self.draw.rectangle([x0, y0, x1, y1], fill=level)
        if mirror_y:
            self.draw.rectangle([x0, self.h - 1 - y1, x1, self.h - 1 - y0], fill=level)

    def ellipse(self, x0, y0, x1, y1, level):
        self.draw.ellipse([x0, y0, x1, y1], fill=level)

    def px(self, x, y, level, mirror_y=True):
        self.img.putpixel((x, y), level)
        if mirror_y:
            self.img.putpixel((x, self.h - 1 - y), level)

    def render(self, bevel=True):
        idx = np.array(self.img, dtype=np.int32)
        filled = idx > 0
        grey = filled & (idx < 20)
        lvl = idx.copy()
        if bevel:
            up = np.zeros_like(filled)
            up[1:, :] = ~filled[:-1, :]
            up[0, :] = True
            left = np.zeros_like(filled)
            left[:, 1:] = ~filled[:, :-1]
            down = np.zeros_like(filled)
            down[:-1, :] = ~filled[1:, :]
            right = np.zeros_like(filled)
            right[:, :-1] = ~filled[:, 1:]
            # interior edges between different levels also get a bevel
            diff_up = np.zeros_like(filled)
            diff_up[1:, :] = (idx[:-1, :] < idx[1:, :]) & filled[:-1, :]
            lvl = np.where(grey & (up | left | diff_up), np.minimum(lvl + 2, 7), lvl)
            lvl = np.where(grey & (down | right) & ~(up | left), np.maximum(lvl - 1, 1), lvl)
        rgba = np.zeros((self.h, self.w, 4), np.float32)
        for y in range(self.h):
            for x in range(self.w):
                v = lvl[y, x]
                if v == 0:
                    continue
                col = GREYS[v - 1] if v < 20 else ACCENTS[v]
                rgba[y, x, :3] = hexc(col)
                rgba[y, x, 3] = 1
        # 1px outline outside the silhouette
        grow = np.zeros_like(filled)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            grow |= np.roll(np.roll(filled, dy, 0), dx, 1)
        edge = grow & ~filled
        rgba[edge, :3] = hexc(OUTLINE)
        rgba[edge, 3] = 1
        return rgba


def with_border(rgba, pad=1):
    h, w = rgba.shape[:2]
    out = np.zeros((h + pad * 2, w + pad * 2, 4), np.float32)
    out[pad:pad + h, pad:pad + w] = rgba
    return out


# ------------------------------------------------------------------ small ships (ASCII, facing up)
UNIT_PAL = {"o": OUTLINE, "d": GREYS[1], "m": GREYS[3], "l": GREYS[4], "W": GREYS[6],
            "c": ACCENTS[20], "e": ACCENTS[21], "r": ACCENTS[23]}

FLY_HALF = [
    "......o",
    ".....ol",
    ".....oW",
    "o...omc",
    "lo.odmc",
    "Wmodmml",
    "lmmdmlm",
    "odmmmmd",
    ".oodddo",
    "....oeo",
    ".....o.",
]

FIGHTER_HALF = [
    "........o",
    ".......oW",
    ".......ol",
    "......oml",
    "......omc",
    "o....odcc",
    "Wo...odmc",
    "lmo.odmml",
    "lmmoddmlW",
    "odmmddmml",
    ".oddmmmmd",
    "..ooddddd",
    "....odoed",
    ".....oeeo",
    "......oo.",
]


def ascii_ship(half):
    rows = [r + r[:-1][::-1] for r in half]
    up = ascii_to_rgba(rows, UNIT_PAL)
    return np.rot90(up, k=-1).copy()


# ------------------------------------------------------------------ heavy ships (shapes, facing right)
def gen_corsair():
    """Corsair: agile mid-size assault ship with forward prongs (guns)."""
    c = Canvas(33, 27)
    c.poly([(9, 1), (15, 1), (26, 7), (24, 9), (12, 9)], 2)    # forward-swept prongs
    c.poly([(4, 8), (19, 8), (31, 13)], 3)                      # hull (mirrored -> diamond)
    c.rect(7, 11, 20, 15, 4, mirror_y=False)                    # spine
    c.rect(1, 6, 7, 9, 3)                                       # engine pods
    c.rect(25, 6, 27, 7, 5)                                     # gun tips
    c.px(22, 13, 20, mirror_y=False)
    c.px(23, 13, 20, mirror_y=False)
    c.px(22, 12, 20)
    c.px(0, 7, 21)
    c.px(0, 8, 21)
    c.px(13, 4, 23)
    save(with_border(c.render()), os.path.join(SPR, "corsair.png"))


def gen_heavy():
    """Missile gunship: 4 missile rails on each wing."""
    c = Canvas(50, 41)
    c.poly([(9, 1), (29, 1), (31, 13), (6, 13)], 2)          # wings (rack plates)
    c.poly([(4, 12), (32, 12), (44, 16), (48, 20)], 3)        # hull
    c.rect(7, 16, 30, 20, 4)                                   # spine
    c.rect(2, 13, 6, 18, 2)                                    # engine block
    for x in (12, 21):                                         # rails
        c.rect(x - 1, 3, x + 6, 3, 1)
        c.rect(x - 1, 8, x + 6, 8, 1)
    c.rect(34, 18, 38, 20, 5)
    c.px(41, 19, 20)
    c.px(42, 19, 20)
    c.px(41, 20, 20)
    c.px(42, 20, 20)
    for y in (14, 15, 16, 17):
        c.px(1, y, 21)
    c.px(33, 13, 23)
    rgba = with_border(c.render())
    save(rgba, os.path.join(SPR, "heavy.png"))
    # rack slots (local px from sprite centre) for the game code
    h, w = rgba.shape[:2]
    cx, cy = (w - 1) / 2, (h - 1) / 2
    slots = []
    for x in (15, 24):
        for y in (5, 10):
            slots.append((x + 1 - cx, y + 1 - cy))
            slots.append((x + 1 - cx, (40 - y) + 1 - cy))
    print("heavy size", w, h, "rack slots", slots)


def gen_carrier():
    """Siege carrier: big front cannon, hangar bay for escort flies."""
    c = Canvas(66, 47)
    c.poly([(12, 2), (40, 2), (44, 11), (10, 11)], 2)          # side pods
    c.poly([(3, 9), (44, 9), (56, 16), (58, 23)], 3)           # hull
    c.rect(8, 13, 42, 23, 4)                                   # deck
    c.rect(12, 17, 28, 23, 24)                                 # hangar (dark)
    c.rect(50, 20, 65, 23, 4)                                  # cannon barrel
    c.rect(46, 18, 52, 23, 5)                                  # cannon mount
    c.rect(1, 12, 3, 20, 2)
    for x in range(13, 28, 3):
        c.px(x, 17, 22)
    for y in range(12, 21, 2):
        c.px(0, y, 21)
    for x in range(14, 40, 5):
        c.px(x, 4, 23)
    c.px(64, 22, 1)
    c.px(64, 23, 1)
    rgba = with_border(c.render())
    save(rgba, os.path.join(SPR, "carrier.png"))
    print("carrier size", rgba.shape[1], rgba.shape[0])


def gen_post():
    """Defense post (station)."""
    c = Canvas(41, 41)
    c.rect(18, 1, 22, 39, 2, mirror_y=False)                   # vertical arm
    c.rect(1, 18, 39, 22, 2, mirror_y=False)                   # horizontal arm
    c.poly([(12, 8), (28, 8), (33, 13), (33, 27), (28, 32), (12, 32), (7, 27), (7, 13)], 3, mirror_y=False)
    c.ellipse(13, 13, 27, 27, 4)
    c.ellipse(16, 16, 24, 24, 5)
    for (x, y) in ((20, 2), (20, 38), (2, 20), (38, 20)):
        c.px(x, y, 22, mirror_y=False)
    c.px(20, 20, 20, mirror_y=False)
    c.px(19, 20, 20, mirror_y=False)
    c.px(20, 19, 20, mirror_y=False)
    c.px(21, 20, 20, mirror_y=False)
    c.px(20, 21, 20, mirror_y=False)
    save(with_border(c.render()), os.path.join(SPR, "post.png"))


def gen_turrets():
    base = Canvas(19, 19)
    base.poly([(5, 1), (13, 1), (17, 5), (17, 13), (13, 17), (5, 17), (1, 13), (1, 5)], 2, mirror_y=False)
    base.ellipse(4, 4, 14, 14, 3)
    for (x, y) in ((3, 3), (15, 3), (3, 15), (15, 15)):
        base.px(x, y, 22, mirror_y=False)
    save(with_border(base.render()), os.path.join(SPR, "turret_base.png"))

    gun = Canvas(17, 11)
    gun.ellipse(0, 1, 9, 10, 4)
    gun.rect(8, 2, 16, 3, 5)      # twin barrels (mirrored)
    gun.rect(15, 2, 16, 3, 2)
    gun.px(4, 5, 20, mirror_y=False)
    save(with_border(gun.render()), os.path.join(SPR, "turret_gun.png"))

    ml = Canvas(15, 17)
    ml.rect(0, 2, 11, 14, 3, mirror_y=False)
    ml.rect(2, 1, 13, 3, 4)       # rails (mirrored)
    ml.rect(2, 6, 13, 6, 2)
    ml.px(5, 8, 20, mirror_y=False)
    save(with_border(ml.render()), os.path.join(SPR, "turret_launcher.png"))


def gen_missile():
    rows = [
        "..ommo..",
        "eommlWcc",
        "..ommo..",
    ]
    save(ascii_to_rgba(rows, UNIT_PAL), os.path.join(SPR, "missile.png"))


def gen_pickups():
    ore = ascii_to_rgba([
        ".oooo.",
        "oyYyao",
        "oYyaao",
        "oyaaAo",
        "oaaAAo",
        ".oooo.",
    ], {"o": "#1a1016", "y": "#ffd08a", "Y": "#ffe8c0", "a": "#d0803a", "A": "#8a4a2a"})
    save(ore, os.path.join(SPR, "pickup_ore.png"))
    scrap = ascii_to_rgba([
        "oooo..",
        "oWllo.",
        "olmmlo",
        "olmdmo",
        ".olmdo",
        "..oooo",
    ], {"o": "#101018", "W": "#ffffff", "l": "#b8c4d0", "m": "#7a8898", "d": "#4a5668"})
    save(scrap, os.path.join(SPR, "pickup_scrap.png"))
    crystal = ascii_to_rgba([
        "..o..",
        ".oWo.",
        "oWpco",
        "opPco",
        "oPPco",
        ".oPo.",
        "..o..",
    ], {"o": "#1a0a24", "W": "#ffe8ff", "p": "#f070ff", "P": "#b040e0", "c": "#6ff3ff"})
    save(crystal, os.path.join(SPR, "pickup_crystal.png"))


def gen_key_icon():
    rows = [
        ".ooooooooo.",
        "oWWWWWWWWWo",
        "oWWkkkkkWWo",
        "oWWkWWWWWWo",
        "oWWkkkkWWWo",
        "oWWkWWWWWWo",
        "oWWkkkkkWWo",
        "oWWWWWWWWWo",
        "oddddddddd o".replace(" ", ""),
        ".ooooooooo.",
    ]
    rows = [r[:11] for r in rows]
    save(ascii_to_rgba(rows, {"o": "#0e0e18", "W": "#f2f2f2", "k": "#20202c", "d": "#8a8a9a"}),
         os.path.join(SPR, "key_e.png"))


if __name__ == "__main__":
    save(with_border(ascii_ship(FLY_HALF)), os.path.join(SPR, "fly.png"))
    save(with_border(ascii_ship(FIGHTER_HALF)), os.path.join(SPR, "fighter.png"))
    gen_corsair()
    gen_heavy()
    gen_carrier()
    gen_post()
    gen_turrets()
    gen_missile()
    gen_pickups()
    gen_key_icon()
    print("done")
