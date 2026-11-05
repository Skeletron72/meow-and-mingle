#!/usr/bin/env python3
"""Выгрузка спрайтов в PNG (docs/art): значки интерфейса, значки и баночки ингредиентов, вся мебель (с оттенками стилей).
  python3 tools/export_sprites.py
*_raw.png — в родном размере без подписей (для правки в редакторе), *_labeled.png — крупно и с названиями.
Значки ингредиентов нарисованы строками в scripts/pixel_art.gd (EXTRA_ROWS, JAR_ROWS, shelf_icon): скрипт берёт их оттуда же."""
import json
import os
import re

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "art")
os.makedirs(OUT, exist_ok=True)
FONT = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13)
BG = (86, 110, 108, 255)


def hexc(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5)) + (255,)


def parse_pal(text):
    return {m.group(1): hexc(m.group(2)) for m in re.finditer(r'"(.)": Color\("(#?[0-9a-fA-F]{6})"\)'.replace('(#?', '(#?'), text.replace('Color("', 'Color("#'))}


src = open(os.path.join(ROOT, "scripts", "pixel_art.gd"), encoding="utf-8").read()


def block(name):
    i = src.index(name)
    j = src.index("}", i) + 1
    return src[i:j]


def rows_of(text):
    out = {}
    for m in re.finditer(r'"(\w+)": \[((?:"[^"]*",?\s*)+)\]', text):
        out[m.group(1)] = re.findall(r'"([^"]*)"', m.group(2))
    return out


def render(rows, pal):
    h, w = len(rows), len(rows[0])
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch in pal:
                im.putpixel((x, y), pal[ch])
    return im


def labeled(items, cols, scale, cell, path, title):
    """items: [(подпись, Image)] → лист с сеткой cols колонок, масштаб scale, ячейка cell (px исходных)."""
    cw, ch = cell[0] * scale, cell[1] * scale + 20
    rowsn = (len(items) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cw + 8, rowsn * ch + 36), BG)
    d = ImageDraw.Draw(sheet)
    d.text((8, 8), title, font=FONT, fill=(255, 241, 214, 255))
    for i, (name, im) in enumerate(items):
        x, y = 4 + (i % cols) * cw, 30 + (i // cols) * ch
        big = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
        sheet.alpha_composite(big, (x + (cw - big.width) // 2, y + (cell[1] * scale - big.height)))
        d.text((x + 2, y + cell[1] * scale + 2), name[:int(cw / 7.5)], font=FONT, fill=(255, 241, 214, 255))
    sheet.save(path)


# 1. значки интерфейса (assets/ui/icons_game.png + data/icons.json)
icons = json.load(open(os.path.join(ROOT, "data", "icons.json"), encoding="utf-8"))
sheet = Image.open(os.path.join(ROOT, "assets", "ui", "icons_game.png")).convert("RGBA")
sheet.save(os.path.join(OUT, "icons_game_raw.png"))
labeled([(n, sheet.crop((r[0], r[1], r[0] + r[2], r[1] + r[3]))) for n, r in icons.items()], 8, 4, (16, 16), os.path.join(OUT, "icons_game_labeled.png"), "Значки интерфейса 16×16 (tools/generators/make_icons.py), %d шт." % len(icons))

# 2. ингредиенты: значки 10×10, баночки 16×16, молоко и сироп
extra_pal = parse_pal(block("const EXTRA_PAL"))
jar_pal = parse_pal(block("const JAR_PAL"))
shelf_pal = {"o": hexc("#3b2a3d"), "w": hexc("#f4ecd8"), "s": hexc("#d3c5a6"), "b": hexc("#5b8fd9"), "r": hexc("#c0392b"), "d": hexc("#8a2a20"), "h": hexc("#ee7a68"), "g": hexc("#e8c15a")}
extras = [("значок: " + k, render(v, extra_pal)) for k, v in rows_of(block("const EXTRA_ROWS")).items()]
jars = [("баночка: " + k, render(v, jar_pal)) for k, v in rows_of(block("const JAR_ROWS")).items()]
shelf_src = src[src.index("static func shelf_icon"):src.index("## Рыбка")]
shelf_rows = re.findall(r'\[\s*((?:"[.a-zA-Z]{16}",?\s*)+)\]', shelf_src)
shelf = [("полка: молоко", render(re.findall(r'"([^"]*)"', shelf_rows[0]), shelf_pal)), ("полка: сироп", render(re.findall(r'"([^"]*)"', shelf_rows[1]), shelf_pal))]
allx = extras + jars + shelf
strip = Image.new("RGBA", (16 * len(allx), 16), (0, 0, 0, 0))
for i, (_, im) in enumerate(allx):
    strip.alpha_composite(im, (i * 16, 0))
strip.save(os.path.join(OUT, "ingredients_raw.png"))
labeled(allx, 6, 8, (16, 16), os.path.join(OUT, "ingredients_labeled.png"), "Ингредиенты: значки 10×10, баночки и молоко/сироп 16×16 (scripts/pixel_art.gd)")

# 3. мебель: лист кафе + оттенки стилей (data/furniture.json)
furn = json.load(open(os.path.join(ROOT, "data", "furniture.json"), encoding="utf-8"))
pack = Image.open(os.path.join(ROOT, "assets", "cafe", "neko-cafe-furnitures.png")).convert("RGBA")
pack.save(os.path.join(OUT, "furniture_pack_sheet.png"))
items = []
for f in furn:
    r = f["rect"]
    im = pack.crop((r[0], r[1], r[0] + r[2], r[1] + r[3]))
    if "tint" in f:
        t = hexc(f["tint"])
        px = im.load()
        for y in range(im.height):
            for x in range(im.width):
                p = px[x, y]
                if p[3]:
                    px[x, y] = (p[0] * t[0] // 255, p[1] * t[1] // 255, p[2] * t[2] // 255, p[3])
    items.append((f"{f['id']}", im, f["style"]))
cell = (64, 40)
raw = Image.new("RGBA", (8 * cell[0], ((len(items) + 7) // 8) * cell[1]), (0, 0, 0, 0))
for i, (_, im, _s) in enumerate(items):
    raw.alpha_composite(im, ((i % 8) * cell[0] + (cell[0] - im.width) // 2, (i // 8) * cell[1] + cell[1] - im.height))
raw.save(os.path.join(OUT, "furniture_all_raw.png"))
labeled([(n, im) for n, im, _s in items], 6, 3, cell, os.path.join(OUT, "furniture_all_labeled.png"), "Вся мебель (%d шт.) с оттенками стилей; базовые спрайты — из набора neko-cafe-furnitures, оттенки (loft, japan, winter, золото, спонсорские) — умножение цвета" % len(items))
print("готово:", sorted(os.listdir(OUT)))
