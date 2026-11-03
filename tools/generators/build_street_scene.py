#!/usr/bin/env python3
"""Генерирует scenes/street.tscn (здания, предметы, зоны) БЕЗ земли. Землю (слой Ground) добавляет
tools/generators/paint_street_ground.gd. ВНИМАНИЕ: перезаписывает сцену целиком — это сброс уровня к исходному,
не запускайте, если правили street.tscn в редакторе.

  python3 tools/generators/build_street_scene.py
  godot --headless --path . --script res://tools/generators/paint_street_ground.gd
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
m = json.load(open(os.path.join(ROOT, "data", "street.json")))

BASE = 704                      # линия, где фасады встают на тротуар (кратна 32)
WORLD = (2624, 960)
scripts = {"level": "street_level", "zone": "street_zone", "building": "street_building", "prop": "street_prop"}
ext, ids, nodes = [], {}, []


def eid(kind, path):
    key = (kind, path)
    if key not in ids:
        ids[key] = len(ids) + 1
        ext.append(f'[ext_resource type="{kind}" path="{path}" id="{ids[key]}"]')
    return ids[key]


for v in scripts.values():
    eid("Script", f"res://scripts/{v}.gd")


def sid(k):
    return ids[("Script", f"res://scripts/{scripts[k]}.gd")]


nodes.append(f'[node name="Street" type="Node2D"]\nscript = ExtResource("{sid("level")}")\nworld_size = Vector2({WORLD[0]}, {WORLD[1]})')
nodes.append('[node name="Zones" type="Node2D" parent="."]')
KIND = {"WALK": 0, "BLOCK": 1, "LANE_EAST": 2, "LANE_WEST": 3, "CAFE_INTERIOR": 4}

# здания: (id, x). Между домами проходы ≥ 96 px; у кафе x подобран так, чтобы пол интерьера лёг в сетку 32 px
BLDS = [("building3", 64), ("building4", 374), ("building1", 832), ("building2", 1152), ("building7", 1600), ("building3", 1920), ("building1", 2240)]
zones = []
zones.append(("CafeInterior", "CAFE_INTERIOR", 384, BASE - 320, 320, 320))
zones.append(("Sidewalk", "WALK", 32, BASE, WORLD[0] - 64, 64))
zones.append(("BackYard", "WALK", 32, 96, WORLD[0] - 64, 224))
zones.append(("LaneWest", "LANE_WEST", 0, 784, WORLD[0], 80))
zones.append(("LaneEast", "LANE_EAST", 0, 876, WORLD[0], 80))
# проходы между домами (и по краям): от заднего двора до тротуара
edges = [(0, BLDS[0][1])]
widths = {b: m["buildings"][b]["size"][0] * 2 for b, _ in BLDS}
for i in range(len(BLDS) - 1):
    edges.append((BLDS[i][1] + widths[BLDS[i][0]], BLDS[i + 1][1]))
edges.append((BLDS[-1][1] + widths[BLDS[-1][0]], WORLD[0]))
for i, (r, l) in enumerate(edges):
    x0, x1 = (32, 64) if i == 0 else (r + 16, l - 16 if i < len(edges) - 1 else WORLD[0] - 32)
    zones.append((f"Alley{i}", "WALK", x0, 288, x1 - x0, BASE - 288))
for name, k, x, y, w, h in zones:
    nodes.append(f'[node name="{name}" type="ReferenceRect" parent="Zones"]\nlayout_mode = 3\nanchors_preset = 0\noffset_left = {float(x)}\noffset_top = {float(y)}\noffset_right = {float(x + w)}\noffset_bottom = {float(y + h)}\nscript = ExtResource("{sid("zone")}")\nkind = {KIND[k]}')

nodes.append('[node name="Buildings" type="Node2D" parent="."]')
cnt = {}
for b, x in BLDS:
    tid = eid("Texture2D", f"res://assets/street/buildings/{b}.png")
    h = m["buildings"][b]["size"][1]
    cnt[b] = cnt.get(b, 0) + 1
    name = b.capitalize() + ("" if cnt[b] == 1 else str(cnt[b]))
    cafe = "\nis_cafe = true" if b == "building4" else ""
    nodes.append(f'[node name="{name}" type="Sprite2D" parent="Buildings"]\nposition = Vector2({x}, {BASE})\nscale = Vector2(2, 2)\ntexture = ExtResource("{tid}")\ncentered = false\noffset = Vector2(0, {-h})\nscript = ExtResource("{sid("building")}"){cafe}')

nodes.append('[node name="Props" type="Node2D" parent="."]')
# (id, x, y лапок, blocks, emits_light)
street = [("vending_beige", 232, 724), ("hydrant", 850, 724), ("bush1", 910, 724), ("bush2", 970, 724), ("trashbin", 1004, 724),
          ("vending_red", 1200, 724), ("plant3", 1340, 724), ("vending_green", 1630, 724), ("tree2", 1840, 756),
          ("trashbin", 1960, 724), ("bush1", 2090, 724), ("vending_yellow", 2270, 724), ("tree1", 2480, 756), ("tree3", 2570, 756), ("tree3", 24, 756)]
lamps = [320, 772, 1090, 1540, 1860, 2180, 2520]
yard = [("tree2", 140, 200), ("tree1", 420, 160), ("tree3", 700, 230), ("tree2", 980, 170), ("tree1", 1300, 210), ("tree3", 1560, 150),
        ("tree2", 1860, 220), ("tree1", 2200, 180), ("tree3", 2500, 240), ("bush1", 300, 270), ("bush2", 560, 262), ("bush1", 880, 270),
        ("bush2", 1200, 262), ("bush1", 1700, 270), ("bush2", 2040, 268), ("bush1", 2380, 270), ("table_round", 520, 232),
        ("chair_side", 488, 238), ("chair_side", 552, 238), ("trashbin", 240, 312), ("trashbin", 1450, 312), ("plant1", 800, 300), ("plant4", 1750, 300)]
props = [(p, x, y, True, False) for p, x, y in street + yard] + [("lamp", x, 776, False, True) for x in lamps] + [("lamp", 480, 300, False, True), ("lamp", 1500, 300, False, True)]
cnt = {}
for p, x, y, bl, li in props:
    cnt[p] = cnt.get(p, 0) + 1
    name = p.capitalize().replace("_", "") + str(cnt[p])
    tid = eid("Texture2D", f"res://assets/street/props/{p}.png")
    w, h = m["props"][p]["size"]
    extra = ("\nblocks = true" if bl else "") + ("\nemits_light = true" if li else "")
    nodes.append(f'[node name="{name}" type="Sprite2D" parent="Props"]\nposition = Vector2({x}, {y})\nscale = Vector2(2, 2)\ntexture = ExtResource("{tid}")\ncentered = false\noffset = Vector2({-(w // 2)}, {-h})\nscript = ExtResource("{sid("prop")}"){extra}')

head = f"[gd_scene load_steps={len(ext) + 1} format=3]\n\n" + "\n".join(ext) + "\n\n"
open(os.path.join(ROOT, "scenes", "street.tscn"), "w").write(head + "\n\n".join(nodes) + "\n")
print(len(nodes), "nodes; world", WORLD)
