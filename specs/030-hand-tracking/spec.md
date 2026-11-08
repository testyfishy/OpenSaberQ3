# Feature Specification: Quest 3 hand tracking as swords with pinch UI clicks for 0.7.7

**Feature Branch**: `030-hand-tracking`

**Created**: 2026-11-07

**Status**: In progress — 0.7.7 installed, awaiting on-device validation

**Input**: User description: "Quest 3 hand tracking as swords with pinch UI clicks for 0.7.7" — owner chose the hand-ray + pinch-click approach over direct poke.

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
- **FR-010**: A hand-only saber position/rotation correction MUST exist (identity by default) and
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

- Rendered hand meshes / skin and `XRHandModifier3D` skeleton rigs.
- Direct poke/touch UI (index-tip collision, press depth) — the owner chose hand ray + pinch.
- Custom gestures beyond pinch: palm-up menu, swipe, two-hand gestures, microgestures.
- Hand-based locomotion or turning.
- Pausing during a song with hands (pause is on the left B button in 0.7.7); it needs a gesture in a
  later build.
- Haptic feedback through hands (the runtime provides none).
- Any engine fork or engine modification.

## Assumptions

- The owner enables hand tracking in the headset's settings and the Quest 3 runtime supports
  `XR_EXT_hand_tracking` and `XR_EXT_hand_interaction` (it does on current firmware).
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
