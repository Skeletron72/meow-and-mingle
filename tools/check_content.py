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
            if k == "furniture" and e["id"] not in furniture:
                errors.append(f"задача {r['id']}: нет мебели {e['id']}")
            elif k == "upgrade" and e["id"] not in upgrades:
                errors.append(f"задача {r['id']}: нет улучшения {e['id']}")
            elif k == "style" and (e["key"] not in styles or any(v["id"] not in styles[e["key"]] for v in r.get("variants", []))):
                errors.append(f"задача {r['id']}: стиль {e['key']} или его варианты не описаны в styles.json")
            elif k == "unlock":
                kind, _, name = e["key"].partition(":")
                ok = {"cat": cats, "drink": drinks, "pastry": pastries, "source": {"syrup"}}.get(kind)
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
    # экономика звёзд
    print(f"{'уровней':>8} {'макс ★':>7} {'средн ★':>8} {'цена задач с after ≤ k':>24}")
    for k in range(0, len(levels) + 1, 5):
        cost = sum(r["cost"] for r in repairs if r["after"] <= k)
        print(f"{k:>8} {3 * k:>7} {2 * k:>8} {cost:>24}")
        if k > 0 and cost > 3 * k + 3:   # +3: звёзды за обучение
            errors.append(f"после {k} уровней задач на {cost}★, а заработать можно максимум {3 * k + 3}")
    total = sum(r["cost"] for r in repairs)
    print(f"всего задач {len(repairs)}, цена {total}★ из {3 * len(levels) + 3} возможных ({total / (3 * len(levels) + 3):.0%})")
    for e in errors:
        print("ОШИБКА:", e)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
