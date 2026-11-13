# Brief: Noodle Extensions animation

A self-contained brief for the next block of work. Paste it into a **fresh** session: a new session
does not re-read this project's long history on every step, which is the single biggest saving in
tokens. Everything it needs is in this file and in the repository.

## Where things stand (0.7.27, branch `audit/fable-5.2`)

- Notes move at the map's note jump speed: `game/NoteMotion.gd` (`configure`, `speed_at`,
  `distance_between`, `spawn_beats`, `spawn_distance`).
- Only **static** Noodle data is read: per-note position, rotation, scale and speed in
  `game/BeatmapInfo/ColorNoteInfo.gd` (`_read_custom_position`), applied in
  `game/BeepCube/BeepCube.gd` `spawn()`. Nothing animated exists.
- Objects are pooled, spawned from stacks in `game/scripts/GameState/Playing.gd`, parsed in
  `game/scripts/MapData.gd` (partly on worker threads), and moved in `Cuttable._physics_process`
  by `transform.origin.z += speed * delta`.
- `game/scripts/MapSupport.gd` only flags animated maps as unsupported.

## What the fixture maps use

Measured with `python tools/dev/census.py` over the 45 maps in `%TEMP%\toolchain\allsongs` (a
feature-biased test set, not a random BeatSaver sample): 16 require Noodle Extensions; 12 use
`AnimateTrack` (62,656 events), 8 `AssignPathAnimation`, 9 `AssignTrackParent`, 9
`AssignPlayerToTrack`; 11 put `track` and `animation` on objects, 11 a per-object
`noteJumpStartBeatOffset`, 10 a per-object `noteJumpMovementSpeed`, 9 `disableNoteGravity`.
Animated properties, most used first: position, rotation, scale, localRotation, offsetPosition,
localPosition, offsetWorldRotation, dissolve. Both v2 spelling (`_customEvents`, `_track`,
`_position`) and v3 spelling (`customEvents`, `track`, `offsetPosition`) occur.

## Build, in this order, one commit and one harness check each

1. **Point definitions**: inline arrays and named `pointDefinitions` / `_pointDefinitions`, with
   per-point time, easing names and the spline flag; evaluate at time t for vector, rotation and
   scalar properties. Test interpolation and each easing against hand-computed values.
2. **Track registry**: objects join tracks through `track` / `_track` (string or array); a track
   holds the current value of each animated property.
3. **Custom events**, sorted by beat and dispatched from `Playing.gd` next to the event stack:
   `AnimateTrack` (duration, easing, repeat), `AssignPathAnimation`, then `AssignTrackParent` and
   `AssignPlayerToTrack`.
4. **Applying it** to notes, bombs and walls each tick: position offset, local and world rotation,
   scale, dissolve as visibility, `interactable` / `uninteractable` (must be neither hittable nor
   missable), `definitePosition`, and the per-object `animation` block. Path animation runs over
   the object's own lifetime (0 at spawn, 0.5 at the hit, 1 at despawn); track animation over
   song time. No allocation per tick: this runs at 120 Hz with hundreds of live objects.
5. **Per-object** `noteJumpStartBeatOffset` for notes, bombs and walls, `noteJumpMovementSpeed`
   for bombs and walls, spawning early when an object's own half jump is longer than the map's,
   and `disableNoteGravity`.
6. Update `MapSupport.gd` to flag only what is still missing, and `docs/map-compatibility.md`.

Read the Heck / Noodle Extensions animation documentation first rather than working from memory.

## Rules

- No pushing, tagging or keystore changes; nothing closed-source.
- Tabs, small commits, behaviour changes named in the commit message.
- Verify with `pwsh tools/dev/check.ps1` (must end `CHECKS PASS`); add
  `tools/harness/verify_noodle.tscn` printing `NOODLE PASS` (the check script picks it up).
- `tools/harness/map_dump.tscn -- <map-folder> <outfile>` must stay byte-identical for a map
  without Noodle data, for example `%TEMP%\toolchain\allsongs\3af66`.
- Do not export or install from the session. The owner runs
  `pwsh tools/dev/build.ps1 -Bump -Install` and `pwsh tools/dev/botrun.ps1` in their own terminal.

## Out of scope

Vivify (Unity asset bundles), Chroma environment objects, and fog, camera and component events.
