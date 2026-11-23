#!/usr/bin/env python3
"""Образцы голосов для Chatterbox: ~10 с чистой речи чтецов LibriVox (общественное достояние).

    python3 make_refs.py   # скачивает главы с archive.org и режет ref/*.wav
"""
import os, re, subprocess
HERE = os.path.dirname(os.path.abspath(__file__))
SOURCES = {
    # роль: (файл, страница archive.org, глава mp3)
    "belkin": ("dispatch — Берег-четыре", "belkintales_1406_librivox", "belkintales_01_pushkin_64kb.mp3"),
    "avant": ("ghost — голос в эфире", "avanturisty_2201_librivox", "avanturisty_01_avetlugin_64kb.mp3"),
    "obryv": ("captain — капитан на картине", "obryv_1906_librivox", "obryv_001_goncharov_64kb.mp3"),
    "underground": ("record — записи прежней смены", "notes_underground_russian", "01-dostoevsky-zapiski-iz-podpolya-I-01-02_64kb.mp3"),
}


def main():
    os.makedirs(os.path.join(HERE, "ref"), exist_ok=True)
    for name, (_role, item, chapter) in SOURCES.items():
        mp3 = os.path.join(HERE, "ref", name + ".mp3")
        if not os.path.exists(mp3):
            subprocess.run(["curl", "-sL", "-o", mp3, f"https://archive.org/download/{item}/{chapter}"], check=True)
        log = subprocess.run(["ffmpeg", "-ss", "100", "-t", "60", "-i", mp3, "-af", "silencedetect=n=-35dB:d=0.25", "-f", "null", "-"],
                             capture_output=True, text=True).stderr
        ends = [float(x) for x in re.findall(r"silence_end: ([\d.]+)", log)]
        starts = [float(x) for x in re.findall(r"silence_start: ([\d.]+)", log)]
        seg = next(((a, b) for a in ends for b in starts if 9 <= b - a <= 13), None)
        if seg is None:
            print("нет подходящего отрезка", name)
            continue
        a, b = seg
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(100 + a - 0.05), "-t", str(b - a + 0.1), "-i", mp3, "-ac", "1", "-ar", "24000",
                        "-af", "highpass=f=70,loudnorm=I=-20:TP=-2", os.path.join(HERE, "ref", name + ".wav")], check=True)
        print(name, seg)


if __name__ == "__main__":
    main()
