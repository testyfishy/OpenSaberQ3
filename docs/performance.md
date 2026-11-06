# Performance

Everything here was measured on a Quest 3 at 120 Hz with a signed release build of the commit in
question, bot playing a real map through the real collision path. The full raw log, validity rules
and retractions are in [PERF.md](../PERF.md); the story of the v0.3 fix is in the
[v0.3 report](v0.3-report.md).

## Metrics

- **dropped** — a frame that missed a whole vsync slot (>= 1.5x the frame period). This is the one
  a player feels as a hitch.
- **on time** — a frame delivered within ~1.05x the period. Always the lower number.

Every capture reports both.

## Frame time through a song

![Frame time through a song](images/frametime.png)

X is seconds from the start, y is the interval between consecutive frames. The shaded band is the
min-to-max range within each second, the line through it is the median, the thin line is the
slowest frame in that second, and the **red dots are frames that missed a vsync slot**, drawn when
they happened. The triangles at the top are song-start pipeline compiles, pinned above the axis.

- **v0.1 is clean for about 28 seconds, then drops slots continuously to the end of the song** —
  119 of them.
- **v0.2 has nine in three minutes.** Its median is identical to v0.1's (8.37 vs 8.43 ms); the
  difference is entirely in the tail.

Regenerate with `python tools/perf/plot_frametime.py`.

## Stutter: a physics read in `Cuttable`

`Cuttable._physics_process` read `global_transform` twice per tick per live note. Frame time
climbed 8.40 -> 8.95 ms across three minutes — worse the longer you played.
(PERF.md records the earlier harness-only conclusion and its retraction.)

| | before | after |
|---|---|---|
| on time | 64.3% | **76.6%** |
| dropped | 0.72% | **0.01%** (2 frames in 21,348) |
| p99 | 11.98 ms | **9.97 ms** |
| mean frame, thirds | 8.40 / 8.69 / 8.95 ms | **8.33 / 8.33 / 8.33 ms** |
| on-time, thirds | 78.5 / 62.6 / 51.7% | **81.3 / 75.0 / 73.5%** |

Dropped frames fell 72x and the decay disappeared. Replacing the repeated reads with one local
read is the whole fix.

## The GPU is the limiter

The preset sets the three GPU levers together, because the individual names mean nothing on their
own.

| Preset | Render target | MSAA | Foveation | GPU | On time |
|---|---|---|---|---|---|
| Quality | 2107x2208 (native supersample) | 4x | off | 0.86 | 78.3% |
| Balanced | 1848x1936 | 4x | low | 0.75 | - |
| **Performance (default)** | **1680x1760** (runtime recommended) | **2x** | **medium** | **0.68-0.70** | **76.6%** |

## The map matrix: walls were the hidden cost

Six maps, 90 s each, same bot, same 120 Hz settings. Bombs and arcs are free; density alone is not
the cost.

| map | notes | bombs | walls | arcs | fps | on time | dropped |
|---|---|---|---|---|---|---|---|
| Empires (Ex+) | 823 | 0 | 0 | 0 | 120.0 | 80.5% | 0.00% |
| ODDS&ENDS | - | - | few | - | 120.0 | 78.3% | 0.01% |
| Void Hornet (Ex+) | 657 | 0 | 16 | 6 | 120.0 | 72.0% | 0.00% |
| HEARTATTACK (Ex+) | 2,118 | 575 | 567 | 153 | 120.0 | 71.8% | 0.00% |
| **Gloom (Ex+)** | 411 | 4 | **12,340** | 0 | **92.9** | 27.5% | **24.07%** |
| **Somewhere Out There (Ex+)** | 2,905 | 8 | **3,530** | 0 | **65.1** | 6.2% | **66.29%** |

The two maps that collapsed were the two wall maps: every wall was instantiated and freed, ~74
times a second on Gloom. Walls now come from a `ScenePool` like notes; the dense-map capture below
is the same map at the modern build.

## Dense notes, v0.6

The hardest map in the device library: **Somewhere Out There ExpertPlus, 2,913 notes, 9.64 NPS**,
120 Hz, bot hitting notes.

| run | fps | App | GPU | p99 | dropped | cubes live |
|---|---|---|---|---|---|---|
| steady default | 120 | 5.02 ms | 0.85 | 11.37 ms | **0.14%** | 7 |
| hot (after 180 s of runs) | 120 | 6.01 ms | 0.97 | 12.79 ms | 1.09% | 7 |
| light map (ODDS) | 120 | 4.97 ms | 0.85 | 10.24 ms | 0.11% | 9 |
| debris / glow / flash off | 120 | 5.18-5.22 ms | 0.87 | 10.90-11.60 ms | 0.10-0.27% | 7 |

Feature-off arms do not move the result; spike attribution shows spawn <= 0.9 ms, swing <= 3 ms,
cuttable <= 0.1 ms. The hot-run delta is device/GPU state, not the note stream. That is why the
note path was not changed for v0.6; the [full analysis](../specs/019-chains-dense/spec.md) records
the arms and the conclusion.

## Human play

`[bench] player_capture` records the same CSV while a person plays instead of the bot, and writes
it out when the song ends. Method: [tools/perf/benchmark.md](../tools/perf/benchmark.md).

## What is not achievable

Ray tracing, physics ragdolls, HRTF spatialisation and per-hit music ducking at note rate are not
supported: Godot has no RT API on Quest, and the hardware/audio path cannot deliver the rest.
Sky, reflections and audio ship in the forms Quest 3 runs at 120 Hz.
