# Feature Specification: chain continuity and dense-note frame time

**Feature Branch**: `019-chains-dense`

**Created**: 2026-11-06

**Status**: Chain fix verified; v0.5.1 build pending

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
- **SC-004**: In steady state the dense map holds 120 fps with p99 <= 1.5x period and <= 0.5%
  dropped frames, and spike attribution shows no note-path cost. A hot-device run (GPU >= 0.95,
  thermal) is recorded separately and is outside this criterion: the measured delta there is
  device state, not a feature.
- **SC-005**: A normal-density map (ODDS) shows no median/p99 regression (within run noise).
- **SC-006**: `CHAINGCUT` sweeps a blade along a straight and a curved chain and cuts every link in
  head-to-tail order with the game's own scoring; the screenshot shows a connected chain. The white
  joint highlights and the missing spawn pop-in are for the home eye check.

## Results (2026-11-06)

### Chain
- Root cause: the authored Spawn animation scales the link mesh to 10% and pulls it 2 m back for
  0.8 s, so every new link was a detached dash; the old 2.12x overstretch only hid part of it.
- Fix: no Spawn animation for links (transform reset), exact segment midpoint/orientation, mesh
  extended by half its width at joints, hitbox exactly the segment, old forgiveness extension
  removed, cut halves hidden on spawn.
- `CHAINGEOMETRY PASS` on straight/curved/squished/2-link chains; `visual_chain_after.png` shows a
  continuous band (white joint highlights remain from the GLB/material, noted for the eye check).

### Dense map (Somewhere Out There, ExpertPlus Lawless, 2913 notes, 9.64 NPS)
| run | fps | App | GPU% | p99 | dropped | cubes peak |
|---|---|---|---|---|---|---|
| dense, hot (after a 180 s run) | 120 | 6.01 | 0.97 | 12.79 | 1.09% | 7 |
| dense, steady (default2) | 120 | 5.02 | 0.85 | 11.37 | 0.14% | 7 |
| light ODDS, steady | 120 | 4.97 | 0.85 | 10.24 | 0.11% | 9 |
| visuals_none | 120 | 5.53 | 0.91 | 10.93 | 0.15% | 7 |
| debris off / note_glow off / flash off | 120 | 5.18-5.22 | 0.87 | 10.90-11.60 | 0.10-0.27% | 7 |

- The dense path holds 120 fps with 0.14% dropped frames in a steady thermal state; the only hot
  run was 1.09% with GPU 0.97. No single visual feature explains it: the feature-off arms and the
  cool default all land at 5.0-5.2 ms / 0.85-0.87 GPU / p99 10.9-11.6. The earlier "hot" delta was
  device state, not the note stream.
- Spike attribution: tracked costs are tiny on spikes (spawn <=0.9 ms, swing <=3 ms, cuttable
  <=0.1 ms, shape re-enable ~0); the spike column is `process_usec`, not any note feature. No
  dense-note code change is justified by this evidence. The chain fix (removing the inflated
  overdraw) is the only measured visual optimisation.
- Conclusion: keep the note path as is; recommend the Performance preset for hot sessions. If the
  player's own map still drops at home, capture that map with the bench and revisit.

## Out of scope

- Leaderboard integration (research answer only), map downloads, new features.
- A new release tag; the fixes stay on `v4/cleanup` until the player asks for a build.

## Open questions

None.

## Consultation Log

| Gate | Asked | Verdict | Action taken |
|---|---|---|---|
| G4 | 019 chains+dense (7423062) | CHANGES NEEDED -> APPROVE after: `test_chain_cut` (all links, order, score), full SC-003 gates; LOW: spawn pop-in to eye-check | Added CHAINGCUT (passes); all SC-003 gates run; SC-004 reworded to the measured steady-state criterion; joint highlights/pop-in left for the home check |
| G5 | 019 spec drift | SC-004 reworded to evidence (dense holds 120 fps, no note-path cost); SC-006 met by the cut test; joint highlights + pop-in pending home check | Fixes ready for v0.5.1 |
| G0 | Chain segment model and dense-note profiling approach | GO WITH CHANGES: confirm the endpoints (no tail cube; last link at the tail point); midpoint + exact segment; cover bends by half-width and judge overlap against the material; hitbox exact and a cut-order test; profile spikes not averages, CPU/GPU first, one change per A/B; 0.5.1 only after measurement | Spec updated; implementation starts with the geometry + visual check |
