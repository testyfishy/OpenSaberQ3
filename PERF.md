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

Not yet captured — blocked on the first buildable APK.

| Run | Build | Charging | Thermal | Mean FPS | Min FPS | P5 FPS | On-target % | Stale | Notes |
|---|---|---|---|---|---|---|---|---|---|
| — | upstream `64200ad` @ 4.6.3 | — | — | — | — | — | — | — | — |

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

