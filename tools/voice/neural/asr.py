import sys, soundfile as sf, numpy as np
from scipy.signal import resample_poly
from faster_whisper import WhisperModel
m = WhisperModel("medium", device="cpu", compute_type="int8", cpu_threads=8)
def load(f):
    x, sr = sf.read(f, dtype="float32")
    if x.ndim > 1: x = x.mean(1)
    from math import gcd
    g = gcd(sr, 16000)
    return resample_poly(x, 16000//g, sr//g).astype("float32")
def transcribe(f):
    segs,_ = m.transcribe(load(f), language="ru", beam_size=3)
    return " ".join(s.text for s in segs).strip()
if __name__ == "__main__":
    for f in sys.argv[1:]:
        print(f, "|", transcribe(f))
