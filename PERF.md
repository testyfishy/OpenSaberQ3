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

## Blocker on the baseline

There is no deterministic way to start a song over `adb`: the main menu is a VR UI, and using a
human player would make every run non-reproducible. Before any tuning number is trusted we need
one of:

- an in-engine benchmark mode (CLI flag that loads the reference map at a fixed difficulty,
  auto-hits notes so debris/particles are included, and exits at the end), or
- a recorded pose replay driving the sabers, which is also what FR-024 needs.

Until one exists, every "after" number would be unverifiable against a "before".


## Optimizations

Kept changes only. Each row must be reproducible from the commit in the last column.

| # | Change | Metric | Before | After | Method | Commit |
|---|---|---|---|---|---|---|
| — | *none yet* | — | — | — | — | — |

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

