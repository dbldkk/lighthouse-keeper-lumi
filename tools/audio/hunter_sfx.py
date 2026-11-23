#!/usr/bin/env python3
"""Звуки охотника, привязанные к его анимациям (чистый синтез, numpy/scipy, seed фиксирован):
  hunter_step_1..4   — тяжёлый мокрый шаг с щелчком когтей (stalk / lurch);
  hunter_breath_1..3 — влажное, булькающее дыхание с низким хрипом (idle / door_wait);
  hunter_sniff_1..2  — частое принюхивание (search);
  hunter_crack_1..4  — хруст суставов и костей (рывки головы в search, бросок grab, lurch);
  hunter_grab_1..2   — сиплый рёв-визг броска (grab).
Запуск из корня проекта:  python3 tools/audio/hunter_sfx.py  → assets/audio/sfx/hunter_*.wav
"""
import os, wave
import numpy as np
from scipy import signal

SR = 44100
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio", "sfx")
rng = np.random.default_rng(4040)

def t_axis(sec):
    return np.arange(int(sec * SR)) / SR

def band(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, hi], btype="bandpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)

def low(x, hz, order=2):
    return signal.sosfilt(signal.butter(order, hz, btype="lowpass", fs=SR, output="sos"), x)

def high(x, hz, order=2):
    return signal.sosfilt(signal.butter(order, hz, btype="highpass", fs=SR, output="sos"), x)

def reson(x, f, q):
    b, a = signal.iirpeak(f, q, fs=SR)
    return signal.lfilter(b, a, x)

def env(n, attack, decay):
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / max(attack, 1e-4)) * np.exp(-np.maximum(0, t - attack) / decay)
    return e

def place(buf, snd, at):
    i = int(at * SR)
    j = min(len(buf), i + len(snd))
    buf[i:j] += snd[: j - i]

def reverb(x, sec=.45, mix=.18):
    n = int(sec * SR)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / (SR * sec / 5))
    ir = low(ir, 3500)
    wet = signal.fftconvolve(x, ir)[: len(x)]
    wet /= (np.max(np.abs(wet)) + 1e-9)
    return x * (1 - mix) + wet * mix * np.max(np.abs(x))

def write(name, x, peak_db=-3.0):
    x = x - np.mean(x)
    fade = int(.01 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)
    x = x / (np.max(np.abs(x)) + 1e-9) * 10 ** (peak_db / 20)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    print("wrote", path, round(len(x) / SR, 2), "s")

def step(i):
    dur = .5
    buf = np.zeros(int(dur * SR))
    t = t_axis(.22)
    f = 72 - 30 * t / .22 + rng.uniform(-6, 6)
    thud = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / .07)
    place(buf, thud * 1.6, 0)
    n = int(.12 * SR)
    slap = band(rng.standard_normal(n), 380, 2400) * env(n, .002, .035)
    place(buf, slap * .7, .004)
    # мокрое чавканье: резонанс уходит вниз, пузырьки
    n = int(.2 * SR)
    sq = rng.standard_normal(n)
    sweep = np.linspace(1100, 260, n)
    out = np.zeros(n)
    for k in range(0, n, 256):
        out[k:k + 256] = reson(sq[k:k + 256 + 512], sweep[k], 6)[:len(out[k:k + 256])]
    bubbles = (rng.random(n) < 30 / SR).astype(float)
    bubbles = low(np.convolve(bubbles, np.hanning(int(.012 * SR)), "same"), 600)
    place(buf, out * env(n, .01, .07) * (.5 + 3 * bubbles) * .5, .03 + rng.uniform(0, .02))
    # когти по доскам / камню
    for c in range(2 + i % 2):
        m = int(.015 * SR)
        click = band(rng.standard_normal(m), 2800, 6500) * env(m, .0005, .003)
        place(buf, click * .55, .02 + c * rng.uniform(.018, .03))
    return low(reverb(buf, .3, .12), 2600)

def breath(i):
    dur = 2.7
    buf = np.zeros(int(dur * SR))
    def airflow(sec, lo, hi, gurgle):
        n = int(sec * SR)
        x = band(rng.standard_normal(n), lo, hi)
        e = np.sin(np.linspace(0, np.pi, n)) ** 1.4
        bub = (rng.random(n) < gurgle / SR).astype(float)
        bub = np.convolve(bub, np.hanning(int(.02 * SR)), "same")
        gurg = reson(rng.standard_normal(n), 240 + 60 * i, 8) * bub * 2.5
        return x * e + gurg * e
    inhale = airflow(.95, 500, 2600, 14)
    exhale = airflow(1.4, 250, 1300, 26)
    place(buf, inhale * .8, .05)
    place(buf, exhale, 1.15)
    # низкий хрип на выдохе
    t = t_axis(1.4)
    f0 = 52 + 6 * np.sin(2 * np.pi * 3.1 * t) + rng.uniform(-4, 4)
    ph = np.cumsum(f0) / SR
    growl = signal.sawtooth(2 * np.pi * ph) * (1 + .5 * rng.standard_normal(len(t)) * .3)
    growl = low(growl, 420) * np.sin(np.linspace(0, np.pi, len(t))) ** 2
    place(buf, growl * .35, 1.15)
    return reverb(buf, .5, .2)

def sniff(i):
    dur = 1.1
    buf = np.zeros(int(dur * SR))
    at = .03
    for k in range(4 + i):
        n = int(rng.uniform(.06, .1) * SR)
        x = band(rng.standard_normal(n), 900, 4800) * env(n, .015, .03)
        place(buf, x * rng.uniform(.6, 1.0), at)
        at += rng.uniform(.11, .17)
    n = int(.35 * SR)
    wet = reson(rng.standard_normal(n), 300, 10) * env(n, .02, .08)
    place(buf, wet * .3, at)
    return reverb(buf, .35, .15)

def crack(i):
    dur = .5
    buf = np.zeros(int(dur * SR))
    at = .01
    for k in range(rng.integers(5, 10)):
        m = int(.03 * SR)
        imp = np.zeros(m); imp[0] = 1.0
        x = sum(reson(imp, f * rng.uniform(.9, 1.1), 30) for f in (2200, 3700, 5100))
        x = x * env(m, .0002, rng.uniform(.004, .012))
        place(buf, x * rng.uniform(.4, 1.0), at)
        at += rng.uniform(.004, .018)
    n = int(.12 * SR)
    t = t_axis(.12)
    pop = np.sin(2 * np.pi * (180 + 40 * i) * t) * np.exp(-t / .025)
    place(buf, pop * .6, .012)
    crunch = band(rng.standard_normal(n), 1200, 5000) * env(n, .001, .02)
    place(buf, crunch * .35, .015)
    return reverb(buf, .25, .1)

def grab(i):
    dur = 1.6
    buf = np.zeros(int(dur * SR))
    t = t_axis(1.3)
    f0 = (118 - 45 * t / 1.3) * (1 + .03 * np.sin(2 * np.pi * 6.5 * t)) * (1.0 + .08 * i)
    src = signal.sawtooth(2 * np.pi * np.cumsum(f0) / SR) + .35 * rng.standard_normal(len(t))
    vowel = sum(reson(src, f, q) * g for f, q, g in ((720, 6, 1.0), (1150, 7, .7), (2600, 8, .4)))
    roar = np.tanh(vowel * 3) * np.minimum(1, t / .05) * np.exp(-np.maximum(0, t - .5) / .35)
    place(buf, roar, .05)
    # визг поверх — тонкий, с вибрато
    f1 = (760 + 140 * np.sin(2 * np.pi * .8 * t)) * (1 + .02 * np.sin(2 * np.pi * 11 * t))
    shriek = np.sin(2 * np.pi * np.cumsum(f1) / SR) + .3 * band(rng.standard_normal(len(t)), 1500, 4000)
    shriek *= np.minimum(1, t / .12) * np.exp(-t / .45) * .35
    place(buf, shriek, .08)
    place(buf, crack(i) * .8, 0)
    return low(reverb(buf, .6, .22), 3800)

os.makedirs(OUT, exist_ok=True)
for i in range(4):
    write("hunter_step_%d" % (i + 1), step(i), -4)
for i in range(3):
    write("hunter_breath_%d" % (i + 1), breath(i), -5)
for i in range(2):
    write("hunter_sniff_%d" % (i + 1), sniff(i), -6)
for i in range(4):
    write("hunter_crack_%d" % (i + 1), crack(i), -3)
for i in range(2):
    write("hunter_grab_%d" % (i + 1), grab(i), -2)
