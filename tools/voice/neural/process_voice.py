#!/usr/bin/env python3
"""Хоррор-обработка нейроозвучки: из «сухих» WAV (generate.py) делает OGG для игры.

    python3 tools/voice/neural/process_voice.py RAW_DIR

Стили (поле style в tools/voice/lines.json):
  dispatch — береговая станция: полоса рации, компрессия, тихий эфир, лёгкое «железо» рубки;
  ghost    — чужой голос: ниже, обратная реверберация (нарастающее эхо перед словами),
             дрожание, тяжёлые помехи;
  captain  — портрет капитана: низкий голос в деревянной рубке, без рации;
  record   — старая плёнка: узкая полоса, плавание скорости, шипение.
Нужен ffmpeg с libvorbis.
"""
import json, os, subprocess, sys, tempfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio", "voice")
LINES = os.path.join(ROOT, "tools", "voice", "lines.json")

STYLES = {
    "dispatch": {
        "chain": "highpass=f=280,lowpass=f=3400,acompressor=threshold=0.1:ratio=5:attack=4:release=90,"
                 "asoftclip=type=tanh:param=1.4,aecho=0.8:0.35:18|31:0.25|0.15,volume=1.6",
        "noise": "pink", "amp": 0.012, "noise_band": "highpass=f=500,lowpass=f=4000",
    },
    "ghost": {
        "chain": "asetrate=24000*0.9,aresample=24000,"
                 "areverse,aecho=0.8:0.7:120|260|410:0.5|0.35|0.2,areverse,"
                 "highpass=f=220,lowpass=f=2800,tremolo=f=4.5:d=0.35,aecho=0.8:0.6:90|170:0.35|0.2,volume=1.8",
        "noise": "brown", "amp": 0.045, "noise_band": "highpass=f=300,lowpass=f=3500",
    },
    "captain": {
        "chain": "asetrate=24000*0.92,aresample=24000,highpass=f=80,lowpass=f=5200,"
                 "aecho=0.8:0.45:38|67:0.3|0.18,acompressor=threshold=0.12:ratio=3,volume=1.7",
        "noise": "brown", "amp": 0.004, "noise_band": "lowpass=f=600",
    },
    "record": {
        "chain": "highpass=f=380,lowpass=f=2900,vibrato=f=0.7:d=0.1,acrusher=bits=11:mix=0.35,"
                 "aecho=0.8:0.4:60:0.25,volume=1.6",
        "noise": "white", "amp": 0.016, "noise_band": "highpass=f=1500,lowpass=f=7000",
    },
}


def duration(path):
    out = subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path])
    return float(out.strip())


def process(raw, style_name, target):
    style = STYLES[style_name]
    length = duration(raw) * (1 / 0.9 if style_name == "ghost" else 1 / 0.92 if style_name == "captain" else 1.0) + 1.2
    graph = (
        f"[0:a]aresample=24000,silenceremove=start_periods=1:start_threshold=-50dB,adelay=260|260,apad=pad_dur=0.9,{style['chain']}[v];"
        f"[1:a]{style['noise_band']}[n];"
        f"[v][n]amix=inputs=2:duration=first:normalize=0,"
        f"afade=t=in:d=0.04,afade=t=out:st={max(0.1, length - 0.25):.2f}:d=0.25,"
        f"loudnorm=I=-18:TP=-1.5:LRA=9"
    )
    with tempfile.TemporaryDirectory() as tmp:
        mid = os.path.join(tmp, "v.wav")
        subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", raw,
                        "-f", "lavfi", "-i", f"anoisesrc=d={length + 1:.2f}:c={style['noise']}:a={style['amp']}:r=24000",
                        "-filter_complex", graph, "-t", f"{length:.2f}", "-ac", "1", "-ar", "24000", "-c:a", "pcm_s16le", mid], check=True)
        if target.endswith(".wav"):
            subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", mid, "-c:a", "pcm_s16le", target], check=True)
        else:
            subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", mid, "-c:a", "libvorbis", "-q:a", "4", target], check=True)


def main():
    raw_dir = sys.argv[1]
    lines = json.load(open(LINES, encoding="utf-8"))
    extra = os.path.join(os.path.dirname(LINES), "extra_lines.json")
    if os.path.exists(extra):
        lines.update(json.load(open(extra, encoding="utf-8")))
    for name in ("lore_lines.json", "round7_lines.json"):  # кассеты, «ваш голос», события v1.3
        path = os.path.join(os.path.dirname(LINES), name)
        if os.path.exists(path):
            lines.update(json.load(open(path, encoding="utf-8")))
    for line_id, line in lines.items():
        raw = os.path.join(raw_dir, line_id + ".wav")
        if not os.path.exists(raw):
            continue
        target = line.get("target") or os.path.join(OUT, line_id + ".ogg")
        target = os.path.join(ROOT, target) if not os.path.isabs(target) else target
        process(raw, line.get("style", "dispatch"), target)
        print(f"{line_id}: {duration(target):.1f} c")


if __name__ == "__main__":
    main()
