# Feature Specification: chain continuity and dense-note frame time

**Feature Branch**: `019-chains-dense`

**Created**: 2026-11-06

**Status**: In progress (G0 approved with changes)

**Input**: Player: "the gameplay mechanic about having a translucent line that connects between
boxes - they are not connected well and it's still an issue from yesterday's gameplay. Also test
gameplay on another map with more boxes. If there's a lot of boxes at the same time there's frame
time drops which we need to optimize for v5."

## Intent

Two defects on the shipped v0.5 build: chain links do not form a continuous line between the
notes, and dense note sections drop frame time. Fix both with evidence. The open-source
ecosystem/leaderboard question is research only.

## Scoped change: chain continuity

- **Symptom**: the translucent chain between notes reads as detached/oversized plates rather than
  one line joining the head cube to the tail cube.
- **Reproduction**: any map with chains (the synthetic `tools/visual_check.tscn` renders one), or
  watch a chain in play.
- **Current model**: each link is centred on its own bezier point and scaled by ~2.12x the chord to
  its neighbour (`ChainLink.spawn`), so it overshoots into the neighbour; the first segment from
  the head cube and the last to the tail are not explicitly covered, and the last link's measure
  runs backwards.
- **Blast radius**: `ChainLink.spawn`, `_link_length`, the chain portion of `Playing`; no other
  object type.

### Requirements

- **FR-001**: Each link MUST span one exact segment between consecutive chain points (head cube
  -> link 1 -> ... -> last link at the tail point; there is no tail cube), with its centre at the
  segment midpoint and its length equal to the segment (no hitbox overlap).
- **FR-002**: At joints, the **mesh** MUST cover the outer edge of a bend up to 90 degrees (no
  visible gap); the mesh may extend by its half-width per end, while the hitbox stays exact. The
  link material MUST be checked first: if it is transparent/additive, overlap is judged by the
  screenshot, not by a percentage.
- **FR-003**: Chain hit behaviour MUST be unchanged: the hitbox segments touch but do not overlap
  (so a swing cannot hit two links out of order), and a synthetic test MUST assert the segment
  order and non-overlap. The cut/score code is not modified.

## Scoped change: dense-note frame time

- **Symptom**: frame time drops when many boxes are on screen at once (player, v0.5).
- **Dense map**: `UploadedSong-3629265728` ExpertPlus, 2913 notes at 9.64 NPS (the densest of the
  device maps), v2.0.0.
- **Requirements**:
  - **FR-004**: Record a baseline on the v0.5 debug build of the same code: fps median, App ms,
    p99 and max frame interval, and the per-column costs (spawn, cuttable, swing, shape re-enable,
    draw calls/GPU). The bench must hit notes (non-zero cuts) so the measurement is real play.
  - **FR-005**: Attribute costs on **spike frames** (frames over 1.5x the period), not averages:
    sum spawn/cuttable/swing/shape-reenabled per spike and rank. Establish first whether the dense
    run is CPU- or GPU-bound from GPU% and frame time. One change per A/B.
  - **FR-006**: After the change: fps median 120, p99/max frame interval and App ms no worse than
    the baseline (target: within the light-map band), no increase in dropped frames, and the bot's
    score/sample counts comparable so the workload did not shrink.
  - **FR-007**: If the dominant cost is visual, its setting may be changed only with a measured
    A/B arm; no silent quality cut.

## Success criteria

- **SC-001**: `CHAINGEOMETRY PASS` on synthetic straight/curved/squished/short chains (max gap
  <= 2 cm, overlap <= 5%), and the `visual_check` chain screenshot shows a continuous line.
- **SC-002**: Dense baseline and after numbers are recorded in `specs/019-chains-dense/plan.md`;
  after: 120 fps median, p99/max and App no worse, cuts/samples comparable.
- **SC-003**: Existing gates pass (`RELOADTEST`, `BPMTEST`, `SUPPORTTEST`, `HITAUDIOTEST`,
  `ANALYSERTEST`, settings gates, map dump) and the game remains playable.
- **SC-004**: On the dense map, p99 frame interval and the count of frames over 1.5x period both
  improve on the same-commit debug baseline (target: p99 <= 1.5x period, spike count halved).
- **SC-005**: A normal-density map (ODDS) shows no median/p99 regression (within run noise).
- **SC-006**: Chain cut order/score is covered by the non-overlap test, and the device/desktop
  screenshot shows a connected chain; the screenshot is recorded in the sheet.

## Out of scope

- Leaderboard integration (research answer only), map downloads, new features.
- A new release tag; the fixes stay on `v4/cleanup` until the player asks for a build.

## Open questions

None.

## Consultation Log

| Gate | Asked | Verdict | Action taken |
|---|---|---|---|
| G0 | Chain segment model and dense-note profiling approach | GO WITH CHANGES: confirm the endpoints (no tail cube; last link at the tail point); midpoint + exact segment; cover bends by half-width and judge overlap against the material; hitbox exact and a cut-order test; profile spikes not averages, CPU/GPU first, one change per A/B; 0.5.1 only after measurement | Spec updated; implementation starts with the geometry + visual check |
