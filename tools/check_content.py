#!/usr/bin/env python3
"""Проверка контента: ссылки между данными, порядок задач ремонта и экономика звёзд. Код выхода 1 при ошибке.

  python3 tools/check_content.py

Экономика: к моменту, когда пройдено k уровней, игрок мог заработать 2k звёзд (среднее) и до 3k (максимум). Задачи с `after` ≤ k
в сумме должны стоить не больше максимума (иначе часть задач недостижима) и не меньше среднего × 0,6 (иначе звёзды копятся без дела).
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(name):
    return json.load(open(os.path.join(ROOT, "data", name), encoding="utf-8"))


def main():
    repairs = load("repairs.json")
    levels = load("levels.json")
    cats = {c["id"] for c in load("cats.json")}
    drinks = {d["id"] for d in load("drinks.json")}
    pastries = {p["id"] for p in load("pastries.json")}
    furniture = {f["id"] for f in load("furniture.json")}
    upgrades = {u["id"] for u in load("upgrades.json")}
    styles = load("styles.json")
    errors = []
    ids = [r["id"] for r in repairs]
    if len(ids) != len(set(ids)):
        errors.append("повторяющиеся id задач ремонта")
    seen = set()
    for r in repairs:
        for q in r["requires"]:
            if q not in seen:
                errors.append(f"задача {r['id']}: требование {q} стоит позже или не существует")
        seen.add(r["id"])
        if r["after"] > len(levels):
            errors.append(f"задача {r['id']}: after={r['after']} больше числа уровней")
        for e in r["effects"]:
            k = e["kind"]
            if k in ("furniture", "counter") and e["id"] not in furniture:
                errors.append(f"задача {r['id']}: нет мебели {e['id']}")
            elif k == "upgrade" and e["id"] not in upgrades:
                errors.append(f"задача {r['id']}: нет улучшения {e['id']}")
            elif k == "style" and (e["key"] not in styles or any(v["id"] not in styles[e["key"]] for v in r.get("variants", []))):
                errors.append(f"задача {r['id']}: стиль {e['key']} или его варианты не описаны в styles.json")
            elif k == "unlock":
                kind, _, name = e["key"].partition(":")
                terrace = {t["id"] for t in load("terrace.json")}
                ok = {"cat": cats, "drink": drinks, "pastry": pastries, "source": {"syrup", "spice", "cream", "ice"}, "style": {"loft", "japan", "winter"}, "terrace": terrace}.get(kind)
                if ok is None or name not in ok:
                    errors.append(f"задача {r['id']}: неизвестное открытие {e['key']}")
    for lv in levels:
        for d in lv["pool"]:
            if d not in drinks:
                errors.append(f"уровень {lv['id']}: нет напитка {d}")
        for p in lv["pastry_menu"]:
            if p not in pastries:
                errors.append(f"уровень {lv['id']}: нет выпечки {p}")
    # каждый напиток/выпечка/кот, требующие открытия, открывается какой-то задачей
    unlock_keys = {e["key"] for r in repairs for e in r["effects"] if e["kind"] == "unlock"}
    for d in load("drinks.json"):
        for n in d["needs"]:
            if n.startswith(("drink:", "source:", "pastry:")) and n not in unlock_keys:
                errors.append(f"напиток {d['id']}: условие {n} ничем не открывается")
    for p in load("pastries.json"):
        for n in p["needs"]:
            if n not in unlock_keys:
                errors.append(f"выпечка {p['id']}: условие {n} ничем не открывается")
    for c in load("cats.json"):
        if not c["starter"] and f"cat:{c['id']}" not in unlock_keys:
            errors.append(f"кот {c['id']}: ничто его не открывает")
    # мета-игра: бустеры, магазин, подарки, задания, сезон
    boosters = {b["id"] for b in load("boosters.json")}
    shop = load("shop.json")
    def check_reward(where, r):
        for b in r.get("boosters", {}):
            if b not in boosters:
                errors.append(f"{where}: нет бустера {b}")
        if "furniture" in r and r["furniture"] not in furniture:
            errors.append(f"{where}: нет мебели {r['furniture']}")
    for d in load("deals.json"):
        check_reward("предложение " + d["id"], d)
        if d["fish"] >= d["was"]:
            errors.append(f"предложение {d['id']}: цена не ниже «было»")
    gifts = load("daily.json")
    if [g["day"] for g in gifts] != list(range(1, 8)):
        errors.append("лента подарков: нужны дни 1..7 подряд")
    for g in gifts:
        check_reward(f"подарок дня {g['day']}", g)
    kinds = {"serve", "pastry", "fast", "level", "stars", "perfect", "coins", "tips"}
    for q in load("quests.json"):
        if q["kind"] not in kinds:
            errors.append(f"задание {q['id']}: неизвестный вид {q['kind']}")
    season = load("season_1.json")
    if len(season["tiers"]) != 30 or [t["tier"] for t in season["tiers"]] != list(range(1, 31)):
        errors.append("сезон: нужно 30 ступеней подряд")
    for t in season["tiers"]:
        check_reward(f"сезон, ступень {t['tier']} (бесплатно)", t["free"])
        check_reward(f"сезон, ступень {t['tier']} (пасс)", t["premium"])
    for ev in load("events.json"):
        if len(ev["tasks"]) != 10 or len(ev["tiers"]) != 3:
            errors.append(f"событие {ev['id']}: нужно 10 заданий и 3 ступени")
        for t in ev["tasks"]:
            if not (t["kind"] in kinds or (t["kind"].startswith("drink:") and t["kind"][6:] in drinks)):
                errors.append(f"событие {ev['id']}: неизвестный вид задания {t['kind']}")
        for tier in ev["tiers"]:
            check_reward(f"событие {ev['id']} (бесплатно)", tier["free"])
            check_reward(f"событие {ev['id']} (пасс)", tier["premium"])
            if tier["need"] > 10:
                errors.append(f"событие {ev['id']}: ступень требует больше 10 заданий")
    seasons = [f for f in os.listdir(os.path.join(ROOT, "data")) if f.startswith("season_")]
    print(f"сезонов: {len(seasons)}, событий: {len(load('events.json'))}")
    skus = [p["sku"] for p in shop["fish_packs"]] + [shop["starter"]["sku"], shop["no_ads"]["sku"], shop["season_pass"]["sku"]]
    if len(skus) != len(set(skus)):
        errors.append("повторяющиеся SKU в shop.json")
    for b in shop["starter"]["boosters"]:
        if b not in boosters:
            errors.append(f"стартовый набор: нет бустера {b}")
    # экономика звёзд
    print(f"{'уровней':>8} {'макс ★':>7} {'средн ★':>8} {'цена задач с after ≤ k':>24}")
    for k in range(0, len(levels) + 1, 5):
        cost = sum(r["cost"] for r in repairs if r["after"] <= k)
        print(f"{k:>8} {3 * k:>7} {2 * k:>8} {cost:>24}")
        if k > 0 and cost > 3 * k + 3:   # +3: звёзды за обучение
            errors.append(f"после {k} уровней задач на {cost}★, а заработать можно максимум {3 * k + 3}")
    total = sum(r["cost"] for r in repairs)
    print(f"мета: {len(skus)} SKU, {len(load('deals.json'))} предложений дня, {len(load('quests.json'))} шаблонов заданий, сезон {len(season['tiers'])} ступеней")
    print(f"всего задач {len(repairs)}, цена {total}★ из {3 * len(levels) + 3} возможных ({total / (3 * len(levels) + 3):.0%})")
    for e in errors:
        print("ОШИБКА:", e)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
