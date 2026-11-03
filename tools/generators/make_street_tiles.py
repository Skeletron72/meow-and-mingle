#!/usr/bin/env python3
"""Рисует атлас тайлов земли улицы: assets/street/tiles/street_tiles.png (тайлы 16×16, сетка 8×4).
Атлас можно спокойно перерисовать вручную — тайлы в сцене и TileSet привязаны к координатам клеток атласа.
Таблица тайлов — assets/street/tiles/README.md. Запуск:  python3 tools/generators/make_street_tiles.py
"""
import os
import random

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "street", "tiles", "street_tiles.png")
T = 16

SIDEWALK = (185, 178, 170)
SEAM = (163, 156, 149)
SEAM_DARK = (140, 134, 128)
CURB = (214, 207, 199)
ASPHALT = (70, 74, 85)
ASPHALT_DARK = (58, 62, 72)
ASPHALT_LIGHT = (80, 84, 96)
PAINT = (232, 226, 200)
GRASS = (92, 156, 76)
GRASS_L = (112, 176, 90)
GRASS_D = (70, 128, 64)
CONCRETE = (170, 168, 164)
CONCRETE_D = (150, 148, 145)
PATH = (196, 168, 120)


def blank(color):
    return Image.new("RGBA", (T, T), color + (255,))


def speckle(im, color, n, rng):
    for _ in range(n):
        im.putpixel((rng.randrange(T), rng.randrange(T)), color + (255,))


def sidewalk(rng, specks=0, crack=False, shadow=False, curb=False):
    im = blank(SIDEWALK)
    for i in range(T):                       # швы плитки: правый и нижний край
        im.putpixel((T - 1, i), SEAM + (255,))
        im.putpixel((i, T - 1), SEAM + (255,))
    speckle(im, SEAM, specks, rng)
    if crack:
        for i, (x, y) in enumerate([(3, 4), (4, 4), (5, 5), (6, 5), (7, 6), (7, 7)]):
            im.putpixel((x, y), SEAM_DARK + (255,))
    if shadow:                               # тень под фасадом
        for y in range(3):
            for x in range(T):
                im.putpixel((x, y), tuple(int(c * (0.78 + 0.07 * y)) for c in SIDEWALK) + (255,))
    if curb:                                 # бордюр: нижние 5 px
        for y in range(T - 5, T):
            for x in range(T):
                im.putpixel((x, y), (CURB if y < T - 2 else SEAM_DARK) + (255,))
        for x in range(T):
            im.putpixel((x, T - 5), SEAM + (255,))
    return im


def asphalt(rng, specks=0, edge=False):
    im = blank(ASPHALT)
    speckle(im, ASPHALT_DARK, specks, rng)
    speckle(im, ASPHALT_LIGHT, specks // 2, rng)
    if edge:                                  # тень от бордюра
        for y in range(3):
            for x in range(T):
                im.putpixel((x, y), ASPHALT_DARK + (255,))
    return im


def dash():
    """Разделительная: штрих на всю ширину клетки (чередуется с обычным асфальтом)."""
    im = asphalt(random.Random(1))
    for y in range(3, 5):
        for x in range(T):
            im.putpixel((x, y), PAINT + (255,))
    return im


def zebra():
    """Зебра для горизонтальной дороги: полосы идут ВДОЛЬ движения (по x), а пешеходы идут поперёк (по y)."""
    im = asphalt(random.Random(2))
    for band in (1, 9):
        for y in range(band, band + 5):
            for x in range(T):
                im.putpixel((x, y), PAINT + (255,))
    return im


def grass(rng, kind=0):
    base = (GRASS, GRASS_L, GRASS_D)[kind]
    im = blank(base)
    speckle(im, GRASS_L if kind != 1 else GRASS, 10, rng)
    speckle(im, GRASS_D if kind != 2 else GRASS, 6, rng)
    return im


def tufted(rng):
    im = grass(rng, 0)
    for x, y in [(3, 5), (11, 9), (6, 12)]:   # цветочки
        im.putpixel((x, y), (250, 236, 120, 255))
        im.putpixel((x, y + 1), (240, 120, 150, 255))
    return im


def concrete(rng, cracked=False):
    im = blank(CONCRETE)
    speckle(im, CONCRETE_D, 12, rng)
    if cracked:
        for x, y in [(2, 10), (3, 10), (4, 11), (5, 11), (6, 12), (7, 12), (8, 13)]:
            im.putpixel((x, y), CONCRETE_D + (255,))
    return im


def dirt(rng):
    im = blank(PATH)
    speckle(im, (170, 140, 96), 14, rng)
    return im


def main():
    rng = random.Random(42)
    atlas = Image.new("RGBA", (T * 8, T * 4), (0, 0, 0, 0))
    tiles = {
        (0, 0): sidewalk(rng, 3), (1, 0): sidewalk(rng, 6, crack=True), (2, 0): sidewalk(rng, 3, shadow=True), (3, 0): sidewalk(rng, 2, curb=True),
        (4, 0): concrete(rng), (5, 0): concrete(rng, cracked=True), (6, 0): dirt(rng), (7, 0): sidewalk(rng, 3),
        (0, 1): asphalt(rng, 10), (1, 1): asphalt(rng, 22), (2, 1): asphalt(rng, 8, edge=True), (3, 1): dash(),
        (4, 1): zebra(),
        (0, 2): grass(rng, 0), (1, 2): grass(rng, 1), (2, 2): grass(rng, 2), (3, 2): tufted(rng),
    }
    for (cx, cy), im in tiles.items():
        atlas.alpha_composite(im, (cx * T, cy * T))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    atlas.save(OUT)
    print("ok", OUT, atlas.size)


if __name__ == "__main__":
    main()
