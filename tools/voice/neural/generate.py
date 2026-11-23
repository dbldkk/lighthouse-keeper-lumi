#!/usr/bin/env python3
"""Нейроозвучка «Смотрителя маяка»: Chatterbox Multilingual (Resemble AI, MIT) на CPU.

    python3 generate.py ../lines.json RAW_DIR [id ...]
    python3 generate.py ../extra_lines.json RAW_DIR

* Голоса задаются короткими образцами чтецов LibriVox (общественное достояние), см. VOICES и
  AUDIO_SOURCES.md. Образцы режутся скриптом make_refs.py.
* Ударения: stress.py ставит знак ударения по словарю модели Vosk-TTS ru 0.9 (Apache 2.0).
* Каждая фраза генерируется до ATTEMPTS раз; лучший дубль выбирается по разборчивости
  (распознавание faster-whisper medium) и темпу — так отсекаются обрывы и «зажёванные» хвосты.
Дальше: process_voice.py RAW_DIR — хоррор-обработка и OGG для игры.
"""
import json, re, sys, os, time, difflib
import torch, torchaudio as ta, numpy as np
import stress
from chatterbox.mtl_tts import ChatterboxMultilingualTTS
from asr import transcribe  # проверка разборчивости (faster-whisper)
torch.set_num_threads(8)
torch.manual_seed(7)
REF = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ref")
VOICES = {"dispatch": (os.path.join(REF, "belkin.wav"), .55), "ghost": (os.path.join(REF, "avant.wav"), .7), "captain": (os.path.join(REF, "obryv.wav"), .8), "record": (os.path.join(REF, "underground.wav"), .45)}
lines = json.load(open(sys.argv[1], encoding="utf-8"))
out = sys.argv[2]; os.makedirs(out, exist_ok=True)
only = sys.argv[3:]
ATTEMPTS = int(os.environ.get('ATTEMPTS', '3'))
def speakable(t):
    for a in "«»“”": t = t.replace(a, "")
    t = t.replace("…", "... ").replace(" — ", ", ").replace("—", ", ")
    return re.sub(r"\s+", " ", t).strip(" ,")
def norm(t): return re.sub(r"[^а-яё0-9 ]", "", t.lower().replace("ё","е").replace("-", " ")).split()
NUM = {"четыре":"4","три":"3","двадцать два десять":"22 10"}
from num2words import num2words
def words_for_digits(t):
    return re.sub(r"\d+", lambda m: " " + num2words(int(m.group(0)), lang="ru") + " ", t)
def cer(ref, hyp):
    hyp = words_for_digits(hyp)
    r = " ".join(norm(ref)); h = " ".join(norm(hyp))
    return 1 - difflib.SequenceMatcher(None, r, h).ratio()
allw = []
for v in lines.values(): allw += stress.words(v.get("say") or v["text"])
stress.load(allw)
m = ChatterboxMultilingualTTS.from_pretrained(device="cpu")
report = {}
for lid, line in lines.items():
    if only and lid not in only: continue
    style = line.get("style", "dispatch")
    ref, exa = VOICES[style]
    text = speakable(line.get("say") or line["text"])
    sents = [s.strip() for s in re.split(r"(?<=[.!?])\s+", text) if s.strip()]
    # короткие предложения объединяем, чтобы интонация не рвалась
    chunks = []
    for s in sents:
        if chunks and len(chunks[-1]) + len(s) < 110: chunks[-1] += " " + s
        else: chunks.append(s)
    pieces = []; worst = 0
    for ch in chunks:
        best = None
        for attempt in range(ATTEMPTS):
            wav = m.generate(stress.stress_text(ch), language_id="ru", audio_prompt_path=ref, exaggeration=exa, cfg_weight=.4, temperature=.75)
            tmp = f"{out}/_tmp.wav"; ta.save(tmp, wav, m.sr)
            hyp = transcribe(tmp)
            # цифры в распознавании — словами в тексте; сравниваем мягко
            e = cer(ch, hyp)
            dur = wav.shape[-1] / m.sr
            cps = len(ch) / max(dur, .1)
            rw, hw = norm(ch), norm(hyp)
            hw = norm(words_for_digits(hyp))
            tail_ok = bool(hw) and difflib.SequenceMatcher(None, rw[-1], hw[-1]).ratio() > .6
            head_ok = bool(hw) and difflib.SequenceMatcher(None, rw[0], hw[0]).ratio() > .6
            slow = cps < 7 and len(ch) > 30
            score = e + (0.3 if cps > 22 or slow else 0) + (0 if tail_ok else .25) + (0 if head_ok else .15)
            if best is None or score < best[0]: best = (score, wav, hyp)
            if score < .12: break
        pieces.append(best[1]); worst = max(worst, best[0])
        print(lid, round(best[0], 3), "|", ch, "->", best[2], flush=True)
    gap = torch.zeros(1, int(m.sr * .32))
    full = []
    for i, p in enumerate(pieces):
        if i: full.append(gap)
        full.append(p)
    ta.save(f"{out}/{lid}.wav", torch.cat(full, -1), m.sr)
    report[lid] = worst
    json.dump(report, open(f"{out}/_report.json", "w"), ensure_ascii=False, indent=1)
print("DONE")
