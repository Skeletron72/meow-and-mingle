#!/usr/bin/env python3
"""Набор значков интерфейса 16×16 в стиле игры: тёплая палитра, тёмная обводка 1 px, свет сверху-слева. Рисуются примитивами (прямоугольники,
эллипсы, многоугольники, линии) на поле 14×14, обводка добавляется автоматически.

  python3 tools/generators/make_icons.py     # пишет assets/ui/icons_game.png и data/icons.json (имя → [x, y, w, h])

Добавить значок: функция с декоратором @icon("имя") и запуск скрипта.
"""
import json
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_PNG = os.path.join(ROOT, "assets", "ui", "icons_game.png")
OUT_JSON = os.path.join(ROOT, "data", "icons.json")
OL = (59, 42, 61, 255)
C = {k: tuple(int(v[i:i + 2], 16) for i in (0, 2, 4)) + (255,) for k, v in {
    "w": "fbf3e2", "c": "f2dcae", "y": "ffd640", "Y": "c2891a", "r": "e0503f", "R": "8f2a22", "p": "ff9bb0", "P": "c8506c", "b": "62b6e0", "B": "2f6ea0",
    "g": "6fc45a", "G": "3d8c48", "n": "b88050", "N": "6b4527", "s": "c4c4d4", "S": "70708a", "l": "b4e4f6", "v": "a878d8", "V": "6a44a0", "x": "f4963a", "k": "3b2a3d", "t": "e8b88a"}.items()}
ICONS = {}


def icon(name):
    def deco(fn):
        ICONS[name] = fn
        return fn
    return deco


class Canvas:
    """Поле 16×16; рисуем в координатах 0..15, потом outline() обводит всё нарисованное."""

    def __init__(self):
        self.img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def rect(self, x0, y0, x1, y1, c):
        self.d.rectangle([x0, y0, x1, y1], fill=C[c])

    def ell(self, x0, y0, x1, y1, c):
        self.d.ellipse([x0, y0, x1, y1], fill=C[c])

    def poly(self, pts, c):
        self.d.polygon(pts, fill=C[c])

    def line(self, pts, c, w=1):
        self.d.line(pts, fill=C[c], width=w)

    def px(self, x, y, c):
        self.img.putpixel((x, y), C[c])

    def outline(self):
        src = self.img.copy()
        for y in range(16):
            for x in range(16):
                if src.getpixel((x, y))[3] == 0:
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < 16 and 0 <= ny < 16 and src.getpixel((nx, ny))[3] > 0:
                            self.img.putpixel((x, y), OL)
                            break
        return self.img


def hard(img):
    """Убирает полупрозрачность от рисования (Pillow без сглаживания и так даёт 0/255, но на всякий случай)."""
    for y in range(16):
        for x in range(16):
            r, g, b, a = img.getpixel((x, y))
            img.putpixel((x, y), (r, g, b, 255 if a > 127 else 0))
    return img


@icon("star")
def _(c):
    c.poly([(8, 1), (10, 6), (14, 6), (11, 9), (12, 14), (8, 11), (4, 14), (5, 9), (2, 6), (6, 6)], "y")
    c.poly([(8, 3), (9, 6), (12, 6), (9, 8), (8, 10)], "w") if False else None
    c.px(7, 5, "w"); c.px(6, 7, "w")
    c.px(10, 10, "Y"); c.px(11, 12, "Y"); c.px(9, 11, "Y")


@icon("star_off")
def _(c):
    c.poly([(8, 1), (10, 6), (14, 6), (11, 9), (12, 14), (8, 11), (4, 14), (5, 9), (2, 6), (6, 6)], "s")
    c.px(7, 5, "w"); c.px(6, 7, "w")


@icon("fish")
def _(c):
    c.ell(1, 4, 11, 12, "b")
    c.poly([(10, 8), (15, 4), (15, 13)], "B")
    c.rect(3, 6, 8, 7, "l")
    c.px(3, 7, "w"); c.px(3, 8, "k")


@icon("gift")
def _(c):
    c.rect(2, 6, 13, 14, "r")
    c.rect(1, 4, 14, 7, "p")
    c.rect(7, 4, 8, 14, "y")
    c.ell(3, 1, 7, 4, "y"); c.ell(8, 1, 12, 4, "y")
    c.rect(2, 12, 13, 14, "R")


@icon("bag")
def _(c):
    c.rect(2, 6, 13, 14, "r")
    c.rect(2, 12, 13, 14, "R")
    c.rect(4, 8, 11, 10, "w")
    c.line([(5, 6), (5, 3), (10, 3), (10, 6)], "n", 1)
    c.px(7, 9, "r"); c.px(8, 9, "r")


@icon("quest")
def _(c):
    c.rect(2, 2, 13, 14, "w")
    c.rect(5, 1, 10, 3, "n")
    for y in (6, 9, 12):
        c.px(4, y, "g"); c.px(5, y, "g")
        c.rect(7, y, 11, y, "S")
    c.px(3, 6, "G")


@icon("hammer")
def _(c):
    c.rect(2, 1, 12, 5, "s")
    c.rect(2, 4, 12, 5, "S")
    c.rect(6, 6, 8, 14, "n")
    c.rect(8, 6, 8, 14, "N")


@icon("paw")
def _(c):
    for x0, y0, x1, y1 in ((1, 6, 3, 9), (4, 2, 6, 6), (9, 2, 11, 6), (12, 6, 14, 9)):
        c.ell(x0, y0, x1, y1, "n")
    c.ell(3, 9, 12, 14, "n")
    c.rect(5, 11, 10, 12, "t")


@icon("cat")
def _(c):
    c.poly([(2, 7), (3, 1), (7, 4)], "x"); c.poly([(13, 7), (12, 1), (8, 4)], "x")
    c.ell(1, 3, 14, 14, "x")
    c.rect(4, 7, 5, 9, "k"); c.rect(10, 7, 11, 9, "k")
    c.px(4, 7, "w"); c.px(10, 7, "w")
    c.px(7, 10, "p"); c.px(8, 10, "p")
    c.px(6, 11, "k"); c.px(9, 11, "k"); c.px(7, 12, "k"); c.px(8, 12, "k")


@icon("book")
def _(c):
    c.rect(2, 2, 13, 13, "b")
    c.rect(2, 11, 13, 13, "B")
    c.rect(4, 3, 12, 11, "w")
    c.rect(4, 3, 4, 11, "r")
    c.rect(6, 5, 10, 5, "S"); c.rect(6, 7, 10, 7, "S"); c.rect(6, 9, 9, 9, "S")


@icon("calendar")
def _(c):
    c.rect(2, 3, 13, 14, "w")
    c.rect(2, 3, 13, 6, "r")
    c.rect(4, 1, 5, 4, "S"); c.rect(10, 1, 11, 4, "S")
    for x, y in ((4, 8), (7, 8), (10, 8), (4, 11), (7, 11)):
        c.rect(x, y, x + 1, y + 1, "S")
    c.rect(10, 11, 11, 12, "y")


@icon("crown")
def _(c):
    c.poly([(1, 5), (4, 8), (8, 2), (12, 8), (15, 5), (14, 13), (2, 13)], "y")
    c.rect(2, 11, 14, 13, "Y")
    c.px(8, 4, "w"); c.px(4, 10, "r"); c.px(8, 10, "b"); c.px(12, 10, "g")


@icon("heart")
def _(c):
    c.ell(1, 2, 8, 9, "r"); c.ell(7, 2, 14, 9, "r")
    c.poly([(2, 7), (13, 7), (8, 14)], "r")
    c.px(4, 4, "p"); c.px(5, 3, "p")


@icon("heart_off")
def _(c):
    c.ell(1, 2, 8, 9, "s"); c.ell(7, 2, 14, 9, "s")
    c.poly([(2, 7), (13, 7), (8, 14)], "s")
    c.px(4, 4, "w"); c.px(5, 3, "w")


@icon("lock")
def _(c):
    c.line([(5, 7), (5, 3), (10, 3), (10, 7)], "s", 2)
    c.rect(3, 7, 12, 14, "y")
    c.rect(3, 12, 12, 14, "Y")
    c.rect(7, 9, 8, 11, "k")


@icon("clock")
def _(c):
    c.ell(1, 1, 14, 14, "w")
    c.line([(8, 8), (8, 4)], "k"); c.line([(8, 8), (11, 9)], "k")
    c.rect(7, 7, 8, 8, "r")


@icon("bell")
def _(c):
    c.poly([(8, 1), (11, 4), (12, 11), (14, 12), (14, 13), (2, 13), (2, 12), (4, 11), (5, 4)], "y")
    c.rect(2, 12, 14, 13, "Y")
    c.ell(6, 12, 9, 15, "n") if False else c.rect(7, 14, 8, 14, "N")
    c.px(6, 5, "w"); c.px(6, 7, "w")


@icon("note")
def _(c):
    c.line([(5, 3), (5, 11)], "k", 2)
    c.line([(5, 3), (12, 2)], "k", 2)
    c.line([(12, 2), (12, 9)], "k", 2)
    c.ell(2, 10, 6, 13, "k"); c.ell(9, 8, 13, 11, "k")


@icon("speaker")
def _(c):
    c.rect(1, 5, 4, 10, "s")
    c.poly([(4, 5), (9, 2), (9, 13), (4, 10)], "s")
    c.line([(11, 5), (12, 8), (11, 11)], "S", 1)
    c.line([(13, 3), (15, 8), (13, 13)], "S", 1)


@icon("speaker_off")
def _(c):
    c.rect(1, 5, 4, 10, "s")
    c.poly([(4, 5), (9, 2), (9, 13), (4, 10)], "s")
    c.line([(11, 5), (15, 11)], "r", 2); c.line([(15, 5), (11, 11)], "r", 2)


@icon("globe")
def _(c):
    c.ell(1, 1, 14, 14, "b")
    c.poly([(4, 3), (8, 3), (9, 6), (6, 8), (5, 6)], "g"); c.poly([(9, 9), (12, 8), (12, 12), (9, 13)], "g")
    c.px(4, 4, "l")


@icon("video")
def _(c):
    c.rect(1, 3, 14, 12, "S")
    c.rect(2, 4, 13, 11, "k")
    c.poly([(6, 5), (6, 10), (11, 7)], "y")


@icon("bolt")
def _(c):
    c.poly([(9, 1), (3, 9), (7, 9), (6, 15), (13, 6), (9, 6), (11, 1)], "y")
    c.px(8, 3, "w"); c.px(7, 5, "w")


@icon("info")
def _(c):
    c.ell(1, 1, 14, 14, "b")
    c.rect(7, 3, 8, 4, "w"); c.rect(7, 6, 8, 11, "w")


@icon("close")
def _(c):
    c.line([(3, 3), (12, 12)], "r", 3); c.line([(12, 3), (3, 12)], "r", 3)


@icon("plus")
def _(c):
    c.rect(6, 2, 9, 13, "g"); c.rect(2, 6, 13, 9, "g")


@icon("arrow_r")
def _(c):
    c.poly([(2, 5), (8, 5), (8, 2), (14, 8), (8, 14), (8, 11), (2, 11)], "w")


@icon("arrow_l")
def _(c):
    c.poly([(14, 5), (8, 5), (8, 2), (2, 8), (8, 14), (8, 11), (14, 11)], "w")


@icon("mail")
def _(c):
    c.rect(1, 3, 14, 13, "w")
    c.line([(1, 3), (8, 9), (14, 3)], "s")
    c.rect(1, 12, 14, 13, "s")


@icon("shield")
def _(c):
    c.poly([(2, 2), (13, 2), (13, 8), (8, 14), (2, 8)], "b")
    c.poly([(5, 4), (11, 4), (11, 8), (8, 11), (5, 8)], "l")
    c.rect(7, 5, 8, 9, "w")


@icon("doc")
def _(c):
    c.rect(3, 1, 12, 14, "w")
    c.poly([(9, 1), (12, 4), (9, 4)], "s")
    for y in (6, 8, 10, 12):
        c.rect(5, y, 10, y, "S")


@icon("cup")
def _(c):
    c.rect(2, 5, 10, 13, "w")
    c.rect(3, 6, 9, 8, "N")
    c.line([(11, 6), (13, 7), (13, 9), (11, 10)], "w", 1)
    c.rect(2, 12, 10, 13, "s")
    c.px(5, 2, "s"); c.px(7, 1, "s"); c.px(6, 3, "s")


@icon("pastry")
def _(c):
    c.ell(1, 4, 14, 14, "x")
    c.ell(4, 7, 11, 14, "w") if False else None
    c.poly([(1, 10), (4, 5), (8, 3), (12, 5), (14, 10), (11, 8), (8, 7), (5, 8)], "x")
    c.poly([(4, 9), (8, 8), (12, 9), (14, 12), (11, 13), (8, 12), (5, 13), (2, 12)], "Y") if False else None
    for x in (5, 8, 11):
        c.line([(x, 5), (x, 8)], "Y")
    c.px(6, 4, "y"); c.px(9, 4, "y")


@icon("sofa")
def _(c):
    c.rect(2, 3, 13, 8, "p"); c.rect(1, 7, 14, 12, "P")
    c.rect(3, 8, 12, 10, "p")
    c.rect(2, 12, 3, 14, "N"); c.rect(12, 12, 13, 14, "N")


@icon("dots")
def _(c):
    for x in (2, 6, 10):
        c.rect(x, 6, x + 2, 8, "w")
    for x in (2, 6, 10):
        c.px(x, 8, "s")


@icon("snow")
def _(c):
    for p in (((8, 1), (8, 14)), ((2, 4), (13, 11)), ((13, 4), (2, 11))):
        c.line(list(p), "l", 2)
    c.rect(7, 7, 8, 8, "w")


@icon("sun")
def _(c):
    c.ell(4, 4, 11, 11, "y")
    for p in ((8, 0), (8, 14), (0, 8), (14, 8), (2, 2), (13, 2), (2, 13), (13, 13)):
        c.px(p[0], p[1], "x"); c.px(p[0] + (1 if p[0] < 14 else 0), p[1], "x")
    c.px(6, 6, "w")


@icon("drop")
def _(c):
    c.poly([(8, 1), (13, 9), (12, 12), (8, 14), (4, 12), (3, 9)], "b")
    c.px(6, 9, "w"); c.px(6, 10, "w")


@icon("lamp")
def _(c):
    c.poly([(4, 2), (11, 2), (13, 8), (2, 8)], "y")
    c.rect(7, 8, 8, 12, "S"); c.rect(4, 12, 11, 13, "S")
    c.px(5, 4, "w")


def main():
    names = list(ICONS)
    cols = 8
    rows = (len(names) + cols - 1) // cols
    atlas = Image.new("RGBA", (cols * 16, rows * 16), (0, 0, 0, 0))
    rects = {}
    for i, n in enumerate(names):
        cv = Canvas()
        ICONS[n](cv)
        im = hard(cv.outline())
        atlas.paste(im, ((i % cols) * 16, (i // cols) * 16))
        rects[n] = [(i % cols) * 16, (i // cols) * 16, 16, 16]
    atlas.save(OUT_PNG)
    json.dump(rects, open(OUT_JSON, "w"), indent=1)
    big = Image.new("RGBA", (atlas.width, atlas.height), (176, 140, 100, 255))
    big.alpha_composite(atlas)
    big.resize((atlas.width * 6, atlas.height * 6), Image.NEAREST).save("/tmp/icons_preview.png")
    print(len(names), "значков →", OUT_PNG)


if __name__ == "__main__":
    main()
