#!/usr/bin/env python3
"""Generate the hit-feedback one-shots for OpenSaberQ3.

Original assets, synthesised from scratch here, so there is no licence attached
beyond this repository's own (see ATTRIBUTION.md). Regenerating with the same
seed produces byte-identical files.

Design brief: specs/002-hit-audio-research/research.md, revised for v0.3 after
measuring the shipped samples. The measurement that forced the rewrite:

  every shipped file was peak-normalised to -3.1 dBFS with a 14-16.5 dB crest
  factor, and the "hard" layer (the one a normal-speed cut plays) had 0.0 % of
  its energy below 300 Hz. It was all 300 Hz - 4 kHz, which is the cardboard
  band. Combined with the 7-11 dB RMS deficit against the music bus, that is
  the literal signal chain of "tinny and quiet".

So each hit is now ONE layered impact rather than one band per layer:

  sub   55-85 Hz   pitch falls 85 -> 55 Hz over ~40 ms; the "mass" of the hit
  body  120-260 Hz 40-90 ms decay; the size of the object
  crack 1.2-2.8 kHz 8-20 ms; the blade edge meeting the block
  air   5-9 kHz    15-40 ms, quiet; sharpness only

and the crest factor is compressed to ~8-11 dB before the peak ceiling is
applied, because peak-normalising a transient guarantees it loses to mastered
music. Loudness, not headroom, is what makes a hit audible over the track.

Layer roles (unchanged file names, so no runtime change):
  soft   x3  gentle cut: body + soft crack, 70 ms
  hard   x3  normal cut: full stack, 120-180 ms
  accent x1  fast cut: extra sub/body weight, NOT extra treble (the shipped
             accent was 98.6 % in 1-4 kHz, so speed made hits thinner)
  dull   x2  wrong-saber cut / bomb: low-passed, no crack

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
# Peak ceiling after crest compression. 0.85 is -1.4 dBFS: still headroom for the
# accent to sum under the limiter, but far louder in RMS terms than the old -3.1 dBFS
# peak-normalised files, which is the point.
PEAK = 0.90
# Soft-clip drive. Higher flattens the crest further; tanh keeps the peaks rounded
# instead of squaring them off, so it reads as compression rather than distortion.
DRIVE = 1.15


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


def falling_tone(n: int, f_start: float, f_end: float, rng: random.Random) -> list[float]:
    """Glide down over the first 40 ms, then hold. A dropping pitch reads as mass."""
    phase = rng.uniform(0.0, 2.0 * math.pi)
    out = []
    glide = min(n, int(0.040 * RATE))
    for i in range(n):
        t = min(i, glide) / glide if glide else 0.0
        f = f_start + (f_end - f_start) * t
        phase += 2.0 * math.pi * f / RATE
        out.append(math.sin(phase))
    return out


def mix(n: int, parts: list[tuple[list[float], float]]) -> list[float]:
    out = [0.0] * n
    for sig, gain in parts:
        for i in range(n):
            out[i] += sig[i] * gain
    return out


def finish(samples: list[float]) -> list[float]:
    """Soft-clip to compress the crest, then normalise to the peak ceiling.

    Peak normalisation alone is what made the shipped hits quiet: a 16 dB crest
    under a -3.1 dBFS ceiling leaves ~-19 dBFS RMS, which a mastered track buries.
    """
    shaped = [math.tanh(s * DRIVE) / math.tanh(DRIVE) for s in samples]
    peak = max(abs(s) for s in shaped) or 1.0
    scaled = [s * PEAK / peak for s in shaped]
    # 5 ms cosine fade-out: the tail is already near zero, this kills the edge.
    fade = min(len(scaled), int(0.005 * RATE))
    for i in range(fade):
        scaled[len(scaled) - fade + i] *= 0.5 * (1.0 + math.cos(math.pi * i / fade))
    return scaled


def impact(
    rng: random.Random,
    dur_s: float,
    sub_gain: float,
    body_hz: float,
    body_gain: float,
    crack_hz: float,
    crack_gain: float,
    air_cut: float,
    air_gain: float,
    sub_start: float = 85.0,
    sub_end: float = 55.0,
    body_decay: float = 0.055,
    crack_decay: float = 0.010,
) -> list[float]:
    """One hit, four layers, all present in the same sample."""
    n = int(dur_s * RATE)
    sub_env = envelope(n, 0.0012, 0.055)
    body_env = envelope(n, 0.0009, body_decay)
    crack_env = envelope(n, 0.0004, crack_decay)
    air_env = envelope(n, 0.0006, 0.018)

    sub = falling_tone(n, sub_start, sub_end, rng)
    body = one_pole_lowpass(tone(n, body_hz, rng, detune=rng.uniform(-0.02, 0.02)), 1200.0)
    # Crack is a band of noise, not a tone: a tone at 2 kHz sounds like a beep.
    crack = one_pole_highpass(one_pole_lowpass(noise(n, rng), crack_hz * 1.6), crack_hz)
    air = one_pole_highpass(noise(n, rng), air_cut)

    return finish(mix(n, [
        ([sub[i] * sub_env[i] for i in range(n)], sub_gain),
        ([body[i] * body_env[i] for i in range(n)], body_gain),
        ([crack[i] * crack_env[i] for i in range(n)], crack_gain),
        ([air[i] * air_env[i] for i in range(n)], air_gain),
    ]))


def make_soft(rng: random.Random, dur_s: float, body_hz: float) -> list[float]:
    # A light cut still has weight; it just has less crack and a shorter tail.
    return impact(
        rng, dur_s,
        sub_gain=0.45, body_hz=body_hz, body_gain=0.75,
        crack_hz=1300.0, crack_gain=2.6, air_cut=4800.0, air_gain=0.9,
        body_decay=0.045, crack_decay=0.016)


def make_hard(rng: random.Random, dur_s: float, body_hz: float) -> list[float]:
    return impact(
        rng, dur_s,
        sub_gain=0.75, body_hz=body_hz, body_gain=1.0,
        crack_hz=1800.0, crack_gain=3.4, air_cut=5200.0, air_gain=1.1,
        body_decay=0.065, crack_decay=0.020)


def make_accent(rng: random.Random) -> list[float]:
    # Fast cut: more mass, not more treble. The old accent was 98.6 % in 1-4 kHz,
    # which made speed sound thinner the harder you swung.
    return impact(
        rng, 0.150,
        sub_gain=1.0, body_hz=150.0, body_gain=0.9,
        crack_hz=1600.0, crack_gain=2.4, air_cut=5000.0, air_gain=0.8,
        sub_start=80.0, sub_end=48.0, body_decay=0.080, crack_decay=0.018)


def make_dull(rng: random.Random, body_hz: float) -> list[float]:
    n = int(0.100 * RATE)
    env = envelope(n, 0.0020, 0.038)
    body = one_pole_lowpass(tone(n, body_hz, rng), 700.0)
    sub = falling_tone(n, 75.0, 50.0, rng)
    thud = one_pole_lowpass(noise(n, rng), 900.0)
    return finish(mix(n, [
        ([sub[i] * env[i] for i in range(n)], 0.55),
        ([body[i] * env[i] for i in range(n)], 0.9),
        ([thud[i] * env[i] for i in range(n)], 0.35),
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
        ("soft_01", 0x5EED01, lambda r: make_soft(r, 0.080, 190.0)),
        ("soft_02", 0x5EED02, lambda r: make_soft(r, 0.075, 165.0)),
        ("soft_03", 0x5EED03, lambda r: make_soft(r, 0.085, 210.0)),
        ("hard_01", 0x4A4D01, lambda r: make_hard(r, 0.130, 210.0)),
        ("hard_02", 0x4A4D02, lambda r: make_hard(r, 0.140, 180.0)),
        ("hard_03", 0x4A4D03, lambda r: make_hard(r, 0.125, 235.0)),
        ("accent_01", 0xA7CE01, make_accent),
        ("dull_01", 0xD01101, lambda r: make_dull(r, 140.0)),
        ("dull_02", 0xD01102, lambda r: make_dull(r, 120.0)),
    ]

    for name, seed, gen in specs:
        rng = random.Random(seed)
        path = os.path.join(out, name + ".wav")
        write_wav(path, gen(rng))
        print("wrote", path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())



