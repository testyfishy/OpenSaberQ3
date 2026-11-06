"""Derive the 'thump' hit set from the shipped hits: more low end, less 2-6 kHz.

Post-processes game/data/hits/*.wav into game/data/hits_thump/ with the same names, so the
runtime can swap whole pools without changing sample counts or layer logic.
"""
import math, os, struct, wave
from pathlib import Path

SRC = Path("game/data/hits")
DST = Path("game/data/hits_thump")
DST.mkdir(parents=True, exist_ok=True)
RATE = 48000

def read_wav(p):
    with wave.open(str(p), "rb") as w:
        n = w.getnframes()
        data = w.readframes(n)
        ch = w.getnchannels()
        width = w.getsampwidth()
    assert ch == 1 and width == 2, (p, ch, width)
    return [struct.unpack("<h", data[i:i+2])[0] / 32768.0 for i in range(0, len(data), 2)]

def write_wav(p, s):
    with wave.open(str(p), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", max(-32768, min(32767, int(v * 32767)))) for v in s))

def lowpass(x, hz):
    a = 1.0 - math.exp(-2.0 * math.pi * hz / RATE)
    y = 0.0; out = []
    for v in x:
        y += a * (v - y); out.append(y)
    return out

def highpass(x, hz):
    lp = lowpass(x, hz)
    return [a - b for a, b in zip(x, lp)]

for src in sorted(SRC.glob("*.wav")):
    x = read_wav(src)
    sub = lowpass(x, 140.0)
    air = highpass(x, 2500.0)
    y = [v + 1.5 * s - 0.55 * a for v, s, a in zip(x, sub, air)]
    # soft clip, then normalise to -1.4 dBFS like the shipped set
    y = [math.tanh(v * 1.4) for v in y]
    peak = max(abs(v) for v in y) or 1.0
    y = [v / peak * 0.90 for v in y]
    write_wav(DST / src.name, y)
    print("thump:", src.name)
