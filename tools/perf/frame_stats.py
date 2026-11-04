"""Frame-interval statistics for a bench CSV.

Usage: python tools/perf/frame_stats.py perf/captures/a.bench.csv [more.csv ...]

Reports the numbers the player actually feels: on-time share at the requested refresh rate,
dropped frames (>1.5x the period), p50/p95/p99/max, and the three thirds of the run so a slow
drift is visible instead of averaged away.
"""

import csv
import sys


def stats(path: str) -> dict:
    rows = list(csv.DictReader(open(path, encoding="utf-8")))
    frames = [int(r["delta_usec"]) for r in rows if r.get("delta_usec")]
    if not frames:
        return {"path": path, "empty": True}
    # The bench writes the display period into every row's target when available; fall back to
    # 120 Hz, which is the project's target.
    period = 1_000_000.0 / 120.0
    ordered = sorted(frames)
    pct = lambda p: ordered[min(len(ordered) - 1, int(len(ordered) * p))]
    thirds = []
    for i in range(3):
        chunk = frames[i * len(frames) // 3:(i + 1) * len(frames) // 3]
        thirds.append(100.0 * sum(1 for f in chunk if f <= period) / len(chunk))
    return {
        "path": path,
        "samples": len(frames),
        "on_time": 100.0 * sum(1 for f in frames if f <= period) / len(frames),
        "dropped": 100.0 * sum(1 for f in frames if f > period * 1.5) / len(frames),
        "p50": pct(0.50) / 1000.0,
        "p95": pct(0.95) / 1000.0,
        "p99": pct(0.99) / 1000.0,
        "max": ordered[-1] / 1000.0,
        "thirds": thirds,
    }


def main() -> None:
    for path in sys.argv[1:]:
        s = stats(path)
        if s.get("empty"):
            print(f"{path}: no frames")
            continue
        print(
            f"{s['path']}\n"
            f"  samples={s['samples']}  on_time={s['on_time']:.2f}%  dropped={s['dropped']:.2f}%  "
            f"p50={s['p50']:.2f}ms  p95={s['p95']:.2f}ms  p99={s['p99']:.2f}ms  max={s['max']:.2f}ms\n"
            f"  thirds: {s['thirds'][0]:.1f}% / {s['thirds'][1]:.1f}% / {s['thirds'][2]:.1f}%"
        )


if __name__ == "__main__":
    main()
