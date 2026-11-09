#!/usr/bin/env python3
"""Иконка игры: пиксельный кот за чашкой латте на тёплом фоне. Рисуется из спрайтов игры (кот, чашка) крупными пикселями, фон — постеризованный
градиент с дизерингом Байера, как в самой игре.
  python3 tools/generators/make_store_icon.py
Пишет: store/ru/icon/icon_512_{a,b,c}.png (варианты для A/B-теста), assets/icons/ (иконка проекта и слои адаптивной иконки Android 432×432)."""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def load(path):
    return Image.open(os.path.join(ROOT, path)).convert("RGBA")


def crop_content(im):
    return im.crop(im.getbbox())


def cat(name, row=0):
    sheet = load(f"assets/cats/{name}")
    return crop_content(sheet.crop((0, 16 * row, 16, 16 * row + 16)))


def cell(col, row):
    sheet = load("assets/cafe/drinks-and-pastries.png")
    return crop_content(sheet.crop((col * 16, row * 16, col * 16 + 16, row * 16 + 16)))


def gradient(size, top, bottom, px, steps=5):
    """Вертикальный градиент, постеризованный в steps ступеней с дизерингом Байера (клетка px)."""
    n = size // px
    im = Image.new("RGBA", (size, size))
    for y in range(n):
        for x in range(n):
            t = y / (n - 1)
            v = t * (steps - 1)
            lo = int(v)
            frac = v - lo
            lvl = lo + (1 if frac > (BAYER[y % 4][x % 4] + 0.5) / 16.0 else 0)
            u = min(lvl, steps - 1) / (steps - 1)
            c = tuple(int(top[i] + (bottom[i] - top[i]) * u) for i in range(3)) + (255,)
            im.paste(c, (x * px, y * px, (x + 1) * px, (y + 1) * px))
    return im


def scaled(im, k):
    return im.resize((im.width * k, im.height * k), Image.NEAREST)


def compose(size, bg, cat_im, cup_im, ck, uk, cat_xy, cup_xy, extras=()):
    out = bg.copy()
    # лёгкая тень под чашкой
    sh = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    c = scaled(cat_im, ck)
    out.alpha_composite(c, cat_xy)
    u = scaled(cup_im, uk)
    shadow = Image.new("RGBA", u.size, (0, 0, 0, 0))
    ssh = u.split()[3].point(lambda a: 70 if a else 0)
    shadow.putalpha(ssh)
    out.alpha_composite(shadow, (cup_xy[0], cup_xy[1] + uk))
    out.alpha_composite(u, cup_xy)
    for e in extras:
        out.alpha_composite(e[0], e[1])
    return out


def steam(size, x, y, k, color=(255, 255, 255, 235)):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = im.load()
    pts = [(0, 0), (1, 1), (1, 2), (0, 3), (0, 4), (1, 5)]
    for a, b in pts:
        for dx in range(k):
            for dy in range(k):
                px[x + a * k + dx, y + b * k + dy] = color
    return im


def place(size, bg, cat_im, cup_im, ck, uk, cup_dx, cup_dy, extras=()):
    """Кот по центру сверху, чашка (меньше) у нижнего края справа от центра — перекрывает только тело, мордочка открыта."""
    cat_xy = ((size - cat_im.width * ck) // 2, 28)
    cup_xy = ((size - cup_im.width * uk) // 2 + cup_dx, size - cup_im.height * uk - cup_dy)
    return compose(size, bg, cat_im, cup_im, ck, uk, cat_xy, cup_xy, extras)


def make(variant):
    size = 512
    if variant == "a":      # рыжий кот и латте, кремово-персиковый фон
        bg = gradient(size, (255, 233, 196), (240, 168, 104), 8)
        k = place(size, bg, cat("cat-orange-front.png"), cell(4, 1), 30, 12, 96, 20)
    elif variant == "b":    # чёрный кот и эспрессо, тёмно-бирюзовый фон (цвет стеллажа игры)
        bg = gradient(size, (98, 138, 134), (52, 78, 80), 8)
        k = place(size, bg, cat("cat-black-front.png"), cell(2, 1), 30, 12, 96, 20)
    else:                   # кот-официант и круассан, тёплый красный фон
        bg = gradient(size, (255, 214, 168), (214, 102, 76), 8)
        k = place(size, bg, cat("cat-waiter-front.png"), cell(1, 4), 30, 12, 96, 20)
    return k


def adaptive():
    """Слои адаптивной иконки Android: передний (кот и чашка в безопасной зоне 288×288 из 432), фон, монохромный."""
    size = 432
    bgl = gradient(size, (255, 233, 196), (240, 168, 104), 6)
    bgl.save(os.path.join(ROOT, "assets/icons/adaptive_background_432.png"))
    cat_im, cup_im = cat("cat-orange-front.png"), cell(4, 1)
    fg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ck, uk = 16, 7   # кот и чашка помещаются в безопасную зону 288×288
    c = scaled(cat_im, ck)
    fg.alpha_composite(c, ((size - c.width) // 2, 70))
    u = scaled(cup_im, uk)
    fg.alpha_composite(u, ((size - u.width) // 2 + 52, 70 + c.height - u.height + 6))
    fg.save(os.path.join(ROOT, "assets/icons/adaptive_foreground_432.png"))
    mono = Image.new("RGBA", fg.size, (0, 0, 0, 0))
    mono.putalpha(fg.split()[3])
    mono.paste((255, 255, 255, 255), mask=fg.split()[3])
    mono.save(os.path.join(ROOT, "assets/icons/adaptive_monochrome_432.png"))


if __name__ == "__main__":
    out = os.path.join(ROOT, "store/ru/icon")
    for v in "abc":
        make(v).save(os.path.join(out, f"icon_512_{v}.png"))
    make("a").save(os.path.join(ROOT, "assets/icons/icon_512.png"))
    make("a").resize((192, 192), Image.NEAREST).save(os.path.join(ROOT, "assets/icons/icon_192.png"))
    adaptive()
    print("готово")
