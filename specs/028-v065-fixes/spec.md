# Feature Specification: 0.6.5 fixes — wall art, long-arc fade, BeatLeader in the high-score panel

**Feature Branch**: `028-v065-fixes`

**Created**: 2026-11-07

**Status**: In progress - walls and arcs fixed in code; BeatLeader tab and close-cut diagnostics next; no build installed

**Input**: Owner, after playing 0.6.4: "The BeatLeader on the left overlaps the high-score UI; integrate
it into the high-score design. BeastSaber saves playlists but the local library has no playlist/folder
view — cards per source/playlist and sorting would help. The walls look broken; check the BeastSaber
set for unsupported data and fold it into 0.7. Close cuts near the camera do not register. Arcs mostly
fixed, but a long gap makes one disappear for a moment."

## Evidence

- Video `F:\Dev\BeepSaberBin\v064_play.mp4` (4:43, 1080p60): menu at 0–15 s, then one map from the
  DITR8 BeastSaber playlist. Wall-heavy sections at 20–40 s and ~265–280 s.
- **Walls**: the played map is map `53599` "Bensley – Shining For You" (DITR8), **vanilla v3**, 672
  obstacles, all `w=1`, `h=5`, durations ~0.05 beats. No Noodle/Chroma/ME data. The torn/striped
  look is ours: `Wall.gd` grows every wall from 10% to 100% height over **1 s**, and the shader is
  additive with a bright rim per wall. Hundreds of one-lane walls therefore show staggered tops and
  bright vertical stripes.
- **Arcs**: `Arc.material` has `distance_fade_min=15, max=3` (fade measured from the Path3D origin,
  which is the **tail**) and `tip_fade 0.2–2 m`. A gap longer than ~15 m therefore fades the head end
  to zero; the 2 m tip fade also hides the last stretch before the tail note. This matches "a large
  gap makes it disappear for a moment".
- **BeatLeader overlap**: `Highscores_Canvas` sits at `(-2.297, 1.423, -0.237)` on the left;
  `BeatLeaderLauncher` sits at `(-2.43, 1.498, 0.468)` — the same spot. The sign overlaps the local
  high-score panel.
- **Close cuts**: `HitResolver` tests a zero-thickness segment vs box; there is no speed gate, and
  the hit window opens at 3 m. A close jab that grazes the box edge can miss where a blade with a
  radius would hit. Needs a diagnostic before changing behaviour.
- **BeastSaber set scan** (DITR8, 21 maps): 18 vanilla; `Starlight` = 360 rotation + Noodle animation;
  `Three Steps Ahead` = Noodle position + v4 box groups. No Mapping Extensions, asset bundles or
  Chroma events. The 0.7 spec already covers 360/Noodle/box groups; no new format is required for
  this set.

## Scoped changes

1. **Walls**: spawn at full height (no 1 s grow); make dense wall art read as a surface rather than
   stripes (evaluate the rim/additive blending).
2. **Arcs**: disable the distance and tip fades for normal arcs so a long gap stays visible; keep the
   magnet fade.
3. **BeatLeader**: embed the board in the left `HighscorePanel` as a Local/BeatLeader tab; remove the
   separate left sign; the menu's Leaderboard button focuses that tab.
4. **Close cuts**: add a near-miss diagnostic and a capsule-radius hit test candidate; change behaviour
   only with evidence.
5. **Library cards/playlists**: design for 0.7 (separate spec), not in this build.

## Requirements *(mandatory)*

- **FR-001**: Walls MUST appear at their full declared height immediately; no per-wall grow animation.
- **FR-002**: Dense one-lane wall art (hundreds of adjacent walls) MUST read as a continuous surface,
  not alternating bright/dark stripes; the wall colour/opacity stays within the existing palette.
- **FR-003**: A normal arc MUST stay visible to both ends for the longest slider in the corpus; the
  far fade MUST start beyond the 16 m spawn distance (no pop-in), the tip fade MUST be off for ends
  that touch a note, and the magnet fade remains.
- **FR-004**: The BeatLeader board MUST live inside `HighscorePanel` as a tab beside the local scores;
  no second canvas may overlap the panel.
- **FR-005**: Opening the leaderboard from the menu MUST show the BeatLeader tab; the local tab stays
  one press away.
- **FR-006**: The left BeatLeader launcher canvas MUST be removed (or repurposed) so no world-space
  panel overlaps the high-score panel.
- **FR-007**: Close-cut behaviour MUST be instrumented (nearest distance at a miss, hit-segment vs
  blade radius) before any hitbox change; a capsule test is the candidate fix.
- **FR-008**: No vanilla-map regression: hit detection, 120 fps and existing probes unchanged except
  for the explicit wall/arc fixes.
- **FR-009**: The BeastSaber set result (18 vanilla, 2 with 360/Noodle/box groups) MUST be recorded in
  the 0.7 compatibility notes; no new format is added to 0.6.5.
- **FR-010**: An arc MUST NOT pop in at spawn. Any far fade is measured from the camera and starts
  beyond the spawn distance.
- **FR-011**: Every missed hit MUST be classified (`no-contact`, `wrong-direction`, `too-slow`,
  `passed-window`); closest distance and tip speed are logged only when the debug setting is on.
  Release builds log nothing.

## Success Criteria

- **SC-001**: On the DITR8 wall map, walls are full height on the first visible frame and form the
  intended pattern; a paused frame shows continuous wall surfaces, not tilted/torn tops.
- **SC-002**: A synthetic arc with a 32 m gap shows its whole ribbon at spawn and while approaching;
  the head and tail are both rendered.
- **SC-003**: The high-score panel shows Local and BeatLeader in one panel; no world canvas overlaps
  it in the menu; the menu button opens the BeatLeader tab.
- **SC-004**: A close-cut diagnostic records the nearest blade-to-box distance for a missed close
  note; the capsule test is evaluated against the recorded misses.
- **SC-005**: Existing arc/hit/settings probes pass; 120 fps capture stays within 0.6.4.
- **SC-006**: Frame time on the DITR8 wall map (20–40 s section) is no worse than 0.6.4; a paused
  frame shows no stripes.
- **SC-007**: The BeatLeader tab ignores a response for a map that is no longer selected.

## Out of Scope

- Library cards/playlist folders and sorting (0.7, separate spec).
- Mapping Extensions, 90/360, Noodle, Chroma, box groups (0.7 spec 027).
- Asset bundles.
- Any hitbox change without diagnostic evidence.

## Open Questions

- [NEEDS CLARIFICATION: wall look — keep the bright rim for single walls but disable it for adjacent
  walls, or switch to flat translucent walls everywhere?] — assume flat translucent, matching Beat
  Saber, unless it hurts readability.
- [NEEDS CLARIFICATION: should the centred BeatLeader canvas remain for the end screen?] — assume the
  end screen keeps its own panel; only the menu overlap is fixed.

## Consultation Log

| Gate | Question | Verdict | Follow-up |
|------|----------|---------|-----------|
| G0 | Are the wall/arc fixes, the BeatLeader tab integration and the close-cut diagnostic the right 0.6.5 slice? | **GO WITH CHANGES** | Keep additive walls minus grow/rim; verify the fade space and put the far fade beyond spawn; miss reason codes before any radius; BeatLeader lazy-load + stale-response guard; adopted FR-010/011 and SC-006/007, order arcs → walls → tab, close-cut logging only. |
