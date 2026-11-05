#!/usr/bin/env python3
"""Предметы служебки и второго этажа (рисуются кодом в scripts/space_prop.gd) → PNG в docs/art.
  1) godot --path . --rendering-driver opengl3 res://tools/render_props.tscn -- <папка с кадрами>   (нужен xvfb на сервере)
  2) python3 tools/export_props.py <папка с кадрами>
Кадр рисуется в масштабе 2 (пиксель арта = 2 px); скрипт обрезает по содержимому и уменьшает вдвое — получается родной размер арта."""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

src = sys.argv[1]
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs", "art")
FONT = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13)
BG = (86, 110, 108, 255)
NAMES = {"crate": "ящик", "sack": "мешок кофе", "boxes": "коробки", "shelf": "стеллаж", "fridge": "холодильник", "sink": "раковина", "mop": "швабра", "catbed": "лежанка",
         "stairs_up": "лестница наверх (заколочена)", "stairs_up_open": "лестница наверх", "bed": "кровать", "wardrobe": "шкаф", "sofa": "диван", "bookshelf": "книжный шкаф", "lamp": "лампа", "stairs_down": "лестница вниз"}
items = []
for k, label in NAMES.items():
    im = Image.open(os.path.join(src, k + ".png")).convert("RGBA")
    box = im.getbbox()
    im = im.crop(box)
    assert im.width % 2 == 0 and im.height % 2 == 0, k
    im = im.resize((im.width // 2, im.height // 2), Image.NEAREST)
    items.append((k, label, im))
cell = (max(i.width for _, _, i in items) + 4, max(i.height for _, _, i in items) + 4)
cols = 4
rows = (len(items) + cols - 1) // cols
raw = Image.new("RGBA", (cols * cell[0], rows * cell[1]), (0, 0, 0, 0))
for n, (_, _, im) in enumerate(items):
    raw.alpha_composite(im, ((n % cols) * cell[0] + (cell[0] - im.width) // 2, (n // cols) * cell[1] + cell[1] - im.height - 2))
raw.save(os.path.join(OUT, "upstairs_props_raw.png"))
sc = 4
cw, ch = cell[0] * sc, cell[1] * sc + 34
sheet = Image.new("RGBA", (cols * cw + 8, rows * ch + 36), BG)
d = ImageDraw.Draw(sheet)
d.text((8, 8), "Служебка и второй этаж (scripts/space_prop.gd), родной размер ×4", font=FONT, fill=(255, 241, 214, 255))
for n, (k, label, im) in enumerate(items):
    x, y = 4 + (n % cols) * cw, 30 + (n // cols) * ch
    big = im.resize((im.width * sc, im.height * sc), Image.NEAREST)
    sheet.alpha_composite(big, (x + (cw - big.width) // 2, y + cell[1] * sc - big.height))
    d.text((x + 2, y + cell[1] * sc + 4), f"{k}: {label}"[:int(cw / 7.2)], font=FONT, fill=(255, 241, 214, 255))
sheet.save(os.path.join(OUT, "upstairs_props_labeled.png"))
print("готово", raw.size, sheet.size)
