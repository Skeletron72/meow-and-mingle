#!/usr/bin/env python3
"""Аудит лицензий: каждый файл игры (assets/ без packs, шрифты, звук) должен попадать под правило из RULES.
Печатает таблицу «источник → число файлов → статус лицензии» и завершается с кодом 1, если
(а) есть файл без правила или (б) есть правило со статусом BLOCK. Статус UNVERIFIED — предупреждение (код 0, но видно в отчёте);
флаг --strict делает и его ошибкой (для релизной сборки).

  python3 tools/audit_assets.py [--strict]
"""
import fnmatch
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# (шаблон пути, источник, статус, что нужно для релиза)
# OK — коммерческое использование подтверждено; ATTR — нужны титры (учтены в data/credits.json);
# UNVERIFIED — лицензию сверить на странице автора/купить; BLOCK — использовать нельзя.
RULES = [
    ("assets/cats/*", "Neko Cafe Asset Pack (hellorumin)", "ATTR", "коммерция разрешена, титры; хранить чек/скрин лицензии"),
    ("assets/cafe/neko-cafe-*", "Neko Cafe Asset Pack (hellorumin)", "ATTR", "коммерция разрешена, титры; хранить чек/скрин лицензии"),
    ("assets/cafe/drinks-and-pastries.png", "100 Free Pixel Art Foods (Alex Kovacs)", "ATTR", "CC BY 4.0, титры"),
    ("assets/ui/*", "Mega Cozy UI Pack (dobo_ui)", "OK", "лицензия проверена владельцем проекта (2026-11-04); титры есть"),
    ("assets/street/buildings/*", "City Essentials (Ranitaya)", "OK", "лицензия проверена владельцем проекта (2026-11-04); титры есть"),
    ("assets/street/props/*", "City Essentials (Ranitaya)", "OK", "лицензия проверена владельцем проекта (2026-11-04); титры есть"),
    ("assets/street/tiles/*", "собственные (tools/generators)", "OK", "-"),
    ("assets/street/vehicles/*", "TopDown Vehicles (MinZiin_)", "ATTR", "CC BY 4.0, титры"),
    ("assets/fonts/Galmuri*", "Galmuri (SIL OFL 1.1)", "ATTR", "OFL: оставить OFL-Galmuri.txt, упомянуть в титрах"),
    ("assets/fonts/OFL-Galmuri.txt", "Galmuri (SIL OFL 1.1)", "ATTR", "лицензия шрифта"),
    ("assets/shaders/*", "собственные", "OK", "-"),
    ("assets/audio/*", "записи CC0 с OpenGameArt (tools/build_audio.py)", "OK", "источники и авторы: docs/legal/AUDIO_SOURCES.md; CC0, титры есть"),
    ("assets/audio_src/*", "записи CC0 с OpenGameArt (исходники звука)", "OK", "CC0; в сборку не входят (.gdignore)"),
    ("icon.svg", "собственные", "OK", "-"),
    ("assets/icons/*", "собственные (tools/generators/make_store_icon.py)", "OK", "иконка нарисована кодом; персонаж и кружка — свои"),
    ("assets/packs/modern-interiors-free/*", "Modern Interiors Free (LimeZu)", "BLOCK", "только некоммерческое использование"),
]
SKIP_EXT = (".import", ".uid")


def status_of(path):
    for pat, src, st, note in RULES:
        if fnmatch.fnmatch(path, pat):
            return src, st, note
    return None


def main():
    strict = "--strict" in sys.argv
    files = []
    for base in ("assets", "icon.svg"):
        full = os.path.join(ROOT, base)
        if os.path.isfile(full):
            files.append(base)
            continue
        for dp, dn, fn in os.walk(full):
            rel = os.path.relpath(dp, ROOT).replace(os.sep, "/")
            if rel == "assets/packs" or rel.startswith("assets/packs/"):
                dn[:] = []
                continue
            for f in fn:
                if f.endswith(SKIP_EXT) or f in ("README.md", "theme.tres") or f.endswith(".tres") or f == ".gdignore":
                    continue
                files.append(rel + "/" + f)
    summary = {}
    missing = []
    for f in sorted(files):
        r = status_of(f)
        if r is None:
            missing.append(f)
            continue
        key = (r[0], r[1], r[2])
        summary[key] = summary.get(key, 0) + 1
    bad = 0
    print(f"{'источник':58} {'файлов':>6}  статус     что нужно")
    for (src, st, note), n in sorted(summary.items(), key=lambda kv: kv[0][1]):
        print(f"{src:58} {n:>6}  {st:10} {note}")
        if st == "BLOCK" or (strict and st == "UNVERIFIED"):
            bad += n
    for f in missing:
        print("БЕЗ ПРАВИЛА:", f)
    print(f"\nвсего файлов: {len(files)}, без правила: {len(missing)}, мешает релизу: {bad}")
    return 1 if (missing or bad) else 0


if __name__ == "__main__":
    sys.exit(main())
