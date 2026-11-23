import re, os
DICT = os.path.expanduser("~/.cache/vosk/vosk-model-tts-ru-0.9-multi/dictionary")
VOW = "аеёиоуыэюя"
_best = None
def load(words):
    global _best
    words = set(words); best = {}
    with open(DICT, encoding="utf-8") as f:
        for line in f:
            w, _, rest = line.partition(" ")
            if w not in words: continue
            p, _, ph = rest.partition(" ")
            p = float(p)
            if w not in best or p > best[w][0]:
                best[w] = (p, ph.split())
    _best = best
def mark(word):
    lw = word.lower()
    if "ё" in lw or sum(c in VOW for c in lw) < 2 or lw not in _best: return word
    ph = _best[lw][1]
    vows = [p for p in ph if p[-1] in "01" ]
    idx = next((i for i, p in enumerate(vows) if p.endswith("1")), None)
    if idx is None: return word
    pos = [i for i, c in enumerate(lw) if c in VOW]
    if idx >= len(pos): return word
    i = pos[idx]
    return word[:i+1] + "\u0301" + word[i+1:]
def stress_text(t):
    return re.sub(r"[А-Яа-яЁё]+", lambda m: mark(m.group(0)), t)
def words(t):
    return [w.lower() for w in re.findall(r"[А-Яа-яЁё]+", t)]
