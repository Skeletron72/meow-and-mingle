#!/usr/bin/env python3
"""Скриншоты магазина 1080×1920 в единой сетке: кадр игры во весь экран ровно ×3 (1 пиксель арта = 6 px) и подпись на кремовой плашке,
нарисованной в той же сетке и тем же шрифтом, что интерфейс игры. Никаких масштабирований кадра, обводок и скруглений.
  python3 tools/store_compose.py <папка с кадрами store_shots> <ru|en>      → store/<ru|en>/screenshots/NN_name.png"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import store_art as sa  # noqa: E402

src, lang = sys.argv[1], sys.argv[2]
OUT = os.path.join(sa.ROOT, "store", lang, "screenshots")
os.makedirs(OUT, exist_ok=True)
CAPTIONS = {
    "ru": [("01_shift", "Готовь и подавай\nзаказы котам"), ("04_cafe_rain", "Уютное кафе\nв пиксель-арте"), ("02_riddle", "Загадочные гости:\nотгадай заказ"), ("03_results", "Очки, звёзды\nи чаевые"),
           ("06_cats", "Коты с талантами\nи характером"), ("05_repairs", "Верни к жизни\nмамино кафе"), ("07_decorate", "Обставь кафе\nпо-своему"), ("08_snow_night", "Снег, дождь,\nдень и ночь"), ("09_quests", "Задания дня,\nсобытия и награды")],
    "en": [("01_shift", "Brew, serve,\nand charm the cats"), ("04_cafe_rain", "A cozy pixel\ncat café"), ("02_riddle", "Mystery guests:\nguess the order"), ("03_results", "Points, stars\nand tips"),
           ("06_cats", "Cats with talents\nand personality"), ("05_repairs", "Restore mom's\nold café"), ("07_decorate", "Decorate it\nyour way"), ("08_snow_night", "Snow, rain,\nday and night"), ("09_quests", "Daily quests,\nevents and rewards")],
}

BOTTOM = {"02_riddle", "03_results", "06_cats", "05_repairs", "09_quests"}   # кадры, где верх занят заголовком окна или загадкой

for n, (name, text) in enumerate(CAPTIONS[lang], 1):
    shot = Image.open(os.path.join(src, name + ".png")).convert("RGBA")
    assert shot.size == (1080, 1920), "кадр должен быть снят ровно 1080×1920 (игра ×3)"
    plate = sa.up(sa.band(text.split("\n")))
    y = 1920 - plate.height - 4 * sa.K if name in BOTTOM else 4 * sa.K   # плашка не закрывает главное на кадре
    shot.alpha_composite(plate, ((1080 - plate.width) // 2, y))
    x = (1080 - plate.width) // 2
    assert x % sa.K == 0 and y % sa.K == 0 and sa.is_on_grid(shot, sa.K, (x + sa.K, y + sa.K, x + plate.width - sa.K, y + plate.height - sa.K)), "плашка подписи не в сетке"
    shot.convert("RGB").save(os.path.join(OUT, f"{n:02d}_{name.split('_', 1)[1]}.png"))
print("готово", sorted(os.listdir(OUT)))
