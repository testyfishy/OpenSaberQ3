# Feature Specification: Quest 3 hyper-optimized OpenSaber fork

**Feature Branch**: `001-quest3-saber-perf`

**Created**: 2026-11-01

**Status**: In progress — Approved (G0, 2026-11-01); plan approved (G1, 2026-11-01)

**Input**: User description: "Fork OpenSaber to a public GitHub repo and hyper-optimize it for Meta Quest 3 (clarity, frame stability, hit registration) while keeping game logic and BeatSaver map compatibility."

## Intent

Take the existing open-source Beat Saber clone the user actually plays on their Meta Quest 3,
publish it as a public fork under their GitHub account with upstream history and attribution
intact, and make it measurably better on Quest 3 specifically: sharper image, stable frame
pacing, and hit registration that does not silently drop valid swings. Game logic and
BeatSaver map compatibility are preserved, not rewritten.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Public fork exists and builds from scratch (Priority: P1)

The user (and any community member) can clone the public fork on a clean machine, follow one
documented command, and produce an installable APK that runs on a Quest 3.

**Why this priority**: Without a reproducible build there is no project, no community
contribution, and no way to attribute a measurement to a change.

**Independent Test**: Clone into a fresh directory, run the documented build command, install
the resulting APK on the Quest 3, launch it, and load one BeatSaver map.

**Acceptance Scenarios**:

1. **Given** a clean checkout of the fork, **When** the documented build command runs, **Then**
   it produces a signed-if-needed APK without manual IDE steps.
2. **Given** that APK, **When** installed via `adb install`, **Then** the app launches to the
   song menu and plays a BeatSaver map to completion.

---

### User Story 2 - The user can see the improvement, not hear about it (Priority: P1)

Every optimization lands with a before/after measurement taken on the user's own headset,
recorded in the repo.

**Why this priority**: The user's complaint is subjective ("poor", "hitches", "misses"). A
fork that claims speed without numbers is indistinguishable from a rebrand.

**Independent Test**: A `PERF.md` (or equivalent) in the repo lists, per change, the metric, the
before value, the after value, and the method used to capture both.

**Acceptance Scenarios**:

1. **Given** a proposed optimization, **When** it is evaluated, **Then** the same scripted
   scenario is captured before and after with the same instrumentation.
2. **Given** a claimed win that does not reproduce, **When** reviewed, **Then** it is reverted
   rather than kept.

---

### User Story 3 - Sabers stop missing valid hits (Priority: P1)

Swings that visually and physically pass through a note register, at the frame rates the game
actually achieves on Quest 3.

**Why this priority**: This is the complaint that most damages enjoyment, and it is the one
most likely to have a concrete, findable root cause (sampling cadence, collision precision,
frame drops) rather than a subjective one.

**Independent Test**: A deterministic replay of recorded controller poses produces an identical
hit set across runs and across frame-rate variations; on-device play produces no miss reported
as "obvious pass-through".

**Acceptance Scenarios**:

1. **Given** a recorded pose trace that passes a saber through a note at a valid angle,
   **When** replayed at both nominal and degraded frame rates, **Then** the note registers
   as cut in both cases.
2. **Given** a sustained frame-rate drop below nominal, **When** the player swings,
   **Then** hit detection still uses the correct swept path, not a single sampled frame.

---

### User Story 4 - Sharper image at the same or better frame rate (Priority: P2)

The user stops seeing a soft, low-resolution image compared with native Quest 3 titles, while
frame pacing does not regress.

**Why this priority**: Clarity is what makes the headset feel premium, but it is worthless if
bought with hitching, so it ranks below stability.

**Independent Test**: Measured rendered pixels per eye (and OpenXR recommended render scale)
increase while the frame-time distribution stays within budget on the reference map.

**Acceptance Scenarios**:

1. **Given** the reference map, **When** rendering at the new settings, **Then** effective
   per-eye resolution is measurably higher than baseline.
2. **Given** the new settings, **When** frame timing is captured, **Then** the 99th-percentile
   frame time still meets the target budget.

---

### User Story 5 - Sustained play does not degrade (Priority: P2)

A 15-minute session on Quest 3 keeps its frame rate and does not thermally throttle into a
stutter, and does not leak memory across song loads.

**Why this priority**: Burst benchmarks lie on a fanless headset; a fork that is fast for 90
seconds is not actually better.

**Independent Test**: 15-minute scripted session capturing frame timing and memory over time,
plus 10 consecutive song load/unload cycles.

**Acceptance Scenarios**:

1. **Given** a 15-minute session, **When** timing is sampled across the whole run, **Then** the
   final five minutes are not materially worse than the first five.
2. **Given** 10 song load/unload cycles, **When** memory is sampled, **Then** it returns to a
   bounded steady state rather than climbing monotonically.

---

### Edge Cases

- Headset on battery vs. charging (Quest 3 raises clocks when charging) — measurements must
  record which state was used, and comparisons must match.
- Thermals already saturated from prior play — a cold-start measurement and a hot measurement
  are both required.
- BeatSaver maps using v2 vs v3 format, and maps with unsupported features (NJS/NJS-based
  modded characteristics, bombs, walls, arcs/chains) — must still load or fail visibly, never
  silently mis-hit.
- Songs with embedded video or unusually large audio files.
- Frame rate dips during song load (shader compilation) — must not be counted as gameplay
  hitch when deciding pass/fail, but must be documented.
- No network available on the headset (in-game downloader fails) — offline map loading must
  still work.
- A player mid-song disconnects a controller or the headset sleeps.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The fork MUST exist as a public GitHub repository under the user's account,
  created as a true fork so upstream commit history and MIT license are preserved.
- **FR-002**: The fork MUST document the exact upstream repository, branch, and commit it was
  taken from, and remain able to merge upstream changes.
- **FR-003**: The fork MUST record the identity of the build currently installed on the user's
  Quest 3 (Android package name, version, and upstream origin) as the measurement baseline.
- **FR-004**: The repository MUST build a runnable Quest 3 APK from a clean clone with a
  documented, pinned toolchain (engine version, export templates, Android SDK/NDK, JDK).
- **FR-005**: The build MUST be reproducible enough that a second clean build produces a
  functionally identical APK.
- **FR-006**: The fork MUST provide on-device measurement instrumentation sufficient to capture,
  per frame, CPU and GPU time, dropped/reprojected frames, effective render resolution, and
  sustained thermal state.
- **FR-007**: Measurements MUST be capturable without a debugger attached, in a form that
  survives the session (on-device log file or host-side capture).
- **FR-008**: Hit registration MUST use swept-path (not single-frame point) collision for saber
  tips and blades. Upstream already does this (T-1), so the requirement is to preserve it while
  fixing the observed misses; it MUST NOT be regressed to point casting.
- **FR-009**: For the same controller pose trajectory, hit registration MUST produce the same
  hit set at any render frame rate. A fixed simulation tick that is not aligned to pose sampling
  is part of the defect (T-2), not a mitigation, so alignment or interpolation MUST be
  established rather than assumed.
- **FR-010**: Any source of dropped, duplicated, or mis-timed collision reports (polling
  cadence, per-sub-ray duplicate emission, prediction, pose history) affecting hit accuracy MUST
  be identified by measurement and eliminated, and hit handling MUST be idempotent per note.
- **FR-021**: All OpenXR rendering levers (render target size multiplier, fixed foveated
  rendering level, VRS, MSAA mode) MUST be explicit, documented settings rather than engine
  defaults, and MUST be validated on-device before being called an optimization.
- **FR-030**: The rendering backend (Compatibility/GLES3 vs Mobile/Vulkan) MUST be chosen by
  measurement, not assumption, because the build currently installed on the user's headset runs
  Compatibility while `project.godot` declares Mobile. *(Added 2026-11-01 after on-device
  verification.)*
- **FR-031**: Frame pacing MUST be owned by the XR compositor. The app MUST NOT impose an
  in-engine frame limiter (`Engine.max_fps` stays 0); the refresh rate MUST instead be selected
  through OpenXR (`OpenXRInterface.display_refresh_rate`, XR_FB_display_refresh_rate), and
  `adb setprop debug.oculus.refreshRate` used only to pin conditions during measurement.
  *(Added at G2, 2026-11-01.)*
- **FR-032**: Meta dynamic resolution and application spacewarp MUST remain disabled unless a
  measurement proves they fix a specific class of missed frame; both mask instability rather than
  remove it, and spacewarp produces artifacts on fast thin geometry. *(Added at G2.)*
- **FR-033**: Spike sources MUST be attributed before averages are optimized, because a missed
  frame in this workload is a spike (shader/pipeline compile, node spawn/free, per-frame
  allocation, audio decode or file IO on the main thread) rather than a slow mean.
  *(Added at G2.)*
- **FR-034**: The reference workload MUST be a deterministic in-engine bot that plays the map
  (crossing each note at its hit time in the required cut direction through the real swept
  collision path), not a static or non-cutting scene and not a human. A workload that never
  cuts leaves debris, slice particles, scoring and rumble idle and flatters every build.
  *(Added at G2 on user request, 2026-11-01.)*
- **FR-035**: The synthetic workload MUST be calibrated against real play and MUST fail closed:
  it is only accepted if its CPU&GPU mean and p95 are each at least the median of the worn
  calibration runs, and its peak debris/particle load is at least the worn peak. Any later worn
  run that exceeds the synthetic p95 invalidates the workload until it is fixed.
  *(Added at G2.)*
- **FR-036**: A human is required only for (a) the one-time calibration runs, (b) recalibration
  after a renderer or effects change that alters cost per cut, and (c) final release sign-off.
  Every other gate runs on the bot. *(Added at G2.)*
- **FR-037**: Every measurement run MUST record CPU/GPU performance levels, clock MHz, `GPU%`,
  `CPU%` and temperature, because Quest 3 moves these dynamically and a cheap frame can read as
  expensive at a low clock. Comparisons MUST pin the levels or state that they were not pinned.
  *(Added at G2 — corrected the baseline reading.)*
- **FR-038**: All note, debris, chain and wall materials/shaders MUST be prewarmed off-screen
  during load, so the first note of a song cannot produce a multi-hundred-millisecond
  shader/pipeline compilation hitch. *(Added at G2.)*
- **FR-039**: Clarity levers MUST be applied in the measured order MSAA → render-target scale →
  anisotropy → fixed foveation, and glow, post-processing and shadows MUST NOT be increased for
  perceived sharpness, since full-screen passes break tiling without adding sharpness.
  *(Added at G2.)*
- **FR-022**: The "before" in every comparison MUST be the unmodified upstream commit built
  with the pinned toolchain — not the APK currently installed on the headset. The installed
  build may differ in engine version and export settings, so it is a reference point only.
  *(Added at G0.)*
- **FR-023**: Frame metrics MUST be capturable host-side (logcat / `VrApi` / OVR Metrics) as
  well as in-app, because in-app instrumentation cannot measure the installed baseline APK.
  *(Added at G0.)*
- **FR-024**: A controller-pose record/replay harness MUST exist, with an injectable timestep
  and note motion accounted for, because SC-004 and FR-009 cannot be tested without one.
  *(Added at G0.)*
- **FR-025**: Every missed hit in a diagnostic build MUST be logged with the saber's closest
  approach to the note, so a miss can be attributed to cadence, geometry, or player error
  instead of being argued about. *(Added at G0.)*
- **FR-026**: A/B protocol: refresh rate and CPU/GPU levels pinned via `debug.oculus.*`
  setprops, ABAB ordering with cooldown, at least three runs per variant, and a change is only
  a win if it exceeds run-to-run noise. *(Added at G0.)*
- **FR-027**: Changing the Android package name for side-by-side install MUST NOT break map
  folder discovery or storage permissions. *(Added at G0.)*
- **FR-028**: The fork MUST NOT use the "Beat Saber" name, logo, or store-listing styling in
  the app name, icon, repo description, or any promotional text, and MUST NOT imply affiliation
  with Beat Games or Meta. Game *mechanics* are not restricted; their *brand* is.
  *(Added post-G1 at user request.)*
- **FR-029**: Every shipped asset MUST have recorded provenance (upstream MIT, CC-BY with
  attribution, or original). No asset may be extracted from Beat Saber or any other commercial
  title; no decompilation of commercial binaries at any point. *(Added post-G1 at user request.)*
- **FR-011**: Rendering MUST support raising effective per-eye resolution and image sharpness
  while remaining within frame budget.
- **FR-012**: Rendering MUST apply Quest-appropriate GPU cost reductions (fixed foveated
  rendering / variable rate shading, MSAA and post-processing budget) with measured justification
  for each.
- **FR-013**: Frame pacing MUST be measured and kept stable; sustained frame time percentile
  targets MUST be met on a reference map.
- **FR-014**: Hitch sources (runtime object spawning, garbage collection, shader pipeline
  compilation, disk IO during play) MUST be identified by measurement and addressed, not
  guessed at.
- **FR-015**: Game logic (note timing, scoring window, cut direction rules, difficulty
  mapping) MUST remain behaviorally equivalent to upstream except where a documented bug fix
  changes it.
- **FR-016**: BeatSaver map compatibility MUST NOT regress: all maps that load at baseline MUST
  still load and play.
- **FR-017**: Quality settings MUST be exposed as presets that can be switched at runtime, with
  a safe fallback that reduces cost automatically rather than stuttering.
- **FR-018**: The fork MUST NOT include proprietary Beat Saber assets; all shipped assets MUST
  be MIT/CC-compatible or user-supplied.
- **FR-019**: The repository MUST contain a performance record listing each optimization with
  metric, before, after, and capture method, plus any rejected optimization and why.
- **FR-020**: The fork MUST be installable alongside the existing installed app (distinct
  package name or documented uninstall path) so the user can A/B the two.

### Technical Baseline (measured 2026-11-01, upstream `godot-4-port`)

Evidence gathered by shallow-cloning `leandrodreamer/BeepSaber@64200ad` (Mar 2025) and
`arpruss/OpenSaberPlus@8c5295c` (Jul 2026) and reading the code. These findings constrain the
requirements below; they are facts, not hypotheses.

| # | Finding | Evidence | Consequence |
|---|---------|----------|-------------|
| T-1 | Hit detection **already** uses swept segmented raycasts (8 sub-rays interpolated between physics frames, skipped below 35 mm) | `game/scripts/SwingableRayCast/SwingableRayCast.gd:8,18,88-126` | FR-008 cannot claim a new feature; the job is to find why hits still miss. |
| T-2 | Hit sampling runs on the **physics tick**, which is **not** 72 Hz: `common/physics_fps` is the Godot 3 key name and Godot 4 ignores it, so physics falls back to the 60 Hz default | `project.godot` `[physics] common/physics_fps=72`; Godot 4 uses `physics/common/physics_ticks_per_second` | Simulation and render rates are mismatched (60 vs 72). Some frames get a tick with almost no motion, which interacts with the 35 mm sweep floor (T-1) to drop casts. This is the leading hypothesis for the user's misses. |
| T-3 | Saber collision is 8 discrete rays + one core ray, each emitting `area_collided` independently | `SwingableRayCast.gd:92-95,103-113` | Same area can be reported multiple times per tick; cut handling must be idempotent or it corrupts direction/speed scoring. |
| T-4 | No OpenXR render-scale, foveation, or VRS setting exists in `project.godot` | `project.godot [rendering]` has only `rendering_method=mobile`, ETC2/ASTC, `msaa=6` | Clarity is at engine defaults. This is the single largest untapped lever. |
| T-5 | `quality/filters/msaa=6` is a **Godot 3** key; Godot 4 reads `rendering/anti_aliasing/quality/msaa_3d` and ignores it | `project.godot` `quality/filters/msaa=6` vs Godot 4 setting name | **MSAA is off.** Edges are aliased, which reads as "low resolution" and is a large part of the user's clarity complaint. Certain win once enabled and cost-measured. |
| T-6 | `3d/physics_engine="Bullet"` is a **Godot 3** key; Godot 4 accepts `GodotPhysics3D`/`Jolt` and ignores the old value | `project.godot` `3d/physics_engine="Bullet"` vs Godot 4 `physics/3d/physics_engine` | Silently falls back to the default engine. No Bullet tuning is in effect; raycast cost and reliability are unexamined. |
| T-9 | All three above are Godot 3 leftovers in a Godot 4 project | `project.godot` as shipped by upstream and by `arpruss/OpenSaberPlus` | The fork inherits dead configuration. Any claimed "tuned" build before this is corrected was tuned by string, not by effect. Measurement must precede tuning. |
| T-10 | The installed 0.5.0 build runs the **Compatibility (GLES3)** renderer on Adreno 740, not the Mobile/Vulkan renderer `project.godot` declares | `adb logcat` stdout: `OpenGL API OpenGL ES 3.2 … Compatibility`; `files/shader_cache` is 12/12 `*GLES3*` | Renderer is an unvalidated unknown (FR-030). Compatibility is also the renderer where `xr/openxr/foveation_level` is known to work, so the earlier "foveation is unreachable" conclusion (P-2) is reversed unless Mobile wins measurably |
| T-11 | Installed app is at pure defaults: `files/config.ini` is 0 bytes; 10 songs installed; maps live in `user://OpenSaber/Songs` | `adb run-as` on the debug-signed APK | The user's complaint is about an untuned build. Baseline reference scenario can use the bundled `TheFatRat_Timelapse` |
| T-7 | Both candidates are the same Godot 4 lineage; arpruss is a superset with 16 months more work | repo metadata, `git log` | Base choice is a real fork decision (see OQ-1), not a formality. |
| T-8 | Nearest competing fork (`arpruss/OpenSaberPlus`) shares identical physics and rendering settings | `arpruss/project.godot` | No fork on this lineage has done the XR render-tuning work. The niche is genuinely open. |

### Key Entities

- **Upstream snapshot**: repository, branch, commit hash, license, engine version.
- **Baseline build**: the APK currently on the headset — package name, version, origin.
- **Reference scenario**: a fixed map + fixed difficulty + fixed scripted/recorded input used
  for every before/after comparison.
- **Measurement run**: timestamp, headset state (charging/battery, thermal, refresh rate),
  scenario, and the resulting timing statistics.
- **Optimization record**: change, hypothesis, measured effect, verdict (kept/reverted).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A clean clone builds an installable APK on a machine that has never built this
  project, following only the repo's documentation.
- **SC-002**: On the reference scenario, at least 99% of frames meet the **13.9 ms** budget
  (72 Hz) measured on-device, sustained over 15 minutes, with the headset hot and not charging.
- **SC-003**: 99th-percentile frame time stays within **13.9 ms** (no long-tail hitches), measured
  over the same 15-minute run. A frame is only "over budget" if it misses by more than the
  measured run-to-run noise defined in FR-026.
- **SC-004**: A deterministic pose replay that passes a saber through a note registers the cut
  in 100% of trials, at both nominal and degraded frame rates, and produces an identical hit
  set across repeats of the same trajectory.
- **SC-005**: Effective per-eye render scale reaches **≥1.2× linear (≈+44% pixels)** versus the
  FR-022 baseline **with 4× MSAA confirmed active**, while SC-002 and SC-003 still hold hot, at
  the same refresh rate. Falsified if GPU time exceeds ~85% of the 13.9 ms budget after fixed
  foveated rendering is applied. *(Rewritten at G0: pixel count alone is not sharpness; aliasing
  and MSAA state matter as much.)*
- **SC-006**: *(Non-gating, informational.)* Song load time to playable improves versus baseline.
  No user complaint is attached to load time, so it must not block a release.
- **SC-007**: 100% of a fixed set of at least 20 representative BeatSaver maps (mixed v2/v3,
  mixed note counts, with and without walls/bombs/chains) load and play to the first chorus
  without error.
- **SC-008**: Memory after 10 load/unload cycles is within 20% of the value after the first
  cycle (no unbounded growth).
- **SC-009**: *(Non-gating, manual, single evaluator.)* The user reports the build is visibly
  sharper and more stable in blind play compared with the installed app, and can state which
  build they were playing without being told. Reported, not gating, because it is one
  subjective observer.
- **SC-010**: Zero stale frames during gameplay across a hot 15-minute run at the selected
  refresh rate. *(Added at G2 — this, not average FPS, is the user's real complaint.)*
- **SC-011**: Headroom: during gameplay in a hot 15-minute run, the 99th-percentile GPU time and
  the 99th-percentile CPU time (main and render threads) are each **≤ 75%** of the frame budget,
  with a maximum of **≤ 90%**. At 72 Hz the budget is 13.9 ms; at 90 Hz, 11.1 ms.
  *(Added at G2.)*
- **SC-012**: If Mobile/Vulkan wins the renderer comparison, it wins by measurement: zero compile
  hitches and a p99 CPU time at least as good as Compatibility over three hot runs. Otherwise
  Compatibility remains the base. *(Added at G2, operationalises FR-030.)*
- **SC-013**: After the clarity sweep, on a cold run of the reference workload, `App=` (GPU) p95
  is ≤ 9 ms (~65% of the 13.89 ms budget) and dropped-frame events plus stale samples do not
  exceed the Baseline v0 median plus its measured spread. *(Added at G2.)*

## Assumptions

- The user's headset is a Meta Quest 3, in Developer Mode, reachable over Wi-Fi `adb`.
- The engine lineage is Godot 4 + OpenXR (to be confirmed by FR-003 detection); no Unity
  license or Unity project migration is in scope unless detection disproves this.
- The user is willing to install test APKs and play the reference scenario several times.
- Upstream is MIT-licensed, so a public fork with attribution is permitted.
- "Hyper-optimization" is delivered as measured, incremental wins on this device, not a
  from-scratch rewrite; the first public release targets the P1 stories.
- Target refresh rate is 72 Hz initially (Quest 3 default for this class of app), with 90 Hz
  evaluated only if the frame budget allows and the user prefers it.

## Risks

- **R-1** Godot 4.3's mobile (Vulkan) renderer may not support fixed foveated rendering. If it
  does not, choosing between the Compatibility renderer and an engine upgrade is a G2 decision,
  not a unilateral call.
- **R-2** The `godot_openxr_vendors` plugin version is not pinned upstream; an unpinned vendor
  plugin across two measurements invalidates the comparison. Pin it before the baseline.
- **R-3** Thermal noise on a fanless device can bury small gains; ABAB ordering and an
  above-noise threshold (FR-026) are mandatory, not optional.
- **R-4** Device detection may show the installed app is a lineage we have not examined.
- **R-5** `.gitignore` excludes `/addons/godotopenxrvendors`, so the OpenXR vendor plugin is
  absent from a clean clone and its version is unpinned (gap G-1). If it turns out to be
  required, the baseline build is not reproducible until it is pinned (OQ-4).
- **R-6** Wi-Fi ADB perturbs thermals and timing. Measurements must be taken consistently over
  USB with charging state recorded, or over Wi-Fi on battery — never mixed (G1).

## Out of Scope

- Rewriting the game engine or porting to a different engine.
- Multiplayer, leaderboards, accounts, or any networked feature.
- New gameplay modes, campaign, or progression systems.
- Cosmetic redesign of the UI or menus beyond what clarity/perf requires.
- PCVR, SteamVR, Quest 2, Quest Pro, or Pico support (builds may keep working; tuning is not
  promised).
- Distributing or extracting proprietary Beat Saber content.
- Publishing to the Meta Store or App Lab.
- Legal advice on trademark or naming; naming must simply avoid implying affiliation.

## Open Questions

- **OQ-1** ~~Which upstream repository is installed~~ — **RESOLVED 2026-11-01 by `adb`:
  `org.godotengine.open_saber` 0.5.0 (code 5) ⇒ `leandrodreamer/BeepSaber@godot-4-port`.
  Evidence in `UPSTREAM.md`.**
- **OQ-2** `[NEEDS CLARIFICATION: public repo name — proposed `OpenSaberQ3`, fork already created under that name; say so if it should be renamed]`
- **OQ-3** Target refresh rate: 72 Hz baseline for headroom, or 90 Hz for smoothness, at the cost
  of resolution. Needs one play-test comparison from the user.
- **OQ-4** `[NEEDS CLARIFICATION: is the `godotopenxrvendors` plugin (excluded by .gitignore) required
  to reproduce the shipped APK? — settles gap G-1 and whether foveation is reachable on 4.3]`

## Consultation Log

| Gate | Asked | Verdict | Action taken |
|------|-------|---------|--------------|
| G0 | Spec review: base-repo choice, realism of SC-005, root cause of misses, missing requirements | **GO WITH CHANGES** | See below |
| G0 | Base repo while OQ-1 pends | Fork whatever detection identifies (likely leandrodreamer); cherry-pick arpruss fixes individually with their own measurement; read arpruss LICENSE + asset credits before taking any code (NOASSERTION) | OQ-1 still pending on device detection; license audit is now a precondition for cherry-picking |
| G0 | SC-005 realism | Bar is reachable but measured the wrong thing | SC-005 rewritten to ≥1.2× linear **with 4× MSAA confirmed**, hot, same refresh rate; falsified above ~85% GPU budget after FFR |
| G0 | Root cause of misses | Input/physics path, not rendering; Godot 3 keys are inert | T-2/T-5/T-6/T-9 added; hit-registration diagnostics moved ahead of rendering work in the plan |
| G0 | Missing requirements | 6 added + FR-009 reworded | FR-022…FR-027 added; FR-009 now demands frame-rate-invariant hit sets; SC-002/003 budget fixed at 13.9 ms; SC-006/SC-009 made non-gating |
| G1 | P-2: is foveation reachable on Godot 4.3 mobile? Engine: Jolt or stay? Phase order? Task hygiene? | **GO WITH CHANGES** | Foveation not available on 4.3 Mobile/Vulkan ⇒ don't add vendors plugin to mainline, don't upgrade engine for it; clarity = render scale + MSAA + multiplier; 4.6 upgrade moved to optional Phase 5b (5b dropped — see below); stay on GodotPhysics3D, fix sampling instead of solver |
| G1 | Order changes | Applied | T018 (physics key) moved to **after** baseline miss capture (T020c); T017b added = fix MSAA key alone to validate the rig first; Wi-Fi vs USB measurement rule recorded as R-6 |
| G1 | Tasks to add | Applied | T003b (renderer + vendors plugin), T011b (distinct package for the baseline too), T020b (instrumented-before, prove inert), T020c (baseline miss rate), T025 rewritten as replay-harness parity |
| G1 | Task fixes | Applied | T029 typo fixed to ≤85%; T035 simplified to presets + fallback on sustained frame time |
| Post-G1 | User IP concern | Constraint added | FR-028 (no Beat Saber branding/affiliation), FR-029 (asset provenance, no decompilation) |
| G2 | Engine migration: pinned 4.3 cannot import its own assets on a clean clone (LOD-generation crash, 1-byte meshes); user pre-approved an engine upgrade | **MIGRATE** to Godot 4.6.3-stable | D-2 amended; baseline is now "upstream commit built on 4.6.3"; migration is its own commit (D-7); 4.7.2 deferred to an optional measured change (D-8). 4.6.3 also unlocks the ≥4.5 Meta fragment-density path, which weakens the earlier P-2 conclusion that foveation was unreachable |
| G2 | User restated the end goal: super-stable frame times with headroom, paced to the panel refresh rate. Asked for the ordered path, renderer call, headroom criterion, and whether dynamic-res/spacewarp belong | **DECISIVE PLAN** (see below) | FR-031/032/033 and SC-010/011/012 added |
| G2 | Order of work | Spikes before averages | FR-033: attribute spikes (shader/pipeline compile, node spawn, per-frame allocation, audio/IO on main thread) before optimizing averages |
| G2 | Renderer | **Compatibility (GLES3) is the base**; Mobile/Vulkan is the challenger, decided by a three-column capture (installed 4.3 GLES, fork 4.6.3 GLES, fork 4.6.3 Mobile), ranked by stale frames then p99 CPU then p99 GPU | FR-030 operationalised as SC-012; a Mobile win requires zero compile hitches and p99 CPU at least equal |
| G2 | Frame pacing to the panel | No in-engine limiter: `xrWaitFrame` paces, `OpenXRInterface.display_refresh_rate` selects the rate, `Engine.max_fps` stays 0; `setprop` only to pin conditions while measuring | FR-031 |
| G2 | Headroom criterion | Zero stale frames; p99 CPU and GPU each ≤75% of budget, max ≤90%; start at 72 Hz (13.9 ms), step to 90 Hz (11.1 ms) only when that holds | SC-010, SC-011 |
| G2 | Dynamic resolution / spacewarp | Keep both off; they mask instability and spacewarp artifacts on fast thin sabers | FR-032 |
| G2 | First five steps | (1) OpenXR in the fork APK — **DONE 2026-11-01**, `libopenxr_loader.so` packaged, runtime confirmed; (2) capture script across VrApi + OVR Metrics + in-engine timings; (3) baseline the installed 4.3 build; (4) Compatibility vs Mobile three-column run; (5) attribute every spike | T0013 onwards |
| G2 | User rejected worn/human baseline runs as too variable; asked for a standardized scripted workload that genuinely loads GPU and CPU | **APPROVED with one change**: the bot must actually cut notes (a non-cutting path is a flattering microbenchmark) | FR-034/035/036 added; `game/scripts/BotDriver.gd` implemented; head sway on `XROrigin3D` only (timewarp runs regardless of motion, so sway affects culling/overdraw, not compositor cost); human needed only for calibration, recalibration and release sign-off |
| G2 | User asked: where should GPU optimization go to look better efficiently, and what is eating CPU | **GO WITH CHANGES** — see rows below | Baseline reading corrected; plan in PERF.md / tasks |
| G2 | `App=` semantics | **`App=` is GPU time only**; `CPU&GPU=` is frame-to-GPU-completion latency, not cost. The ~4 ms gap is main+render thread + sync, not the compositor | Judge runs on Stale count, dropped-frame events and p99; stop using `CPU&GPU=` as a budget figure |
| G2 | Clock drift | Quest moves CPU/GPU clock levels dynamically, so a cheap frame can still read ~86% | FR-037: record CPU/GPU levels, MHz, `GPU%`, `CPU%`, `Temp` per run; pin levels when comparing |
| G2 | Physics 60 Hz vs 72 Hz display | Aliases: some frames get 0 ticks, some 2 — a hit-registration issue before a cost issue | E2 makes the tick 72 Hz and proves an identical hit set |
| G2 | The 459 ms spike | Missing warm-up, not slowness — first-note shader/pipeline compilation | FR-038: prewarm every note/debris/chain/wall material during load |
| G2 | Clarity lever order and cost | MSAA 4× (~3-7%) → render scale 1.2/1.3/1.4 (+10/16/24%) → aniso 4× (<1%) → fixed foveation (saves 5-10%, spend on scale). Skip glow, post, shadows | FR-039; stop rule `App=` p95 ≤ ~65% (9 ms) cold, no regression in dropped events/Stale |
| G2 | Renderer before clarity | Compatibility/GLES3 gets cheap MSAA + Qualcomm foveation and less CPU on Quest; costs differ per backend, so do not tune clarity twice | E1 (renderer A/B) runs before the clarity sweep |
| G2 | Raycast CPU suspicion | 18 rays × 60 ticks ≈ 1k queries/s against a few dozen Area3Ds ≈ 0.1-0.3 ms/tick — probably a rounding error | Measure with `Time.get_ticks_usec()` before optimizing anything |

| G1 | Benchmark-mode implementation (delegated to `coder`, its own consult) | **GO WITH CHANGES**, all applied: flag read from `user://` then external app dir, renamed `.consumed` before the run, proximity/focus documented plus a `focused` CSV column, `song_end` only after playback was seen, separate `process_delta_usec` column, verified with a 3-second headless run | `game/scripts/BenchmarkRunner.gd` + a 9-line guarded hook in `BeepSaber_Game._ready()`; 437 samples at 3 s, mean 6.87 ms, p99 10.03 ms, max 14.62 ms on desktop headless |

