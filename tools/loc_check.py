#!/usr/bin/env python3
"""Проверка локализации: ищет русские строки в коде и данных и сверяет с data/loc/en.json.

  python3 tools/loc_check.py          # список непереведённых строк (код выхода 1, если есть)
  python3 tools/loc_check.py --dump   # напечатать все найденные русские строки

Строки с форматом (%d, %s) переводятся целиком, вместе со спецификаторами. Комментарии и тесты не проверяются.
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CYR = re.compile(r"[А-Яа-яЁё]")
STR = re.compile(r'"((?:[^"\\]|\\.)*)"')


# Только для разработчиков или рисуются как картинка — не переводятся.
SKIP_FILES = ("street_zone.gd", "street_building.gd", "street_prop.gd", "pixel_art.gd", "fx.gd")
SKIP_LINE = re.compile(r"push_error|push_warning|_get_configuration_warnings|assert\(|print\(")
# Название кафе на вывеске рисуется пиксельным шрифтом, а в игре «Тёплая Лапка» — имя собственное, в английском тексте остаётся как есть.


def code_strings():
    out = {}
    files = glob.glob(os.path.join(ROOT, "scripts", "**", "*.gd"), recursive=True) + glob.glob(os.path.join(ROOT, "autoload", "*.gd"))
    for f in files:
        if os.path.basename(f) in SKIP_FILES:
            continue
        for n, line in enumerate(open(f, encoding="utf-8"), 1):
            if line.lstrip().startswith("#") or SKIP_LINE.search(line):
                continue
            # хвостовой комментарий отрезаем, только если # вне строки
            code = re.sub(r'#(?=(?:[^"]*"[^"]*")*[^"]*$).*$', "", line)
            for m in STR.finditer(code):
                s = m.group(1).replace("\\n", "\n").replace('\\"', '"')
                if CYR.search(s):
                    out.setdefault(s, f"{os.path.relpath(f, ROOT)}:{n}")
    return out


def data_strings():
    out = {}
    keys = {"name", "flavor", "desc", "line", "title", "caption", "text", "label", "lines"}
    def walk(o, f):
        if isinstance(o, dict):
            for k, v in o.items():
                if k in keys and isinstance(v, str) and CYR.search(v):
                    out.setdefault(v, f)
                elif k in keys and isinstance(v, list):
                    for x in v:
                        if isinstance(x, str) and CYR.search(x):
                            out.setdefault(x, f)
                walk(v, f)
        elif isinstance(o, list):
            for v in o:
                walk(v, f)
    for f in glob.glob(os.path.join(ROOT, "data", "*.json")):
        walk(json.load(open(f, encoding="utf-8")), os.path.relpath(f, ROOT))
    return out


def main():
    found = {**data_strings(), **code_strings()}
    if "--dump" in sys.argv:
        for s, where in sorted(found.items(), key=lambda kv: kv[1]):
            print(f"{where}\t{s!r}")
        return 0
    en = json.load(open(os.path.join(ROOT, "data", "loc", "en.json"), encoding="utf-8"))
    missing = {s: w for s, w in found.items() if s not in en}
    stale = [k for k in en if k not in found]
    for s, w in sorted(missing.items(), key=lambda kv: kv[1]):
        print(f"НЕТ ПЕРЕВОДА  {w}  {s!r}")
    if stale:
        print(f"\nЛишних ключей в en.json: {len(stale)} (строки больше не встречаются в коде/данных)")
    print(f"\nнайдено строк: {len(found)}, переведено: {len(found) - len(missing)}, нет перевода: {len(missing)}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
