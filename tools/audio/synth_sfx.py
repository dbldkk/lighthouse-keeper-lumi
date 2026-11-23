#!/usr/bin/env python3
"""Процедурные звуки для «Смотрителя маяка»: шаги по поверхностям и звуки ужаса.

Запуск из корня проекта:  python3 tools/audio/synth_sfx.py
Результат: assets/audio/steps/*.wav и assets/audio/horror/*.wav (44.1 кГц, моно, 16 бит).
Нужен только numpy. Seed фиксирован — файлы воспроизводимы.
"""
import math, os, wave
import numpy as np

SR = 44100
ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")
rng = np.random.default_rng(20261123)


def biquad(x, kind, f0, q=0.707, gain_db=0.0):
    a = 10 ** (gain_db / 40)
    w0 = 2 * math.pi * f0 / SR
    cw, sw = math.cos(w0), math.sin(w0)
    alpha = sw / (2 * q)
    if kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]; aa = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]; aa = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "bp":
        b = [alpha, 0, -alpha]; aa = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "peak":
        b = [1 + alpha * a, -2 * cw, 1 - alpha * a]; aa = [1 + alpha / a, -2 * cw, 1 - alpha / a]
    else:
        raise ValueError(kind)
    b = [v / aa[0] for v in b]; a1, a2 = aa[1] / aa[0], aa[2] / aa[0]
    y = np.zeros_like(x); x1 = x2 = y1 = y2 = 0.0
    for i, xi in enumerate(x):
        yi = b[0] * xi + b[1] * x1 + b[2] * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, xi, y1, yi
        y[i] = yi
    return y


def t_axis(sec):
    return np.arange(int(sec * SR)) / SR


def env_exp(sec, tau, attack=0.003):
    t = t_axis(sec)
    e = np.exp(-t / tau)
    a = np.clip(t / attack, 0, 1)
    return e * a


def fade(x, fin=0.003, fout=0.02):
    n_in, n_out = int(fin * SR), int(fout * SR)
    x = x.copy()
    if n_in > 0:
        x[:n_in] *= np.linspace(0, 1, n_in)
    if n_out > 0:
        x[-n_out:] *= np.linspace(1, 0, n_out) ** 2
    return x


def norm(x, peak_db=-3.0):
    m = np.max(np.abs(x)) or 1.0
    return x / m * (10 ** (peak_db / 20))


def save(path, x):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data.tobytes())


def noise(sec):
    return rng.uniform(-1, 1, int(sec * SR))


def grains(sec, count, spread, length=0.004, start=0.0):
    out = np.zeros(int(sec * SR))
    for _ in range(count):
        at = int((start + abs(rng.normal(0, spread))) * SR)
        n = int(length * SR * rng.uniform(.6, 1.4))
        if at + n >= out.size:
            continue
        out[at:at + n] += rng.uniform(-1, 1, n) * np.hanning(n) * rng.uniform(.3, 1)
    return out


# ---------------------------------------------------------------- шаги
def step_grass(v):
    sec = 0.26
    crunch = grains(sec, 70 + v * 6, 0.035, 0.003, 0.004)
    crunch = biquad(biquad(crunch, "hp", 900), "lp", 5200)
    body = np.sin(2 * math.pi * (68 + v * 4) * t_axis(sec)) * env_exp(sec, 0.025, 0.004)
    swish = biquad(noise(sec), "bp", 2400 + v * 200, 0.8) * env_exp(sec, 0.05, 0.012) * 0.35
    return fade(norm(crunch * 0.9 + body * 0.55 + swish, -6))


def step_wood(v):
    sec = 0.3
    t = t_axis(sec)
    f = 118 + v * 9
    knock = (np.sin(2 * math.pi * f * t) * env_exp(sec, 0.05)
             + 0.5 * np.sin(2 * math.pi * f * 2.13 * t) * env_exp(sec, 0.028)
             + 0.3 * np.sin(2 * math.pi * f * 3.71 * t) * env_exp(sec, 0.016))
    click = biquad(noise(sec), "bp", 1800 + v * 150, 1.2) * env_exp(sec, 0.006, 0.0008)
    creak = biquad(noise(sec), "bp", 650, 6) * env_exp(sec, 0.07, 0.02) * 0.15
    return fade(norm(knock * 0.8 + click * 0.7 + creak, -5))


def step_stone(v):
    sec = 0.22
    tap = biquad(noise(sec), "hp", 1500) * env_exp(sec, 0.008, 0.0006)
    grit = biquad(grains(sec, 40, 0.02, 0.002, 0.006), "bp", 3800 + v * 300, 0.9) * 0.6
    body = np.sin(2 * math.pi * (92 + v * 5) * t_axis(sec)) * env_exp(sec, 0.018, 0.002) * 0.5
    room = biquad(noise(sec), "lp", 900) * env_exp(sec, 0.06, 0.01) * 0.12
    return fade(norm(tap + grit + body + room, -5))


def step_sand(v):
    sec = 0.32
    g = grains(sec, 160 + v * 10, 0.06, 0.002, 0.008)
    g = biquad(biquad(g, "hp", 1600), "lp", 7000)
    hush = biquad(noise(sec), "bp", 1200, 0.6) * env_exp(sec, 0.07, 0.015) * 0.4
    body = np.sin(2 * math.pi * 60 * t_axis(sec)) * env_exp(sec, 0.03, 0.006) * 0.35
    return fade(norm(g + hush + body, -7))


# ---------------------------------------------------------------- ужас и обратная связь
def heartbeat():
    sec = 0.7
    t = t_axis(sec)
    def beat(at, f, amp):
        tt = np.clip(t - at, 0, None)
        e = np.where(t >= at, np.exp(-tt / 0.06) * np.clip(tt / 0.006, 0, 1), 0)
        return np.sin(2 * math.pi * f * tt) * e * amp
    x = beat(0.0, 52, 1.0) + beat(0.19, 46, 0.7)
    x = biquad(x, "lp", 180)
    return fade(norm(x, -2), 0.002, 0.08)


def static_burst():
    sec = 1.4
    t = t_axis(sec)
    n = noise(sec)
    crackle = grains(sec, 220, 0.5, 0.0015, 0.0)
    gate = (np.sin(2 * math.pi * 9 * t) > -0.2).astype(float) * 0.6 + 0.4
    tone = np.sin(2 * math.pi * 1450 * t + 6 * np.sin(2 * math.pi * 3 * t)) * 0.12
    x = biquad(n, "bp", 2200, 0.5) * gate + crackle * 0.8 + tone
    x *= np.clip(t / 0.01, 0, 1) * np.clip((sec - t) / 0.25, 0, 1)
    return norm(x, -2)


def stinger():
    sec = 2.6
    t = t_axis(sec)
    freqs = [138.6, 146.8, 207.7, 293.7, 311.1, 622.3]
    x = sum(np.sin(2 * math.pi * f * t + rng.uniform(0, 6)) * (1 / (i + 1)) for i, f in enumerate(freqs))
    scrape = biquad(noise(sec), "bp", 3200, 3) * 0.5
    hit = biquad(noise(sec), "lp", 400) * env_exp(sec, 0.08, 0.002) * 2.0
    e = env_exp(sec, 0.9, 0.004)
    x = (x * 0.5 + scrape) * e + hit
    return fade(norm(x, -1), 0.002, 0.3)


def door_slam():
    sec = 1.5
    t = t_axis(sec)
    impact = biquad(noise(sec), "lp", 600) * env_exp(sec, 0.05, 0.001) * 1.6
    body = (np.sin(2 * math.pi * 74 * t) + 0.6 * np.sin(2 * math.pi * 131 * t)) * env_exp(sec, 0.16, 0.001)
    rattle = biquad(grains(sec, 60, 0.12, 0.003, 0.03), "bp", 2600, 1.5) * 0.5
    tail = biquad(noise(sec), "lp", 300) * env_exp(sec, 0.5, 0.02) * 0.2
    return fade(norm(impact + body + rattle + tail, -1), 0.001, 0.2)


def whisper():
    sec = 2.4
    t = t_axis(sec)
    n = noise(sec)
    # «Слоги»: полосовой шум с бегущими формантами.
    f1 = 900 + 500 * np.sin(2 * math.pi * 1.7 * t)
    out = np.zeros_like(n)
    for lo, hi in [(700, 1400), (1800, 3200), (3800, 6000)]:
        out += biquad(n, "bp", (lo + hi) / 2, 2.0)
    syll = np.clip(np.sin(2 * math.pi * 3.3 * t + np.sin(2 * math.pi * 0.7 * t) * 2), 0, 1) ** 2
    x = out * syll * np.clip(t / 0.3, 0, 1) * np.clip((sec - t) / 0.4, 0, 1)
    _ = f1
    return norm(x, -4)


def lantern_flicker():
    sec = 0.9
    t = t_axis(sec)
    sputter = grains(sec, 45, 0.3, 0.006, 0.0)
    sputter = biquad(sputter, "bp", 900, 0.8)
    hiss = biquad(noise(sec), "hp", 3000) * 0.15 * np.clip((sec - t) / sec, 0, 1)
    return fade(norm(sputter + hiss, -4), 0.002, 0.1)


def breath():
    sec = 1.8
    t = t_axis(sec)
    n = biquad(noise(sec), "bp", 1100, 0.7)
    inhale = np.clip(np.sin(math.pi * np.clip(t / 0.8, 0, 1)), 0, 1) ** 2
    exhale = np.where(t > 0.9, np.clip(np.sin(math.pi * np.clip((t - 0.9) / 0.85, 0, 1)), 0, 1), 0) ** 1.5
    x = n * (inhale * 0.7 + exhale)
    return fade(norm(x, -5), 0.01, 0.1)


def hit():
    sec = 0.45
    t = t_axis(sec)
    thud = np.sin(2 * math.pi * (90 - 40 * t) * t) * env_exp(sec, 0.07, 0.001)
    crack = biquad(noise(sec), "bp", 1500, 0.7) * env_exp(sec, 0.03, 0.0005)
    sub = biquad(noise(sec), "lp", 200) * env_exp(sec, 0.12, 0.002) * 0.7
    return fade(norm(thud + crack * 0.8 + sub, -1))


def tell():
    sec = 0.55
    t = t_axis(sec)
    rise = np.sin(2 * math.pi * (300 + 900 * t ** 2) * t) * 0.3
    air = biquad(noise(sec), "bp", 2500, 2) * 0.8
    e = np.clip(t / 0.4, 0, 1) ** 2 * np.clip((sec - t) / 0.08, 0, 1)
    return norm((rise + air) * e, -4)


def splash():
    sec = 1.1
    t = t_axis(sec)
    body = biquad(noise(sec), "lp", 1400) * env_exp(sec, 0.18, 0.004)
    drops = biquad(grains(sec, 80, 0.25, 0.006, 0.05), "bp", 2200, 1.0) * 0.6
    return fade(norm(body + drops, -3), 0.003, 0.2)


def drone_low():
    sec = 8.0
    t = t_axis(sec)
    x = (np.sin(2 * math.pi * 41.2 * t) + 0.6 * np.sin(2 * math.pi * 43.1 * t)
         + 0.25 * np.sin(2 * math.pi * 61.7 * t + np.sin(2 * math.pi * 0.125 * t) * 2))
    air = biquad(noise(sec), "lp", 260) * 0.4
    x = x + air
    # Бесшовная петля: нечётные частоты дают целое число периодов за 8 с лишь приблизительно — сглаживаем стык.
    n = int(0.3 * SR)
    x[:n] = x[:n] * np.linspace(0, 1, n) + x[-n:] * np.linspace(1, 0, n)
    x = x[:-n]
    return norm(x, -6)


def main():
    steps = {"grass": step_grass, "wood": step_wood, "stone": step_stone, "sand": step_sand}
    for name, fn in steps.items():
        for v in range(1, 6):
            save(os.path.join(ROOT, "steps", f"{name}_{v}.wav"), fn(v))
    horror = {"heartbeat": heartbeat, "static_burst": static_burst, "stinger": stinger, "door_slam": door_slam,
              "whisper": whisper, "lantern_flicker": lantern_flicker, "breath": breath, "hit": hit,
              "tell": tell, "splash": splash, "drone_low": drone_low}
    for name, fn in horror.items():
        save(os.path.join(ROOT, "horror", f"{name}.wav"), fn())
    print("ok")


if __name__ == "__main__":
    main()
