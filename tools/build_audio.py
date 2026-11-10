#!/usr/bin/env python3
"""Звук игры из настоящих записей (все источники — CC0 с OpenGameArt, лежат без изменений в assets/audio_src/).

  python3 tools/build_audio.py           # пишет assets/audio/*.ogg и docs/legal/AUDIO_SOURCES.md (нужны numpy и ffmpeg с libvorbis)

Обработка намеренно лёгкая, чтобы запись оставалась записью: обрезка тишины, вырезка фрагмента, плавные края, сдвиг высоты (только где указан),
мягкий срез верхов и выравнивание громкости по пику. Таблица SOUNDS — единственное место, где звук игры сопоставлен с исходником."""
import os
import subprocess
import tempfile
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "audio_src")
OUT = os.path.join(ROOT, "assets", "audio")
SR = 44100
OGA = "https://opengameart.org/content/"
PACKS = {   # набор → (название, автор, страница)
    "kui": ("Interface Sounds", "Kenney (kenney.nl)", OGA + "interface-sounds"),
    "krpg": ("50 RPG sound effects", "Kenney (kenney.nl)", OGA + "50-rpg-sound-effects"),
    "cutlery": ("cutlery sounds", "TinyWorlds", OGA + "cutlery-sounds"),
    "cat": ("Cat Purr & Meow", "Kerzoven", OGA + "cat-purr-meow"),
    "meow": ("Meow", "dino1489", OGA + "meow"),
    "kitten": ("Kitten Mew", "см. страницу", OGA + "kitten-mew"),
    "bell": ("Pleasing Bell Sound Effect", "Spring Spring", OGA + "pleasing-bell-sound-effect"),
    "ding": ("Bell dings/chimes", "PWL", OGA + "bell-dingschimes"),
    "water": ("40 CC0 water / splash / slime SFX", "rubberduck", OGA + "40-cc0-water-splash-slime-sfx"),
    "swish": ("Swishes Sound Pack", "artisticdude", OGA + "swishes-sound-pack"),
    "metal": ("Metal Interactions", "qubodup", OGA + "metal-interactions"),
    "steam": ("Steam release sounds", "bart", OGA + "steam-release-sounds"),
    "cozy": ("Cozy Puzzle (Title, In-Game 1, Jingle & Result)", "MintoDog", OGA + "cozy-puzzle-title"),
}
# звук игры: (набор, файл, что это, параметры). Параметры: start/dur — фрагмент (с), peak — пик после выравнивания (дБ), pitch — полутоны,
# lowpass — срез верхов (Гц), fin/fout — плавные края (с), stereo — оставить стерео (музыка и джинглы)
SOUNDS = {
    "click": ("kui", "select_002.ogg", "кнопки интерфейса", {"peak": -10}),
    "back": ("kui", "back_004.ogg", "кнопка «Назад»", {"peak": -10}),
    "tap": ("kui", "back_002.ogg", "касание в обучении", {"peak": -10}),
    "pick": ("kui", "drop_003.ogg", "автосборка заказа", {"peak": -8}),
    "pop": ("cutlery", "cup_on_table_01.ogg", "выпечка или добавка легла на поднос (чашка о стол)", {"peak": -5}),
    "pour": ("water", "loop_water_01.ogg", "напиток льётся в чашку", {"start": 0.35, "dur": 0.85, "fin": 0.04, "fout": 0.35, "peak": -7}),
    "steam": ("steam", "steam_hiss_1.wav", "пар кофемашины, когда наливают кофе", {"dur": 0.9, "fout": 0.5, "lowpass": 7000, "peak": -16}),
    "success": ("cutlery", "fork_on_dish_01.ogg", "заказ подан (звон тарелки)", {"peak": -6}),
    "purr": ("cat", "cat_mewpurr.wav", "довольный гость: быстрая подача", {"peak": -6, "fout": 0.2}),
    "fail": ("krpg", "bookClose.ogg", "не тот заказ (глухой стук)", {"pitch": -3, "peak": -9}),
    "angry": ("cat", "cat_mewfood.wav", "гость ушёл недовольным", {"pitch": -3, "peak": -6, "fout": 0.15}),
    "meow1": ("meow", "Meow.ogg", "мяу", {"peak": -6}),
    "meow2": ("kitten", "kitten_mew-1.wav", "мяу котёнка", {"peak": -6, "fout": 0.1}),
    "coin": ("krpg", "handleCoins2.ogg", "монеты в итогах и наградах", {"peak": -7}),
    "star": ("bell", "pleasing-bell.wav", "звезда, награда", {"peak": -5}),
    "bell": ("ding", "bell_ding2.wav", "колокольчик над дверью кафе", {"peak": -8, "fout": 0.4}),
    "shutter": ("metal", "metal_swing1.wav", "ставни кафе", {"peak": -6}),
    "box": ("krpg", "dropLeather.ogg", "коробка во вступлении", {"peak": -7}),
    "whoosh": ("swish", "swish-7.wav", "поднос уезжает к гостю", {"peak": -12}),
    "page": ("krpg", "bookFlip2.ogg", "шпаргалка рецептов: открыть, перелистнуть", {"peak": -10}),
    "jingle_win": ("cozy", "cozy_puzzle_clear_jingle.ogg", "итог смены: есть звёзды", {"peak": -7, "stereo": True}),
    "jingle_lose": ("cozy", "cozy_puzzle_failure_jingle.ogg", "итог смены: без звёзд", {"peak": -8, "stereo": True}),
    "music_city": ("cozy", "cozy_puzzle_title_bpm95.ogg", "музыка города (петля)", {"peak": -4, "stereo": True, "music": True}),
    "music_shift": ("cozy", "cozy_puzzle_in-game_1_bpm118.ogg", "музыка смены (петля)", {"peak": -4, "stereo": True, "music": True}),
}


def decode(path, channels):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", str(channels), "-ar", str(SR), "-f", "f32le", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, channels).copy()


def trim_silence(x, thresh=0.01):
    amp = np.abs(x).max(axis=1)
    idx = np.nonzero(amp > thresh * max(amp.max(), 1e-9))[0]
    if len(idx) == 0:
        return x
    a = max(0, idx[0] - int(0.003 * SR))
    b = min(len(x), idx[-1] + int(0.02 * SR))
    return x[a:b]


def lowpass(x, cutoff):
    spec = np.fft.rfft(x, axis=0)
    freq = np.fft.rfftfreq(len(x), 1.0 / SR)
    gain = 1.0 / np.sqrt(1.0 + (freq / cutoff) ** 8)      # плавный срез 4-го порядка, без звона
    return np.fft.irfft(spec * gain[:, None], n=len(x), axis=0).astype(np.float32)


def repitch(x, semitones):
    k = 2.0 ** (semitones / 12.0)                          # как пластинка: ниже и чуть длиннее
    n = int(len(x) / k)
    pos = np.arange(n) * k
    i = np.minimum(pos.astype(int), len(x) - 2)
    f = (pos - i)[:, None]
    return (x[i] * (1 - f) + x[i + 1] * f).astype(np.float32)


def fade(x, fin, fout):
    n = len(x)
    a, b = min(int(fin * SR), n // 2), min(int(fout * SR), n // 2)
    if a > 0:
        x[:a] *= np.linspace(0, 1, a, dtype=np.float32)[:, None] ** 2
    if b > 0:
        x[-b:] *= np.linspace(1, 0, b, dtype=np.float32)[:, None] ** 2
    return x


def encode(x, path, quality):
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        name = tmp.name
    with wave.open(name, "wb") as w:
        w.setnchannels(x.shape[1])
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", name, "-c:a", "libvorbis", "-q:a", str(quality), "-map_metadata", "-1", path], check=True)
    os.unlink(name)


def build(name):
    pack, file, _, o = SOUNDS[name]
    x = decode(os.path.join(SRC, file), 2 if o.get("stereo") else 1)
    if not o.get("music"):
        x = trim_silence(x)
    if "start" in o or "dur" in o:
        a = int(o.get("start", 0.0) * SR)
        x = x[a:a + int(o["dur"] * SR)] if "dur" in o else x[a:]
    if "pitch" in o:
        x = repitch(x, o["pitch"])
    if "lowpass" in o:
        x = lowpass(x, o["lowpass"])
    if not o.get("music"):
        x = fade(x, o.get("fin", 0.002), o.get("fout", 0.03))
    x = x / max(float(np.abs(x).max()), 1e-9) * (10.0 ** (o.get("peak", -6) / 20.0))
    encode(x, os.path.join(OUT, name + ".ogg"), 4 if o.get("stereo") else 5)
    return len(x) / SR


def write_sources(lengths):
    lines = ["# Источники звука", "",
             "Все звуки и музыка игры — настоящие записи с лицензией **CC0** (общественное достояние), взяты с OpenGameArt. Исходные файлы лежат без изменений",
             "в `assets/audio_src/`, игровые файлы `assets/audio/*.ogg` собирает `python3 tools/build_audio.py` (вырезка фрагмента, плавные края, громкость;",
             "сдвиг высоты и срез верхов — только где указано в таблице скрипта). Указывать авторов CC0 не требует, но они перечислены в титрах игры.", "",
             "| Звук в игре | Где звучит | Длина, с | Исходный файл | Набор | Автор | Страница |", "|---|---|---|---|---|---|---|"]
    for name, (pack, file, what, _) in SOUNDS.items():
        title, author, url = PACKS[pack]
        lines.append(f"| `{name}` | {what} | {lengths[name]:.2f} | `{file}` | {title} | {author} | {url} |")
    lines += ["", "Проверено при загрузке (2026-11-10): на странице каждого набора указана лицензия CC0. Сохраните снимки страниц в `docs/legal/receipts/` перед релизом.", ""]
    open(os.path.join(ROOT, "docs", "legal", "AUDIO_SOURCES.md"), "w", encoding="utf-8").write("\n".join(lines))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    lengths = {}
    for n in SOUNDS:
        lengths[n] = build(n)
        print(f"{n:12s} {lengths[n]:7.2f} с  ← {SOUNDS[n][1]}")
    write_sources(lengths)
