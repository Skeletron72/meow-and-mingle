#!/usr/bin/env python3
"""Собирает вертикальные скриншоты магазина 1080×1920: подпись сверху, кадр игры в рамке, тёплый фон с дизерингом.
  python3 tools/store_compose.py <папка с кадрами store_shots> <ru|en>      → store/<ru|en>/screenshots/NN_name.png"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src, lang = sys.argv[1], sys.argv[2]
OUT = os.path.join(ROOT, "store", lang, "screenshots")
os.makedirs(OUT, exist_ok=True)
FONT = ImageFont.truetype(os.path.join(ROOT, "assets", "fonts", "Galmuri11-Bold.ttf" if os.path.exists(os.path.join(ROOT, "assets", "fonts", "Galmuri11-Bold.ttf")) else "Galmuri11.ttf"), 76)
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
CAPTIONS = {
    "ru": [("01_shift", "Готовь и подавай\\nзаказы котам"), ("04_cafe_rain", "Уютное кафе\\nв пиксель-арте"), ("02_riddle", "Загадочные гости:\\nотгадай заказ"), ("03_results", "Очки, звёзды\\nи чаевые"),
           ("06_cats", "Коты с талантами\\nи характером"), ("05_repairs", "Верни к жизни\\nмамино кафе"), ("07_decorate", "Обставь кафе\\nпо-своему"), ("08_snow_night", "Снег, дождь,\\nдень и ночь"), ("09_quests", "Задания дня,\\nсобытия и награды")],
    "en": [("01_shift", "Brew, serve,\\nand charm the cats"), ("04_cafe_rain", "A cozy pixel\\ncat café"), ("02_riddle", "Mystery guests:\\nguess the order"), ("03_results", "Points, stars\\nand tips"),
           ("06_cats", "Cats with talents\\nand personality"), ("05_repairs", "Restore mom's\\nold café"), ("07_decorate", "Decorate it\\nyour way"), ("08_snow_night", "Snow, rain,\\nday and night"), ("09_quests", "Daily quests,\\nevents and rewards")],
}


def background(w, h):
    top, bot = (255, 226, 178), (232, 140, 96)
    im = Image.new("RGB", (w, h))
    px = im.load()
    step = 12
    for y in range(0, h, step):
        for x in range(0, w, step):
            t = y / h * 4.0
            lo = int(t)
            lvl = lo + (1 if (t - lo) > (BAYER[(y // step) % 4][(x // step) % 4] + 0.5) / 16.0 else 0)
            u = min(lvl, 4) / 4.0
            c = tuple(int(top[i] + (bot[i] - top[i]) * u) for i in range(3))
            for dy in range(step):
                for dx in range(step):
                    if x + dx < w and y + dy < h:
                        px[x + dx, y + dy] = c
    return im


for n, (name, text) in enumerate(CAPTIONS[lang], 1):
    shot = Image.open(os.path.join(src, name + ".png")).convert("RGB")
    canvas = background(1080, 1920)
    gw, gh = 900, 1600
    game = shot.resize((gw, gh), Image.LANCZOS)
    mask = Image.new("L", (gw, gh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, gw - 1, gh - 1), radius=40, fill=255)
    border = Image.new("RGB", (gw + 16, gh + 16), (59, 42, 61))
    bm = Image.new("L", border.size, 0)
    ImageDraw.Draw(bm).rounded_rectangle((0, 0, border.width - 1, border.height - 1), radius=48, fill=255)
    canvas.paste(border, (82, 292), bm)
    canvas.paste(game, (90, 300), mask)
    d = ImageDraw.Draw(canvas)
    lines = text.replace("\\n", "\n").split("\n")
    y = 40
    for line in lines:
        w = d.textlength(line, font=FONT)
        d.text(((1080 - w) / 2, y), line, font=FONT, fill=(255, 250, 238), stroke_width=8, stroke_fill=(59, 42, 61))
        y += 108
    canvas.save(os.path.join(OUT, f"{n:02d}_{name.split('_', 1)[1]}.png"))
print("готово", sorted(os.listdir(OUT)))
