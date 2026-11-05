#!/usr/bin/env python3
"""Разбор лога тестовой сборки (user://analytics.log, строки JSON): промахи и броски по баночкам, смены, подсказки.

  python3 tools/analyze_log.py analytics.log

Как забрать лог с телефона: в игре Настройки → «Для тестов» → «Скопировать лог» (вставить в файл) или
  adb shell run-as ru.warmpaw.cafe.test cat files/analytics.log > analytics.log
Что смотреть при живом тесте пальцем (docs/release/09-test-build.md): процент промахов по краям (sx < 60 или > 300), долю «не той половины» подноса.
"""
import collections
import json
import sys

rows = []
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    line = line.strip()
    if line.startswith("{"):
        try:
            rows.append(json.loads(line))
        except ValueError:
            pass
drops = [r["p"] for r in rows if r.get("e") == "drop"]
print(f"событий: {len(rows)}, бросков ингредиентов: {len(drops)}")
by = collections.defaultdict(lambda: [0, 0])
for p in drops:
    k = (p.get("id"), p.get("sx"))
    by[k][0] += 1
    by[k][1] += 0 if p.get("hit") else 1
print(f"{'ингредиент':14} {'ячейка x':>8} {'бросков':>8} {'промахов':>9}")
for (i, sx), (n, miss) in sorted(by.items(), key=lambda kv: (kv[0][1] or 0)):
    edge = " ← край экрана" if sx is not None and (sx < 60 or sx > 300) else ""
    print(f"{str(i):14} {sx!s:>8} {n:>8} {miss / n * 100:8.0f}%{edge}")
halves = collections.Counter(int(p.get("half", 0)) for p in drops if p.get("kind") in ("syrup", "extra") and p.get("hit"))
print("половины подноса для начинок (1 весь, 2 напиток, 3 выпечка):", dict(halves))
ends = [r["p"] for r in rows if r.get("e") == "level_end"]
if ends:
    print("смен:", len(ends), "средняя точность:", round(sum(float(e.get("acc", 0)) for e in ends) / len(ends), 2), "ошибок:", sum(int(e.get("wrong", 0)) for e in ends), "ушло:", sum(int(e.get("lost", 0)) for e in ends))
print("открытий шпаргалки:", sum(1 for r in rows if r.get("e") == "recipe_book"))
