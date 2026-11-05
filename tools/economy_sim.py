#!/usr/bin/env python3
"""Оценка экономики: сколько монет приносит смена по главам (средний игрок из levels_tool) и за сколько смен окупается Уют.

  python3 tools/economy_sim.py            # таблица по главам: доход за смену при Уюте 0/50/100, накопление и цена Уюта 100 по мебели

Модель грубая (проверка порядка величин, а не точный баланс): заказ = средняя цена напитка из пула + выпечка с шансом уровня (+начинка и комбо +20%),
гурманы ×2, чаевые 20% с множителем Уюта, бонус скорости ≈ 3, один загадочный гость за смену ×2, монеты за новые звёзды (10 за звезду, один раз).
"""
import json
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import levels_tool as lt  # noqa: E402

ROOT = lt.ROOT


def load(name):
    return json.load(open(os.path.join(ROOT, "data", name), encoding="utf-8"))


DRINKS = {d["id"]: d for d in load("drinks.json")}
PASTRY = {p["id"]: p for p in load("pastries.json")}
FURN = load("furniture.json")
LEVELS = json.load(open(lt.PATH, encoding="utf-8"))
COZY_TIPS = 0.35
VARIETY = 2


def shift_income(lv, served, cozy):
    pool = [DRINKS[d]["price"] for d in lv["pool"]]
    drink = sum(pool) / len(pool)
    menu = [PASTRY[p]["price"] for p in lv["pastry_menu"]] or [0]
    pastry = sum(menu) / len(menu)
    p_past = lv["pastry"] if lv["pastry_menu"] else 0.0
    pm = lv.get("pastry_mods", 0.0)
    order = drink + p_past * (pastry + pm * 1.3 * 3.0)
    order *= 1.0 + p_past * pm * 0.2          # комбо +20% на заказах с начинкой
    order *= 1.0 + lv["types"]["gourmet"] + 0.5 * lv["types"].get("critic", 0.0) * 0.5
    tips = 0.2 * order * (1.0 + COZY_TIPS * cozy / 100.0)
    per = order + tips + 3.0
    return served * per + (order * 1.0 if lv.get("riddle", 0.0) else 0.0)


def cozy_cost(limit=40, goal=100):
    """Минимальная цена Уюта `goal` мебелью (копии можно, до `limit` предметов): динамическое программирование по (предметы, очки).
    Бонус за разнообразие не учитывается (даёт запас в 10–30 очков), поэтому цена слегка завышена."""
    inf = 10 ** 9
    dp = [[inf] * (goal + 1) for _ in range(limit + 1)]
    dp[0][0] = 0
    for n in range(limit):
        for p in range(goal + 1):
            if dp[n][p] >= inf:
                continue
            for f in FURN:
                q = min(goal, p + f["cozy"])
                dp[n + 1][q] = min(dp[n + 1][q], dp[n][p] + f["price"])
    best = min((dp[n][goal], n) for n in range(limit + 1))
    return best


def main():
    rng = random.Random(3)
    cost100, n100 = cozy_cost()
    print(f"Цена Уюта 100 самой выгодной мебелью: {cost100} монет, {n100} предметов")
    print(f"{'гл':>2} {'уровни':>7} {'монет/смену Уют0':>17} {'Уют50':>7} {'Уют100':>7} {'накоплено к концу главы (Уют 50, 1,5 прохода)':>46}")
    total = 0.0
    for ch in range(1, 7):
        lvs = [lv for lv in LEVELS if lv["chapter"] == ch]
        inc = {0: 0.0, 50: 0.0, 100: 0.0}
        for lv in lvs:
            served = []
            for _ in range(60):
                a, acc = lt.simulate(lv, "средний", rng, detail=True)
                served.append(acc * lv["customers"])
            s = sum(served) / len(served)
            for c in inc:
                inc[c] += shift_income(lv, s, c)
        n = len(lvs)
        stars = 10 * 2.0 * n          # в среднем ~2 новых звезды за уровень
        total += inc[50] * 1.5 + stars
        print(f"{ch:>2} {lvs[0]['id']+'-'+lvs[-1]['id']:>7} {inc[0] / n:17.0f} {inc[50] / n:7.0f} {inc[100] / n:7.0f} {total:46.0f}")
    print(f"\nВся мебель из data/furniture.json: {sum(f['price'] for f in FURN)} монет; улучшения (data/upgrades.json): {sum(u['price'] for u in load('upgrades.json'))}")


if __name__ == "__main__":
    main()
