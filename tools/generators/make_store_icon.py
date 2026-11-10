#!/usr/bin/env python3
"""Иконка игры в ОДНОЙ сетке пикселей: кот выглядывает из-за чашки латте. Кот и чашка — спрайты игры в их родном масштабе 1:1 на поле 32×32,
фон (маркиза, стена и столешница) нарисован в той же сетке; затем всё поле увеличивается целым числом — ни один элемент не мельче и не крупнее другого.

  python3 tools/generators/make_store_icon.py

Пишет: store/ru/icon/icon_512_{a,b,c}.png (варианты), assets/icons/icon_512.png и icon_192.png, слои адаптивной иконки Android 432×432.
Масштабы целые: 512 = 32×16, 192 = 32×6, 432 = 36×12 (поле 36×36: кот и чашка в безопасной зоне 24×24)."""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
N = 32
VARIANTS = {   # кот, клетка чашки в листе напитков, стена (верх, низ), столешница (свет, тень), кайма стола
    "a": ("cat-orange-front.png", (4, 1), ((255, 236, 200), (250, 214, 160)), ((214, 142, 88), (184, 112, 66)), (122, 72, 44)),
    "b": ("cat-black-front.png", (2, 1), ((150, 190, 180), (116, 160, 152)), ((96, 122, 118), (72, 96, 96)), (44, 60, 62)),
    "c": ("cat-waiter-front.png", (3, 0), ((255, 222, 190), (250, 190, 150)), ((208, 104, 80), (176, 78, 62)), (116, 44, 40)),
}


def load(path):
    return Image.open(os.path.join(ROOT, path)).convert("RGBA")


def sprite(path, col, row):
    im = load(path).crop((col * 16, row * 16, col * 16 + 16, row * 16 + 16))
    return im.crop(im.getbbox())


AWNING = ((224, 80, 63), (255, 241, 214), (143, 42, 34))   # полосы маркизы кафе: красная, кремовая, тень под кромкой


def background(n, wall, table, edge, table_y, awning=True):
    """Стена: две ступени цвета с шахматной строкой между ними (дизеринг в той же сетке). Сверху — полосатая маркиза кафе с фестонами,
    ниже — столешница с тёмной каймой. Всё в клетках поля."""
    im = Image.new("RGBA", (n, n))
    px = im.load()
    aw = 5 if awning else 0
    mid = aw + (table_y - aw) // 2
    for y in range(n):
        for x in range(n):
            if y < table_y:
                c = wall[0] if y < mid else wall[1]
                if y == mid - 1 and (x + y) % 2 == 0:
                    c = wall[1]
                elif y == mid and (x + y) % 2 == 0:
                    c = wall[0]
            elif y == table_y:
                c = edge
            else:
                c = table[0] if y < table_y + 3 else table[1]
            if awning:
                stripe = AWNING[(x // 4) % 2]
                if y < aw:
                    c = stripe
                elif y == aw and x % 4 in (1, 2):      # фестон: закруглённый низ каждой полосы
                    c = stripe
                elif y == aw or (y == aw + 1 and x % 4 in (1, 2)):
                    c = AWNING[2]
            px[x, y] = c + (255,)
    return im


def subject(variant):
    """Кот и чашка одним слоем 16×23: чашка стоит впереди и закрывает подбородок и тело, глаза над краем чашки."""
    cat_file, cup_cell = VARIANTS[variant][0], VARIANTS[variant][1]
    cat = sprite("assets/cats/" + cat_file, 0, 0)                 # 14×14
    cup = sprite("assets/cafe/drinks-and-pastries.png", *cup_cell)  # до 16×16
    w = max(cat.width, cup.width)
    h = 9 + cup.height   # чашка начинается на 9-й строке кота: глаза (строки 5–7) остаются над ней
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    im.alpha_composite(cat, ((w - cat.width) // 2, 0))
    im.alpha_composite(cup, ((w - cup.width) // 2, 9))
    return im


def art(variant, n=N):
    _, _, wall, table, edge = VARIANTS[variant]
    sub = subject(variant)
    top = 7 + (n - 7 - sub.height) // 2 - 1    # под маркизой, чуть выше центра оставшегося поля
    table_y = top + sub.height - 5             # чашка стоит на столе: стол начинается под её нижней третью
    im = background(n, wall, table, edge, table_y)
    im.alpha_composite(sub, ((n - sub.width) // 2, top))
    return im


def up(im, k):
    return im.resize((im.width * k, im.height * k), Image.NEAREST)


def adaptive():
    """Слои адаптивной иконки Android на поле 36×36 по 12 px: фон отдельно, кот с чашкой — в безопасной зоне (центральные 24 клетки)."""
    n, k = 36, 12
    _, _, wall, table, edge = VARIANTS["a"]
    sub = subject("a")
    top = (n - sub.height) // 2
    bg = background(n, wall, table, edge, top + sub.height - 5, False)   # маску системы маркиза не переживёт: фон слоя — только стена и стол
    up(bg, k).save(os.path.join(ROOT, "assets/icons/adaptive_background_432.png"))
    fg = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    fg.alpha_composite(sub, ((n - sub.width) // 2, top))
    fg = up(fg, k)
    fg.save(os.path.join(ROOT, "assets/icons/adaptive_foreground_432.png"))
    mono = Image.new("RGBA", fg.size, (0, 0, 0, 0))
    mono.paste((255, 255, 255, 255), mask=fg.split()[3])
    mono.save(os.path.join(ROOT, "assets/icons/adaptive_monochrome_432.png"))


if __name__ == "__main__":
    out = os.path.join(ROOT, "store/ru/icon")
    for v in VARIANTS:
        up(art(v), 16).save(os.path.join(out, f"icon_512_{v}.png"))
    up(art("a"), 16).save(os.path.join(ROOT, "assets/icons/icon_512.png"))
    up(art("a"), 6).save(os.path.join(ROOT, "assets/icons/icon_192.png"))
    adaptive()
    print("готово")
