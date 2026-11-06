#!/usr/bin/env python3
"""Measure the game's audio mix from a WAV recorded by the bench audio probe.

Why this and not the headset microphone: the microphone measures the room and the speakers, with
the headset's AGC/noise suppression in the path, so the same mix can read differently on two runs.
The probe taps the Master bus *after* music, SFX and the hit limiter, which is exactly the signal
the player is meant to hear. The mic is still useful as a final sanity check; this is the
repeatable instrument.

Usage:
  python tools/perf/audio_probe.py mix.wav
  python tools/perf/audio_probe.py --compare no_hits.wav with_hits.wav

Reads 16-bit PCM WAV (mono or stereo), prints:
  - peak and median RMS in dBFS
  - per-band energy (body 150-800 Hz, transient 2-6 kHz)
  - transient count: 10 ms windows where the transient band is > 6 dB above its rolling median
  - with --compare: the extra transient-band energy in the second file, i.e. what the hits add
    over the same music bed.

Needs numpy (no scipy).
"""

import argparse
import struct
import sys
import wave

import numpy as np

WINDOW_S = 0.010  # 10 ms
TRANSIENT_BAND = (2000.0, 6000.0)
BODY_BAND = (150.0, 800.0)


def read_wav(path):
    with wave.open(path, "rb") as w:
        if w.getsampwidth() != 2:
            raise SystemExit("%s: expected 16-bit PCM, got %d bytes/sample" % (path, w.getsampwidth()))
        rate = w.getframerate()
        channels = w.getnchannels()
        raw = w.readframes(w.getnframes())
    data = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    if channels > 1:
        data = data.reshape(-1, channels).mean(axis=1)
    return rate, data


def windows(signal, rate, seconds=WINDOW_S):
    n = max(1, int(rate * seconds))
    count = len(signal) // n
    if count == 0:
        return np.zeros((0, n), dtype=np.float32)
    return signal[: count * n].reshape(count, n)


def band_energy(block, rate, lo, hi):
    spectrum = np.abs(np.fft.rfft(block * np.hanning(len(block))))
    freqs = np.fft.rfftfreq(len(block), 1.0 / rate)
    mask = (freqs >= lo) & (freqs <= hi)
    return float(np.sqrt(np.mean(np.square(spectrum[mask])))) if mask.any() else 0.0


def db(value):
    return 20.0 * np.log10(max(value, 1e-9))


def describe(path):
    rate, signal = read_wav(path)
    if len(signal) == 0:
        raise SystemExit("%s: empty" % path)
    blocks = windows(signal, rate)
    rms = np.sqrt(np.mean(np.square(blocks), axis=1))
    transient = np.array([band_energy(b, rate, *TRANSIENT_BAND) for b in blocks])
    body = np.array([band_energy(b, rate, *BODY_BAND) for b in blocks])

    # A hit is a short transient-band peak well above the local music bed. The rolling median is
    # robust to the transients themselves, unlike a mean.
    local = np.array([
        np.median(transient[max(0, i - 50): i + 50]) if len(transient) else 0.0
        for i in range(len(transient))
    ])
    with np.errstate(divide="ignore"):
        lift = np.where(local > 0, 20.0 * np.log10(np.maximum(transient, 1e-9) / np.maximum(local, 1e-9)), 0.0)
    hits = int(np.sum(lift > 6.0))

    print("%s: %.2f s, %d Hz, %d windows" % (path, len(signal) / rate, rate, len(blocks)))
    print("  peak %.1f dBFS   median RMS %.1f dBFS" % (db(float(rms.max())), db(float(np.median(rms)))))
    print("  transient band median %.1f dB   body band median %.1f dB" % (
        db(float(np.median(transient))), db(float(np.median(body)))))
    print("  transient peaks (>6 dB over local bed): %d" % hits)
    return {
        "rate": rate,
        "rms_median": float(np.median(rms)),
        "transient_median": float(np.median(transient)),
        "body_median": float(np.median(body)),
        "hits": hits,
    }


def compare(a_path, b_path):
    a = describe(a_path)
    b = describe(b_path)
    print("")
    print("difference (B - A), same music bed:")
    print("  transient band: %+.1f dB" % (db(b["transient_median"]) - db(a["transient_median"])))
    print("  body band:      %+.1f dB" % (db(b["body_median"]) - db(a["body_median"])))
    print("  transient peaks: %d -> %d" % (a["hits"], b["hits"]))
    print("  verdict: %s" % (
        "hits add audible transient energy" if db(b["transient_median"]) - db(a["transient_median"]) >= 2.0
        else "hits are not adding measurable transient energy"))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("wav", nargs="?")
    parser.add_argument("--compare", nargs=2, metavar=("NO_HITS", "WITH_HITS"))
    args = parser.parse_args()
    if args.compare:
        compare(*args.compare)
    elif args.wav:
        describe(args.wav)
    else:
        parser.error("give a WAV or --compare A B")


if __name__ == "__main__":
    main()
