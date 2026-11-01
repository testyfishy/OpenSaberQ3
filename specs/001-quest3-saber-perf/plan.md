# Implementation Plan: Quest 3 hyper-optimized OpenSaber fork

**Spec**: `specs/001-quest3-saber-perf/spec.md` (Status: Approved at G0)

**Status**: Draft — pending G1

## Strategy

Measure first, then change one thing at a time, and only keep changes that beat the
run-to-run noise. The user's three complaints (misses, soft image, hitches) are treated as
three separate investigations with three separate evidence trails, because the code review at
G0 showed they have different causes and the miss complaint is *not* a rendering problem.

The order below is deliberately not "rendering first". G0 established that hit registration
suspicions live in the physics/input path and that three rendering settings the upstream author
believed were active are inert Godot 3 keys (T-9). Rendering work on top of a broken simulation
tick would produce a build that looks better and feels worse.

## Decisions taken (and why)

| # | Decision | Basis |
|---|----------|-------|
| D-1 | Base = the repository identified by FR-003 detection; arpruss changes are cherry-picked individually, never merged wholesale | G0 verdict; arpruss targets Godot 4.6 vs upstream 4.3, so a wholesale base swap invalidates every before/after pair |
| D-2 | Keep the base's engine version for the baseline build; any engine upgrade is a separate, separately measured change | Same reason; also R-2 |
| D-3 | arpruss code is usable: his `LICENSE` shows MIT for code ("Copyright (c) 2020-25 Holger Dammertz and Alexander Pruss") with one CC-BY-4.0 image (Nightsky) | Resolves the G0 license concern; attribution text must travel with any cherry-pick |
| D-4 | The "before" build = unmodified pinned upstream commit on the pinned toolchain (FR-022), not the installed APK | G0 |
| D-5 | Host-side metrics (logcat `VrApi`/OVR Metrics) are the primary numbers; in-app instrumentation is secondary | FR-023; in-app code cannot measure the installed APK |
| D-6 | Side-by-side install via distinct package name, so A/B needs no uninstall | FR-020, FR-027 |

## Open decision for G1

- **P-1** Physics engine and tick: fix the Godot 3 key to `physics/common/physics_ticks_per_second`, and
  decide between staying on GodotPhysics3D at a pose-aligned tick versus moving to Jolt (4.4+).
  Jolt may require an engine upgrade that conflicts with D-2.
- **P-2** Does Godot 4.3's mobile (Vulkan) renderer support fixed foveated rendering / VRS at all
  (R-1)? If not, the clarity story needs a different lever (render scale + MSAA + resolution
  multiplier only) or an engine upgrade.

## Phases

### Phase 0 — Establish ground truth (no code changes)

1. Connect headset, record package/version/engine of the installed app (FR-003).
2. Tag every third-party/fork lineage found, note license (FR-018).
3. Verify the toolchain bootstraps and Godot opens the project headless. (FR-004)

**Exit**: OQ-1 answered; a table of "what is installed" committed.

### Phase 1 — Public fork with intact history

1. Fork detection-identified repo to `testyfishy` as public, true fork (FR-001).
2. Record upstream repo/branch/commit in `UPSTREAM.md`; keep `upstream` remote (FR-002, FR-019).
3. Add `ATTRIBUTION.md` covering MIT lineage + any CC-BY assets (FR-018).
4. Rename to a distinct package (`FR-020`) and verify map-folder discovery still works (FR-027).

**Exit**: `git remote -v` shows upstream; repo public; clean clone builds (FR-004/005).

### Phase 2 — Measurement before optimization

1. Build the unmodified pinned commit; install; confirm it runs (FR-022).
2. Capture host-side metrics: sustained frame time, dropped/reprojected, thermal
   (`dumpsys thermalservice`), per-eye resolution, at pinned CPU/GPU levels (FR-006/023/026).
3. Define reference scenario: one map, one difficulty, fixed start state, hot and cold runs.
4. Write `PERF.md` with the baseline table, including the "no change yet" row (FR-019).

**Exit**: baseline numbers reproducible across 3 runs within noise; noise band quantified.

### Phase 3 — Hit registration (P1, ahead of rendering)

1. Correct the inert Godot 3 physics key; confirm the tick actually changes (T-2/T-9).
2. Build the pose record/replay harness (FR-024) and the miss logger (FR-025).
3. Reproduce a miss deterministically; attribute it to cadence, geometry, duplicate emission
   (T-3), or player error — with logs, not opinion.
4. Fix; prove frame-rate invariance (FR-009, SC-004); re-measure SC-007 map set.

**Exit**: SC-004 and SC-007 pass; PERF.md records the miss rate before/after.

### Phase 4 — Clarity within budget

1. Fix inert MSAA key; measure 4× MSAA cost alone (T-5).
2. Add render-scale multiplier and foveation settings (FR-011/012/021); sweep the
   scale × foveation × MSAA space on the reference map.
3. Select the point that maximises SC-005 while holding SC-002/003 hot.

**Exit**: SC-005 met at 13.9 ms with the headset hot.

### Phase 5 — Hitch hunt

1. Attribute every over-budget frame using on-device traces (FR-014): spawning, GC, shader
   compilation, disk IO, audio decode.
2. Fix only what the trace names; each fix gets its own before/after.

**Exit**: SC-003 holds over 15 minutes (SC-002/003 together).

### Phase 6 — Endurance and safety

1. 15-minute sustained run, hot; 10 load/unload cycles for memory (SC-008).
2. Switchable presets with automatic fallback rather than stutter (FR-017).
3. Blind A/B against the installed app for SC-009.

**Exit**: SC-008 passes; presets switchable at runtime.

### Phase 7 — Publish

1. `README` build instructions from a clean machine (SC-001), pinned versions (FR-004).
2. `PERF.md` complete: every kept and rejected optimization with numbers (FR-019).
3. Release APK + install note; G4 + drift check.

## Requirement coverage

| Requirement | Phase |
|---|---|
| FR-001, FR-002 | 1 |
| FR-003 | 0 |
| FR-004, FR-005 | 1, 7 |
| FR-006, FR-007, FR-022, FR-023, FR-026 | 2 |
| FR-008, FR-009, FR-010, FR-024, FR-025 | 3 |
| FR-011, FR-012, FR-021 | 4 |
| FR-013, FR-014 | 5 |
| FR-015, FR-016 | 3, 4 (regression gates) |
| FR-017 | 6 |
| FR-018 | 0, 1 |
| FR-019 | 2, 7 |
| FR-020, FR-027 | 1 |

## Rollback

- Every optimization is a separate commit; revert is `git revert <sha>` and re-measure.
- Package rename is reversible via the export preset; keep the original `org.godotengine.open_saber`
  preset intact until the side-by-side build is proven.
- Toolchain install is user-scope (`%LOCALAPPDATA%`), no system PATH or registry changes, so
  removal is a folder delete.

## Verification commands (evidence, not adjectives)

```powershell
adb devices
adb shell pm list packages | Select-String -Pattern 'godot|saber'
adb shell dumpsys package <pkg> | Select-String -Pattern 'versionName|versionCode'
adb logcat -d -s VrApi:* | Select-String -Pattern 'FPS=|Frame|Dropped'
adb shell dumpsys thermalservice | Select-String -Pattern 'Temperature|status'
adb install -r build/<apk>
```
