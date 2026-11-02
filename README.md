# OpenSaberQ3

An MIT-licensed fork of [BeepSaber](https://github.com/leandrodreamer/BeepSaber), optimised
specifically for the **Meta Quest 3** — frame-time stability, image clarity and hit registration.

## Upstream credit

**This is a fork. The original project is not ours and remains the work of its authors.**

| | |
|---|---|
| Forked from | [`leandrodreamer/BeepSaber`](https://github.com/leandrodreamer/BeepSaber), branch [`godot-4-port`](https://github.com/leandrodreamer/BeepSaber/tree/godot-4-port), commit [`64200ad`](https://github.com/leandrodreamer/BeepSaber/commit/64200ad3572b634ae57159e234e87b5e3e5d96eb) (2025-03-05) |
| Descends from | [`NeoSpark314/BeepSaber`](https://github.com/NeoSpark314/BeepSaber) and the [Godot Oculus Quest Toolkit](https://github.com/NeoSpark314/godot_oculus_quest_toolkit) |
| This fork | [`testyfishy/OpenSaberQ3`](https://github.com/testyfishy/OpenSaberQ3) |

The pinned upstream commit, the full lineage and the toolchain used for every measurement are
recorded in [`UPSTREAM.md`](UPSTREAM.md); per-component credits are in
[`ATTRIBUTION.md`](ATTRIBUTION.md).

## Status: early / work in progress

This fork does not yet have the performance it is aiming for. The engine migration and the
configuration fixes below are in place; the hitches and hit-registration work are in progress.
Claims are made only where a measurement exists, and every measurement, including the ones that
went badly, is recorded in [`PERF.md`](PERF.md). Where that file has an empty table, nothing has
been measured yet.

## What this fork changes so far

- **Builds on Godot 4.6.3.** Upstream declares 4.3, but 4.3 cannot import this repository's own
  assets on a clean clone (the mesh importer crashes and leaves 1-byte mesh files), so this fork
  builds on 4.6.3-stable.
- **Renders at about native panel resolution.** OpenXR recommends 1680×1760 per eye, roughly
  **81%** of the Quest 3's 2064×2208 panel. The render-target multiplier is raised so the image is
  rendered at about native resolution instead.
- **MSAA 4×.** Upstream shipped `quality/filters/msaa`, a Godot 3 key that Godot 4 ignores, so
  anti-aliasing was off. This fork sets `rendering/anti_aliasing/quality/msaa_3d=2` (4×).
- **Physics tick pinned to the display rate.** Upstream shipped `common/physics_fps`, also a dead
  Godot 3 key, so physics ran at the 60 Hz default against a 72 Hz panel. This fork sets
  `physics/common/physics_ticks_per_second=72`, and a benchmark run pins the tick to the refresh
  rate it selected, so collision sampling matches the panel.
- **Deterministic benchmark mode.** A flag file starts a scripted run, a bot plays the map through
  the real collision path on the song clock, and the app writes a per-frame CSV plus a metadata
  block and quits itself. Host-side capture and summarising scripts live in [`tools/perf/`](tools/perf/).

None of these are claimed as a performance gain yet: the only gameplay figures in this repository
are the baseline below, taken before them.

## Measured performance

All runs below are dated, taken on the same Quest 3, with the same workload: `ODDS&ENDS feat.
Hatsune Miku` ExpertPlus, with an in-engine bot that actually plays the map (it cuts the notes
through the real collision path, so debris, particles and scoring are all loaded). Method,
validity rules, per-run spread and caveats: [`PERF.md`](PERF.md).

### Before and after

| | **Before** — 2026-11-01 (Baseline v0) | **After** — 2026-11-01 (v2) |
|---|---|---|
| Display refresh | 72 Hz | **90 Hz** (120 Hz reached 116.85 fps, see below) |
| Render target per eye | 1680 × 1760 — **81% of panel width** | **2107 × 2208 — native** |
| MSAA | off (the setting was an inert Godot 3 key) | **4×** |
| Physics tick | 60 Hz against a 72 Hz panel | **matched to the display** |
| Frames delivered on vsync | 99.876% | **99.880%** |
| Dropped-frame events | 16 per 180 s | **13 per 120 s** |
| Frame interval p50 / p95 / p99 | 13.91 / 15.44 / 16.50 ms | **11.13 / 12.26 / 12.95 ms** |
| GPU `App=` mean | 3.94 ms (28.4% of budget) | **2.40 ms (21.6% of budget)** |

The "after" column renders **1.57× more pixels**, at a **25% shorter frame budget**, and is still
faster and steadier than the baseline. GPU use *fell* from 28.4% to 21.6% of budget because the
scene is CPU-bound, not fill-rate-bound — which is why raising resolution was affordable.

### 120 Hz status — shipping, with one known defect

| Metric | 90 Hz | **120 Hz (default)** |
|---|---|---|
| Sustained | 89.90 fps | **116.8 fps** |
| Frames on vsync | 99.880% | **99.151%** |
| Dropped events per 120 s | 13 | **119** |
| GPU `App=` mean | 2.40 ms (21.6%) | 3.26 ms (39.3%) |
| Frame interval p50 / p95 / p99 | 11.13 / 12.26 / 12.95 ms | **8.43 / 10.09 / 12.14 ms** |

120 Hz is the default. Physics runs at 120, matching the display, and resolution is native.
**Known defect: roughly one dropped frame per second** (0.85% of frames). It is not GPU-bound and
not physics-bound; a once-per-second periodic event is suspected, with Adreno pipeline compilation
as the leading candidate (Godot disables ubershaders on this GPU family). 90 Hz remains available
and is measurably cleaner: 99.88% on vsync.


### Baseline v0 detail (before any optimisation)

Upstream `64200ad` built on Godot 4.6.3, 3 × 180 s runs at 72 Hz, medians of three:

| Metric | Median |
|---|---|
| Frames delivered on vsync | 99.876% |
| Dropped-frame events (per 180 s run) | 16 |
| Severe drops (≥ 2 vsync) | 1 |
| Frame interval p50 / p95 / p99 | 13.91 / 15.44 / 16.50 ms |
| Frame interval max | 54.40 ms * |
| `App=` GPU per-eye time mean | 3.94 ms (28.4% of the 13.89 ms budget) |
| Notes cut (median) | 653 |

\* Run 1's single 459 ms spike is first-note shader/pipeline compilation; it is recorded and
excluded from judgement rather than hidden.


## Build from source

The build is pinned to a specific toolchain so that any two measurements are comparable.

| Component | Version |
|---|---|
| Godot | 4.6.3-stable (editor + matching export templates) |
| JDK | 17 |
| Android SDK platforms | 34 and 36 |
| Build-tools | 34.0.0 and 36.1.0 |
| NDK | 23.2.8568313 and 29 |
| Output ABI | arm64-v8a only |

- Export preset: **`Oculus Quest (RELEASE)`**. The release preset uses the Gradle build
  (`use_gradle_build=true`), because the OpenXR loader is supplied on that path — a prebuilt-template
  build produces an APK that starts in flat mode with `libopenxr_loader.so` missing.
- `android/.build_version` must match the engine (`4.6.3.stable`), or Godot refuses to export.
- The release preset expects a keystore on your own machine. No keystore is committed, and none
  should be; create one locally and point the preset at it. The `Oculus Quest (DEBUG)` preset is
  fine for functional testing.
- Exact commands, paths and the known reproducibility gaps live in [`UPSTREAM.md`](UPSTREAM.md).
  Benchmark tooling is documented in [`tools/perf/benchmark.md`](tools/perf/benchmark.md). Those
  two files are maintained; a copy-pasted build recipe in this README would go stale.

Measurements must use release builds — a Godot debug export carries runtime checks and would
invent a performance problem that is not there.

## Install on a Quest 3

1. Enable **Developer mode** for the headset in the Meta Horizon phone app and connect USB.
2. `adb devices` should list the headset; accept the debugging prompt in the headset if asked.
3. `adb install -r <path-to-apk>`
4. Launch **Open Saber Q3** from *Unknown Sources* in the app library.

Package id: `io.github.testyfishy.opensaberq3`. It is deliberately different from upstream's
`org.godotengine.open_saber`, so this build installs **side by side** with an existing copy and
does not touch its songs or scores.

## Benchmarking

- [`tools/perf/benchmark.md`](tools/perf/benchmark.md) — what benchmark mode does, the flag file,
  the CSV/meta outputs, and the device recipe.
- [`tools/perf/bench.ps1`](tools/perf/bench.ps1) — push the flag, launch, pull the results.
- [`tools/perf/summarize.ps1`](tools/perf/summarize.ps1) — turn a capture into the summary used in
  `PERF.md`.
- [`tools/perf/capture.ps1`](tools/perf/capture.ps1) — host-side logcat/`VrApi` capture, for checks
  that do not need in-app instrumentation.
- A `compare.ps1` (A/B of two captures) exists in the working tree and will land with the next
  tooling commit.

## License and attribution

MIT — see [`LICENSE`](LICENSE) (retained unmodified, © 2020 Holger Dammertz) and
[`ATTRIBUTION.md`](ATTRIBUTION.md) for the full chain of authors and asset provenance.

- This project contains **no Beat Saber assets**: no audio, font, shader, level, model or UI element
  from Beat Saber or any other commercial title.
- It claims **no affiliation with Beat Games or Meta**, and does not use the Beat Saber name, logo
  or branding.
- The bundled demo track is "Time Lapse" by TheFatRat, per upstream credits.

## Contributing and roadmap

Current focus, in order:

1. **Hitches** — attribute and remove the ~16 dropped-frame events per three minutes, which are a
   CPU/physics-side problem on this workload.
2. **90 Hz** — verify frame pacing and headroom at 90 Hz (11.1 ms budget) before claiming it; today
   the recorded numbers are at 72 Hz only.
3. **Hit registration** — a swept-path and tick-alignment rework is planned but **not implemented
   yet**. No hit-registration fix should be assumed from the configuration changes above.

Contributions are welcome as issues or pull requests. A performance change without a reproducible
before/after in `PERF.md`, taken with the same method, will not be merged; a claimed win that does
not reproduce gets reverted.
