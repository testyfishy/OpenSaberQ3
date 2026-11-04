# Performance record

Every number here was captured on the author's own Meta Quest 3 with the method stated in the
same row. A change that cannot show a number here does not ship (spec FR-019, SC-002, SC-003).

**Nothing in this file is an estimate.** Empty tables mean "not measured yet", not "good".

## Device under test

| Field | Value |
|---|---|
| Model | Meta Quest 3 (`eureka`), serial `2G0YC1ZF9J0G2V` |
| OS | Android 14 / SDK 34 |
| Installed reference app | `org.godotengine.open_saber` 0.5.0 (code 5), built upstream on Godot 4.3 |
| Installed app settings | defaults — `files/config.ini` is 0 bytes, so MSAA off and render scale 1.0 |

## Method

Capture tool: `tools/perf/capture.ps1` (host-side only, no in-app code — spec FR-023).

```powershell
pwsh -File tools/perf/capture.ps1 -Seconds 120 -Label baseline-charging
```

It records, per run:

- achieved/target FPS per VR-runtime sample (`VrApi` logcat tag), from which we derive mean,
  minimum, 1st and 5th percentile FPS and the share of samples on target;
- stale-frame count, CPU/GPU performance level;
- battery level and charging state;
- thermal status (`dumpsys thermalservice`).

Frame budget at 72 Hz is **13.9 ms** (SC-002/SC-003).

### Rules that make the numbers valid

1. **Never mix charging states.** USB = charging = higher clocks and more heat. A baseline and
   its "after" must both be charging or both be on battery. State is recorded in every row.
2. **ABAB ordering** between variants, with a cooldown between runs (FR-026).
3. **At least 3 runs per variant**; a difference smaller than the spread is not a win.
4. **Hot state only for pass/fail.** A cold headset flatters every build.
5. Wi-Fi `adb` stays connected for convenience, but a run is marked invalid if the transport
   dropped mid-capture.
6. **Measure release builds, never debug.** A Godot debug export carries runtime checks and is
   slower than release, so timing a debug APK would invent a performance problem. Debug builds
   are for functional verification only; every number in the tables below comes from a release
   export.
7. **The headset is idle except while capturing.** Force-stop the app before and after every run
   (`adb shell am force-stop <pkg>`), and let it sleep when not measuring. A headset left
   rendering the menu builds heat and shifts every subsequent measurement.
8. **All compilation happens on the host.** The APK is arm64-v8a only; engine code comes from
   prebuilt Android export templates and GDScript is compiled to bytecode at export time.
   Nothing is compiled on the device, so the device's CPU is never spent on the build.


## Reference scenario

| Field | Value |
|---|---|
| Map | `TheFatRat_Timelapse` (bundled with the project; identical on every install) |
| Start state | fresh app launch, song list, no prior play in the session |
| Warm-up | one full song discarded before measurement |
| Duration | 15 minutes sustained for SC-002/SC-003; 120 s for quick iteration |

## Baseline

Not yet captured — currently blocked on a deterministic gameplay scenario (see below).

### First trustworthy data point (2026-11-01, menu screen, not gameplay)

Fork build `build/OpenSaberQ3-gradle.apk`, Godot 4.6.3, **Vulkan 1.3 / Forward Mobile**, OpenXR
runtime `Oculus 209.166.0`, 72 Hz, charging, cold (31.0 °C).

```
VrApi: FPS=73/72, Stale=0, Stale2/5/10/max=0/0/0/0, App=5.94ms, CPU&GPU=9.22ms,
       GPU%=0.52, CPU%=0.12, CPU4/GPU=2/2, 1382/456MHz, DpuScale=1.00
```

| Metric | Value | Budget | Used |
|---|---|---|---|
| App GPU+CPU | 5.94 ms | 13.9 ms | 43% |
| Subsystem | 9.22 ms | 13.9 ms | 66% |
| Stale frames | 0 | 0 | ok |

**This is a menu, not gameplay, so it is not the baseline.** It proves the pipeline works and
that the headset is nowhere near GPU-bound when idle. Gameplay is where spikes will live.

### Baseline v0 — 2026-11-01 — "before anything was changed"

**Workload:** `ODDS&ENDS feat. Hatsune Miku`, ExpertPlus (Standard characteristic, index 5),
bot autoplay, 180 s per run, 3 runs with 60 s cooldowns.

**Conditions:** release build, Godot 4.6.3, Vulkan Forward Mobile, Adreno 740, 72 Hz, USB-connected
(charging), headset unworn, thermal status 0, every row focused. Booted from the same APK each run.

**Workload validity (all runs):** notes queued > 0; notes actually cut 642 / 655 / 653; debris peak
8 / 10 / 8; no run was an empty scene. The bot is *not* bit-deterministic (cut counts vary by ~2%
because input timing depends on frame delivery), so spread below includes that variance and it is
part of the noise floor.

| Metric | Run 1 | Run 2 | Run 3 | **Median** | Spread |
|---|---|---|---|---|---|
| Frames | 12,923 | 12,955 | 12,954 | 12,954 | ±32 |
| Delivered on vsync | 99.861% | 99.876% | 99.876% | **99.876%** | 0.015 pp |
| Dropped-frame events | 18 | 16 | 16 | **16** | 2 |
| Severe (>=2 vsync) | 2 | 1 | 1 | **1** | 1 |
| p50 interval (ms) | 13.91 | 13.92 | 13.90 | **13.91** | 0.02 |
| p95 interval (ms) | 15.38 | 15.44 | 15.52 | **15.44** | 0.14 |
| p99 interval (ms) | 16.44 | 16.50 | 16.62 | **16.50** | 0.18 |
| Max interval (ms) | **459.49** | 54.40 | 48.30 | 54.40 | — |
| `App=` GPU+CPU mean (ms) | 3.40 | 3.94 | 4.04 | **3.94** | 0.64 |
| `App=` as % of budget | 24.5% | 28.4% | 29.1% | **28.4%** | 4.6 pp |
| `CPU&GPU=` mean (ms) | 7.38 | 8.00 | 8.24 | **8.00** | 0.86 |
| `CPU&GPU=` p95 as % of budget | 85.4% | 86.3% | 88.0% | **86.3%** | 2.6 pp |
| Notes cut | 642 | 655 | 653 | **653** | 13 |

**What this baseline says, before any change is made:**

1. **GPU is not the bottleneck.** `App=` mean is 28% of the 13.89 ms budget — roughly **72% of the
   GPU frame budget is unused**. Clarity (render scale, MSAA) can be bought without touching frame
   stability, and that is the cheapest real win available.
2. **The CPU side is the binding constraint.** `CPU&GPU=` p95 sits at ~86% of budget — above the
   75% headroom target (SC-011). This is where frame stability will be won or lost.
3. **~16 dropped-frame events per 3 minutes** is the user's "intermittent hitch", quantified for the
   first time. Run 1's 459 ms outlier is almost certainly first-note shader/pipeline compilation and
   is excluded from judgement, not ignored (see FR-014).
4. Stale-frame samples (37–52 per run) corroborate the drops from the runtime's own side.

Baseline committed as: **no optimization has been applied yet.** Every later row must beat the
medians above by more than the spread.

### Measurement correction — 2026-11-01 (applies to every row above)

Reading Godot 4.6 `main.cpp` established two facts that change how the earlier tables must be
interpreted:

1. **`Performance.TIME_PROCESS` includes render submission.** The process timer is closed after
   `RenderingServer::sync()` and `draw()`, so it covers pipeline creation, command recording and
   `xrEndFrame` present — not just game logic.
2. **It is a once-per-second maximum, not a per-frame value.** The monitor is written inside
   `if (frame > 1000000)`, i.e. once per second, holding the worst frame of that second.

Therefore every `TIME_PROCESS` p95/p99 in this file means "in 95%/99% of *seconds*, the worst frame
was this long". In particular the ~120 dropped frames per 120 s at 120 Hz is **~1 dropped frame per
second**, which points at a periodic once-per-second event rather than a random tail.
`TIME_PHYSICS_PROCESS` is written in the same block and is subject to the same caveat.

The correct rig (per-frame ring buffer, script self-time from `process_priority` -1000/+1000, and
`RenderingServer.frame_pre_draw`/`frame_post_draw` timestamps, cross-checked against VrApi `Stale`)
is specified and **not yet implemented**. Until it is, per-frame tail conclusions in this file are
directional, not exact.

### v7 — 2026-11-01 — collision fixes and arc tessellation

| Metric | v4 (120 Hz) | v7 (120 Hz) |
|---|---|---|
| On vsync | 99.122 % | 99.144 % |
| Dropped / 120 s | 123 | 120 |
| Physics p95 (see caveat) | 5.83 ms | **3.66 ms** |
| Arcs disabled (A/B) | 104 drops, physics p95 3.61 | — |

Changes: redundant per-tick `CollisionShape3D.disabled` writes removed; shared `BoxShape3D`
mutation isolated per instance (a correctness defect where the last-spawned note set every live
note's hitbox); arc CSG tessellation reduced (`path_interval` 0.13 → 0.45, smoothing off).

**Final configuration for this release:** refresh **120 Hz** default (`xr/openxr/default_refresh_rate`),
physics 120 Hz (matching the display), render target 2107x2208/eye, MSAA 4x, collision fixes on.
(An earlier revision of this row said 90 Hz. The shipped default is 120 Hz - corrected 2026-11-02
after the 120 Hz default was confirmed on device.)


Same workload/conditions as v0/v1. Validity flags now recorded per run: `refresh_request_honoured=true`
and `physics_matches_display=true` on both rows (the earlier runs had physics pinned to a stale
rate; that is fixed and proven, not asserted).

### v2 — 2026-11-01 — 90 Hz and 120 Hz, physics matched to display, native resolution

| Metric | v0 (72 Hz) | **v2 90 Hz** | **v2 120 Hz** |
|---|---|---|---|
| Render target / eye | 1680×1760 | **2107×2208** | **2107×2208** |
| Refresh / physics | 72 / 60→72 (mismatched) | **90 / 90** | **120 / 120** |
| Sustained fps | 71.96 | **89.90** | **116.85** |
| Frames on vsync | 99.876 % | **99.880 %** | 99.066 % |
| Dropped events / 120 s | 16 per 180 s | **13** | 131 |
| Severe (≥2 vsync) | 1 | 1 | 3 |
| p50 / p95 / p99 interval | 13.91 / 15.44 / 16.50 ms | **11.13 / 12.26 / 12.95 ms** | 8.43 / 10.06 / 12.31 ms |
| `App=` GPU mean | 3.94 ms (28.4 %) | **2.40 ms (21.6 %)** | 3.26 ms (39.1 %) |
| `TIME_PROCESS` p95 / p99 | — | 8.26 / 26.63 ms | **10.23 / 22.54 ms** |
| `TIME_PHYSICS_PROCESS` p95 / p99 | — | 5.91 / 11.47 ms | 5.85 / 11.59 ms |

**Reading:**
1. **90 Hz is solid**: 99.88 % of frames on vsync, 13 drops in two minutes, GPU at 22 %.
2. **120 Hz is reachable in GPU terms but not yet stable**: 116.85 fps average with 0.93 % of
   frames dropped, because main-thread `TIME_PROCESS` p95 (10.23 ms) exceeds the entire 8.33 ms
   budget. GPU is only at 39 % of the same budget.
3. **Physics is not the 120 Hz blocker** at p95 5.85 ms — but its p99 (11.59 ms) still exceeds
   the frame, and the main-thread spikes (p99 22.5 ms, max 147 ms) are the real cause of drops.
4. The advisor's 120 Hz gate requires CPU p99 ≤ 7.0 ms, no frame over 16 ms outside song load,
   and GPU p99 ≤ 6.5 ms, cold and after a 15-minute hot run. v2 120 Hz fails the CPU criteria.

### v1 — 2026-11-01 — native resolution at 90 Hz

**Changes vs Baseline v0:** Manifest declares `com.oculus.supportedDevices` (unlocks rates
above 72), 4× MSAA is now real, physics tick follows the display, render target multiplier is
applied at runtime, resolution raised from the runtime default to native.

**Workload and conditions:** identical map/difficulty/bot as Baseline v0; release build; 120 s
runs; USB/charging; cold; all rows focused.

| Metric | Baseline v0 (72 Hz, 1680×1760) | v1 (90 Hz, 2107×2208) |
|---|---|---|
| Display refresh granted | 72 Hz | **90 Hz** (`[72, 80, 90, 120]` available) |
| Sustained frame rate | 71.96 fps | **89.90 fps** |
| Frames on vsync | 99.876 % | 99.852 % |
| p50 / p95 / p99 interval | 13.91 / 15.44 / 16.50 ms | 11.13 / 12.24 / 13.07 ms |
| Frame budget | 13.89 ms | **11.11 ms** |
| `App=` GPU mean | 3.94 ms (28.4 %) | **2.87 ms (25.8 %)** |
| Render target per eye | 1680 × 1760 (81 % of panel width) | **2107 × 2208 (native, +2 % width)** |
| Dropped-frame events | 16 per 180 s | 16 per 120 s |

**Reading:**
1. **90 Hz was never a performance problem — it was a manifest declaration.** Without
   `com.oculus.supportedDevices`, Horizon OS ran the app in compatibility mode as an older
   device and reported exactly one rate. One declaration exposed 72/80/90/120.
2. **Native resolution is affordable.** Rendering 1.57× more pixels (1680×1760 → 2107×2208) at a
   20 % shorter frame budget still left GPU at ~26 %, because the scene is CPU-bound, not
   fill-rate-bound. This is the clarity win, and it is now real rather than a setting that
   silently did nothing.
3. **Caveat on this row:** the runtime's refresh change is asynchronous and the harness pinned
   physics to the *stale* reading (120 Hz physics against a 90 Hz display) for this run. Frame
   pacing was unaffected, CPU cost was inflated. Fixed by pinning physics at record-start from
   the settled rate; the corrected row follows as v1a.

### v0 harness validation (2026-11-01)


Release build, Godot 4.6.3, Vulkan Forward Mobile, Adreno 740, 72 Hz, charging, cold
(thermal status 0), headset unworn, **bot autoplay with zero deliberately-missed notes**.

Workload proof (this is what makes the run meaningful):
`bot_notes_queued=180 bot_swings=120 bot_skipped=0 bot_score_right_notes=120
bot_score_wrong_notes=0 bot_score_full_combo=true slice_bursts_total=100 debris_peak=4`.

| Metric | Value | Budget (13.89 ms) |
|---|---|---|
| Frames delivered on vsync | 8637 / 8639 = **99.977 %** | — |
| Dropped-frame events (>=1.5x period) | **2** (both 1 frame) | 0 |
| p50 / p95 / p99 / max interval | 13.89 / 15.01 / 15.79 / 30.51 ms | — |
| `App=` GPU+CPU, mean / p95 / max | **3.79 / 6.24 / 6.96 ms** | 27 % at mean |
| `CPU&GPU=`, mean / p95 / max | 7.68 / 10.92 / 11.80 ms | 55 % / 79 % |
| VrApi stale samples | 11 over 80 samples | — |

**Reading:** the app is *not* GPU-bound on this workload — roughly 70 % of the GPU budget is
unused. The tighter constraint is the combined CPU side (p95 79 % of budget). So the wins
available here are spending GPU headroom on clarity, and removing the two hitches.

**Why this is not yet the baseline:** the bundled demo map is Easy and short on notes (180 over
2 minutes). FR-035 requires the reference workload to be a dense map (>= 6 notes/s, chains and
arcs) plus a walls/bombs stress map, calibrated against worn runs. This row validates the
harness, not the game.

## Blocker on the baseline — resolved 2026-11-01

The earlier blocker (no way to start a song without a human) is gone: `BotDriver` starts the
map, plays it through the real collision path on the song clock, and quits itself. What remains
before a true baseline is a dense reference map and the FR-035 calibration against worn runs.



## Optimizations

Kept changes only. Each row must be reproducible from the commit in the last column.

| # | Change | Metric | Before | After | Method | Commit |
|---|---|---|---|---|---|---|
| — | *none yet* | — | — | — | — | — |

### Stress run + metric correction (2026-11-02)

**The pass metric was too lenient.** `summarize.ps1` counts a frame as dropped only when the
interval reaches 1.5x the period (12.5 ms at 120 Hz). Every frame landing between 8.75 and
12.5 ms was therefore reported as "on vsync" when it is in fact late. Re-analysing the saved
CSVs by true on-time share:

| Run | <= 8.75 ms | 8.75-12.5 ms | >= 12.5 ms | mean fps |
|---|---|---|---|---|
| Default visuals (60 s, rays) | **77.8 %** | 21.8 % | 0.4 % | **118.5** |
| Everything on (334 s, song end) | **60.6 %** | 38.8 % | 0.5 % | **114.3** |

Two corrections to earlier claims:
1. The game has **never** held a true 120 Hz. Even at defaults, ~22 % of frames are late.
   The "99.79 % on vsync" figures in this file measured only catastrophic misses.
2. **Everything on is genuinely worse**: -4.2 fps mean and the on-time share falls 78 -> 61 %,
   despite the runtime never dropping the display below 120 Hz.

Stress run conditions: `visuals_all=true` (floor light, saber halo, note edge glow, hit flash,
per-note colours, event tint, grid, sky, wall fresnel, debris cap, mirrors, bloom), 120 Hz, bot
playing. It ended at song end (334 s) rather than the 900 s cap. Drops per ~56 s bucket were
flat (0.47 / 0.61 / 0.66 / 0.52 / 0.49 / 0.53 %), so **no thermal degradation**; `refresh_rate_final`
stayed 120. **0 SHADER ERROR**, which is the first execution of the alpha floor variant with
mirrors enabled.



### A/B result — analytic hit resolver vs the ray fan (2026-11-02)

Measured on device, same map, same bot, 60 s per side, only `gameplay/swing_hit/detection` differed.

| | rays | analytic |
|---|---|---|
| Notes cut | **114** | **114** |
| Wrong cuts | 0 | 0 |
| physics p95 | **3.28 ms** | 3.54 ms |
| physics p99 | **4.28 ms** | 7.15 ms |
| dropped-frame events | **30** | 38 |

**Verdict: reverted to `rays` as the default.** The analytic path is behaviourally identical
(parity is exact), but it did **not** reduce physics cost — it slightly increased it. The advisor
had estimated the 9 forced raycasts at 0.1–0.3 ms; measurement says they are cheap, and the
resolver's per-note work costs more than it saves. Single run per side, so treat the margin as
noise-level, but there is no win to chase here.

The resolver and its parity test remain in the tree behind the flag, because the test proved it is
correct and it is the right architecture if the ray fan ever becomes a measured cost. It is not the
current bottleneck.


| Change | Implemented | Verified | Pending |
|---|---|---|---|
| **Analytic swept hit test** (`HitResolver`, `detection = analytic\|rays`) | yes | unit parity: 26 checks pass; analytic registers 9/9 test cubes vs 7/9 for the ray fan, and the fan false-positives on a note 2 m away | **A/B RUN 2026-11-02: 114 vs 114 cuts, 0 wrong both; physics p95 3.28 (rays) vs 3.54 (analytic); reverted to rays as default
| **Effect prewarm** (arcs, bombs, walls instantiated per spawn) | yes | parse only | first-song hitch measurement on device |
| **Arc pooling** (reuse instead of instantiate/free) | yes | parse only | device run; pooled reuse resets travelled Z and visibility |
| **Bloom / glow** (`Settings.glare`, `Environment.glow_*`) | **removed** | - | gone from the tree 2026-11-02: a full-screen post pass forces the 4x MSAA image out of tile memory and our halos already carry the glow |
| **Wall fresnel** (`wall_fresnel.gdshader`, FR-009) | **removed** | compile only ever; the test map has no full-height walls, so it never executed | gone 2026-11-02: additive overdraw across large surfaces for no gameplay gain |
| **Residual ~0.2 % drops** | no | — | needs the per-frame timing rig (the current `Performance.TIME_PROCESS` is a once-per-second maximum) |

### Sustained run with every visual enabled - 2026-11-03

The sustained test that used to be listed here as never run, now measured. Every visual setting
forced on (mirrors, panorama sky, halos, note glow, grid, hit flash, event tint), 120 Hz,
shipped Performance preset, bot playing ODDS ExpertPlus for the whole song:

| | value |
|---|---|
| duration | **334 s** (the song ended; the 900 s limit was not reached) |
| frames | 39,815 |
| on time | 75.4% |
| **dropped** | **0.02%** (8 frames) |
| p95 / p99 | 9.36 / 10.12 ms |
| thirds (on time) | 75.1 / 73.7 / 77.2% |
| thirds (mean frame) | 8.33 / 8.34 / 8.34 ms |

Flat across five and a half minutes with the heaviest visual set, and the mean frame does not
move. The all-visuals cost against the shipped default is about 1 point of on-time (75.4 vs
76.6), which is inside the run-to-run band.

Still not covered: a true 15-minute run (the reference song is 5.5 minutes) and the 10x
load/unload memory test. A 900 s capture needs a longer map or a loop setting.


## 120 Hz frame-budget investigation - 2026-11-02

Reported symptom: with the stricter metric, only ~78-80 % of frames were "truly on time" at
120 Hz, while the lenient metric said 99.6 % "on vsync". Resolved by measuring what the
number actually means rather than by changing rendering.

### The ladder (45 s each, bot on ODDS, 120 Hz, physics pinned to the display)

All arms ran on the same build (bloom and wall fresnel already removed), same map, same bot.
Each arm is ~5 300 frames, so the binomial 95 % interval on a percentage is about +/-1.2 pp.

| Arm | Change vs shipped defaults | Truly on time | Delivered fps | Skipped slots |
|---|---|---|---|---|
| d-def | none (shipped) | 80.07 % | 119.17 | 0.32 % |
| e-collonce | `enable_collision_once=true` (already the default) | 81.66 % | - | - |
| e-collonce-iso | + `isolate_shapes=true` (already the default) | 79.48 % | - | - |
| d-ffr1 | foveation level 1 | 81.31 % | - | - |
| d-ffr2 | foveation level 2 | 79.71 % | - | - |
| d-msaa1 | MSAA 2x instead of 4x | 81.80 % | - | - |
| d-scale115 | render scale 1.15 | 81.66 % | - | - |
| gpu-100 | every visual setting forced on | 79.70 % | - | - |
| gpu-070 | every visual on, render scale 0.70 | 86.28 % | - | - |
| e-90hz | 90 Hz display, 90 Hz physics | 92.91 % | 89.87 | 0.10 % |

**The first three rows are the same configuration.** `enable_collision_once` and
`isolate_collision_shapes` are already `true` in `project.godot`, so those two "overrides"
changed nothing. That makes the spread between them - 79.48 / 80.07 / 81.66 - a direct
measurement of run-to-run noise: **sigma ~= 1.1 pp**. Everything from MSAA 2x to foveation to
render scale 1.15 sits inside that band and is therefore indistinguishable from noise.

### What the numbers mean

- **p50 frame interval is 100.0-100.5 % of the display period in every arm**, including
  render scale 0.70 and 90 Hz. A loop that is compute-limited would sit below 100 % when you
  cut the work in half; this one does not move. The loop is paced by the compositor's
  deadline, so "late" here means jitter around a fixed deadline, not an overrunning frame.
- Widening the tolerance from 1.05x to 1.5x the period turns the same run from 80 % "on time"
  into 99.7 % delivered, because the frames in the 8.75-12.5 ms band are **presented**, not
  lost. `frames_drawn` increments by exactly one on every one of them.
- Delivered rate is the figure that matters: **119.2 fps of 120** at 120 Hz, **89.9 of 90** at
  90 Hz. Rendering 32 % more frames per second costs 0.22 pp of slot reliability.
- Halving the pixel count (scale 0.70) buys +6 pp and nothing else does. So GPU work is a
  small part of the budget margin and CPU work is smaller still: physics is 2.3 ms of an
  8.33 ms frame at p50, and every instrumented gameplay path (swing, cuttable, floor ray,
  spawn) sums to 0.13 ms.

### Verdict

**Keep 120 Hz.** It delivers 119.2 fps; the "22 % late" figure was a 1.05x threshold applied
to a deadline-paced loop, not frame loss. `SC-010` ("zero dropped frames") is not met at
either rate - 0.32 % at 120 Hz, 0.10 % at 90 Hz, so it is not achievable as written on this
device; the honest working target is **>=99 % of vsync slots delivered**, which both meet.

`tools/perf/summarize.ps1` now prints delivered fps, budget use as a percentage of the period
and the skipped-slot rate above the on-time figure, with the band labelled as late-latch rather
than dropped, so the flattering and alarming numbers cannot be quoted in isolation again.

### Cost of the visual set, post-bloom

Every visual setting forced on (mirrors + gradient sky included) is 79.70 % against 80.07 %
for the shipped defaults - inside the noise band. The visual layer is free at this point; the
remaining margin problem is the platform's, not the content's.
### The within-run drift, found and fixed - 2026-11-03

Symptom the player reported: "I'm definitely feeling more stutter with the new changes", worse
the longer a session runs. Six 180 s runs on ODDS ExpertPlus at 120 Hz found it.

First, what it was NOT:

| 180 s run | on time | dropped | p99 | mean frame: 1st / 2nd / 3rd third |
|---|---|---|---|---|
| defaults | 63.0% | 0.72% | 11.93 | 8.39 / 8.70 / 8.95 |
| every visual off | 64.3% | 0.72% | 11.98 | 8.40 / 8.69 / 8.95 |

The same numbers twice: **the visual layer costs nothing measurable.** The 60 s comparison that
suggested a 4 pp visual cost was inside its own noise band (three runs of one scenario measured
74.5 / 78.4 / 78.3), which is why every claim below is a 180 s run.

| 180 s run | on time | dropped | p99 | thirds |
|---|---|---|---|---|
| no hit audio | 78.4% | 0.19% | 10.30 | 78.3 / 78.7 / 78.3 |
| no arcs | 77.5% | 0.18% | 10.36 | 78.4 / 75.7 / 78.3 |
| **control, no extra flags** | **78.3%** | **0.21%** | **10.37** | 82.7 / 75.6 / 76.6 |

Both isolation arms and the control landed in the same place, so neither audio nor arcs was the
cause: the change they shared was the build, and the only gameplay change in it was one line.

`Cuttable._physics_process` read `global_transform` **twice per tick per live note**, right
after writing `transform.origin.z`. Notes are children of the track, which sits at the origin
unrotated and unscaled, so local z is the same number - but each global read walks the tree and
touches the transform cache. At 8 notes live and 120 Hz that is ~2 000 extra reads a second.

Replacing them with a single local read:

  on time  64.3% -> 78.3%      dropped  0.72% -> 0.21%
  p99      11.98 -> 10.37 ms   thirds   78.5/62.6/51.7  ->  82.7/75.6/76.6

The level rose **and the decay disappeared**. That decay is what "worse the longer I play"
meant: frame time rising 8.40 -> 8.95 ms over three minutes, tracking notes live (1.1 -> 7.8).

Method note for anything after this: report thirds, not just the average. A run that averages
78% but decays to 52% is worse for a player than one that holds 74% flat.
### The limiter is the GPU, not the CPU - 2026-11-03

The runtime's own counters, sampled 38 times during a 40 s 120 Hz run (VrApi line, filtered
with `adb logcat -s VrApi:I`):

  FPS=120/120  App=5.57ms  GPU%=0.85-0.86  CPU%=0.22  TW=1.19ms  Stale=0  Tear=1-2
  clocks 1382/545 MHz, 45.0 C

**The GPU is at 85-86% of the 8.33 ms budget. The CPU is at 22%.**

(Re-measured later with only 120 Hz samples included, the shipped Performance preset sits at
GPU 0.68-0.70. The first numbers were diluted by 72 Hz menu samples; the direction stands.) That reframes the whole
optimisation pass: every CPU-side cost measured tonight - physics 2.4 ms, swing peaks of 3.7 ms,
the per-note drift - happened while three quarters of the CPU was idle. The frames that miss
are missing because the GPU ran out of time, not because the main thread did.

It also explains two earlier results that made no sense in isolation:

  render target 2107x2208 -> 1176x1232 (render_scale 0.7)  +6.6 points on time
  physics 120 Hz -> 60 Hz                                  +0.6 points (noise)

Cutting pixels helped; cutting CPU work did not. The floor run (nothing spawning at all,
88.6% on time, p99 9.23) is the engine + XR + render cost, and at 86% GPU there is only ~1 ms
of headroom in it.

Consequence for v0.3: the target ("worst case under 8.33 ms with margin to 7 ms") is a GPU
budget problem. The levers are resolution, MSAA and foveation - all measurable as GPU% - and
the visual cost of each has to be weighed by the player, not decided by me.
### Wall pooling, measured - 2026-11-03

Same maps, same harness, same settings, before and after walls stopped being instantiated per spawn:

| map | before | after |
|---|---|---|
| Gloom (12,340 walls) | 92.9 fps, 27.5% on time, **24.07% dropped**, p99 19.35 ms | **119.1 fps, 66.1% on time, 2.14% dropped**, p99 13.62 ms |
| Somewhere Out There (3,530 walls, 50 notes/s peaks) | 65.1 fps, 6.2% on time, **66.29% dropped**, p99 34.79 ms | **120.0 fps, 70.9% on time, 0.01% dropped**, p99 10.60 ms |
| HEARTATTACK (567 walls, 575 bombs, 153 arcs) | 120.0 fps, 71.8% on time, 0.00% dropped | 120.0 fps, 70.5% on time, 0.00% dropped |
| ODDS&ENDS default, 180 s | 76.6% on time, 0.01% dropped, p99 9.97 ms | 76.7% on time, 0.01% dropped, p99 9.95 ms |

Somewhere Out There went from unusable (65 fps, two thirds of frames dropped) to indistinguishable
from any other map. HEARTATTACK is unchanged, so the fix cost nothing elsewhere; arcs and bombs were
never the problem.

Gloom still drops 2.14% of frames - 11x better, but not the 0.01% the other maps show. Two further
measurements on that map:

| Gloom variant | fps | on time | dropped | p99 |
|---|---|---|---|---|
| pooled, AnimationPlayer per wall | 119.1 | 66.1% | 2.14% | 13.62 ms |
| pooled, spawn animation skipped entirely | 119.8 | 68.4% | **0.82%** | 12.33 ms |
| pooled, scale-in done in `_physics_process` (shipped) | 119.8 | 65.6% | 1.70% | 12.95 ms |

So the AnimationPlayer node was worth 1.3 points, and doing the same scale-in in code recovers most
but not all of it: writing `scale` on an animating wall is itself a transform update, and ~30 walls
are mid-animation at any moment on that map. The animation is kept because it is the wall's only
motion cue; the cost is recorded rather than hidden.

Also measured: **wall_pool_peak = 569** live walls on Gloom. The pool is presized to 256 (enough for
every normal map) and grows once during that song, because presizing 570 nodes at boot costs more
than the amortised growth.
## Rejected

Changes that were measured, did not beat the noise, and were reverted (SC-002 scenario 2).

| # | Change | Metric | Result | Why rejected | Commit reverted |
|---|---|---|---|---|---|
| — | *none yet* | — | — | — | — |

## Open questions affecting measurement

- ~~Which renderer the installed 0.5.0 build actually runs.~~ **ANSWERED 2026-11-01 from the
  device's own stdout:** `Godot Engine v4.3.stable.official.77dcf97d8` and
  `OpenGL API OpenGL ES 3.2 … Compatibility - Using Device: Qualcomm - Adreno (TM) 740`.
  The shipped app runs the **Compatibility (GLES3) renderer**, not the Mobile/Vulkan renderer
  that `project.godot` declares. Its `files/shader_cache` contains only `*GLES3*` entries,
  which corroborates it.
- Consequence: the fork's own build defaults to **Mobile/Vulkan** (`renderer/rendering_method="mobile"`),
  so a fork build and the installed app are not renderer-comparable. The renderer choice is now
  a measured experiment rather than an assumption (see task T030b): build the same commit both
  ways, measure, keep the winner. Compatibility is the incumbent and is the only one where
  `xr/openxr/foveation_level` is known to work.

## v0.3 feature cost arms (Quest 3, ODDS ExpertPlus, 120 Hz, Performance preset pinned)

Each feature was run as an arm pair back to back in one session, 60 s per arm, bot at 0% miss,
with `render_scale=1.0`, `msaa=1`, `foveation=2`. VrApi `GPU%` and `App` are the runtime's own
numbers; `on_time`, `dropped` and `p99` come from the bench CSV (`tools/perf/frame_stats.py`).

| feature | off | on | delta | decision |
|---|---|---|---|---|
| Glow (full chain) | 0.75 GPU / 4.98 ms | 0.78 GPU / 5.13 ms | +0.03 GPU, +0.15 ms, p99 +0.15 | setting, default Subtle |
| Glow (single level) | - | 0.78 GPU / 5.08 ms | +0.12 ms | the MSAA resolve dominates; Subtle is the default |
| Cut debris | 0.75 GPU / 4.94 ms | 0.76 GPU / 4.97 ms | +0.01 GPU, +0.03 ms, p99 +0.16 | on by default |
| Environment palette | 0.76 GPU / 5.06 ms | 0.75 GPU / 4.93 ms | inside noise | on by default |

The glow result matters because the previous removal was reasoned from the tiled-GPU mechanism
but never measured: the real cost is about 2-3% of the GPU budget, not the 1-2 ms that reasoning
implied. The single-level and full chains are within 0.04 ms of each other - the MSAA resolve,
not the blur count, is what costs.

Reproduce: `pwsh -File tools/perf/bloom-ab.ps1` and
`pwsh -File tools/perf/feature-ab.ps1 -Feature debris|environment`.
