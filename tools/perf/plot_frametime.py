#!/usr/bin/env python3
"""Frame-time comparison across releases, for the README.

Two panels, split by refresh rate, with a shared y axis in milliseconds:

  left   v0.0 upstream at 72 Hz, against its own 13.89 ms budget
  right  v0.1 and v0.2 at 120 Hz, against the 8.33 ms budget

Why split. The first three attempts put all three builds on one axis and every review flagged the
same thing: a 72 Hz build sitting at 13.9 ms looks like a catastrophe next to 8.4 ms builds, when
in fact it was exactly on its own budget and simply ran half the frame rate. Splitting by rate
keeps the honest absolute comparison (same y axis) without inviting the wrong conclusion. The
right-hand panel is also where the release-over-release story is - identical median, 0.8 ms off the
p99 tail - and it now gets the whole width instead of the last 8% of a percentile axis.

Add a release by appending to the appropriate panel's list.

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
WARMUP_FRAMES = 240
# The shortest capture decides the comparison window: v0.0 runs 56 s.
COMMON_WINDOW_S = 55.0

LOW_RATE = [
    ("v0.0 upstream", "perf/captures/fork-baseline-1.bench.csv", 72.0, "#8e44ad"),
]
HIGH_RATE = [
    ("v0.1", "perf/captures/v120-final.bench.csv", 120.0, "#d68910"),
    ("v0.2", "perf/captures/v03d-180.bench.csv",  120.0, "#1f6fb2"),
]


def read_frame_ms(path: str, hz: float) -> list[float]:
    limit = int(COMMON_WINDOW_S * hz)
    out = []
    with open(path, newline="") as f:
        for i, row in enumerate(csv.DictReader(f)):
            if i < WARMUP_FRAMES:
                continue
            if len(out) >= limit:
                break
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


def draw(ax, series, hz, title):
    period = 1000.0 / hz
    for label, rel, _, colour in series:
        path = os.path.join(REPO, rel)
        if not os.path.exists(path):
            print("skip (missing):", rel)
            continue
        ms = read_frame_ms(path, hz)
        if not ms:
            continue
        ordered = sorted(ms)
        ps = [50 + i * 0.5 for i in range(101)]
        ax.plot(ps, [pct(ordered, p) for p in ps], color=colour, linewidth=2.2,
                linestyle=(0, (3.5, 2)) if label == "v0.1" else "-", label=label)
        dropped = sum(1 for v in ms if v >= 1.5 * period) / len(ms) * 100.0
        print(f"{label:<16} {hz:>3.0f} Hz  frames={len(ms):>5}  p50={pct(ordered,50):5.2f}  "
              f"p99={pct(ordered,99):5.2f}  worst={ordered[-1]:5.2f} ms  dropped={dropped:.2f}%")

    ax.axhline(period, color="#333333", linewidth=1.3, linestyle=(0, (5, 3)))
    ax.text(51.0, period - 0.55, f"{period:.2f} ms budget", fontsize=8.5, color="#333333",
            bbox=dict(facecolor="white", edgecolor="none", pad=1.0, alpha=0.85))
    ax.axvline(99, color="#666666", linewidth=0.8, linestyle=(0, (2, 2)), alpha=0.8)
    ax.text(98.2, 17.35, "p99", fontsize=8, color="#333333", ha="right",
            bbox=dict(facecolor="white", edgecolor="none", pad=1.0, alpha=0.85))
    ax.set_xlim(50, 100)
    ax.set_ylim(7.4, 17.8)
    ax.grid(True, alpha=0.22)
    ax.tick_params(labelsize=8.5)
    ax.set_xlabel("percentile of frames", fontsize=9)
    ax.set_title(title, fontsize=10)
    ax.legend(fontsize=8.5, loc="upper left", framealpha=0.95)


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    fig, (ax_l, ax_r) = plt.subplots(1, 2, figsize=(7.4, 3.9), sharey=True)

    draw(ax_l, LOW_RATE, 72.0, "v0.0 upstream - 72 Hz")
    draw(ax_r, HIGH_RATE, 120.0, "v0.1 -> v0.2 - 120 Hz")

    ax_l.set_ylabel("frame time (ms)", fontsize=9)
    fig.suptitle("Frame time by percentile, Quest 3 - shared scale, split by refresh rate",
                 fontsize=11, fontweight="bold")
    fig.tight_layout(rect=(0, 0, 1, 0.94))

    for name in ("frametime.png", "frametime.svg"):
        fig.savefig(os.path.join(OUT_DIR, name), dpi=130)
        print("wrote", os.path.join(OUT_DIR, name))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


