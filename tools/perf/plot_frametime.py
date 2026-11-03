#!/usr/bin/env python3
"""Frame time through a whole song, one panel per build.

x = seconds from the song starting, y = the interval between consecutive frames in milliseconds.

Why not a raw per-frame polyline: 21,600 frames into ~950 px is ~23 frames per pixel, so a single
spike becomes band thickness and the plot stops showing what it claims to show. Instead, each
one-second bucket is drawn as its min..max envelope (the shaded band) with its median line, and
every frame that actually missed a slot (>= 1.5x the period) is drawn as a point at its real time.
The band shows jitter, the points show the hitches, and neither is averaged away.

The y axis reaches the worst frame in the data rather than being clipped at an arbitrary ceiling -
the first versions cut the 41-51 ms song-start frames off the top, which is exactly what a reader
wants to see.

Add a release by appending to SERIES.

Usage:  python tools/perf/plot_frametime.py
Output: docs/images/frametime.png and .svg
"""
from __future__ import annotations

import csv
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(REPO, "docs", "images")

# label, capture, refresh_hz, colour
SERIES = [
    ("v0.0 upstream, 72 Hz", "perf/captures/fork-baseline-1.bench.csv", 72.0,  "#8e44ad"),
    ("v0.1, 120 Hz",         "perf/captures/v120-final.bench.csv",      120.0, "#d68910"),
    ("v0.2, 120 Hz",         "perf/captures/v03d-180.bench.csv",        120.0, "#1f6fb2"),
]


def read_frames(path: str) -> list[float]:
    out = []
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            try:
                out.append(float(row["delta_usec"]) / 1000.0)
            except (KeyError, ValueError):
                continue
    return out


def pct(sorted_vals: list[float], p: float) -> float:
    if not sorted_vals:
        return 0.0
    i = min(len(sorted_vals) - 1, max(0, int(round((len(sorted_vals) - 1) * p / 100.0))))
    return sorted_vals[i]


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    fig, axes = plt.subplots(len(SERIES), 1, figsize=(9.8, 8.2), sharex=True, sharey=True)
    if len(SERIES) == 1:
        axes = [axes]

    for ax, (label, rel, hz, colour) in zip(axes, SERIES):
        path = os.path.join(REPO, rel)
        if not os.path.exists(path):
            print("skip (missing):", rel)
            continue
        ms = read_frames(path)
        if not ms:
            continue
        period = 1000.0 / hz
        duration = len(ms) / hz

        # one-second envelope: min / median / max inside each bucket
        bucket = int(round(hz))
        xs, lo, mid, hi = [], [], [], []
        for start in range(0, len(ms), bucket):
            chunk = sorted(ms[start:start + bucket])
            if not chunk:
                continue
            xs.append((start + len(chunk) / 2.0) / hz)
            lo.append(chunk[0])
            mid.append(pct(chunk, 50))
            hi.append(chunk[-1])

        ax.fill_between(xs, lo, hi, color=colour, alpha=0.30, linewidth=0)
        ax.plot(xs, mid, color=colour, linewidth=1.6, label="median (1 s buckets)")
        ax.plot(xs, hi, color=colour, linewidth=0.8, alpha=0.9, label="slowest frame in bucket")

        # every genuinely dropped frame, at its real time
        drops_x = [i / hz for i, v in enumerate(ms) if v >= 1.5 * period]
        drops_y = [v for v in ms if v >= 1.5 * period]
        if drops_x:
            ax.scatter(drops_x, drops_y, s=16, color="#b03a2e", zorder=5,
                       label=f"dropped slot ({len(drops_x)})")

        # Song-start pipeline compilation produces a handful of very large frames. Letting them set
        # the axis squashed the entire song into a 5 ms strip, so they are pinned at the top edge
        # and counted instead of being allowed to dictate the scale.
        big_x = [i / hz for i, v in enumerate(ms) if v > 19.0]
        if big_x:
            ax.axhline(19.6, color="#b03a2e", linewidth=0.7, linestyle=(0, (2, 3)), alpha=0.8)
            ax.scatter(big_x, [19.0] * len(big_x), marker="^", s=26, color="#b03a2e", zorder=6,
                       label="frame >20 ms, pinned")
            ax.annotate(f"{len(big_x)} frame(s) {min(v for v in ms if v > 19.0):.0f}-{max(ms):.0f} ms",
                        xy=(big_x[0], 19.0), xytext=(big_x[0] + 4, 17.2), fontsize=7.5,
                        color="#b03a2e",
                        arrowprops=dict(arrowstyle="-", color="#b03a2e", lw=0.7))

        ax.axhline(period, color="#111111", linewidth=1.0, linestyle=(0, (5, 3)), alpha=0.85)

        ordered = sorted(ms)
        dropped = len(drops_x) / len(ms) * 100.0
        ax.set_title(
            f"{label}  -  {duration:.0f} s, median {pct(ordered, 50):.2f} ms, "
            f"p99 {pct(ordered, 99):.2f} ms, worst {ordered[-1]:.1f} ms, dropped {dropped:.2f}%",
            fontsize=9.5, loc="left")
        ax.set_ylabel("frame time (ms)", fontsize=9)
        ax.grid(True, axis="x", alpha=0.15)
        ax.tick_params(labelsize=8.5)
        ax.text(0.4, period + 1.0, f"budget {period:.2f} ms", fontsize=8, color="#222222",
                bbox=dict(facecolor="white", edgecolor="none", pad=1.8, alpha=1.0))
        ax.legend(fontsize=7.5, loc="upper right", framealpha=0.9)

        print(f"{label:<24} frames={len(ms):>6}  {duration:6.0f}s  median={pct(ordered,50):5.2f}  "
              f"p99={pct(ordered,99):5.2f}  worst={ordered[-1]:6.1f}  dropped={dropped:.2f}% "
              f"({len(drops_x)})")

    axes[-1].set_xlabel("seconds from song start", fontsize=10)
    axes[-1].set_xlim(0, 185)
    axes[0].set_ylim(0, 20)
    fig.suptitle("Frame time through a song - band = jitter within each second, dots = dropped slots, "
                 "Quest 3", fontsize=11.5, fontweight="bold")
    fig.tight_layout(rect=(0, 0, 1, 0.955))

    for name in ("frametime.png", "frametime.svg"):
        fig.savefig(os.path.join(OUT_DIR, name), dpi=110)
        print("wrote", os.path.join(OUT_DIR, name))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


