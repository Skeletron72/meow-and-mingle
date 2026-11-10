#!/usr/bin/env python3
"""Накладки трейлера в сетке игры (1 пиксель арта = 6 px): плашки-подписи c0…c6.png (прозрачные 1080×1920) и финальный кадр end.png
(кадр фасада из записи + плашка с иконкой и названием).  python3 tools/make_trailer_art.py <папка> <ru|en> <кадр фасада.png>"""
import importlib.util
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import store_art as sa  # noqa: E402

out, lang, frame = sys.argv[1], sys.argv[2], sys.argv[3]
CAPS = {
    "ru": ["Мама оставила кафе…", "…пора его открыть!", "Готовь, добавляй, подавай!", "27 напитков с начинками", "Очки, звёзды и чаевые", "Коты с талантами", "Обставь кафе по-своему"],
    "en": ["Mom left her café…", "…time to open it!", "Brew, top up, serve!", "27 drinks with toppings", "Points, stars and tips", "Cats with talents", "Decorate it your way"],
}
for i, text in enumerate(CAPS[lang]):
    layer = Image.new("RGBA", (1080, 1920), (0, 0, 0, 0))
    plate = sa.up(sa.band([text]))
    layer.alpha_composite(plate, ((1080 - plate.width) // 2, 4 * sa.K))
    layer.save(os.path.join(out, f"c{i}.png"))

spec = importlib.util.spec_from_file_location("icon", os.path.join(sa.ROOT, "tools", "generators", "make_store_icon.py"))
icon_mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(icon_mod)
end = Image.open(frame).convert("RGBA")
assert end.size == (1080, 1920)
title = ["Тёплая Лапка", "кошачье кафе"] if lang == "ru" else ["Meow & Mingle", "cozy cat café"]
plate = sa.up(sa.band(title, 172, icon_mod.art("a")))     # иконка 32×32 в родном масштабе — та же сетка, что и текст
foot = sa.up(sa.band(["Скоро в RuStore" if lang == "ru" else "Coming soon"], 124))
y = 4 * sa.K
end.alpha_composite(plate, ((1080 - plate.width) // 2, y))
end.alpha_composite(foot, (((1080 - foot.width) // 2) // sa.K * sa.K, y + plate.height + 2 * sa.K))
end.convert("RGB").save(os.path.join(out, "end.png"))
