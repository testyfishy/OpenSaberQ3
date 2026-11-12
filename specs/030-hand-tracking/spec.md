# Feature Specification: Quest 3 hand tracking as swords with pinch UI clicks for 0.7.7

**Feature Branch**: `030-hand-tracking`

**Created**: 2026-11-07

**Status**: In progress — 0.7.9 (quick settings) building, awaiting on-device validation

**Input**: User description: "Quest 3 hand tracking as swords with pinch UI clicks for 0.7.7" — owner chose the hand-ray + pinch-click approach over direct poke.

## Scoped change — rendered hands and a runtime-independent hand path (post-0.7.7 install)

Symptom: with controllers set down, the runtime switched to hands (logcat: controllers sent to sleep,
hand tracking enabled) but the sabers did not follow. Cause: Meta's Quest runtime does not implement
`XR_EXT_hand_interaction`, so the hand interaction profile's aim pose and pinch float never arrive;
the hand *joint* data (`XR_EXT_hand_tracking`) is live. The owner also cannot see whether hands are
tracked because nothing is drawn.

Change:
- **FR-011**: Render both hands from the MIT Godot demo hand models, each in an `XRNode3D` bound to
  `/user/hand_tracker/left|right` with `show_when_tracked`, plus `XRHandModifier3D`
  (`BONE_UPDATE_ROTATION_ONLY`) so the hand mesh follows the live joints and stays hidden when the
  hand is not tracked.
- **FR-012**: When hand data is live, drive each saber from the hand tracker's `default` (palm) pose,
  the same pose the rendered hand uses, via a saber base-transform override. The blade therefore
  sits in the visible hand and follows it even without the hand interaction profile.
- **FR-013**: Compute pinch from the thumb-tip/index-tip joint distance (press `30 mm`, release
  `50 mm`, both joints position-valid) and drive the existing UI `trigger` edge. Do not depend on
  `pinch_ext`.
- **FR-014**: Keep the hand-only saber offset (`hand_saber_offset_pos/rot`) for on-device alignment;
  the controller path and the persisted saber offset stay unchanged when hands are not live.
- The hand interaction profile stays in the action map (harmless, and used on runtimes that support
  it), but nothing depends on it for 0.7.7.

**SC-006**: Controllers down, hands visible: both rendered hands hold the sabers, a hand swing cuts
notes, and a pinch clicks a menu button.

## Scoped change — quick settings panel with a Hands toggle

The owner asked for a few important settings in one pinned place on the main window, with the hands
toggle inside it, rather than hunting through the full settings panel.

- **FR-015**: The main menu MUST show a pinned `QuickSettings` panel with three toggles: **Hands**
  (`Settings.hand_tracking_enabled`), **120 Hz** (on = 120, off = 90, `Settings.display_refresh_rate`)
  and **Lights** (`Settings.events`). Initial states MUST be read before connecting so loading the
  menu cannot write a different value back.
- **FR-016**: Turning **Hands** off MUST stop the hand path (`is_hand_tracking()` false), hide the
  rendered hands, and leave controller input untouched. Turning it on restores both when hand data is
  live; no app restart.
- **FR-017**: The quick panel MUST use the existing menu theme and sit inside the 1408x640 menu
  canvas without overlapping the Play/Exit/Settings controls.

**SC-007**: In the main menu, pinching or triggering the Hands toggle hides/shows the rendered hands
and changes only `Settings.hand_tracking_enabled`; the 120 Hz and Lights toggles persist their
settings.

## Scoped change — audit fixes on `audit/fable-5.2` (not yet in an installed build)

Found by the 0.7.9 code audit ([report](../../docs/audit-fable-5.2.md)) and reproduced headless with
a synthetic hand tracker (`tools/harness/verify_hand_path.tscn`). All of them follow from one fact:
with the controllers asleep, `XRController3D.get_is_active()` is false and the node keeps its last
transform.

- **FR-018**: Pinch MUST be evaluated whenever hand data is live, not only while the controller is
  active. (0.7.9 computed the pinch inside a block gated on `get_is_active()`.)
- **FR-019**: Swing travel (`movement_aabb`) and the cut-plane origin MUST be measured at the palm
  while the hands drive the sabers (`BeepSaberController.swing_origin()`), and at the controller
  node, exactly as before, while a controller is tracked.
- **FR-020**: The hand pose MUST be applied to the saber in `_physics_process` as well as in
  `_process`, so the blade segment used for cuts is the pose of the same tick.
- **FR-021**: Buttons MUST only be read from a tracked controller.
- **FR-023**: A pinch held when hand data drops MUST release the trigger on that tick, and a hand
  that returns still pinched MUST open once before it can click.
- **FR-022**: A parked saber (hands own it, no hand data, no controller) MUST NOT cut. It stays
  drawn at its last pose and resumes when data returns. Hiding it while parked is an open owner
  decision.

**SC-008**: `verify_hand_path.tscn` prints `HANDPATH PASS`.

Still unverified on the headset: SC-006/SC-007, and whether the APK manifest declares hand
tracking at all (see the audit report, finding H-1).

## Scoped change — light-skeleton hands (0.7.11, owner feedback on 0.7.10)

Owner, in the headset: the humanoid hand mesh looks jarring in a light-show game, and there is a
visible gap between the ring and little fingers.

- **FR-024**: Each hand MUST be drawn as glowing bars between the tracked joints (27 bars, one
  MultiMesh draw per hand, unshaded, in that hand's saber colour, bright enough for the glow pass).
  This replaces the humanoid mesh and `XRHandModifier3D` of FR-011. The bars are placed from the
  joint positions directly, so nothing is skinned and the mesh's proportions cannot open gaps.
- **FR-025**: A bar whose joints have no valid position MUST be hidden, not drawn to the origin.
- The hand node is a plain `Node3D` under the XR origin (joint transforms are already in the
  origin's space). The humanoid `.gltf` assets stay in the repo, unused, until the owner confirms
  the new look on the headset.

## Scoped change — grip to ignite (0.7.13, owner decision)

Owner, after playing 0.7.10: the saber stuck to the wrist reads wrong; "make a fist, the lightsaber
ignites, and then you just start smashing". The light-skeleton hands of FR-024 are approved.

- **FR-026**: With hands, the blade MUST be out only while the game state wants it AND that hand is
  a fist. Opening the hand sheathes it; closing it ignites it again. Controllers are unchanged.
- **FR-027**: A fist is detected from the middle, ring and little fingertips' distance to the palm,
  divided by the wrist-to-middle-knuckle length (grip below 0.62, release above 0.80). The index
  finger and thumb are excluded, and a pinch is ignored while gripping, so a fist never clicks.
- **FR-028**: While the blade is out (or animating), the saber is posed as a hilt held in the fist:
  along the little-knuckle to index-knuckle line, leaving the fist on the thumb side, offset by
  `grip_saber_offset`. With the blade away the saber node is the open-hand pointer of FR-012, which
  the UI ray rides on. The pose only switches while the blade has no length.
- **FR-029**: The grip is sticky through a tracking dropout (a fist hides its own fingers); FR-022
  still stops a parked blade from cutting.

Owner on 0.7.13: hands approved; the held saber's position "doesn't feel natural", and an open
hand should hold nothing rather than a hilt at the wrist.

- **FR-030** (0.7.14): With hands, the whole saber visual, hilt included, MUST be hidden unless
  the blade is out or animating. With a controller the hilt is always drawn, as before.
- **FR-031** (0.7.14): The gripped blade MUST lean forward from the knuckle line, away from the
  wrist, by `grip_blade_lean_deg` (default 25, on top of the ~15 degrees the knuckle line already
  has), the way a sword sits in a neutral wrist.

Owner on 0.7.14: a fist in the menu spawned no saber; the selection line followed the fist (where
a pinch is impossible) and, with the hand open, ran square to the hand.

- **FR-032** (0.7.15, replaces the state half of FR-026): With hands, a fist ignites the saber in
  every game state and an open hand sheathes it. Hits are still only scored in play.
- **FR-033** (0.7.15): The UI ray MUST be hidden, and must not hover or click, while the hand is a
  fist. Pointing and pinching belong to the open hand only.
- **FR-034** (0.7.15): The open-hand pointer MUST run along the hand (wrist to middle knuckle),
  built from joint positions. The palm pose's orientation is no longer used for it: the -90 degree
  X correction of FR-014 produced a ray square to the hand on the headset.

Owner on 0.7.15: the selection line should start between the thumb and index finger, where the
click happens; and the hilt still reads as attached to the wrist - a held stick sits in the
fingers at the MCP and PIP joints, inside the palm.

- **FR-035** (0.7.16): The open-hand pointer MUST start midway between the thumb tip and the index
  tip and run the way the hand points.
- **FR-036** (0.7.16, replaces the position half of FR-028): The gripped hilt MUST be centred in
  the loop of the curled fingers: the centroid of the knuckle row (MCP), the middle-joint row
  (PIP) and the fingertips. The palm joint and the palm pose's orientation are no longer used for
  the grip pose. `grip_saber_offset` is now (0, 0.03, 0): the hilt mesh's own centre offset.

Owner on 0.7.16: tapping thumb and index is itself movement and swings the far end of the line;
can we not do what Meta's own pointer does?

- **FR-037** (0.7.17, replaces the direction half of FR-034): The open-hand pointer MUST behave
  like the system pointer: direction from an estimated shoulder through the index knuckle (not
  along the hand), low-pass filtered, with the start point held relative to the hand while the
  fingers close to pinch. The start stays at the thumb/index midpoint (FR-035).
- The runtime's real aim pose (`XR_FB_hand_tracking_aim`) is only reachable through the
  open-source Godot OpenXR Vendors extension, which this project does not ship. FR-037 is an
  emulation; adopting the extension is an open option if the emulation is not good enough.

Owner decision after 0.7.17: adopt the open-source Godot OpenXR Vendors extension to get the
headset's own pointer.

- **FR-038** (0.7.19): The project uses Godot OpenXR Vendors 5.1.0-stable (MIT, GodotVR) with
  `xr/openxr/extensions/meta/hand_tracking_aim` enabled. It lives in `addons/godotopenxrvendors`,
  which is gitignored (48 MB of binaries): a fresh clone must install that release before
  exporting. Its Meta package contains only the extension's own library; no Meta SDK binary ships.
- **FR-039** (0.7.19): When the runtime's aim pose (`/user/fbhandaim/<side>`, pose `default`) is
  live, the open-hand pointer MUST be that pose and the click MUST be the runtime's `index_pinch`.
  Otherwise the emulation of FR-037 and the joint-distance pinch of FR-013 apply unchanged.
- **FR-040** (0.7.19): The hand-tracking manifest entries come from the export preset
  (`meta_xr_features/hand_tracking=1`, optional) instead of a hand edit to the Gradle template.

Still first guesses, to be tuned from owner feedback: the shoulder estimate (0.18 m to the side,
0.22 m below the head), the 60 ms smoothing, the two grip thresholds, the hilt offset and
the lean angle.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Hands drive the sabers (Priority: P1)

With the Touch controllers set down (hand tracking active on the headset), the player's palms hold
the two sabers and swinging a hand cuts notes, hits walls and draws arcs exactly like a controller.

**Why this priority**: Without a working saber pose there is no game. This is the whole feature.

**Independent Test**: Controllers off, hands up. Both sabers sit at the hands and follow them; a
swing cuts a cube and the score increments.

**Acceptance Scenarios**:

1. **Given** hand tracking is enabled on the headset and the controllers are off, **When** the app
   starts, **Then** both sabers follow the palms with no menu interaction.
2. **Given** a hand-swung saber crossing a cube, **When** the blade segment intersects it, **Then**
   the cut resolves as with a controller.

---

### User Story 2 - Pinch clicks the 3D UI (Priority: P2)

In menus the player points the saber/hand ray at a button and pinches thumb and index finger to
click it, matching the Meta system UI gesture.

**Why this priority**: Menus are where hand tracking first becomes usable without controllers.

**Independent Test**: On the song-selection page, point the ray at a button and pinch; the button
fires. Release the pinch and pinch again; it fires again.

**Acceptance Scenarios**:

1. **Given** the UI ray is visible in a menu, **When** the player pinches, **Then** the highlighted
   button receives a press exactly once.
2. **Given** the pinch is released, **When** the player pinches a second button, **Then** that button
   fires.

---

### User Story 3 - Controllers keep working unchanged (Priority: P3)

Players with controllers (or with hand tracking disabled on the headset) get the existing behaviour
with no new setting to find.

**Why this priority**: Hand tracking must not regress the normal input path.

**Independent Test**: Controllers on, hands down: trigger clicks UI, A/B extend/sheath, cuts work,
haptics fire.

**Acceptance Scenarios**:

1. **Given** controllers are tracked, **When** the player presses the trigger, **Then** the UI
   click path behaves exactly as in 0.7.6.
2. **Given** hand tracking data is not live, **When** `select_button` is polled, **Then** it does not
   mask or alter controller input.

---

### Edge Cases

- Hand tracking drops mid-song (occlusion, low light): the hand pose stops; tracks are lost and the
  player can pick the controllers back up. No crash, no stuck trigger.
- Controllers and hands both report at once: hand mapping only applies while `XRHandTracker`
  reports live tracking data, so a dormant hand tracker cannot hold `trigger` pressed.
- The headset has hand tracking off or the runtime lacks `XR_EXT_hand_interaction`: the hand profile
  registers but never activates; controllers are unaffected.
- No haptics with hands: clash/cut feedback is audio/visual only.
- Pinch while cutting: trigger does not gate cuts, so a pinch during a swing changes nothing.
- The app must not require a hand mesh; no skeleton rendering in 0.7.7.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The project MUST enable OpenXR hand tracking, the unobstructed data source and the
  hand interaction profile (`xr/openxr/extensions/hand_tracking`,
  `hand_tracking_unobstructed_data_source`, `hand_interaction_profile`).
- **FR-002**: `openxr_action_map.tres` MUST contain the hand interaction profile
  (`/interaction_profiles/ext/hand_interaction_ext`) with `default_pose`/`aim_pose`/`grip_pose` and
  a dedicated `pinch` float action bound to `pinch_ext/value` per hand. Godot only auto-creates
  these for its built-in map; this project ships a custom map. `palm_pose` and `select_button` are
  deliberately not bound (nothing uses the palm; `ready_ext` does not mean "fingers touching").
- *FR-003 and FR-004 are superseded by FR-012 and FR-013: Quest does not deliver the hand
  interaction profile, so the saber pose comes from the hand tracker's palm pose and the pinch from
  joint distance.*
- **FR-003**: The sabers MUST follow the hand pose through the existing
  `left_hand`/`right_hand` `XRController3D` trackers (the hand interaction profile's aim pose), with
  no new rig and no per-hand scene duplication.
- **FR-004**: When the hand tracker at `/user/hand_tracker/<side>` has live tracking data, the
  controller MUST read the `pinch` float with hysteresis (press at `>= 0.8`, release at `< 0.5`)
  and drive the internal `trigger`, which is what the UI raycast already reads
  (`trigger_just_pressed`/`trigger_just_released`). A float read through `is_button_pressed()` is
  pressed for any nonzero value and MUST NOT be used for the click edge.
- **FR-005**: The hand mapping MUST be inactive whenever the hand tracker has no tracking data, so
  controller-only play is byte-for-byte the old behaviour.
- **FR-006**: The app MUST log hand activation once per boot (`HAND tracking active on <tracker>`)
  for on-device diagnosis.
- **FR-007**: Saber extend/sheath and game-state visibility MUST stay on the existing paths; with
  hands the sabers are shown automatically during play and the A/B extend toggle is not required.
- **FR-008**: Haptics MUST NOT be called for hand input; `simple_rumble` on a hand tracker is a
  no-op in the runtime and must not error.
- **FR-009**: Version MUST be 0.7.7 (versionCode 23) for this build.
- **FR-010**: A hand-only saber position/rotation correction MUST exist (default: zero position,
  -90 degrees about X, see FR-014; it was identity in 0.7.7) and
  apply only while hand tracking is live, so the blade can be aligned to the hand aim pose on-device
  without changing the controller or the player's persisted saber offset.

### Key Entities

- **Hand tracker**: OpenXR `XRHandTracker` named `/user/hand_tracker/left|right`, exposes joints and
  `has_tracking_data`.
- **Controller tracker**: `XRControllerTracker` `left_hand`/`right_hand` bound to the two
  `XRController3D` nodes, carries the aim pose and the action-map inputs.
- **Hand interaction profile**: action-map entry binding pose + pinch-ready for each hand.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With controllers off, both sabers visibly follow the hands within one physics tick on
  the headset, and a hand swing cuts notes.
- **SC-002**: A pinch fires a menu button exactly once, and a release + re-pinch fires again, with no
  double clicks.
- **SC-003**: Controller play shows no behaviour change: trigger UI clicks, A/B extend, cuts and
  haptics all still work.
- **SC-004**: The 0.7.7 APK installs and reports `versionName=0.7.7`, `versionCode=23`; the app
  launches with no script or parse errors.
- **SC-005**: The app boots and plays with hand tracking both enabled and disabled on the headset.

## Out of scope

- Rendered hand meshes / skin and `XRHandModifier3D` skeleton rigs. *(Superseded by FR-011 in
  0.7.8: the hands are rendered.)*
- Direct poke/touch UI (index-tip collision, press depth) — the owner chose hand ray + pinch.
- Custom gestures beyond pinch: palm-up menu, swipe, two-hand gestures, microgestures.
- Hand-based locomotion or turning.
- Pausing during a song with hands (pause is on the left B button in 0.7.7); it needs a gesture in a
  later build.
- Haptic feedback through hands (the runtime provides none).
- Any engine fork or engine modification.

## Assumptions

- The owner enables hand tracking in the headset's settings and the Quest 3 runtime supports
  `XR_EXT_hand_tracking`. *(The 0.7.7 assumption that it also supports `XR_EXT_hand_interaction`
  was wrong; see the first scoped change above.)*
- The hand interaction aim pose is a sensible saber direction; if the blade angle reads wrong
  on-device, the hand-only correction (`FR-010`) is tuned, not a redesign.
- Pinch is the click edge: the `pinch_ext/value` float crosses 0.8 = press, drops below 0.5 =
  release, matching Meta's own UI gesture. `ready_ext` is not a click.
- 120 Hz / 90 Hz, walls, arcs and clash from 0.7.6 are unchanged.

## Consultation Log

| Gate | Question | Verdict | Follow-up |
|---|---|---|---|
| G0/G1 | Hand-tracking approach for 0.7.7: hand interaction profile in the custom action map, pose via the existing controller trackers, pinch-ready → trigger for UI; any hidden trap? | APPROVE WITH CHANGES: `ready_ext` is not a click edge — bind `pinch_ext/value` to a dedicated float action and use hysteresis; drop the `palm_pose` binding; `default_pose` → aim pose is sufficient; expose a hand-only saber offset for on-device tuning | Implemented: `pinch` float action (0.8 press / 0.5 release), hand profile = default/aim/grip pose + pinch, palm/select removed, `FR-010` hand offset |
| G4 | Review the implemented diff before install | APPROVE with three small changes: guard `simple_rumble` for hands (FR-008), use `is XRHandTracker` not `get_class()`, clear `_pinch_down` when tracking drops; pre-existing test-script parse errors do not block install | All three applied. Pause-with-hands recorded as out of scope. |
| G4 | Rendered hands implementation | CHANGES NEEDED: `get_adjusted_transform()` is in XR-origin space, so a top-level saber must be lifted by the origin's world transform; otherwise the blade sits about 1 m from the hand. `-90 X` confirmed as the correct finger-direction basis; timing and switch-back logic fine | Fixed `hand_world_transform()` with `parent.global_transform * palm.get_adjusted_transform()`; rebuilding 0.7.8 |
| G4 | Quick settings panel with Hands toggle | APPROVE: gating is safe because the panel is menu-only; hardcoded 90 Hz is clamped by `_resolve_refresh_rate`; read-before-connect is correct. One medium follow-up: keep the toggles in sync when the full settings panel changes the same keys | Added `Settings.changed` sync with `set_pressed_no_signal` and `_exit_tree` disconnect. Noted: with Hands off and controllers asleep, a pinch cannot re-enable Hands; pick up a controller |
| G1 | Rendered hands + runtime-independent hand path: hand tracker palm pose drives both the mesh and the saber; joint-distance pinch | GO WITH CHANGES: do not stack the Touch offset on the hand path; make the saber top-level with the palm world pose (sleeping controller stale transform); gate on unobstructed hand data; arm pinch after an open-hand frame | Applied: -90 X hand-only default, top_level hand drive in _process, unobstructed/unknown source gate, 30/50 mm pinch with open-hand arming; no quick-settings toggle (auto mode is unambiguous) |
