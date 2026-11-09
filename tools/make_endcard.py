#!/usr/bin/env python3
"""Финальная плашка трейлера 1080×1920: иконка, название, слоган.  python3 tools/make_endcard.py <out.png> <ru|en>"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out, lang = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.join(ROOT, "tools"))
FONT = os.path.join(ROOT, "assets", "fonts", "Galmuri11.ttf")
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
top, bot = (255, 226, 178), (232, 140, 96)
im = Image.new("RGB", (1080, 1920))
px = im.load()
for y in range(0, 1920, 12):
    for x in range(0, 1080, 12):
        t = y / 1920 * 4.0
        lo = int(t)
        lvl = lo + (1 if (t - lo) > (BAYER[(y // 12) % 4][(x // 12) % 4] + 0.5) / 16.0 else 0)
        u = min(lvl, 4) / 4.0
        c = tuple(int(top[i] + (bot[i] - top[i]) * u) for i in range(3))
        for dy in range(12):
            for dx in range(12):
                px[x + dx, y + dy] = c
icon = Image.open(os.path.join(ROOT, "assets/icons/icon_512.png")).convert("RGBA")
icon = icon.resize((640, 640), Image.NEAREST)
mask = Image.new("L", icon.size, 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, 639, 639), radius=120, fill=255)
im.paste(icon, (220, 420), mask)
d = ImageDraw.Draw(im)
title = "Тёплая Лапка" if lang == "ru" else "Meow & Mingle"
sub = ["Кошачье кафе", "в пиксель-арте"] if lang == "ru" else ["A cozy pixel-art", "cat café game"]
foot = "Скоро в RuStore" if lang == "ru" else "Coming soon"
f1, f2, f3 = (ImageFont.truetype(FONT, s) for s in (120, 64, 56))
d.text(((1080 - d.textlength(title, font=f1)) / 2, 1160), title, font=f1, fill=(255, 250, 238), stroke_width=10, stroke_fill=(59, 42, 61))
y = 1340
for line in sub:
    d.text(((1080 - d.textlength(line, font=f2)) / 2, y), line, font=f2, fill=(255, 250, 238), stroke_width=6, stroke_fill=(59, 42, 61))
    y += 84
d.text(((1080 - d.textlength(foot, font=f3)) / 2, 1640), foot, font=f3, fill=(255, 250, 238), stroke_width=6, stroke_fill=(59, 42, 61))
im.save(out)
