#!/usr/bin/env python3
"""Раскраски мебели: для каждого базового предмета data/furniture.json делает версии в стилях лофт, японский и зимний (тот же спрайт, другой оттенок).
Стили и оттенки — в data/styles.json ("decor"). Базовые предметы не меняются; запуск пересобирает только варианты (поле "base").

  python3 tools/gen_decor.py
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
path = os.path.join(ROOT, "data", "furniture.json")
items = json.load(open(path, encoding="utf-8"))
styles = json.load(open(os.path.join(ROOT, "data", "styles.json"), encoding="utf-8"))["decor"]
base = [i for i in items if "base" not in i]
out = []
for b in base:
    b = dict(b)
    b.setdefault("style", "cozy")
    out.append(b)
for style, info in styles.items():
    if style == "cozy":
        continue
    for b in base:
        v = dict(b)
        v["id"] = f"{b['id']}_{style}"
        v["base"] = b["id"]
        v["style"] = style
        v["tint"] = "#" + info["tint"]
        v["price"] = int(round(b["price"] * 1.5 / 5.0)) * 5
        out.append(v)
json.dump(out, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent="\t")
print(len(base), "базовых,", len(out) - len(base), "вариантов")
