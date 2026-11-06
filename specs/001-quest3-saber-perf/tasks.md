# Tasks: Quest 3 hyper-optimized OpenSaber fork

Ordered. Each task names the requirement it serves. `[P]` = parallelisable within its phase.

## Phase 0 — Ground truth

- [ ] T001 `adb devices`, enable `adb tcpip 5555`, connect over Wi-Fi (FR-003)
- [ ] T002 `pm list packages`, `dumpsys package`, record package/version/engine of installed app (FR-003) — **DONE: `org.godotengine.open_saber` 0.5.0 (code 5)**
- [ ] T003 Verify toolchain: Godot 4.3 headless opens project, `sdkmanager --list_installed` shows platform-34/build-tools/ndk (FR-004) — **DONE**
- [ ] T003b Record the renderer (`renderer/rendering_method`) and whether `addons/godotopenxrvendors` is present or required; settles P-2 and gap G-1 (FR-004, FR-021)
- [ ] T004 Write OQ-1 resolution + installed-build table into `UPSTREAM.md` (FR-002, FR-003) — **DONE**
- [ ] T005 License audit of base + any fork we borrow from (FR-018) — **DONE: MIT code, CC-BY Nightsky image only in arpruss**

## Phase 1 — Public fork

- [ ] T006 Fork to `testyfishy/OpenSaberQ3`, keep `upstream` remote (FR-001, FR-002) — **DONE**
- [ ] T007 Pin upstream commit in `UPSTREAM.md` (FR-002) — **DONE: `64200ad`**
- [ ] T008 `ATTRIBUTION.md`: MIT lineage + CC-BY assets (FR-018) — **DONE**
- [ ] T009 Distinct package name in export preset, original preset preserved (FR-020)
- [ ] T010 Confirm map folder discovery + storage permission under new package (FR-027)
- [ ] T011 Clean-clone build → installable APK on device (FR-004, FR-005)

## Phase 2 — Baseline measurement

- [ ] T012 Build unmodified pinned commit = the "before" build (FR-022)
- [ ] T011b Give the **baseline** build a distinct package too (export-preset change only, zero
  code delta) so installing it never overwrites the user's existing app (FR-020, FR-022)
- [ ] T013 Host-side capture script: frame time, dropped frames, thermals, resolution (FR-006, FR-023)
- [ ] T014 Reference scenario definition committed (map, difficulty, start state, hot/cold) (FR-026)
- [ ] T015 Pin CPU/GPU/refresh via `debug.oculus.*`; record method (FR-026)
- [ ] T016 Three baseline runs; compute run-to-run noise band (FR-026)
- [ ] T017 `PERF.md` baseline table (FR-019)
- [ ] T013b Benchmark mode: flag-file triggered deterministic run (`game/scripts/BenchmarkRunner.gd`,
  `tools/perf/benchmark.md`). Reaches the map without touching the VR menu and records per-frame
  timings to `bench.csv`. Unblocks the baseline (FR-006, FR-007, FR-023) — **code complete,
  on-device verification pending**
- [ ] T017c Build the same pinned commit **twice** — Mobile/Vulkan and Compatibility/GLES3 — and
  measure both, because the installed app runs Compatibility while `project.godot` declares
  Mobile (T-10). The winner becomes the baseline renderer (FR-030)
- [ ] T017b Fix the inert MSAA key **alone** and measure it as the first change — a
  known-direction change that validates the whole measurement rig before the hard diagnostic
  work (FR-011, FR-021)

## Phase 3 — Hit registration

- [ ] T019 Pose record/replay harness with injectable timestep (FR-024)
- [ ] T020 Miss logger: closest approach per miss (FR-025)
- [ ] T020b Build an "instrumented-before" = pinned commit + recorder/logger only; prove
  instrumentation does not change behaviour (identical hit set with and without it) (FR-024)
- [ ] T019b Bot workload (FR-034): `game/scripts/BotDriver.gd` drives head sway on `XROrigin3D`
  and swings each saber through the real `SwingableRayCast` at each note's hit time, from the
  song clock, with a deterministic `miss_percent` pass. Implemented and headless-verified;
  **on-device cut verification pending** (check `bot_score_good` > 0)
- [ ] T019c Calibration (FR-035): 3 worn runs on a dense map; accept the bot only if its CPU&GPU
  mean/p95 and peak debris load meet or exceed the worn medians
- [ ] T020c Capture the **baseline miss rate** before touching any setting (FR-025)
- [ ] T018 THEN replace inert `common/physics_fps` with `physics/common/physics_ticks_per_second`;
  log the actual tick to prove it changed (FR-009)
- [ ] T021 Deterministic miss reproduction, root-cause attribution (FR-010)
- [ ] T022 Fix cadence/geometry/duplicate-emission cause (FR-008, FR-009, FR-010)
- [ ] T023 Idempotent per-note cut handling (FR-010)
- [ ] T024 Regression: 20-map set loads and plays (FR-016, SC-007)
- [ ] T025 Behavioural parity via the replay harness: the same pose trace must produce the same
  score on upstream as on the fork (FR-015)

## Phase 4 — Clarity

- [ ] T026 Measure 4× MSAA cost properly (settings key already corrected in T017b) (FR-011, FR-021)
- [ ] T027 Add render scale multiplier settings + UI (FR-011, FR-012)
- [ ] T028 Sweep scale × MSAA (foveation only if T003b proves it exists on this renderer); pick
  the SC-005 point (FR-012)
- [ ] T029 Verify GPU headroom — GPU time ≤85% of the 13.9 ms budget hot (SC-005)

## Phase 5 — Hitches

- [ ] T030 On-device trace: attribute every over-budget frame (FR-014)
- [ ] T031 Fix named cause #1, measure (FR-013)
- [ ] T032 Fix named cause #2, measure (FR-013)
- [ ] T033 15-minute sustained run; SC-002/003 (FR-013)

## Phase 6 — Endurance

- [ ] T034 10 load/unload cycles, memory sampling (SC-008)
- [ ] T035 Quality presets + automatic fallback (FR-017)

## Phase 6b - Stress test and bisection (planned; needs the headset on adb)

The headset has been off adb for every attempt so far, so none of this has run.

### S1. Everything on, long run
- Enable every visual and audio feature: floor light, halos, note emission, hit flash, per-note
  colour, event tint, floor grid, sky, trail, wall fresnel, debris cap, mirrors, bloom.
- Flag: 900 s, `refresh_hz=120`, `detection=analytic`, bot enabled.
- Record: `thermal_status` start and end, dropped frames per 20-second bucket,
  `refresh_rate_final` (does the runtime drop us to 72 Hz?), GPU `App=` mean/p95, main-thread p95.
- PASS: >= 99.5 % of frames on vsync for the whole run, `refresh_rate_final` still 120, no crash,
  no `SHADER ERROR`.

### S2. If S1 fails - bisect in short bursts
Do not guess which feature is expensive. Halve the suspect set, 120 s per run, ABAB order:
1. Reproduce with everything on in 120 s to confirm the failure is repeatable.
2. All gated features OFF (trail, wall fresnel, debris cap, mirrors, bloom), free ones still on.
   Pass => the cost is in the gated set; fail => it is in the free set or the base build.
3. Binary search within whichever half failed: enable half of those features, 120 s each, until a
   single feature reproduces the drop on its own.
4. For the guilty feature, measure it alone against baseline, then decide: off by default, reduce
   its cost parameter, or keep it and document the trade.
5. Record every step in `PERF.md` with the settings used and the numbers, kept or reverted.

### S3. Defaults
Whatever S2 concludes becomes the shipping default (FR-051). Anything that cannot hold the budget
stays available but OFF, and is named in the release notes so players know why.

## Phase 7 - Publish
- [ ] T036 Clean-machine build docs (SC-001)
- [ ] T037 Complete `PERF.md` kept/rejected table (FR-019)
- [ ] T038 Release APK + install note (FR-019)
- [ ] T039 G4 final review + spec drift check
