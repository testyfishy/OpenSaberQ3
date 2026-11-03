# OpenSaberQ3

An MIT-licensed fork of [BeepSaber](https://github.com/leandrodreamer/BeepSaber), optimised
specifically for the **Meta Quest 3** — frame stability, clarity, hit registration, and the
things a rhythm game needs to feel good to play.

## Upstream credit

**This is a fork. The original project is not ours and remains the work of its authors.**

| | |
|---|---|
| Forked from | [`leandrodreamer/BeepSaber`](https://github.com/leandrodreamer/BeepSaber), branch [`godot-4-port`](https://github.com/leandrodreamer/BeepSaber/tree/godot-4-port), commit [`64200ad`](https://github.com/leandrodreamer/BeepSaber/commit/64200ad3572b634ae57159e234e87b5e3e5d96eb) (2025-03-05) |
| Descends from | [`NeoSpark314/BeepSaber`](https://github.com/NeoSpark314/BeepSaber) and the [Godot Oculus Quest Toolkit](https://github.com/NeoSpark314/godot_oculus_quest_toolkit) |
| This fork | [`testyfishy/OpenSaberQ3`](https://github.com/testyfishy/OpenSaberQ3) |

The pinned upstream commit, full lineage and the toolchain used for every measurement are in
[`UPSTREAM.md`](UPSTREAM.md); per-component credits are in [`ATTRIBUTION.md`](ATTRIBUTION.md).

## Status

**v0.2 is released** — [download the APK](https://github.com/testyfishy/OpenSaberQ3/releases).
**v0.3 is in progress**, focused on frame stability across maps and on hit feedback.

Everything claimed below has a measurement behind it, and the measurements that went badly are
recorded too. [`PERF.md`](PERF.md) is the full log; [`docs/v0.3-report.md`](docs/v0.3-report.md)
is the current release write-up.

### How to read the numbers

Two different things get called "performance", so this repository states both:

- **dropped** — a frame that missed a whole vsync slot (≥1.5× the frame period). This is the one a
  player feels as a hitch.
- **on time** — a frame delivered within ~1.05× the period. Stricter; it counts frames the
  compositor still presented, so it is always the lower number.

Quoting the first without the second is how a 120 Hz build gets described as "99.8% perfect" while
one frame in five lands late. Both are in every capture.

## What this fork changes

**Engine and rendering**
- **Godot 4.6.3** (upstream 4.3 cannot import this repo's own assets on a clean clone)
- **120 Hz with physics matched to the display** (was 72 Hz / 60 Hz physics)
- **Performance / Balanced / Quality preset**, one switch for the three GPU levers, plus the
  individual settings underneath. Default is Performance.
- **Bloom removed**: a full-screen pass that forced the 4× MSAA image out of tile memory. The
  saber halos carry the glow instead.
- **Ten visual options**, each with its own persisted setting and applied without a restart.

**Content**
- **Every map format**: v2, v3 and v4, including the hybrid BeatSaver actually serves (v2
  `Info.dat` pointing at v3 difficulty files) and v4's split beatmap/lightshow with index-shared
  geometry.
- **In-VR BeatSaver browser**: search, sort, filter, download straight to the headset.
- **Local upload page**: serve a small page on the LAN and drop a map zip in from a PC browser.
  Switchable, and off means the port is closed, not just ignored.

**Gameplay and feedback**
- **Working hit registration**: sub-threshold sweep movement is no longer discarded, collision
  flags are not rewritten every tick, notes no longer share one mutated hitbox.
- **The Meta recenter button works** (was ignored, leaving the menu rotated)
- **Layered hit audio**: sub + body + crack + air in one sample, crest-compressed rather than
  peak-normalised (+8–9 dB RMS over the old assets)
- **Per-event haptics**: a cut is 28 ms with speed/accuracy-driven amplitude; a wrong-colour cut
  or bomb is a short dull pulse. It used to be one 100 ms buzz for everything.
- **A reproducible benchmark harness** in `tools/perf/`, including human-play capture.

## Settings

Main menu → Settings. The preset sets the three GPU levers together, because their individual
names mean nothing on their own:

| Preset | Render target | MSAA | Foveation | Measured GPU |
|---|---|---|---|---|
| Quality | 2107×2208 (native supersample) | 4× | off | 0.86 of budget |
| Balanced | 1848×1936 | 4× | low | 0.75 |
| **Performance (default)** | **1680×1760** (runtime-recommended) | **2×** | **medium** | **0.68–0.70** |

Everything else is also adjustable: refresh rate, the individual render/MSAA/foveation values,
layered hit audio, and the ten visual toggles.

## Measured performance

![Frame time by percentile across releases](docs/images/frametime.png)

Frame time at each percentile, from the same harness on the same map, 55 s of play each (the
upstream capture is that long — every series gets the same window). Panel left is the 72 Hz
upstream build against its own 13.9 ms budget; panel right is the two 120 Hz builds against
8.33 ms. The shared y axis keeps the absolute comparison honest while the split stops the
frame-rate change from being read as an efficiency win.

The right panel is the release story: **v0.1 and v0.2 have the same median** (8.36 vs 8.35 ms)
and diverge only in the tail — p99 10.50 → 9.66 ms, worst frame 17.16 → 13.22 ms, dropped
frames 0.38% → 0.02%. Medians hid that; the tail is what a player feels.

Regenerate with `python tools/perf/plot_frametime.py` after adding a capture to its series list.

Quest 3, 120 Hz, bot playing `ODDS&ENDS feat. Hatsune Miku` ExpertPlus through the real collision
path, 180 s unless stated. Method, validity rules and caveats: [`PERF.md`](PERF.md).

### v0.2 shipped default

| | value |
|---|---|
| Frames | 21,348 |
| Delivered | 120 fps |
| **Dropped** | **0.01%** — 2 frames in three minutes |
| On time | 76.6% |
| p95 / p99 frame interval | 9.30 / 9.97 ms (8.33 ms budget) |
| Mean frame, thirds | 8.33 / 8.33 / 8.33 ms |
| GPU / CPU | 0.68–0.70 / 0.22 of budget |

**Every visual setting on**, 334 s sustained: **0.02% dropped**, on-time 75.4%, flat across the
run. The whole visual layer costs about 1 point of on-time.

### The stutter that was real

An earlier "the stutter was the benchmark" conclusion was only half right. The harness *was*
inflating early numbers, but a real defect was also present: `Cuttable._physics_process` read
`global_transform` twice per tick per live note. Frame time climbed 8.40 → 8.95 ms across three
minutes — worse the longer you played — and on-time collapsed from 78.5% to 51.7%. Replacing those
reads with one local read took it to **78.3% on time, 0.21% dropped, flat thirds**.

### Per-map matrix (why some maps feel worse)

| map | walls | fps | on time | dropped |
|---|---|---|---|---|
| Empires | 0 | 120.0 | 80.5% | 0.00% |
| HEARTATTACK (575 bombs, 153 arcs) | 567 | 120.0 | 71.8% | 0.00% |
| Gloom | **12,340** | 92.9 | 27.5% | 24.07% |
| Somewhere Out There | **3,530** | 65.1 | 6.2% | 66.29% |

Bombs and arcs are free. Walls were not pooled — every wall was instantiated and freed, ~74 times
a second on a wall map. That is fixed in v0.3 (pooled, shared unit mesh, sized pool) and awaiting
verification.

## Build from source

Pinned toolchain, so any two measurements are comparable:

| Component | Version |
|---|---|
| Godot | 4.6.3-stable (editor + matching export templates) |
| JDK | 17 |
| Android SDK platforms | 34 and 36 |
| Build-tools | 34.0.0 and 36.1.0 |
| NDK | 23.2.8568313 and 29 |
| Output ABI | arm64-v8a only |

- Export preset: **`Oculus Quest (RELEASE)`**. It uses the Gradle build (`use_gradle_build=true`)
  because the OpenXR loader is supplied on that path; a prebuilt-template build starts in flat
  mode with `libopenxr_loader.so` missing.
- `android/.build_version` must match the engine (`4.6.3.stable`) or Godot refuses to export.
- The release preset expects a keystore on your machine. None is committed and none should be.
- Exact commands and known reproducibility gaps: [`UPSTREAM.md`](UPSTREAM.md). Benchmark tooling:
  [`tools/perf/benchmark.md`](tools/perf/benchmark.md).

Measurements must use release builds — a debug export carries runtime checks and invents a
performance problem that is not there.

## Install on a Quest 3

1. Enable **Developer mode** for the headset in the Meta Horizon phone app and connect USB.
2. `adb devices` should list the headset; accept the debugging prompt if asked.
3. `adb install -r <path-to-apk>`
4. Launch **Open Saber Q3** from *Unknown Sources*.

Package id `io.github.testyfishy.opensaberq3` is deliberately different from upstream's, so it
installs **side by side** and does not touch an existing copy's songs or scores.

## Known limitations

- **No HRTF.** Godot has none and Quest does not provide one to us, so left/right is stereo
  panning only; above/below cannot be reproduced faithfully.
- **Quest 3 speakers roll off below ~150–200 Hz.** Hit sounds are built with their weight at
  200–800 Hz for that reason, not sub-bass.
- **360°/90° lane rotation** is parsed but not applied.
- **v4 event-box groups and VFX boxes** are ignored; basic lighting events are supported.
- A **red dot** has been reported at screen centre during play and has never been reproduced in
  testing. It is tracked, not forgotten.

## Ongoing work — v0.3

Current focus, in the order it is being tackled. Each item ships only when a before/after
measurement exists.

**1. Walls on wall-heavy maps** *(code done, verification pending)*
Pooled instead of instantiated per spawn, one shared unit mesh with node scaling instead of a
per-wall mesh rebuild, and a 160-instance pool sized from the measured live count. A real
regression was caught offline before release: pooled walls lacked `clear_from_track()`, so a map
transition freed them while the pool still referenced them. Fixed and verified clean.

**2. Map coverage**
The six-map matrix above is being extended. Once walls are fixed, the test is whether all maps
sit within a few points of each other — and if Somewhere Out There still lags, that map is
revealing a second cost (it is the only one with both heavy walls and 50 notes/second bursts).

**3. Feedback / physicality**
The player's summary was "minimal physicality" and "the vibration is better feedback than the
audio". Layered samples and per-event haptics are in. Still open:
- a continuous per-hand hum whose pitch follows swing speed — the only mechanism that gives the
  ear a sense of *which hand* without HRTF
- miss feedback (currently nothing: no sound, no haptic) and wall-contact feedback
- applying the interaction-feedback research in [`docs/`](docs/) rather than inventing it

**4. UI**
HUD text overlaps at the bottom right; the end-of-map card does not lay out cleanly. The HUD fix
is placement, the end card wants a `SubViewport` with real containers.

**5. Sky**
Implemented: black void (default), gradient, panorama. Ambient light is set explicitly for void so
the scene does not go dull — the sky used to supply it.

**6. Instruments**
Added so the above can be judged rather than guessed:
`[bench] player_capture` (records *your* play, not the bot's), `ui_scroll_probe`, subsystem
kill-switches (`no_notes`, `hud_off`, `floor_off`, `no_audio`, `physics_hz`), wall-pool peak
telemetry, screenshot capture, and `tools/audio/analyse_hitsounds.py`.

**Not planned:** ray tracing (no Godot RT API, no Quest support), physics ragdolls, HRTF
spatialisation, per-hit music ducking (pumps at note rate), and camera shake.

## License and attribution

MIT — see [`LICENSE`](LICENSE) (retained unmodified, © 2020 Holger Dammertz) and
[`ATTRIBUTION.md`](ATTRIBUTION.md) for the full chain of authors and asset provenance.

- Contains **no Beat Saber assets**: no audio, font, shader, level, model or UI element from Beat
  Saber or any other commercial title.
- Claims **no affiliation with Beat Games or Meta**, and does not use the Beat Saber name, logo or
  branding.
