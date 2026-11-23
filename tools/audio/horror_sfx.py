#!/usr/bin/env python3
"""Хоррор-набор звуков «Смотрителя маяка»: фон, отклик действий, мини-игры, пугалки.

Источники:
  * записи CC0 с freesound.org (список, авторы и ссылки — tools/audio/cc0_sources.json,
    скачать заново: python3 tools/audio/fetch_cc0.py);
  * процедурный синтез (numpy) для гулов, ударов, щелчков и диссонансов.
Обработка: понижение тона, фильтры, «комнатная» реверберация, сжатие динамики.

Запуск из корня проекта:  python3 tools/audio/horror_sfx.py
Нужны numpy, scipy и ffmpeg. Результат: assets/audio/ambience/*.wav, assets/audio/sfx/*.wav,
обновлённые assets/audio/steps/*.wav и assets/audio/music/menu_tide.wav.
Seed фиксирован — синтетические файлы воспроизводимы.
"""
import json, math, os, subprocess, wave
import numpy as np
from scipy import signal

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
AUDIO = os.path.join(ROOT, "assets", "audio")
CACHE = os.environ.get("CC0_CACHE", os.path.join(HERE, ".cc0_cache"))
rng = np.random.default_rng(1123)


# ---------------------------------------------------------------- базовые операции
def t_axis(sec, sr=SR):
    return np.arange(int(sec * sr)) / sr


def noise(sec, sr=SR):
    return rng.uniform(-1, 1, int(sec * sr))


def filt(x, kind, f, order=2, sr=SR):
    if kind == "bp":
        b, a = signal.butter(order, [f[0] / (sr / 2), f[1] / (sr / 2)], "bandpass")
    else:
        b, a = signal.butter(order, f / (sr / 2), {"lp": "lowpass", "hp": "highpass"}[kind])
    return signal.lfilter(b, a, x)


def env(sec, attack, tau, sr=SR):
    t = t_axis(sec, sr)
    return np.clip(t / max(attack, 1e-4), 0, 1) * np.exp(-np.maximum(t - attack, 0) / tau)


def fade(x, fin=0.005, fout=0.05, sr=SR):
    x = x.copy()
    a, b = int(fin * sr), int(fout * sr)
    if a: x[:a] *= np.linspace(0, 1, a)
    if b: x[-b:] *= np.linspace(1, 0, b) ** 2
    return x


def norm(x, peak_db=-3.0):
    m = np.max(np.abs(x)) or 1.0
    return x / m * 10 ** (peak_db / 20)


def pad(x, sec, sr=SR):
    return np.concatenate([x, np.zeros(int(sec * sr))])


def mix(*parts):
    n = max(p.size for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:p.size] += p
    return out


def at(x, sec, total, sr=SR):
    out = np.zeros(int(total * sr))
    i = int(sec * sr)
    n = min(x.size, out.size - i)
    if n > 0:
        out[i:i + n] = x[:n]
    return out


def reverb(x, seconds=1.6, wet=0.35, damp=3500, pre=0.02, sr=SR):
    """Простая реверберация: свёртка с затухающим отфильтрованным шумом."""
    n = int(seconds * sr)
    ir = rng.normal(0, 1, n) * np.exp(-t_axis(seconds, sr) * 6.9 / seconds)
    ir = filt(ir, "lp", damp, sr=sr)
    ir = np.concatenate([np.zeros(int(pre * sr)), ir])
    ir /= np.sqrt(np.sum(ir ** 2)) or 1
    tail = signal.fftconvolve(pad(x, seconds + pre, sr), ir)[: x.size + int((seconds + pre) * sr)]
    dry = pad(x, seconds + pre, sr)
    tail = tail / (np.max(np.abs(tail)) or 1) * (np.max(np.abs(dry)) or 1)
    return dry * (1 - wet) + tail * wet


def pitch(x, factor):
    """Сдвиг высоты ресемплингом (с изменением длительности) — тяжелее и медленнее."""
    n = int(x.size / factor)
    return signal.resample(x, n)


def compress(x, amount=0.6):
    return np.tanh(x * (1 + amount * 3)) / np.tanh(1 + amount * 3)


def loopify(x, xfade=1.5, sr=SR):
    n = int(xfade * sr)
    head, body, tail = x[:n], x[n:-n], x[-n:]
    k = np.linspace(0, 1, n)
    joined = tail * np.cos(k * math.pi / 2) + head * np.sin(k * math.pi / 2)
    return np.concatenate([body, joined])


def save(rel, x, sr=SR, peak=-3.0):
    path = os.path.join(AUDIO, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = (np.clip(norm(x, peak), -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes(data.tobytes())


def load_cc0(key, index=1, start=0.0, length=None, sr=SR):
    """Загрузка записи CC0 из кэша (mp3 с freesound) в моно float."""
    path = os.path.join(CACHE, f"{key}_{index}.mp3")
    if not os.path.exists(path):
        return None
    cmd = ["ffmpeg", "-v", "error", "-ss", str(start)] + (["-t", str(length)] if length else []) + ["-i", path, "-ac", "1", "-ar", str(sr), "-f", "f32le", "-"]
    raw = subprocess.run(cmd, capture_output=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    return x if x.size else None


# ---------------------------------------------------------------- синтез
def sine(f, sec, phase=0.0, sr=SR):
    return np.sin(2 * math.pi * f * t_axis(sec, sr) + phase)


def drone_cluster(sec, base=55.0):
    """Диссонансный гул: малая секунда + тритон, медленные биения, шум ветра снизу."""
    t = t_axis(sec)
    lfo = lambda f, d: 1 + d * np.sin(2 * math.pi * f * t + rng.uniform(0, 6))
    x = (sine(base, sec) * lfo(.07, .3) + .7 * sine(base * 1.059, sec) * lfo(.05, .4)
         + .45 * sine(base * 1.414, sec) * lfo(.031, .5) + .25 * sine(base * 2.12, sec) * lfo(.09, .6)
         + .35 * sine(base / 2, sec))
    air = filt(noise(sec), "bp", (60, 300)) * 1.6 * lfo(.04, .5)
    return x * .6 + air


def bell(f0=110.0, sec=5.0, bright=0.4):
    """Низкий надтреснутый колокол — неровные обертоны вместо «детского» звона."""
    partials = [(.5, 1.0, 4.0), (1.0, .8, 3.0), (1.19, .6, 2.2), (1.56, .45, 1.6), (2.0, .4, 1.3), (2.51, .25 * bright * 2, .9), (3.1, .2 * bright * 2, .6)]
    x = np.zeros(int(sec * SR))
    for r, a, tau in partials:
        detune = 1 + rng.uniform(-.004, .004)
        x += a * sine(f0 * r * detune, sec) * env(sec, .004, tau)
    x += filt(noise(sec), "bp", (800, 3000)) * env(sec, .001, .03) * .4
    return x


def thud(f=60.0, sec=.6, tau=.12, click=.3):
    x = sine(f, sec) * env(sec, .002, tau) + sine(f * 1.6, sec) * env(sec, .002, tau * .5) * .4
    x += filt(noise(sec), "lp", 900) * env(sec, .001, .02) * click
    return x


def metal_hit(f=180.0, sec=1.6, tau=.5):
    ratios = [1.0, 2.76, 5.4, 8.93, 1.47]
    x = sum(sine(f * r, sec) * env(sec, .001, tau / (1 + i * .6)) * (1 / (1 + i)) for i, r in enumerate(ratios))
    x += filt(noise(sec), "hp", 2000) * env(sec, .0005, .01) * .6
    return x


def creak_synth(sec=1.4, f0=90.0):
    """Скрип дерева: серия импульсов трения с плавающей частотой через резонансы."""
    t = t_axis(sec)
    rate = f0 * (1 + .5 * np.sin(2 * math.pi * .7 * t) + .3 * rng.normal(0, .02, t.size).cumsum() / 50)
    phase = np.cumsum(rate) / SR
    pulses = (np.diff(np.floor(phase), prepend=0) > 0).astype(float)
    x = filt(pulses, "bp", (300, 1400)) + filt(pulses, "bp", (1800, 2600)) * .4
    return x * np.sin(math.pi * np.clip(t / sec, 0, 1)) ** .6


# ---------------------------------------------------------------- фон (петли)
def build_ambience():
    def src_or(key, idx, start, length, fallback):
        x = load_cc0(key, idx, start, length)
        if x is None or x.size < SR * 4:
            print("  (нет записи", key, "— синтез)")
            return fallback()
        return x

    # Море: тяжёлые редкие накаты, без «шипучки».
    sea = src_or("sea", 1, 2, 26, lambda: filt(noise(26), "lp", 500) * (0.5 + .5 * np.sin(2 * math.pi * t_axis(26) / 6.5) ** 2))
    sea = filt(pitch(sea, .85), "lp", 2200)
    sea = sea + filt(sea, "lp", 180) * 1.5
    save("ambience/sea_loop.wav", loopify(fade(sea[: SR * 24], .2, .2)), peak=-4)

    # Ветер: вой с медленными порывами.
    wind = src_or("wind", 1, 3, 24, lambda: filt(noise(24), "bp", (250, 900)))
    w2 = filt(noise(wind.size / SR), "bp", (420, 520), order=2) * (0.5 + .5 * np.sin(2 * math.pi * t_axis(wind.size / SR) / 7.3) ** 4) * .5
    wind = filt(wind, "lp", 2600) + w2
    save("ambience/wind_loop.wav", loopify(fade(wind[: SR * 22], .2, .2)), peak=-5)

    # Дождь: глухой, «по крыше».
    rain = src_or("rain", 1, 1, 14, lambda: filt(noise(14), "bp", (400, 4000)))
    rain = filt(rain, "lp", 3500)
    save("ambience/rain_loop.wav", loopify(fade(rain[: SR * 13], .2, .2)), peak=-5)

    # Ночной гул: диссонанс + далёкий металлический стон.
    sec = 24
    d = drone_cluster(sec, 49.0)
    groan = load_cc0("metal_groan", 1, 0, 6)
    if groan is not None:
        groan = reverb(filt(pitch(groan, .5), "lp", 1500), 3.0, .6)
        d = d + at(groan * .25, 9, sec)
    rumble = load_cc0("thunder", 1, 0, 8)
    if rumble is not None:
        d = d + at(filt(pitch(rumble, .7), "lp", 400) * .5, 15, sec)
    save("ambience/night_drone.wav", loopify(d, 2.0), peak=-5)

    # Двигатель катера: тяжёлый дизель.
    eng = src_or("engine", 1, 2, 8, lambda: compress(sine(28, 8) * (.6 + .4 * (np.sin(2 * math.pi * 7 * t_axis(8)) > 0))))
    eng = filt(pitch(eng, .8), "lp", 1800)
    save("ambience/engine_loop.wav", loopify(eng[: SR * 7], .5), peak=-4)

    # Костёр: треск без «уютного» верха.
    fire = src_or("fire", 1, 2, 10, lambda: filt(noise(10), "lp", 1200))
    fire = filt(fire, "lp", 5000) + filt(fire, "lp", 200) * .8
    save("ambience/fire_loop.wav", loopify(fire[: SR * 9], .5), peak=-5)


# ---------------------------------------------------------------- отклик и мини-игры
def cc0_shot(key, idx=1, start=0.0, length=1.5, pitch_f=1.0, lp=None, hp=None, rev=None, peak=-3.0):
    x = load_cc0(key, idx, start, length)
    if x is None:
        return None
    # обрезаем тишину в начале
    thr = np.max(np.abs(x)) * .08
    first = int(np.argmax(np.abs(x) > thr))
    x = x[max(0, first - int(.005 * SR)):]
    if pitch_f != 1.0:
        x = pitch(x, pitch_f)
    if lp: x = filt(x, "lp", lp)
    if hp: x = filt(x, "hp", hp)
    if rev: x = reverb(x, *rev)
    return fade(x, .002, .08)


def build_sfx():
    S = "sfx/"
    MAXLEN = {"alarm": 4.5, "chime": 6.0, "groan_1": 3.5, "groan_2": 3.5, "stinger": 4.0, "fail": 3.5,
              "knock_2": 2.6, "creak_2": 3.0, "creak_3": 3.0, "interact_metal": 2.2, "clank": 1.4}
    def put(name, x, fallback=None, peak=-3.0):
        if x is None:
            x = fallback()
        if name in MAXLEN and x.size > MAXLEN[name] * SR:
            x = fade(x[: int(MAXLEN[name] * SR)], 0, MAXLEN[name] * .35)
        if name in ("clank", "interact_metal"):
            x = filt(x, "lp", 3800)
        save(S + name + ".wav", x, peak=peak)

    # действия смотрителя
    put("interact_wood", cc0_shot("creak", 1, 0, 1.2, .85, lp=3500, rev=(.6, .2)), lambda: reverb(creak_synth(.9) + thud(70, .9) * .6, .6, .2))
    put("interact_metal", reverb(metal_hit(92, 1.8, .7) + thud(45, 1.8) * .6, 1.4, .3, 2500))
    put("interact_cook", cc0_shot("sizzle", 1, 1, 1.4, .9, lp=6000), lambda: filt(noise(1.2), "hp", 2500) * env(1.2, .05, .5))
    put("interact_fish", cc0_shot("splash", 1, 0, 1.0, .8, lp=4000), lambda: filt(noise(.6), "lp", 1500) * env(.6, .005, .1))
    put("interact_paper", cc0_shot("page", 1, 0, 1.0, .9, lp=6000), lambda: filt(noise(.5), "bp", (1500, 6000)) * env(.5, .02, .1))
    put("interact", reverb(thud(70, .7, .1, .5), .5, .2))

    # сигналы: цель, тревога, тень рассеяна, рация
    put("chime", cc0_shot("bell", 1, 0, 4.5, .75, lp=2600, rev=(3.0, .4)),
        lambda: reverb(bell(98, 5, .3) + thud(40, 5, .5, 0) * .4, 3.0, .45, 2500))
    horn = load_cc0("foghorn", 1, 0, 4)
    put("alarm", None if horn is None else reverb(filt(pitch(horn, .9), "lp", 2200), 3.0, .5),
        lambda: reverb((sine(73, 3) + .6 * sine(77.8, 3) + .3 * sine(146, 3)) * env(3, .3, 1.2), 3, .5))
    dsec = 1.3
    hiss = filt(noise(dsec), "hp", 1800) * env(dsec, .02, .25)
    swell = filt(noise(dsec), "bp", (120, 600)) * (t_axis(dsec) / dsec) ** 3 * np.exp(-np.maximum(t_axis(dsec) - dsec * .8, 0) * 30)
    moan = sine(1, dsec) * 0
    sweep = np.sin(2 * math.pi * np.cumsum(np.linspace(180, 55, int(dsec * SR))) / SR) * env(dsec, .01, .4) * .5
    put("dispel", reverb(filt(hiss, "lp", 4000) * .3 + swell[::-1] * .9 + sweep + moan, 1.2, .4))
    put("radio_signal", reverb(filt(noise(.9), "bp", (500, 3200)) * (.3 + .7 * (np.sin(2 * math.pi * 11 * t_axis(.9)) > 0)) * env(.9, .01, .5) + sine(1050, .9) * env(.9, .01, .2) * .08, .5, .2))

    # мини-игры
    put("tick", reverb(filt(noise(.08), "bp", (900, 2500)) * env(.08, .0005, .008) + thud(140, .08, .02, 0) * .5, .3, .2), peak=-6)
    put("clank", reverb(metal_hit(240, 1.0, .25), .8, .3, 3000))
    for i in (1, 2):
        put(f"zap_{i}", cc0_shot("zap", i, 0, 1.0, .9, rev=(.5, .2)),
            lambda: (filt(noise(.5), "hp", 1500) * (rng.random(int(.5 * SR)) > .7) * env(.5, .001, .15) + sine(120, .5) * env(.5, .001, .2) * .5))
    put("static", cc0_shot("static", 1, 1, 1.2, 1.0, lp=5000), lambda: filt(noise(1.0), "bp", (600, 4000)) * env(1.0, .01, .4))
    wh = load_cc0("static", 2, 1, 1.5)
    put("whisper", reverb(filt(noise(1.4), "bp", (1500, 5500)) * (.4 + .6 * np.abs(np.sin(2 * math.pi * 3.3 * t_axis(1.4)))) * np.sin(math.pi * t_axis(1.4) / 1.4) ** 2, 1.5, .5))
    for i in (1, 2):
        put(f"knock_{i}", cc0_shot("knock", i, 0, 1.6, .8, lp=2500, rev=(1.4, .35)),
            lambda: reverb(sum(at(thud(85, .4, .06, .6), k * .32, 1.2) for k in range(3)), 1.4, .35))
    put("knock_far", cc0_shot("knock", 1, 0, 2.0, .7, lp=1200, rev=(2.5, .6)),
        lambda: reverb(filt(sum(at(thud(70, .4, .08, .4), k * .4, 1.6) for k in range(3)), "lp", 900), 2.5, .6))
    for i, (key, idx) in enumerate((("metal_groan", 1), ("pipe", 1)), 1):
        put(f"groan_{i}", cc0_shot(key, idx, 0, 2.2, .6, lp=2500, rev=(1.6, .4)),
            lambda: reverb(creak_synth(1.6, 40) * .8 + drone_cluster(1.6, 70) * env(1.6, .3, .6) * .3, 1.6, .4))
    for i in (1, 2):
        put(f"cough_{i}", cc0_shot("sputter", i, 0, 1.4, .85, lp=3000, rev=(.6, .2)),
            lambda: reverb(sum(at(thud(50, .3, .05, .9), k * .14, .9) for k in range(4)), .6, .2))
    put("thump", reverb(thud(48, .8, .14, .4) + compress(sine(30, .8) * env(.8, .01, .2)) * .5, .5, .15))
    for i in (1, 2):
        put(f"hammer_{i}", cc0_shot("hammer", i, 0, .8, .85, lp=4000, rev=(.5, .2)),
            lambda: reverb(thud(160, .5, .05, .9) + metal_hit(900, .5, .05) * .2, .5, .2))
    for i in (1, 2):
        put(f"pick_{i}", cc0_shot("pick", i, 0, 1.0, .85, rev=(1.8, .35)),
            lambda: reverb(metal_hit(700, .8, .15) * .5 + filt(noise(.8), "bp", (1500, 6000)) * env(.8, .001, .05), 1.8, .35))
    for i in (1, 2):
        put(f"splash_{i}", cc0_shot("splash", i, 0, 1.2, .75, lp=3000, rev=(.8, .3)),
            lambda: filt(noise(.9), "lp", 1800) * env(.9, .01, .2))
    for i in (1, 2, 3):
        put(f"creak_{i}", cc0_shot("creak", i, 0, 2.0, .75, lp=3000, rev=(1.2, .35)),
            lambda: reverb(creak_synth(1.5, 70 + i * 15), 1.2, .35))
    # провал: низкий диссонансный удар
    fsec = 2.2
    fail = (sine(41, fsec) + sine(43.6, fsec) * .8 + sine(58, fsec) * .5) * env(fsec, .005, .6) + thud(35, fsec, .3, .8)
    put("fail", reverb(compress(fail, .5), 2.0, .45, 1800))
    # стингер: скрежет + диссонансный кластер струнных
    ssec = 2.6
    t = t_axis(ssec)
    cluster = sum(np.sign(np.sin(2 * math.pi * f * t + rng.uniform(0, 6))) * .15 for f in (233, 247, 262, 349, 370))
    cluster = filt(cluster, "lp", 3500) * env(ssec, .01, .7)
    scrape = cc0_shot("metal_groan", 2, 0, 2.6, 1.0, hp=300)
    hit = thud(38, ssec, .35, 1.0)
    put("stinger", reverb(cluster + hit + (scrape[: cluster.size] * .5 if scrape is not None and scrape.size >= cluster.size else 0), 2.4, .45))


# ---------------------------------------------------------------- шаги: глуше и тяжелее
def build_steps():
    """Берём исходные шаги из synth_sfx.py и делаем их глуше, ниже и «в пространстве»."""
    import sys
    sys.path.insert(0, HERE)
    import synth_sfx
    makers = {"grass": synth_sfx.step_grass, "wood": synth_sfx.step_wood, "stone": synth_sfx.step_stone, "sand": synth_sfx.step_sand}
    for surface in ("grass", "wood", "stone", "sand"):
        for v in range(1, 6):
            x = np.asarray(makers[surface](v), dtype=np.float64)
            x = pitch(x, .88)
            x = filt(x, "lp", {"grass": 2600, "wood": 2200, "stone": 3200, "sand": 2400}[surface])
            low = filt(x, "lp", 220) * (1.2 if surface == "wood" else .7)
            room = {"wood": (.45, .22, 2000), "stone": (.6, .25, 2600), "grass": (.25, .08, 2000), "sand": (.25, .06, 2000)}[surface]
            y = reverb(x + low, *room)
            save(f"steps/{surface}_{v}.wav", fade(y, .001, .06), peak=-5)


# ---------------------------------------------------------------- музыка меню
def build_menu_theme():
    sec = 40
    t = t_axis(sec)
    d = drone_cluster(sec, 41.2) * .7
    sea = load_cc0("sea", 2, 1, sec)
    if sea is not None and sea.size >= t.size:
        d = d + filt(pitch(sea, .8)[: t.size], "lp", 1500) * .5
    # редкие удары колокола на тритон
    for k, f in enumerate((98, 69.3, 98, 65.4)):
        d = d + at(bell(f, 7, .2) * .35, 3 + k * 9.5, sec)
    pad_ = sum(sine(f, sec) * (.5 + .5 * np.sin(2 * math.pi * .03 * t + k)) for k, f in enumerate((164.8, 174.6, 233.1))) * .05
    x = reverb(d + pad_, 4.0, .5, 2200)[: t.size]
    save("music/menu_tide.wav", loopify(x, 3.0), peak=-4)


def main():
    build_ambience()
    build_sfx()
    build_steps()
    build_menu_theme()
    print("ok")


if __name__ == "__main__":
    main()
