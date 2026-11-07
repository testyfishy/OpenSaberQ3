# Feature Specification: 0.7.0 map compatibility — measured corpus and mod-layer fidelity

**Feature Branch**: `027-v07-map-compat`

**Created**: 2026-11-07

**Status**: Released as `v0.7.5-q3` (APK 78,119,544, SHA-256 `D56F8938…`). 0.7.5 adds floor-pinned wall growth with the v0.6 rim, merged/tween-free lightshows, arc head attachment and release-build benchmarks. Noodle animation and custom Chroma environments remain. In-VR checks (wall rim/grow, arc attachment, lightshow smoothness, Noodle placement, audio resume, above/below cue) are pending.

**Input**: Owner, after the BeatSaver feature review: "Fix 360/90 and lightshow/box groups on v7.
Resolve Mapping Extensions precision, Noodle position/rotation/scale/animation/speed, Chroma events
and the bundle-based effects for v7 as long as it does not need closed-source content. Update the
public compatibility position now."

## Context and evidence

- Public policy already published: `README.md` → "Map compatibility", `docs/map-compatibility.md`.
- Current loader gaps (`game/scripts/MapSupport.gd`, `ColorNoteInfo`, `ObstacleInfo`):
  int truncation of Mapping Extensions positions; 90/360 rotation parsed and ignored; Noodle
  rotation/scale/animation and per-object speed/offset ignored; Chroma light events and v4 box-group
  lighting ignored; Unity asset bundles unsupported.
- BeatSaver sample (20 top-rated maps, strict scan): Noodle animation keys 50%, asset bundle 25%,
  Noodle/ME wall placement 30%, Chroma per-note colour 20%, Noodle note position 15%; characteristics
  Standard 51, Lawless 8, OneSaber 3, Lightshow 2.
- Advisor position (strategy consult, 2026-11-07): tiered compatibility with measured corpus first;
  fix silent corruption before features; asset bundles out unless an open-source path exists.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A map says what it needs and whether it plays (Priority: P1)

As a player, every map shows Supported / Partial / Visuals limited, computed from the mapper's
declared requirements, and the pause menu names what is missing.

**Acceptance**:
1. A vanilla v3 map is Supported with no warning.
2. A map with `_requirements: [Noodle Extensions]` is Partial while Noodle transforms are missing.
3. A Chroma-lighting-only map is Supported; the pause menu notes that lighting effects are skipped.
4. The badge survives the library, source filter and a relaunch.

### User Story 2 - Measured rate (Priority: P1)

As the maintainer, I can regenerate a compatibility report over a BeatSaver sample and publish it.

**Acceptance**:
1. One command runs the headless loader over ~300 maps and writes per-map tier + missing features.
2. The report prints Supported / Partial / Visuals-limited shares and the top missing features.
3. The README number is generated from that report, not typed by hand.

### User Story 3 - Mapping Extensions precision (Priority: P1)

Notes and walls placed with precision coordinates appear where the mapper put them.

**Acceptance**:
1. A v2 map with an encoded position (≥1000) places the note at the decoded lane, not the truncated
   one.
2. Float wall position/size is honoured.
3. The harness tiers a precision map Supported and its note positions match the reference within
   1 cm.

### User Story 4 - 90°/360° rotation (Priority: P1)

Maps that rotate the lane ring play as designed, with notes and walls coming from the sides.

**Acceptance**:
1. `rotationEvents` (v3/v4) and v2 type 14/15 rotate subsequent notes, walls, arcs and chains.
2. The 360 corpus tiers as Supported in the harness.
3. No regression for Standard maps (rotation of 0 is identity).

### User Story 5 - Noodle static transforms and animation (Priority: P2)

Noodle notes appear at their custom position, rotation and scale; animated notes move along their
tracks; per-object speed/offset changes apply.

**Acceptance**:
1. `_position`/`_rotation`/`_scale` (and v3 equivalents) place and orient a note as declared.
2. `animateTrack`/note animation moves the object over the declared beats.
3. Per-object `_noteJumpMovementSpeed`/`_noteJumpStartBeatOffset` change approach timing.
4. A Noodle map that used to be Partial becomes Supported; a movement map still plays to the end.

### User Story 6 - Chroma events and v4 lightshow (Priority: P2)

Chroma light/environment events and v4 box-group lighting drive the scene.

**Acceptance**:
1. A Chroma light event changes the light colour at its beat.
2. Environment colour/fog/ring events apply.
3. v4 lightColor/rotation/translation event boxes apply over their beat ranges.
4. Lighting-only maps remain Supported; the visual result matches the event values within tolerance.

### User Story 7 - Bundle effects, open source only (Priority: P3)

Vivify/Cinema/custom-environment maps show their effects where an open-source parser can read the
bundle; otherwise they load with a Visuals-limited badge.

**Acceptance**:
1. The decision and licence of any bundle parser are recorded; no closed-source SDK is used.
2. If integrated, a known Vivify map renders its effect; if not, the badge and log say so.
3. The map's notes remain playable either way.

## Requirements *(mandatory)*

- **FR-001**: A headless corpus harness MUST load a configurable BeatSaver sample (top-rated, latest,
  90/360, OneSaber, Lightshow) through the real loader and write per-map tier + detected/missing
  features.
- **FR-002**: The harness MUST print the Supported / Partial / Visuals-limited shares and the most
  common missing features; the README/docs number MUST be generated from its output.
- **FR-003**: `Info.dat` `_requirements`/`_suggestions` MUST be parsed and combined with detected
  features to produce the badge; `MediaFire`-style requirements unknown to the build MUST not crash.
- **FR-004**: The badge MUST be visible in the library row and the pause menu, with the missing
  feature names.
- **FR-005**: Mapping Extensions positions MUST be decoded to floats for notes, bombs and walls:
  v2 lane/layer values ≥1000 or ≤-1000, the precision cut angle (1000–1360), and the wall `_type`
  height/start-height and width encodings; v3 `x`/`y`/`d` follow the same rules. Lanes outside the
  4×3 grid MUST be allowed, never clamped; no placement field may be int-truncated.
- **FR-006**: 90°/360° rotation MUST apply to notes, bombs, walls, arcs and chains from the event
  beat onward: v2 types 14/15 values 0–7 map to ±15/30/45/60° (or use `_rotation`), v3 `e`
  (early/late) decides same-beat objects, and v4 uses the per-object `r` field. The environment and
  the track MUST follow the same rotation.
- **FR-007**: Noodle static transforms (`_position`, `_rotation` in degrees, `_scale`) MUST apply to
  notes and obstacles for v2/v3 customData.
- **FR-008**: Per-object `_noteJumpMovementSpeed` and `_noteJumpStartBeatOffset` MUST apply to that
  object's approach, independent of the map default.
- **FR-009**: Noodle animation MUST honour `_pointDefinitions`, Heck easings, splines,
  `assignPathAnimation`, `assignTrackParent` and `_definitePosition`, plus `_dissolve`, `_interactable`,
  `_fake`, `_disableNoteGravity` and `_disableNoteLook`, with v3 key names (`coordinates`,
  `worldRotation`, `localRotation`, `size`, `njs`, `spawnOffset`). Tracks MUST be sampled at the
  note's song time and resolved once at load; vanilla maps keep a zero-cost path.
- **FR-010**: Chroma `customEvents` MUST apply light colour, environment colour, fog and ring
  rotation; Chroma `environment`/`_environment` JSON (lookup, active, transform, geometry) MUST
  apply; v4 box-group lighting MUST apply colour/rotation/translation boxes over their ranges.
- **FR-010b**: `assignPlayerToTrack` MUST be treated as gameplay: a map that uses it and is not
  supported is Partial, because it moves the player, not just the scenery.
- **FR-011**: No feature may make a vanilla map slower or change its placement/timing; the 120 fps
  budget and existing probes MUST hold.
- **FR-012**: Every map MUST still load if a feature is missing; the badge and log MUST say what was
  skipped, never a silent half-play.
- **FR-013**: Any bundle/video/script support MUST use open-source components only; licence and
  provenance MUST be recorded in `ATTRIBUTION.md`. No closed-source SDK, asset or service. Bundle
  work is a timeboxed spike that defaults to **Visuals limited** (UnityPy is MIT but Python-only;
  AssetRipper is GPL-3; Vivify shaders and Cinema video are not portable to Godot as-is).
- **FR-014**: Regression maps for each feature MUST live in the harness corpus and run headless.
- **FR-015**: The corpus MUST be a pinned list of BeatSaver map hashes plus a date, downloaded into a
  git-ignored cache. BeatSaver maps MUST NOT be committed; fixtures are synthetic or explicitly
  licensed. SC-001 pins the same list.
- **FR-016**: One per-object transform (float position, worldRotation, localRotation, scale, jump
  speed, jump offset) MUST be shared by Mapping Extensions, 360 rotation and Noodle, so the three
  features cannot disagree.

### Key Entities

- **MapRequirement**: declared/suggested mod names from `Info.dat`.
- **CompatReport**: map id, tier, detected features, missing features, loader errors.
- **Placement**: float lane/layer (note, bomb, wall), decoded from the format.
- **RotationState**: current lane-ring rotation at a beat.
- **NoodleTransform**: position, rotation, scale, jump speed/offset, animation tracks.

## Success Criteria *(mandatory)*

- **SC-001**: The harness runs ~300 maps headless and produces a report; the published rate in
  README matches the report exactly.
- **SC-002**: A Mapping Extensions map places decoded notes within 1 cm of the reference; no
  placement field is int-truncated.
- **SC-003**: The 360 corpus tiers as Supported and plays with lanes rotating; Standard maps are
  unchanged.
- **SC-004**: A Noodle transform map's note position/rotation/scale matches its customData within
  1 cm / 1 degree; an animation map moves as declared.
- **SC-005**: A Chroma light map and a v4 box-group map produce the declared colours within
  tolerance at three sampled beats.
- **SC-006**: Badges match `_requirements` for the regression set (Supported/Partial/Visuals limited
  each covered).
- **SC-007**: No vanilla-map regression: existing probes pass and the 120 fps capture stays within
  the 0.6.4 numbers.

## Out of Scope

- Closed-source SDKs, assets or services; proprietary formats that cannot be read with open-source
  code.
- Arbitrary Heck C# gameplay scripts (a managed mod host is a separate project); such maps badge as
  Partial.
- Online services, account features, or map uploads.
- Rewriting the renderer for bundled shaders beyond what an open-source parser can express.

## Open Questions

- [NEEDS CLARIFICATION: which open-source Unity bundle parser (if any) is acceptable, given its
  licence and maintenance?] — evaluate before FR-013 work; default is Visuals limited.
- [NEEDS CLARIFICATION: should Noodle player/camera movement be treated as gameplay (Partial if
  missing) or as a visual effect?] — assume Partial only when it moves notes into reach, otherwise
  Visuals limited.

## Assumptions

- `_requirements` is the mapper's authoritative statement; detection is a fallback.
- The harness can download a bounded sample and cache it; no BeatSaver API key is needed.
- Asset bundles are Unity-format containers; an open-source reader is feasible for simple cases but
  not for arbitrary shaders/scripts.

## Verification evidence (0.7.1)

- `me_probe`: positions 1000=0, 2000=1, -1000=0, -2000=-1, 1500=0.5; cuts 1000/1090/1180/1270 =
  0/90/180/270 and 2000 any; walls 1000=0, 2000=5, 4000=15, 2304301 = 11.5 layers / 6.0 start.
- Real ME map (`Star Sky`, 6,631 walls): 55/400 sampled notes fractional; parsed without errors.
- Zero-size ME walls clamp to 1 cm in the mesh and collision box.
- Regression: SETTINGSTEST, VERIFYSCHEMA 56, library/arc/ME probes pass.

## Verification evidence (0.7.3)

- `noodle_box_probe`: v2 `_position`/`_rotation`/`_scale` → pos 1.50/2.50, Euler (0, 90, 0),
  scale 1.5; wall pos 0.50/1.00, scale (2, 1, 1). v3 `coordinates`/`localRotation`/`size`
  (including `{x, y}` position and scalar size) → pos -0.50/3.25, rot z 45, scale 2.0; wall
  pos 1.00/0.00, scale (1, 2, 1).
- Box groups: index `c` 0/1 with `s=1` → basic `i` 5/1 at the group beat; `s=0` → `i` 0, `f` 0;
  literal RGB payload → `customData.color` with `f` from `s`; group 3 → `et` 3.
- Pool reuse: notes reset rotation/scale at spawn; walls assign rotation (or zero), so a Noodle
  object cannot leak its transform into a later vanilla object.
- Parse clean; LANEPROBE, MEPROBE, SETTINGSTEST, VERIFYSCHEMA 56 pass.
- Pending on headset: Noodle placement/rotation, box-group colours, resume-from-idle audio,
  above/below audibility.

## Scoped change: 0.7.4 box-group fidelity and Noodle cut angle

**Symptom**
1. A box-group event with `i:2` (extend) creates a new light event instead of holding the previous
   one, and `i:1` (transition) is emitted as an instant on, so authored fades become cuts.
2. Box groups whose environment group id is above 4 produce no light at all.
3. The two halves of a cut note split along the wrong angle when the note carries a Noodle x/y
   rotation: the visual slice uses `global_rotation.z`, which Euler decomposition changes.

**Root cause**
1. `MapData.expand_box_group_colors` ignores `i` and always emits an "on" value.
2. It drops `g > 4`.
3. `BeepCube._start_cut_pieces` and `ChainLink._start_cut_pieces` subtract `global_rotation.z`
   instead of projecting the cut plane into the object's basis.

**Blast radius**
`game/scripts/MapData.gd`, `game/Cuttable.gd`, `game/BeepCube/BeepCube.gd`,
`game/Chain/ChainLink.gd`, the probe, version/docs. Scoring is untouched: hit accuracy already uses
`global_transform.basis.y` (`BeepCube.gd:200`). No map files, sidecars or library data are written.

- **FR-017**: `i:0` MUST emit an instant on (1/5/9 by colour), `i:1` a transition to the colour
  (4/8/12), and `i:2` MUST emit nothing, so the previous event keeps running. Two documented
  approximations: a v3 transition fades *towards* its event beat while Godot starts the fade at
  that beat (one gap late), and `s=0` with `i:1` is an instant off because the driver has no
  fade-to-black value.
- **FR-018**: Group ids above the room's five light types MUST be folded deterministically
  (`g % 5`) onto a real light type instead of being dropped; the docs MUST say the fold is an
  approximation because environments define their own groups.
- **FR-019**: The visual cut angle MUST be derived from the object's `Basis` (global plane normal
  projected into local space), so Noodle x/y rotation and 360 lane yaw split correctly. This
  applies to notes and chain links. The normal's local z is dropped (the pieces split in the
  object's XY plane), so a note tilted out of the screen plane is an in-plane approximation.

**SC-006**: The probe shows `i:1` → 8/4/12, `i:2` → no event, and `g:6` → `et:1`.
**SC-007**: A probe cut plane round-trips through an x-rotated basis back to the authored local
angle, and the old Euler-z result differs.
**SC-008**: Parse, LANEPROBE, MEPROBE, SETTINGSTEST and VERIFYSCHEMA still pass.

## Verification evidence (0.7.4)

- Box groups: `i=0` red/white → 5/9, `i=1` blue → 4, `i=2` → no event, `s=0` → 0; group 7 with
  `i=1` blue → `et` 2 (`7 % 5`), value 4; groups -1 and 2.5 dropped. Folded ids are logged once per
  map (`box groups folded onto room lights: {7: 2}`).
- Cut angle: a 0.4 rad authored plane round-trips to 0.4000 through a (35°, 20°, 50°) basis, and to
  0.4000 through `R·S(2, 0.5, 1)`; a zero-scale basis and a plane along the object's z take the
  fallback; the old Euler-z result differs by 13.54°.
- `SUPPORTTEST` PASS after its expectations were updated (box groups, 360 rotation and lane
  rotation are supported, so they no longer warn).
- Parse clean; LANEPROBE, MEPROBE, SETTINGSTEST, VERIFYSCHEMA 56 pass.

## Scoped change: 0.7.5 wall growth, lightshow cost and arc head

**Symptom** (owner, after playing Hand in Hand on 0.7.4)
1. Walls read as flat, broken barriers and grow out of their middle; the V5/V6-early look is gone.
2. Arcs are colour-matched but often look detached from the note at one end.
3. Frame-time drops in parts of the lightshow.

**Root cause**
1. `Wall._apply_grow` scales `WallMeshOrientation` about the wall centre (bottom lifts, top drops),
   and 0.6.5 removed the v0.6 rim from the shader.
2. `Arc.spawn` builds the head from the map's lane fields; the spawned head cube is only used for
   the magnet. The two are normally equal, but Noodle position or a differing motion reference
   separates them, and the mismatch was never measured.
3. Hand in Hand carries 4,593 light-colour box groups / 27,669 events per difficulty for 12 group
   ids; 0.7.4 converted every one to a basic event and `EventDriver` allocated a Tween per `i=1`
   transition.

**Blast radius**
`game/Wall/Wall.gd`, `game/Wall/wall_shared.tres`, `game/scripts/MapData.gd`,
`game/event_driver.gd`, `game/Arc/Arc.gd`, `game/BeepSaber_Game.gd`,
`game/scripts/BenchmarkRunner.gd`, the probe, version/docs. No map, sidecar or score data is
written.

- **FR-020**: A wall MUST grow with its bottom edge pinned to the floor and its collision box full
  size at the wall centre. Ordinary walls (integral grid fields, no Noodle/ME transform) MUST show
  the v0.6 rim; Noodle/ME/off-grid walls MUST keep the flat panel so wall art does not stripe.
- **FR-021**: Box-group events MUST be merged per 1/32 beat and light type (last wins) and a
  repeated value for a type MUST be dropped, before they enter the event stack.
- **FR-022**: Light fades MUST NOT allocate a Tween per event. Each light type keeps one
  interpolation state stepped once per frame.
- **FR-023**: An arc MUST take its head position from the spawned head cube when one exists, and
  log the first ten mismatches against the lane calculation.

**SC-009**: The wall probe pins the bottom at `-size.y/2` at full and partial growth, keeps the
collision scale at 1 and shows rim 1 for a vanilla wall / 0 for a Noodle wall.
**SC-010**: Hand in Hand ExpertPlus drops from 27,669 authored box events to 8,022 merged events
(after repeats), and a synthetic same-beat case merges to one event.
**SC-011**: Parse, NOODLEPROBE, WALLPROBE, SUPPORTTEST, LANEPROBE, MEPROBE, SETTINGSTEST and
VERIFYSCHEMA still pass.

## Verification evidence (0.7.5)

- `WALLPROBE`: full wall scale (0.6, 3.0, 4.0), `pos_y` 0, bottom -1.5, collision scale 1, rim 1;
  at `z=-14` scale (0.6, 1.65, 4.0), `pos_y` -0.68, bottom still -1.5; a Noodle-scaled wall has
  rim 0.
- `NOODLEPROBE`: two events on beat 5 plus one on 5.01 merge to the 5.01 white event; a repeated
  red on 6.0 survives, the same red on 7.0 is dropped; box/cut probes unchanged.
- Hand in Hand (all five difficulties): 27,669 authored box events -> 19,228 unique keys ->
  8,022 emitted events after the repeat rule (71% fewer). At 312 s that is ~26 events/s.
- Parse clean; the desktop renderer compiles the new wall shader (only shutdown leak messages).
- Device benchmark (`0.7.5`, Hand in Hand ExpertPlus, bot, 100 s, 120 Hz target): 9,235
  samples, mean 10.83 ms, p50 10.84, p95 12.98, p99 14.48, max 42.4 (startup only); 0.14% of
  frames over 16.7 ms, `spikes=0`, map load 899 ms, cubes peak 18, walls peak 4.
- No 0.7.4 device baseline exists: the benchmark runner was debug-only before 0.7.5, so this is an
  absolute profile, not a before/after diff. The light path is structurally cheaper (8,022 events,
  five fade states, no per-event tween).
- Pending on the headset: wall rim/grow, arc attachment, lightshow smoothness.

## Scoped change: 0.7.6 filled walls

**Symptom** (owner, after 0.7.5): the walls still look half-filled, like a texture that is half
painted and half empty, and the fill flickers as the background moves. The grow and rim work did
not address it.

**Root cause** `wall_shared.tres` was additive with a body of only 0.10-0.20 of the wall colour, so
the room behind dominated; the near-camera `smoothstep(0.25,1.0,abs(VERTEX.z))` also punched
transparent patches into a wall beside the player. Both change with the background/head position,
which is the flicker.

**Blast radius** `game/Wall/wall_shared.tres` only. No collision, placement or colour data changed.

- **FR-024**: Walls MUST render as a filled panel at 75-100% opacity (rim at full), not a faint
  additive tint, and MUST NOT use a view-space near fade that makes parts of the panel transparent.
- **SC-012**: In VR the wall reads solid with no background-dependent holes; a note behind a wall
  is still visible; putting the head inside a wall dims it instead of filling the view.

**Verification** shader compiles on the desktop renderer; headless parse clean; 0.7.6 / code 22
installed. G4 required cull_back (per-object sort made the two-faced version flicker) and 75%
alpha for note visibility. The in-VR look is the release gate.

## Consultation Log

| Gate | Question | Verdict | Follow-up |
|------|----------|---------|-----------|
| G1 (0.7.4) | Plan for box `i` transition/extend, group-id fold and local cut angle | **PASS WITH CHANGES** | Keep `g % 5` fold but drop malformed ids and log folds; `i=1` → 4/8/12 with the one-gap lag and `s=0` instant-off noted; cut angle from the global basis via `orthonormalized().transposed()` with degenerate/near-z fallback; probe adds non-uniform/degenerate scale, tilt-diff, extend and group-7 cases; `active-spec` moved to 027. |
| G4 (0.7.6) | Wall fill shader | **CHANGES** | Revert cull_disabled to cull_back (per-object transparent sorting would flicker and double overdraw); body alpha 75-100%; tag only after the owner's in-VR look at fill, notes behind a wall and head-in-wall dim. |
| G4 (0.7.5) | Wall growth/rim, lightshow cost, arc head, release benchmark | **PASS (conditional, met)** | Fade tint is written once per fade and published as the start colour; dedup resets after a literal RGB; same-slot conflicts keep the on event; arc head uses the cube only inside a lane node and logs mismatches; flash-on/fade-from-current are linear again. Tag only if the device benchmark on Hand in Hand holds the target frame rate with no regression; in-VR checks pending. |
| G1 (0.7.5) | Wall growth/rim, arc head, lightshow cost | **PASS WITH CHANGES** | Pin the wall bottom and drop the area counter-scale; rim on vanilla walls only (all edges) via a per-wall uniform; do not skip/extend arcs, use the head cube position; replace per-event Tweens with one interpolation state per type, merge at 1/32 beat; allow `bench.flag` in release builds. |
| G4 (0.7.4) | Box-group i/s semantics, g%5 fold, basis-local cut angle, stale unsupported test | **PASS** | Tag after the APK SHA is recorded; in-VR checks of the cut split on tilted notes and box-group fades pending. Later: ChainLink measures cut distance from the local origin while BeepCube uses global. |
| G4 (0.7.3) | Noodle static, box groups, audio resume/elevation review | **CHANGES** then **PASS** | First pass found pooled-note/wall rotation leakage, box-group `c` read as RGB instead of an index and no brightness, and an unguarded resume handler; fixed all three, added v3 key aliases (`coordinates`/`localRotation`/`size`), probe now covers both key spellings plus index colours and `s=0`. Re-review PASS with in-VR checks pending; LOW follow-ups for 0.7.4: box-group transition `i=1`/extend `i=2`, cut angle against Noodle x/y rotation, group id→light type mapping. |
| G4 (0.7.2) | 360/90 rotation review | **CHANGES** | Replaced the track-wide yaw with per-beat lane nodes (in-flight objects keep their rotation); probe now checks the shipped lane path; v3 basic events 14/15 added; v4 per-object rotation recorded as unsupported. |
| G4 (0.7.1) | ME precision release review | **CHANGES** | Fixed the 4001+ wall height (same 5-layer scale, start 4x/50 per layer); clamped zero-size ME walls to 1 cm; cut sign confirmed. 360/Noodle/Chroma recorded as 0.7.2. |
| G0 | Is the 0.7 scope (all listed features, open-source only) and the tier/harness order right? | **GO WITH CHANGES** | Adopted: FR-005 precision details (cut angle, wall encodings, no clamping), FR-006 rotation specifics (v2 types 14/15, v3 `e`, v4 `r`, environment/track), FR-009b animation keys and one-shot track resolution, FR-010 Chroma environment JSON, FR-010b player-track as gameplay, FR-015 pinned corpus (no maps committed), FR-016 one shared per-object transform; bundle work is a spike defaulting to Visuals limited; fixed the tier wording and the public matrix rows. |
