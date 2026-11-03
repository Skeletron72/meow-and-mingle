#!/usr/bin/env python3
"""Отбирает ассеты города из assets/packs (их Godot не импортирует: см. assets/packs/.gdignore)
в assets/street, обрезая пустые поля, и пишет data/street.json (размеры, окна, машины).

  python3 tools/curate_street_assets.py

Нужны Pillow и numpy. Исходные паки не меняются.
"""
import glob
import json
import os
import re

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACKS = os.path.join(ROOT, "assets", "packs")
OUT = os.path.join(ROOT, "assets", "street")

BUILDINGS = {1: "building1", 2: "building2", 3: "building3", 4: "building4", 7: "building7"}
PROPS = {
    "Light Pole": "lamp", "Tree1": "tree1", "Tree2": "tree2", "Tree3": "tree3", "Bush1": "bush1", "Bush2": "bush2",
    "Fire Hidrant": "hydrant", "Closed Trashbin": "trashbin", "Opened Trashbin": "trashbin_open",
    "Beige Vending Machine": "vending_beige", "Green Vending Machine": "vending_green",
    "Red Vending machine": "vending_red", "Yellow Vending Machine": "vending_yellow",
    "Plant1": "plant1", "Plant3": "plant3", "Plant4": "plant4", "Opened Cardboard box": "box_open",
    "vertical cardboardbox": "box", "Trashbag": "trashbag", "Sign1": "sign1", "Sign2": "sign2",
    "Side chair": "chair_side", "Square table": "table_square", "Circular table": "table_round",
}
# (папка пака, цвет или None, id). Только машины не выше ~44 px арта: полоса движения — 80 px (автобус не влезает)
VEHICLES = [
    ("SEDAN TOPDOWN", "Blue", "sedan_blue"), ("SEDAN TOPDOWN", "Red", "sedan_red"),
    ("SEDAN TOPDOWN", "Yellow", "sedan_yellow"), ("SEDAN TOPDOWN", "White", "sedan_white"),
    ("HATCHBACK TOPDOWN", "Green", "hatchback_green"), ("PICKUP TOPDOWN", "Brown", "pickup_brown"),
    ("MINIVAN TOPDOWN", "Magenta", "minivan_magenta"), ("VAN TOP DOWN", "White", "van_white"),
    ("TAXI TOPDOWN", None, "taxi"), ("POLICE TOPDOWN", None, "police"),
]


def trim(im):
    box = im.getbbox()
    return im.crop(box), box


# Окна фасадов (x, y, w, h в пикселях арта обрезанного спрайта) — отмечены вручную; ночью в них зажигается свет.
WINDOWS = {
    "building1": [[7, 75, 15, 23], [77, 75, 14, 23], [7, 121, 26, 25], [65, 121, 27, 25]],
    "building2": [[88, 75, 13, 22], [139, 75, 14, 22], [13, 140, 27, 19], [44, 140, 27, 19], [75, 140, 27, 19], [123, 143, 15, 22]],
    "building3": [[57, 124, 25, 23], [18, 127, 15, 9]],
    "building4": [[17, 75, 27, 21], [127, 75, 26, 21], [33, 131, 33, 26], [68, 131, 33, 26], [104, 131, 33, 26]],
    "building7": [[12, 75, 17, 23], [42, 75, 15, 23], [72, 75, 15, 23], [44, 122, 47, 28], [14, 128, 16, 24]],
}


def curate_buildings(meta):
    os.makedirs(os.path.join(OUT, "buildings"), exist_ok=True)
    meta["buildings"] = {}
    for n, name in BUILDINGS.items():
        im = Image.open(os.path.join(PACKS, "city-essentials", "Buildings", "Pngs", f"Building{n}.png")).convert("RGBA")
        tr, box = trim(im)
        tr.save(os.path.join(OUT, "buildings", name + ".png"))
        meta["buildings"][name] = {"size": list(tr.size), "windows": WINDOWS[name]}


def curate_props(meta):
    os.makedirs(os.path.join(OUT, "props"), exist_ok=True)
    meta["props"] = {}
    for src, name in PROPS.items():
        im = Image.open(os.path.join(PACKS, "city-essentials", "Assets", src + ".png")).convert("RGBA")
        tr, _ = trim(im)
        tr.save(os.path.join(OUT, "props", name + ".png"))
        meta["props"][name] = {"size": list(tr.size)}


def curate_vehicles(meta):
    os.makedirs(os.path.join(OUT, "vehicles"), exist_ok=True)
    meta["vehicles"] = []
    for cat, color, vid in VEHICLES:
        sheets = {}
        for d in ("EAST", "WEST"):
            base = os.path.join(PACKS, "topdown-vehicles", cat, color or "")
            fs = glob.glob(os.path.join(base, "MOVE", d, "*sheet.png"))
            sheets[d] = fs[0]
        im_e = Image.open(sheets["EAST"]).convert("RGBA")
        # размер кадра: делитель листа, дающий 4×3 кадров
        fw = im_e.width // 4
        fh = im_e.height // 3
        frames = {d: [] for d in sheets}
        union = None
        for d, f in sheets.items():
            im = Image.open(f).convert("RGBA")
            for r in range(3):
                for c in range(4):
                    fr = im.crop((c * fw, r * fh, (c + 1) * fw, (r + 1) * fh))
                    frames[d].append(fr)
                    b = fr.getbbox()
                    union = b if union is None else (min(union[0], b[0]), min(union[1], b[1]), max(union[2], b[2]), max(union[3], b[3]))
        w, h = union[2] - union[0], union[3] - union[1]
        for d in sheets:
            sheet = Image.new("RGBA", (w * 4, h * 3))
            for i, fr in enumerate(frames[d]):
                sheet.paste(fr.crop(union), ((i % 4) * w, (i // 4) * h))
            sheet.save(os.path.join(OUT, "vehicles", f"{vid}_{d.lower()}.png"))
        meta["vehicles"].append({"id": vid, "frame": [w, h], "cols": 4, "rows": 3})


if __name__ == "__main__":
    meta = {}
    curate_buildings(meta)
    curate_props(meta)
    curate_vehicles(meta)
    with open(os.path.join(ROOT, "data", "street.json"), "w") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    print("ok:", {k: len(v) for k, v in meta.items()})
