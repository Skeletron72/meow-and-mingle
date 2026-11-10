#!/usr/bin/env python3
"""Общие детали материалов магазина в сетке игры. Всё рисуется в «пикселях арта» (поле 180×320 для кадра 1080×1920) и увеличивается ровно ×6:
подпись получается в той же сетке, что и сама игра на кадре (1 пиксель арта = 6 px), без сглаживания, обводок и скруглений."""
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
K = 6                      # пиксель арта на кадре 1080×1920
INK = (74, 46, 26, 255)
OUT = (59, 42, 61, 255)
CREAM = (255, 241, 214, 255)
LEDGE = (232, 207, 160, 255)
FONT = ImageFont.truetype(os.path.join(ROOT, "assets", "fonts", "Galmuri11.ttf"), 12)   # родной кегль шрифта: 1 пиксель шрифта = 1 пиксель арта


def text_width(text):
    return int(FONT.getlength(text))


def panel(w, h):
    """Кремовая плашка как в игре: тёмный контур в 1 пиксель, срезанные углы, бортик снизу."""
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle((1, 0, w - 2, h - 1), fill=OUT)
    d.rectangle((0, 1, w - 1, h - 2), fill=OUT)
    d.rectangle((1, 1, w - 2, h - 2), fill=CREAM)
    d.rectangle((1, h - 4, w - 2, h - 2), fill=LEDGE)
    return im


def draw_text(im, text, x, y, color=INK):
    d = ImageDraw.Draw(im)
    d.fontmode = "1"       # без сглаживания: только целые пиксели
    d.text((x, y), text, font=FONT, fill=color)


def band(lines, width=172, icon=None):
    """Плашка с подписью по центру (строка 14 пикселей арта). icon — картинка слева (например, иконка игры 32×32)."""
    pad = 5
    ih = icon.height if icon is not None else 0
    h = max(pad + 14 * len(lines) + pad + 3, ih + 2 * pad + 3)
    im = panel(width, h)
    x0 = pad + (icon.width + pad if icon is not None else 0)
    if icon is not None:
        im.alpha_composite(icon, (pad, (h - 3 - ih) // 2))
    ty = (h - 3 - 14 * len(lines)) // 2
    for i, line in enumerate(lines):
        draw_text(im, line, x0 + (width - x0 - pad - text_width(line)) // 2, ty + 14 * i)
    return im


def up(im, k=K):
    return im.resize((im.width * k, im.height * k), Image.NEAREST)


def is_on_grid(im, k=K, box=None):
    """Проверка: область целиком состоит из клеток k×k одного цвета."""
    if box is not None:
        im = im.crop(box)
    small = im.resize((im.width // k, im.height // k), Image.NEAREST)
    return list(up(small, k).getdata()) == list(im.getdata())
