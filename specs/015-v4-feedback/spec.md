# Feature Specification: v4 play-test feedback

**Feature Branch**: `015-v4-feedback`

**Created**: 2026-11-04

**Status**: In progress

**Input**: First v4 play test. The player likes the build, especially the walls, and listed eight
fixes to ship v4.

## Intent

Turn the first real play session into the v4 release: make overhead walls readable from below,
make sabers match the note colours, rebuild the hit sound around a low thump, diagnose the broken
chain links, make BeatSaver and settings scrolling pure stick scroll with a cursor that only
selects, add a Back button that discards settings, and make a miss impossible to miss while
enlarging the combo readout and explaining the percentage.

## Requirements

- **FR-001**: Saber colours MUST match the note colours the map defines. When a map supplies note
  colours (or an environment scheme), both sabers take them; the player's explicit colour override
  still wins. No random/default colour may disagree with the cubes.
- **FR-002**: A wall overhead MUST show its underside, so a crouching player can tell when it is
  safe to stand. Walls MUST render two-sided (or equivalent) and the underside MUST be at least as
  readable as the top. The "hit a wall" sound must not fire from a wall that was never touched.
- **FR-003**: Scrolling the BeatSaver list with the stick MUST be continuous and MUST NOT lock the
  pointer onto a card. The cursor's only job is selection.
- **FR-004**: In the settings menu the stick MUST navigate the list and the cursor MUST only
  select. Cursor-drag scrolling MUST be disabled. A Back button MUST close the panel discarding
  any changes; Apply keeps the existing behaviour.
- **FR-005**: A miss or a wrong-colour cut MUST be prominently visible: a larger marker than today,
  held longer, readable in peripheral vision because the player is looking down the track.
- **FR-006**: The combo readout MUST be larger and more central, and the percentage indicator MUST
  be labelled so its meaning is unambiguous (score accuracy, not song progress) or replaced by two
  clearly named values.
- **FR-007**: The hit sound MUST be rebuilt around a low-frequency thump: most energy under
  ~150 Hz, a short transient, and clearly less 2-6 kHz energy than the current samples.
- **FR-009**: The classic hit set MUST remain selectable; a "Hit sound" setting chooses between
  Classic and Thump, and the two sets swap as a unit without preloading cost concerns (both are
  small WAVs and ship).
- **FR-010**: The settings panel MUST be split into tabs (Audio, Sabers & Controls, Visuals,
  Performance, Debug) with a top tab bar, hidden tabs not reachable by the ray, and the stick
  scroller following the active tab.
- **FR-011**: The end-of-song card MUST not overlap: score and record columns must be clear of the
  saved-score mesh, the percent ring and the buttons.
- **FR-008**: The broken chain links MUST be diagnosed from the data and rendering path and fixed,
  so a chain reads as a continuous path from head to tail with no detachments or stray lines.

## Success criteria

- **SC-001**: On a map with custom note colours, both sabers match their cube colour in a desktop
  render and on device.
- **SC-002**: Standing under an overhead wall shows its underside in the same render; the bench's
  collision probe reports no wall hit while crouched without contact.
- **SC-003**: A 60 s stick scroll of the BeatSaver list reports no multi-frame stalls and no card
  lock (the existing scroll probe, extended).
- **SC-004**: Settings Back closes without writing config; Apply still writes.
- **SC-005**: A forced miss during a bot run is visible in a capture at normal play distance.
- **SC-006**: Combo text is measurably larger (render comparison); the percentage label states what
  it measures.
- **SC-007**: Offline analysis of the new hit samples shows the energy peak below ~150 Hz and a
  lower 2-6 kHz share than the current samples.
- **SC-008**: Chain links are continuous in a face-on render and in the map dump's chain geometry;
  the advisor's diagnosis is recorded.

## Out of scope

- The remaining v4 refactor slices (Map split, pooled nodes, names, settings schema).
- New gameplay modes, scoring changes, or map-format support.

## Open questions

- [NEEDS CLARIFICATION: for FR-002, is an extra underside quad acceptable, or must the wall be
  fully two-sided? Cost differs on wall-heavy maps.]

## Consultation Log

| Gate | Asked | Verdict | Action taken |
|---|---|---|---|
| G0 | Scope and approach for the eight play-test fixes, plus chain diagnosis | GO WITH CHANGES: add a "Use map colours" path for sabers; chain stretch is the likely bug (orient along the 3D tangent or revert); for walls the camera is probably *inside* the box, so log camera vs wall bottom rather than making walls two-sided; bass needs harmonics (160->55 Hz sweep, 220 Hz body, 1-2.5 kHz click); miss marker must be opaque geometry, not a large alpha quad | Applied: FR-009..011 added; chain links oriented along the 3D chord; walls fade when the camera is inside; miss label 28 pt; sound derived with a low shelf and 2.5 kHz cut |
| G1 | Settings tab taxonomy, hit-sound variants, end-card overlap | GO WITH CHANGES: top tab bar with five tabs, per-tab scroll container, no lazy rebuild; sound global and persisted, swap pools as a unit; end card is hand-placed 3D text, move NR above Details and separate z | Tabs built as a top bar with hidden-in-place rows; sound setting added; end card moved and z-separated |
