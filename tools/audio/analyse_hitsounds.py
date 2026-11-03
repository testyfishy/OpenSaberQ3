#!/usr/bin/env python3
"""Measure the generated hit one-shots.

Reports the numbers that decided the v0.3 audio rewrite: level, crest factor and
where the energy actually sits. Run it after gen_hitsounds.py and compare against
the table in specs/002-hit-audio-research/research.md.

Usage:  python tools/audio/analyse_hitsounds.py [hits_dir]
"""
from __future__ import annotations

import cmath
import math
import os
import sys
import wave


def read_wav(path: str) -> tuple[list[float], int]:
    with wave.open(path, "rb") as w:
        rate = w.getframerate()
        frames = w.readframes(w.getnframes())
    out = []
    for i in range(0, len(frames), 2):
        v = int.from_bytes(frames[i:i + 2], "little", signed=True)
        out.append(v / 32768.0)
    return out, rate


def fft_mag(samples: list[float], rate: int) -> list[tuple[float, float]]:
    """Naive DFT on a 4096-sample window. Small files, run offline, clarity over speed."""
    n = 4096
    window = samples[:n] + [0.0] * max(0, n - len(samples))
    window = [w * (0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1))) for i, w in enumerate(window)]
    out = []
    for k in range(1, n // 2):
        acc = 0j
        for i in range(0, n, 2):  # stride 2: fine for band percentages
            acc += window[i] * cmath.exp(-2j * math.pi * k * i / n)
        out.append((k * rate / n, abs(acc)))
    return out


def analyse(path: str) -> dict:
    samples, rate = read_wav(path)
    peak = max(abs(s) for s in samples) or 1e-9
    rms = math.sqrt(sum(s * s for s in samples) / len(samples)) or 1e-9
    crest_db = 20 * math.log10(peak / rms)
    peak_db = 20 * math.log10(peak)
    rms_db = 20 * math.log10(rms)

    spec = fft_mag(samples, rate)
    bands = [(20, 80), (80, 300), (300, 1000), (1000, 4000), (4000, 12000)]
    energy = [0.0] * len(bands)
    total = 0.0
    for freq, mag in spec:
        e = mag * mag
        total += e
        for i, (lo, hi) in enumerate(bands):
            if lo <= freq < hi:
                energy[i] += e
                break
    pct = [100.0 * e / total if total else 0.0 for e in energy]
    return {
        "ms": 1000.0 * len(samples) / rate,
        "peak": peak_db,
        "rms": rms_db,
        "crest": crest_db,
        "bands": pct,
    }


def main() -> int:
    d = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "..", "game", "data", "hits")
    print(f"{'file':<12}{'ms':>6}{'peak':>7}{'rms':>7}{'crest':>7}"
          f"{'20-80':>8}{'80-300':>8}{'0.3-1k':>8}{'1-4k':>8}{'4-12k':>8}")
    for name in sorted(os.listdir(d)):
        if not name.endswith(".wav"):
            continue
        a = analyse(os.path.join(d, name))
        b = a["bands"]
        print(f"{name:<12}{a['ms']:>6.0f}{a['peak']:>7.1f}{a['rms']:>7.1f}{a['crest']:>7.1f}"
              f"{b[0]:>7.1f}%{b[1]:>7.1f}%{b[2]:>7.1f}%{b[3]:>7.1f}%{b[4]:>7.1f}%")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
