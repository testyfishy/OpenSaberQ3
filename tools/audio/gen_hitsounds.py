#!/usr/bin/env python3
"""Generate the hit-feedback one-shots for OpenSaberQ3.

Original assets, synthesised from scratch here, so there is no licence attached
beyond this repository's own (see ATTRIBUTION.md). Regenerating with the same
seed produces byte-identical files.

Design brief: specs/002-hit-audio-research/research.md
  * 48 kHz, 16-bit, mono PCM WAV -- a 60-120 ms transient does not need a codec.
  * 3 "soft" variants, pre-darkened (high-pass 120 Hz + low-pass ~4 kHz). The
    soft layer *is* the low-pass: an AudioStreamPolyphonic voice has no per-voice
    DSP, so filtering has to be baked into the sample.
  * 3 "hard" variants, brighter, longer body.
  * 1 "accent" master layer, brighter and longer still -- it is mixed *under* a
    hard hit, never played alone.
  * 2 "dull" variants for wrong-saber cuts and bombs: heavily low-passed.
  * Every file is peak-normalised to the same ceiling, because the gain mapping
    (and its 9 dB budget) assumes the layers are level-matched per layer.

Usage:  python tools/audio/gen_hitsounds.py [out_dir]
"""
from __future__ import annotations

import math
import os
import random
import struct
import sys
import wave

RATE = 48000
PEAK = 0.70  # -3.1 dBFS; leaves the accent + hard sum room under the limiter


def one_pole_lowpass(samples: list[float], cutoff_hz: float) -> list[float]:
    a = 1.0 - math.exp(-2.0 * math.pi * cutoff_hz / RATE)
    y = 0.0
    out = []
    for x in samples:
        y += a * (x - y)
        out.append(y)
    return out


def one_pole_highpass(samples: list[float], cutoff_hz: float) -> list[float]:
    low = one_pole_lowpass(samples, cutoff_hz)
    return [x - l for x, l in zip(samples, low)]


def envelope(n: int, attack_s: float, decay_s: float) -> list[float]:
    """Exponential decay with a short attack ramp, so nothing clicks."""
    a = max(1, int(attack_s * RATE))
    out = []
    for i in range(n):
        t = i / RATE
        amp = math.exp(-t / decay_s)
        if i < a:
            amp *= i / a
        out.append(amp)
    return out


def noise(n: int, rng: random.Random) -> list[float]:
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def tone(n: int, freq_hz: float, rng: random.Random, detune: float = 0.0) -> list[float]:
    phase = rng.uniform(0.0, 2.0 * math.pi)
    f = freq_hz * (1.0 + detune)
    step = 2.0 * math.pi * f / RATE
    return [math.sin(phase + step * i) for i in range(n)]


def mix(n: int, parts: list[tuple[list[float], float]]) -> list[float]:
    out = [0.0] * n
    for sig, gain in parts:
        for i in range(n):
            out[i] += sig[i] * gain
    return out


def normalise(samples: list[float]) -> list[float]:
    peak = max(abs(s) for s in samples) or 1.0
    scaled = [s * PEAK / peak for s in samples]
    # 5 ms cosine fade-out: the tail is already near zero, this kills the edge.
    fade = min(len(scaled), int(0.005 * RATE))
    for i in range(fade):
        scaled[len(scaled) - fade + i] *= 0.5 * (1.0 + math.cos(math.pi * i / fade))
    return scaled


def make_soft(rng: random.Random, dur_s: float, cut_hz: float, body_hz: float) -> list[float]:
    n = int(dur_s * RATE)
    env_fast = envelope(n, 0.0007, 0.010)
    env_body = envelope(n, 0.0012, 0.022)
    nz = one_pole_highpass(one_pole_lowpass(noise(n, rng), cut_hz), 120.0)
    body = one_pole_lowpass(tone(n, body_hz, rng), 2500.0)
    return normalise(mix(n, [
        ([nz[i] * env_fast[i] for i in range(n)], 1.0),
        ([body[i] * env_body[i] for i in range(n)], 0.55),
    ]))


def make_hard(rng: random.Random, dur_s: float, cut_hz: float) -> list[float]:
    n = int(dur_s * RATE)
    env_click = envelope(n, 0.0005, 0.006)
    env_body = envelope(n, 0.0008, 0.028)
    env_ring = envelope(n, 0.0015, 0.040)
    nz = one_pole_highpass(one_pole_lowpass(noise(n, rng), cut_hz), 140.0)
    ring_a = tone(n, 620.0, rng, detune=rng.uniform(-0.02, 0.02))
    ring_b = tone(n, 1330.0, rng, detune=rng.uniform(-0.02, 0.02))
    return normalise(mix(n, [
        ([nz[i] * env_click[i] for i in range(n)], 1.0),
        ([ring_a[i] * env_body[i] for i in range(n)], 0.6),
        ([ring_b[i] * env_ring[i] for i in range(n)], 0.35),
    ]))


def make_accent(rng: random.Random) -> list[float]:
    n = int(0.110 * RATE)
    env_click = envelope(n, 0.0005, 0.010)
    env_ring = envelope(n, 0.0020, 0.055)
    nz = one_pole_highpass(one_pole_lowpass(noise(n, rng), 15000.0), 900.0)
    ring_a = tone(n, 2600.0, rng, detune=rng.uniform(-0.03, 0.03))
    ring_b = tone(n, 3900.0, rng, detune=rng.uniform(-0.03, 0.03))
    return normalise(mix(n, [
        ([nz[i] * env_click[i] for i in range(n)], 1.0),
        ([ring_a[i] * env_ring[i] for i in range(n)], 0.45),
        ([ring_b[i] * env_ring[i] for i in range(n)], 0.25),
    ]))


def make_dull(rng: random.Random, body_hz: float) -> list[float]:
    n = int(0.095 * RATE)
    env = envelope(n, 0.0020, 0.030)
    nz = one_pole_highpass(one_pole_lowpass(noise(n, rng), 1100.0), 90.0)
    body = one_pole_lowpass(tone(n, body_hz, rng), 900.0)
    return normalise(mix(n, [
        ([nz[i] * env[i] for i in range(n)], 0.8),
        ([body[i] * env[i] for i in range(n)], 1.0),
    ]))


def write_wav(path: str, samples: list[float]) -> None:
    frames = b"".join(
        struct.pack("<h", max(-32768, min(32767, int(round(s * 32767)))))
        for s in samples
    )
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)


def main() -> int:
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "..", "game", "data", "hits")
    os.makedirs(out, exist_ok=True)

    specs = [
        # name, seed, generator
        ("soft_01", 0x5EED01, lambda r: make_soft(r, 0.070, 4000.0, 190.0)),
        ("soft_02", 0x5EED02, lambda r: make_soft(r, 0.065, 4300.0, 165.0)),
        ("soft_03", 0x5EED03, lambda r: make_soft(r, 0.075, 3800.0, 210.0)),
        ("hard_01", 0x4A4D01, lambda r: make_hard(r, 0.080, 14000.0)),
        ("hard_02", 0x4A4D02, lambda r: make_hard(r, 0.085, 12000.0)),
        ("hard_03", 0x4A4D03, lambda r: make_hard(r, 0.075, 16000.0)),
        ("accent_01", 0xA7CE01, make_accent),
        ("dull_01", 0xD01101, lambda r: make_dull(r, 140.0)),
        ("dull_02", 0xD01102, lambda r: make_dull(r, 120.0)),
    ]
    for name, seed, fn in specs:
        rng = random.Random(seed)
        samples = fn(rng)
        path = os.path.join(out, name + ".wav")
        write_wav(path, samples)
        ms = 1000.0 * len(samples) / RATE
        print(f"{path}  {ms:6.1f} ms  peak {max(abs(s) for s in samples):.2f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
