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

