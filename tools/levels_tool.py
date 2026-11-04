#!/usr/bin/env python3
"""Уровни-смены: генерация data/levels.json по главам и симулятор сложности.

  python3 tools/levels_tool.py gen          # пересобрать data/levels.json (30 уровней, главы 1–3)
  python3 tools/levels_tool.py sim [N]      # прогнать каждый уровень N раз (по умолчанию 400) тремя «игроками» и показать долю
                                            # пройденных уровней и звёзд (точность, скорость)

Кривая сложности внутри главы: уровни 1–3 лёгкие, 4–6 новая механика, 7–8 микс, 9 проверка, 10 босс-смена (дольше, чуть быстрее поток).
Цели звёзд растут от главы к главе. Симулятор повторяет правила смены из scripts/main.gd (очередь, терпение, ошибки, расчёт звёзд),
игрок — модель с временем на действие и вероятностью ошибки. Подбор — по таблице «средний игрок»: старт ≈ 85–95% звезды за точность и ≈ 60–75%
за скорость, конец главы 3 — ≈ 25–40%.
"""
import json
import math
import os
import random
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "data", "levels.json")

# (название, напитки-пул, меню выпечки, вероятность выпечки, спешащие, гурманы)
CH1 = [
    ("Первая смена", ["espresso", "tea"], [], 0.0, 0.0, 0.0),
    ("Тёплое утро", ["espresso", "tea"], [], 0.0, 0.0, 0.0),
    ("Двое в очереди", ["espresso", "tea"], [], 0.0, 0.0, 0.0),
    ("Кофе и чай", ["espresso", "tea"], ["croissant"], 0.3, 0.0, 0.0),
    ("Обед в кафе", ["espresso", "tea", "latte"], ["croissant", "donut"], 0.3, 0.0, 0.0),
    ("Молочная пенка", ["latte", "espresso"], ["croissant", "cheesecake"], 0.35, 0.0, 0.0),
    ("Тучка заходит", ["espresso", "latte", "tea"], ["croissant", "donut", "cheesecake"], 0.4, 0.08, 0.0),
    ("Сухарик спешит", ["espresso", "tea", "latte"], ["croissant", "donut"], 0.4, 0.2, 0.0),
    ("Проверка", ["espresso", "tea", "latte"], ["croissant", "donut", "cheesecake"], 0.45, 0.15, 0.0),
    ("Субботний аврал", ["espresso", "tea", "latte"], ["croissant", "donut", "cheesecake"], 0.5, 0.2, 0.0),
]
CH2 = [
    ("Новое меню", ["espresso", "tea", "latte"], ["croissant", "syrniki"], 0.5, 0.1, 0.0),
    ("Какао для всех", ["cocoa", "latte", "tea"], ["croissant", "donut"], 0.45, 0.1, 0.0),
    ("Сырники Маруси", ["latte", "cocoa", "espresso"], ["syrniki", "croissant"], 0.55, 0.12, 0.0),
    ("Облепиховый день", ["sea_tea", "tea", "cocoa"], ["syrniki", "donut"], 0.5, 0.12, 0.1),
    ("Раф по-маминому", ["raf", "latte", "sea_tea"], ["eclair", "syrniki"], 0.55, 0.15, 0.1),
    ("Утро с эклерами", ["raf", "espresso", "cocoa"], ["eclair", "croissant", "syrniki"], 0.6, 0.15, 0.12),
    ("Баюн заказывает", ["sea_tea", "raf", "latte"], ["eclair", "syrniki", "cheesecake"], 0.6, 0.15, 0.2),
    ("Очередь за угол", ["espresso", "raf", "cocoa", "tea"], ["croissant", "eclair", "donut"], 0.55, 0.25, 0.15),
    ("Проба рецептов", ["raf", "sea_tea", "cocoa", "latte"], ["eclair", "syrniki", "cheesecake"], 0.6, 0.2, 0.2),
    ("Ярмарка", ["raf", "sea_tea", "cocoa", "latte", "espresso"], ["eclair", "syrniki", "donut"], 0.65, 0.25, 0.2),
]
CH3 = [
    ("Свет в окнах", ["latte", "raf", "tea"], ["eclair", "syrniki"], 0.55, 0.15, 0.15),
    ("Матча для Рыжика", ["matcha_latte", "latte", "tea"], ["croissant", "eclair"], 0.55, 0.15, 0.15),
    ("Тихий вечер", ["matcha_latte", "cocoa", "sea_tea"], ["syrniki", "cheesecake"], 0.6, 0.15, 0.2),
    ("Письма из ящика", ["raf", "matcha_latte", "espresso"], ["eclair", "donut", "syrniki"], 0.6, 0.2, 0.2),
    ("Дымка ждёт", ["matcha_latte", "sea_tea", "raf"], ["syrniki", "eclair", "cheesecake"], 0.6, 0.2, 0.25),
    ("Ночная смена", ["espresso", "raf", "cocoa", "matcha_latte"], ["croissant", "eclair", "donut"], 0.6, 0.25, 0.2),
    ("Гости с вещами", ["raf", "latte", "sea_tea", "cocoa"], ["syrniki", "eclair", "cheesecake"], 0.65, 0.25, 0.25),
    ("Дождливый четверг", ["matcha_latte", "raf", "cocoa", "tea"], ["eclair", "syrniki", "donut"], 0.65, 0.25, 0.25),
    ("Проверка мамы", ["raf", "matcha_latte", "sea_tea", "cocoa", "latte"], ["eclair", "syrniki", "cheesecake"], 0.7, 0.3, 0.3),
    ("Открытие!", ["raf", "matcha_latte", "sea_tea", "cocoa", "latte", "espresso"], ["eclair", "syrniki", "cheesecake"], 0.7, 0.3, 0.3),
]
CHAPTERS = [CH1, CH2, CH3]
# по главам: клиентов на уровень, интервал (старт → конец), терпение (старт → конец), цель скорости, цель точности, очередь
PARAMS = [
    {"customers": [6, 6, 7, 7, 8, 8, 9, 9, 10, 12], "interval": ((9.0, 12.0), (6.0, 8.5)), "patience": (44.0, 36.0), "speed": (11.0, 9.5), "accuracy": (0.80, 0.85), "queue": [2, 2, 2, 3, 3, 3, 3, 3, 3, 3]},
    {"customers": [10, 10, 11, 11, 12, 12, 13, 13, 14, 16], "interval": ((7.0, 9.5), (4.8, 6.8)), "patience": (40.0, 32.0), "speed": (11.0, 9.0), "accuracy": (0.84, 0.88), "queue": [3] * 10},
    {"customers": [12, 12, 13, 13, 14, 14, 15, 15, 16, 18], "interval": ((6.0, 8.0), (4.0, 5.8)), "patience": (38.0, 30.0), "speed": (11.0, 9.0), "accuracy": (0.86, 0.90), "queue": [3] * 10},
]


def lerp(a, b, t):
    return a + (b - a) * t


def build():
    out = []
    n = 0
    for ci, chapter in enumerate(CHAPTERS):
        P = PARAMS[ci]
        for i, (name, pool, menu, pastry, rushed, gourmet) in enumerate(chapter):
            n += 1
            t = i / 9.0
            lo = lerp(P["interval"][0][0], P["interval"][1][0], t)
            hi = lerp(P["interval"][0][1], P["interval"][1][1], t)
            boss = i == 9
            out.append({
                "id": f"l{n}", "chapter": ci + 1, "name": name, "customers": P["customers"][i],
                "interval": [round(lo * (0.9 if boss else 1.0), 1), round(hi * (0.9 if boss else 1.0), 1)],
                "patience": round(lerp(P["patience"][0], P["patience"][1], t), 1), "queue": P["queue"][i],
                "speed": round(lerp(P["speed"][0], P["speed"][1], t), 1), "accuracy": round(lerp(P["accuracy"][0], P["accuracy"][1], t), 2),
                "pool": pool, "pastry_menu": menu, "pastry": pastry, "types": {"rushed": rushed, "gourmet": gourmet}, "boss": boss,
            })
    return out


# ---------------------------------------------------------------- симулятор

PLAYERS = {   # (заготовка на заказ: прочитать, взять поднос, подать — с; время на одно перетаскивание — с; вероятность ошибки)
    "новичок": (6.0, 3.0, 0.15),
    "средний": (4.0, 2.0, 0.07),
    "мастер": (2.6, 1.3, 0.02),
}
DRINK_STEPS = {"espresso": 1, "tea": 1, "latte": 2, "matcha_latte": 2, "cocoa": 1, "sea_tea": 2, "raf": 3}


def simulate(level, player, rng, detail=False):
    base_t, act, err = PLAYERS[player]
    total = level["customers"]
    interval = level["interval"]
    queue_max = level["queue"]
    rushed_p = level["types"]["rushed"]
    gourmet_p = level["types"]["gourmet"]
    t = 0.0
    next_spawn = 0.8
    spawned = 0
    queue = []   # {"arr", "pat_end", "steps"}
    served = lost = wrong = 0
    times = []
    free_at = 0.0   # игрок занят до этого времени
    while spawned < total or queue:
        # события: приход, уход злым, готовность заказа
        events = []
        if spawned < total and len(queue) < queue_max:
            events.append(("spawn", next_spawn))
        for c in queue:
            events.append(("leave", c["pat_end"]))
        if queue:
            events.append(("free", max(free_at, queue[0]["arr"] + 1.2)))   # кот идёт к стойке ~1.2 с
        if not events:
            t += 0.5
            if spawned < total:
                next_spawn = max(next_spawn, t)
            continue
        kind, when = min(events, key=lambda e: e[1])
        t = max(t, when)
        if kind == "spawn":
            patience = level["patience"] * rng.uniform(0.85, 1.15)
            steps = DRINK_STEPS[rng.choice(level["pool"])]
            tag = rng.random()
            if tag < rushed_p:
                patience *= 0.65
            elif tag < rushed_p + gourmet_p:
                steps += 2   # гурман: напиток и выпечка
            elif level["pastry_menu"] and rng.random() < level["pastry"]:
                steps += 1
            queue.append({"arr": t, "pat_end": t + patience, "steps": steps})
            spawned += 1
            next_spawn = t + rng.uniform(*interval)
        elif kind == "leave":
            for c in list(queue):
                if c["pat_end"] <= t + 1e-9:
                    queue.remove(c)
                    lost += 1
                    if c is queue[:1] and False:
                        pass
        else:   # free: игрок собирает заказ первого кота
            c = queue[0]
            prep = c["steps"] * act + base_t
            if t + prep > c["pat_end"]:   # не успеть: кот уйдёт; игрок бросает (теряет время до ухода)
                free_at = c["pat_end"]
                continue
            t += prep
            free_at = t
            queue.pop(0)
            if rng.random() < err:
                wrong += 1
                lost += 1
            else:
                served += 1
                times.append(t - c["arr"])
    mask = 0
    acc = served / max(1, total)
    avg = sum(times) / len(times) if times else 0.0
    if detail:
        return (avg if avg > 0 else 99.0), acc
    if served * 2 >= total:
        mask |= 1
        if acc >= level["accuracy"]:
            mask |= 2
        if avg > 0 and avg <= level["speed"] and served * 10 >= total * 6:
            mask |= 4
    return mask


def tune(levels, runs=600):
    """Цель скорости по «среднему игроку»: порог такой, чтобы звезду за скорость получала заданная доля средних игроков
    (старт 80% → босс главы 3 ≈ 25%), округление до 0,5 с. Цель точности задана кривой PARAMS (80% → 90%)."""
    rng = random.Random(7)
    base_t, act, err = PLAYERS["средний"]
    for i, lv in enumerate(levels):
        t = i / (len(levels) - 1)
        want_speed = lerp(0.80, 0.30, t) - (0.05 if lv.get("boss") else 0.0)
        avgs, accs = [], []
        probe = dict(lv, speed=999.0, accuracy=0.0)
        for _ in range(runs):
            a, c = simulate(probe, "средний", rng, detail=True)
            avgs.append(a)
            accs.append(c)
        avgs.sort()
        accs.sort(reverse=True)
        k = max(0, min(runs - 1, int(want_speed * runs) - 1))
        lv["speed"] = max(4.0, math.ceil(avgs[k] * 2.0) / 2.0)
    return levels


def sim(n):
    levels = json.load(open(PATH, encoding="utf-8"))
    rng = random.Random(1)
    print(f"{'#':>3} {'уровень':22} {'гл':>2} " + " | ".join(f"{p:^20}" for p in PLAYERS))
    print(f"{'':>3} {'':22} {'':>2} " + " | ".join(f"{'пройд  точн  скор':^20}" for _ in PLAYERS))
    for i, lv in enumerate(levels):
        row = []
        for p in PLAYERS:
            r = [simulate(lv, p, rng) for _ in range(n)]
            ps = sum(1 for m in r if m & 1) / n
            ac = sum(1 for m in r if m & 2) / n
            sp = sum(1 for m in r if m & 4) / n
            row.append(f"{ps * 100:4.0f}% {ac * 100:4.0f}% {sp * 100:4.0f}%")
        print(f"{i + 1:>3} {lv['name'][:22]:22} {lv['chapter']:>2} " + " | ".join(f"{x:^20}" for x in row))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "sim"
    if cmd == "gen":
        lv = tune(build())
        json.dump(lv, open(PATH, "w", encoding="utf-8"), ensure_ascii=False, indent="\t")
        print("записано", PATH, len(lv), "уровней")
    else:
        sim(int(sys.argv[2]) if len(sys.argv) > 2 else 400)
