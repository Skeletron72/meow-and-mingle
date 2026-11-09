#!/usr/bin/env python3
"""Сводная проверка баланса и прогрессии: звёзды против ремонта, монеты против стоков, рыбки, пасс сезона, время на кампанию.

  python3 tools/balance_check.py          # таблицы + список нарушений; код возврата 1, если нарушен хотя бы один инвариант
  python3 tools/balance_check.py --md     # те же таблицы в Markdown (для docs/release/11-balance.md)

Модель грубая (порядок величин): игроки из tools/levels_tool.py, доход смены из tools/economy_sim.py. Инварианты — то, что должно оставаться верным
при любой правке данных: средний игрок закрывает ремонт главы звёздами этой главы; монеты не копятся без дела; пасс сезона закрывается игрой, а не только
заданиями; первая покупка доступна в первый день.
"""
import json
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import economy_sim as es  # noqa: E402
import levels_tool as lt  # noqa: E402

ROOT = lt.ROOT
MD = "--md" in sys.argv
RUNS = 120


def load(name):
    return json.load(open(os.path.join(ROOT, "data", name), encoding="utf-8"))


LEVELS = load("levels.json")
REPAIRS = load("repairs.json")
EQUIP = load("equipment.json")
UPGRADES = load("upgrades.json")
FURN = load("furniture.json")
QUESTS = load("quests.json")
DAILY = load("daily.json")
DEALS = load("deals.json")
BOOSTERS = load("boosters.json")
SEASON = load("season_1.json")
SHOP = load("shop.json")
CHAPTERS = sorted({lv["chapter"] for lv in LEVELS})
PROBLEMS = []


def table(title, head, rows):
    print(("\n### " if MD else "\n== ") + title)
    if MD:
        print("\n| " + " | ".join(head) + " |\n|" + "---|" * len(head))
        for r in rows:
            print("| " + " | ".join(str(c) for c in r) + " |")
    else:
        w = [max(len(str(x)) for x in col) for col in zip(head, *rows)]
        for r in [head] + rows:
            print("  ".join(str(c).rjust(w[i]) for i, c in enumerate(r)))


def need(cond, text):
    if not cond:
        PROBLEMS.append(text)


def stars_stats(player, rng):
    """Для каждого уровня: (ожидаемые звёзды за одну попытку, доля прохождений хотя бы на 1★)."""
    out = []
    for lv in LEVELS:
        tot = passed = 0
        for _ in range(RUNS):
            n = bin(lt.simulate(lv, player, rng)).count("1")
            tot += n
            passed += 1 if n else 0
        out.append((tot / RUNS, passed / RUNS))
    return out


def shift_seconds(lv):
    return lv["customers"] * sum(lv["interval"]) / 2.0 + 12.0


def equip_plan(ch):
    """Уровень оборудования, который средний игрок успевает купить к середине главы (уровень n открыт после 10·(n−1) смен, цена растёт)."""
    return min(ch, 5)


def main():
    rng = random.Random(11)
    stats = {p: stars_stats(p, rng) for p in lt.PLAYERS}

    # ---- 1. звёзды против ремонта
    rows = []
    cum_cost = 0
    cum = {p: 0.0 for p in lt.PLAYERS}
    for ch in CHAPTERS:
        idx = [i for i, lv in enumerate(LEVELS) if lv["chapter"] == ch]
        cost = sum(r["cost"] for r in REPAIRS if r["chapter"] == ch)
        cum_cost += cost
        for p in lt.PLAYERS:
            cum[p] += sum(stats[p][i][0] for i in idx)
        hardest = min(stats["новичок"][i][1] for i in idx)
        rows.append([ch, f"{LEVELS[idx[0]]['id']}–{LEVELS[idx[-1]]['id']}", cost, cum_cost, f"{cum['новичок']:.0f}", f"{cum['средний']:.0f}", f"{cum['мастер']:.0f}",
                     f"{cum['средний'] - cum_cost:+.0f}", f"{hardest * 100:.0f}%"])
        need(cum["средний"] >= cum_cost, f"глава {ch}: среднему игроку не хватает звёзд на ремонт ({cum['средний']:.0f} из {cum_cost}) с первого прохождения")
        need(cum["мастер"] <= len([lv for lv in LEVELS if lv['chapter'] <= ch]) * 3, "звёзд больше максимума")
        for r in REPAIRS:
            if r["chapter"] == ch:
                need(int(r.get("after", 0)) <= idx[-1] + 1, f"задача {r['id']} главы {ch} открывается только после смены {r.get('after')} — позже конца главы")
    table("Звёзды: накоплено с первого прохождения против цены ремонта", ["гл", "уровни", "ремонт★", "ремонт всего★", "новичок", "средний", "мастер", "запас среднего", "худший проход новичка"], rows)
    total_stars = len(LEVELS) * 3
    need(0.55 <= cum_cost / total_stars <= 0.75, f"цена всего ремонта {cum_cost}★ — вне коридора 55–75% от {total_stars}★")

    # ---- 2. монеты: доход против стоков
    rows = []
    earned = 0.0
    quest_avg = sum(q.get("coins", 0) for q in QUESTS) / len(QUESTS)
    furn_total = sum(f["price"] for f in FURN)
    upg_total = sum(u["price"] for u in UPGRADES)
    eq_total = sum(sum(e["prices"]) for e in EQUIP)
    per = {e["kind"]: e["per"] for e in EQUIP}
    first_shift = None
    for ch in CHAPTERS:
        lvs = [lv for lv in LEVELS if lv["chapter"] == ch]
        lvl = equip_plan(ch)
        mult = 1.0 + 0.6 * per["price"] * lvl + 0.25 * per["pastry_price"] * lvl + 0.15 * per["tips"] * lvl   # вклад в чек: напиток ≈ 60%, выпечка ≈ 25%, чаевые ≈ 15%
        inc = 0.0
        secs = 0.0
        for lv in lvs:
            served = [lt.simulate(lv, "средний", rng, detail=True)[1] * lv["customers"] for _ in range(40)]
            one = es.shift_income(lv, sum(served) / len(served), 50) * mult
            if first_shift is None:
                first_shift = one
            inc += one
            secs += shift_seconds(lv)
        n = len(lvs)
        plays = n * 1.5
        stars_bonus = 10 * sum(stats["средний"][i][0] for i, lv in enumerate(LEVELS) if lv["chapter"] == ch)
        quests = plays / 5.0 * 3 * quest_avg * 0.7      # ≈5 смен в день, 3 задания, 70% выполняется
        chapter_total = inc / n * plays + stars_bonus + quests
        earned += chapter_total
        rows.append([ch, f"{inc / n:.0f}", f"{chapter_total:.0f}", f"{earned:.0f}", f"ур. {lvl}", f"{secs / n / 60:.1f}", f"{secs * 1.5 / 3600:.1f}"])
    table("Монеты: доход среднего игрока по главам (1,5 прохода, Уют 50, оборудование по плану)", ["гл", "монет/смену", "за главу", "накоплено", "оборудование", "мин/смену", "часов на главу"], rows)
    sinks = furn_total + upg_total + eq_total
    table("Монеты: куда тратить", ["сток", "монет"], [["мебель (весь каталог)", furn_total], ["разовые улучшения", upg_total], ["оборудование, все уровни", eq_total], ["итого", sinks], ["доход за кампанию", f"{earned:.0f}"], ["доход / стоки", f"{earned / sinks:.2f}"]])
    need(0.7 <= earned / sinks <= 1.15, f"доход за кампанию {earned:.0f} против стоков {sinks}: отношение {earned / sinks:.2f} вне 0,70–1,15 (монеты либо копятся, либо их не хватает)")
    cheapest = min(u["price"] for u in UPGRADES)
    need(first_shift * 2 >= cheapest, f"первое улучшение ({cheapest}) не купить за две первые смены ({first_shift:.0f} за смену)")
    need(min(e["prices"][0] for e in EQUIP) <= first_shift * 6, "первый уровень оборудования дороже шести первых смен")
    for e in EQUIP:
        need(all(b > a for a, b in zip(e["prices"], e["prices"][1:])), f"{e['id']}: цены уровней не растут")
        need(all(b > a for a, b in zip(e["after"], e["after"][1:])) and e["after"][-1] < len(LEVELS), f"{e['id']}: пороги смен не растут или выходят за кампанию")

    # ---- 3. рыбки
    week_daily = sum(d.get("fish", 0) for d in DAILY)
    fish_quests = [q["fish"] for q in QUESTS if q.get("fish")]
    week_quests = 7 * 3 * (len(fish_quests) / len(QUESTS)) * (sum(fish_quests) / max(1, len(fish_quests))) * 0.7
    season_free = sum(t["free"].get("fish", 0) for t in SEASON["tiers"]) / (SEASON["days"] / 7.0)
    week = week_daily + week_quests + season_free
    deal_avg = sum(d["fish"] for d in DEALS) / len(DEALS)
    table("Рыбки: бесплатный приток за неделю против цен", ["источник", "рыбок"], [["лента подарков (7 дней)", week_daily], ["задания дня", f"{week_quests:.0f}"], ["пасс, бесплатная дорожка", f"{season_free:.0f}"], ["итого за неделю", f"{week:.0f}"],
                                                                       ["средняя цена предложения дня", f"{deal_avg:.0f}"], ["предложений в неделю бесплатно", f"{week / deal_avg:.1f}"], ["самый дешёвый бустер", min(b['fish'] for b in BOOSTERS)]])
    need(1.0 <= week / deal_avg <= 5.0, f"бесплатных рыбок {week:.0f} в неделю — на {week / deal_avg:.1f} предложений дня (нужно 1–5: и покупать есть на что, и донат не обесценен)")

    # ---- 4. пасс сезона
    need_xp = SEASON["xp_per_tier"] * len(SEASON["tiers"])
    rows = []
    for name, shifts, quests, new_stars, avg_stars in (("редкий (2 смены в день)", 2, 1, 1.5, 2.0), ("обычный (4 смены)", 4, 2, 2.5, 2.1), ("увлечённый (7 смен)", 7, 3, 4.0, 2.3)):
        day = quests * 20 + new_stars * 10 + shifts * (4 + 2 * avg_stars)
        got = day * SEASON["days"]
        rows.append([name, f"{day:.0f}", f"{min(len(SEASON['tiers']), got / SEASON['xp_per_tier']):.0f} из {len(SEASON['tiers'])}", f"{need_xp / day:.0f}"])
        if shifts == 7:
            need(need_xp / day <= SEASON["days"] - 4, f"увлечённый игрок закрывает пасс за {need_xp / day:.0f} дней из {SEASON['days']} — слишком впритык")
        if shifts == 4:
            need(got / need_xp >= 0.7, f"обычный игрок набирает только {got / need_xp * 100:.0f}% пасса")
        if shifts == 2:
            need(got / need_xp <= 0.75, "редкий игрок закрывает больше 75% пасса: пасс не мотивирует заходить чаще")
    table(f"Пасс сезона: {need_xp} очков за {SEASON['days']} дней", ["игрок", "очков в день", "ступеней к концу", "дней до конца пасса"], rows)

    # ---- 5. сложность: провалы по кривой
    worst = min((stats["средний"][i][1], LEVELS[i]["id"]) for i in range(len(LEVELS)))
    need(worst[0] >= 0.9, f"средний игрок проходит {worst[1]} только в {worst[0] * 100:.0f}% попыток")
    late = [stats["новичок"][i][1] for i in range(len(LEVELS) - 10, len(LEVELS))]
    print(("\n" if not MD else "\n") + f"Новичок без бустеров и оборудования проходит последнюю главу в {sum(late) / len(late) * 100:.0f}% попыток (к тому времени он уже не новичок; подушки и бустеры дают запас).")

    print()
    if PROBLEMS:
        print("НАРУШЕНИЯ:" if not MD else "**Нарушения:**")
        for p in PROBLEMS:
            print(" -", p)
        return 1
    print("BALANCE PASS: нарушений нет")
    return 0


if __name__ == "__main__":
    sys.exit(main())
