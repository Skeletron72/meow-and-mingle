#!/usr/bin/env python3
"""Синтез всего звука игры: звуки интерфейса/игры и две музыкальные петли. Всё считается из формул — права на звук принадлежат проекту.

  python3 tools/generators/make_audio.py        # пишет assets/audio/*.ogg (нужны numpy и ffmpeg с libvorbis)

Повторный запуск даёт те же файлы (фиксированное зерно шума). Названия — в autoload/audio.gd (SFX / MUSIC).
"""
import os
import subprocess
import tempfile
import wave

import numpy as np

SR = 32000
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "assets", "audio")
rng = np.random.default_rng(7)


def t_(dur):
    return np.arange(int(SR * dur)) / SR


def env(n, a=0.005, d=0.08, s=0.0, r=0.05, hold=None):
    """ADSR-подобная огибающая длиной n отсчётов."""
    a_n, d_n, r_n = int(SR * a), int(SR * d), int(SR * r)
    idx = np.arange(n)
    e = np.where(idx < a_n, idx / max(a_n, 1), 1.0)
    dec = np.clip((idx - a_n) / max(d_n, 1), 0, 1)
    e = np.where(idx >= a_n, 1.0 - (1.0 - s) * dec, e)
    rel = np.clip((n - idx) / max(r_n, 1), 0, 1)
    return e * rel


def tone(freq, dur, wave_kind="sine", vol=1.0, **kw):
    t = t_(dur)
    f = freq if np.ndim(freq) else np.full_like(t, freq)
    phase = 2 * np.pi * np.cumsum(f) / SR
    if wave_kind == "sine":
        w = np.sin(phase)
    elif wave_kind == "tri":
        w = 2 / np.pi * np.arcsin(np.sin(phase))
    elif wave_kind == "square":
        w = np.sign(np.sin(phase)) * 0.6
    elif wave_kind == "soft":   # электропиано: несколько гармоник с быстрым затуханием верхних
        w = np.sin(phase) + 0.35 * np.sin(2 * phase) * np.exp(-t * 6) + 0.12 * np.sin(3 * phase) * np.exp(-t * 9)
    else:
        w = np.sin(phase)
    return w * env(len(t), **kw) * vol


def noise(dur, vol=1.0, lp=None, **kw):
    n = rng.uniform(-1, 1, int(SR * dur))
    if lp:   # простой НЧ-фильтр (скользящее среднее)
        k = max(1, int(SR / lp))
        n = np.convolve(n, np.ones(k) / k, mode="same")
        n *= 1.0 / max(np.abs(n).max(), 1e-6)
    return n * env(len(n), **kw) * vol


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def seq(notes, gap=0.0):
    """notes: [(freq, dur, kind, vol)] идут друг за другом."""
    out = []
    for f, d, k, v in notes:
        out.append(tone(f, d, k, v, a=0.004, d=d * 0.6, r=0.04))
        if gap:
            out.append(np.zeros(int(SR * gap)))
    return np.concatenate(out)


def note(n):   # MIDI -> Гц
    return 440.0 * 2 ** ((n - 69) / 12)


def save(name, data, peak=0.85):
    data = np.asarray(data, dtype=np.float64)
    m = np.abs(data).max()
    if m > 0:
        data = data / m * peak
    pcm = (data * 32767).astype("<i2")
    with tempfile.TemporaryDirectory() as td:
        wav = os.path.join(td, name + ".wav")
        with wave.open(wav, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        os.makedirs(OUT, exist_ok=True)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "3", os.path.join(OUT, name + ".ogg")], check=True)
    print(f"{name}.ogg  {len(pcm) / SR:.2f} с")


# ---------------------------------------------------------------- звуки

def sfx():
    save("click", mix(tone(880, 0.07, "tri", 0.8, a=0.002, d=0.05), tone(1320, 0.05, "sine", 0.3, a=0.002, d=0.04)))
    save("back", mix(tone(620, 0.08, "tri", 0.8, a=0.002, d=0.06), tone(420, 0.09, "sine", 0.4, a=0.002, d=0.07)))
    coin = np.concatenate([tone(note(88), 0.07, "square", 0.5, a=0.002, d=0.05), tone(note(95), 0.22, "square", 0.5, a=0.002, d=0.18, r=0.1)])
    save("coin", coin)
    save("pour", noise(0.5, 0.6, lp=1800, a=0.06, d=0.4, r=0.15) * (1 + 0.3 * np.sin(2 * np.pi * 18 * t_(0.5))))
    save("success", seq([(note(72), 0.09, "tri", 0.8), (note(76), 0.09, "tri", 0.8), (note(79), 0.09, "tri", 0.8), (note(84), 0.3, "tri", 0.9)]))
    save("fail", seq([(note(64), 0.14, "tri", 0.8), (note(58), 0.28, "tri", 0.8)]))
    angry = tone(np.linspace(300, 140, int(SR * 0.45)), 0.45, "square", 0.6, a=0.01, d=0.35) * (1 + 0.5 * np.sin(2 * np.pi * 30 * t_(0.45)))
    save("angry", angry)
    bell = mix(tone(1568, 0.8, "sine", 0.7, a=0.002, d=0.7), tone(2349, 0.6, "sine", 0.35, a=0.002, d=0.5), tone(3136, 0.4, "sine", 0.2, a=0.002, d=0.3))
    save("bell", bell)
    shutter = mix(noise(1.1, 0.7, lp=700, a=0.1, d=0.9, r=0.2), tone(np.linspace(90, 170, int(SR * 1.1)), 1.1, "square", 0.25, a=0.05, d=0.9))
    save("shutter", shutter)
    save("box", mix(noise(0.18, 0.8, lp=2500, a=0.002, d=0.12), tone(180, 0.15, "sine", 0.6, a=0.002, d=0.12)))
    save("tap", mix(noise(0.07, 0.6, lp=2200, a=0.002, d=0.05), tone(260, 0.06, "sine", 0.4, a=0.002, d=0.05)))
    save("star", seq([(note(84), 0.07, "sine", 0.7), (note(88), 0.07, "sine", 0.7), (note(91), 0.07, "sine", 0.7), (note(96), 0.35, "sine", 0.8)]))
    save("pop", tone(np.linspace(500, 1100, int(SR * 0.09)), 0.09, "sine", 0.8, a=0.002, d=0.07))
    save("whoosh", noise(0.35, 0.6, lp=1200, a=0.12, d=0.3, r=0.1))
    # мяу: два гласных, скользящая высота с вибрато и формантный всплеск
    def meow(base, dur):
        t = t_(dur)
        f = base * (1.0 + 0.35 * np.sin(np.pi * t / dur)) * (1 + 0.015 * np.sin(2 * np.pi * 7 * t))
        v = tone(f, dur, "soft", 0.9, a=0.03, d=dur * 0.7, r=0.1)
        form = np.sin(2 * np.pi * np.cumsum(f * 2.0) / SR) * 0.25 * np.sin(np.pi * t / dur)
        return (v + form) * env(len(t), a=0.03, d=dur * 0.8, r=0.12)
    save("meow1", meow(560, 0.55))
    save("meow2", meow(720, 0.42))


# ---------------------------------------------------------------- музыка

def piano(freq, dur, vol=0.5):
    return tone(freq, dur, "soft", vol, a=0.006, d=dur * 0.9, r=0.1)


def music(name, bpm, chords, melody, bars, swing=0.0, extra_bar_rest=False):
    """Петля: аккорды (электропиано), бас, лёгкий ритм и мелодия. chords — список из списков нот MIDI на такт."""
    beat = 60.0 / bpm
    total = bars * 4 * beat
    out = np.zeros(int(SR * (total + 1.5)))   # запас на хвост для бесшовной склейки
    for bar in range(bars):
        ch = chords[bar % len(chords)]
        t0 = bar * 4 * beat
        for k, nn in enumerate(ch):   # арпеджио по долям
            for b in (0, 1.5, 2, 3.5):
                s = t0 + (b + k * 0.02) * beat
                p = piano(note(nn), beat * 1.6, 0.22)
                i = int(SR * s)
                out[i:i + len(p)] += p[:len(out) - i]
        bass = tone(note(ch[0] - 12), beat * 1.8, "tri", 0.5, a=0.01, d=beat * 1.5, r=0.1)
        for b in (0, 2):
            i = int(SR * (t0 + b * beat))
            out[i:i + len(bass)] += bass[:len(out) - i]
        for b in range(4):   # щёточка
            hat = noise(0.05, 0.12, lp=6000, a=0.002, d=0.04)
            i = int(SR * (t0 + (b + 0.5) * beat))
            out[i:i + len(hat)] += hat[:len(out) - i]
        for b in (1, 3):   # мягкий «бум» на доли 2 и 4
            kick = tone(np.linspace(110, 60, int(SR * 0.2)), 0.2, "sine", 0.35, a=0.002, d=0.15)
            i = int(SR * (t0 + b * beat))
            out[i:i + len(kick)] += kick[:len(out) - i]
    for (bar, beat_pos, midi, length) in melody:
        s = (bar * 4 + beat_pos) * beat
        p = tone(note(midi), length * beat, "sine", 0.35, a=0.01, d=length * beat * 0.8, r=0.12)
        i = int(SR * s)
        out[i:i + len(p)] += p[:len(out) - i]
    n = int(SR * total)
    loop = out[:n].copy()
    tail = out[n:]
    loop[:len(tail)] += tail   # хвост последнего такта накладываем на начало: петля без щелчка
    save(name, loop, peak=0.7)


def musics():
    am, f, c, g = [57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]
    chords = [am, f, c, g]
    mel = [(0, 0, 76, 1.5), (0, 2, 72, 1), (0, 3, 74, 1), (1, 0, 72, 2), (1, 2, 69, 2), (2, 0, 67, 1.5), (2, 2, 72, 1), (2, 3, 71, 1),
           (3, 0, 69, 3), (4, 0, 76, 1.5), (4, 2, 79, 1), (4, 3, 76, 1), (5, 0, 77, 2), (5, 2, 76, 1), (5, 3, 72, 1), (6, 0, 74, 1.5),
           (6, 2, 72, 1), (6, 3, 67, 1), (7, 0, 69, 3)]
    music("music_city", 78, chords, mel, 8)
    dm, bb, f2, a7 = [50, 53, 57], [58, 62, 65], [53, 57, 60], [57, 61, 64]
    mel2 = [(0, 0, 74, 1), (0, 1, 77, 1), (0, 2, 81, 2), (1, 0, 79, 1), (1, 1, 77, 1), (1, 2, 74, 2), (2, 0, 72, 1), (2, 1, 76, 1), (2, 2, 79, 2),
            (3, 0, 76, 1), (3, 1, 73, 1), (3, 2, 69, 2), (4, 0, 74, 1), (4, 1, 77, 1), (4, 2, 81, 2), (5, 0, 82, 1), (5, 1, 81, 1), (5, 2, 77, 2),
            (6, 0, 76, 1), (6, 1, 72, 1), (6, 2, 69, 2), (7, 0, 74, 4)]
    music("music_shift", 104, [dm, bb, f2, a7], mel2, 8)


if __name__ == "__main__":
    sfx()
    musics()
