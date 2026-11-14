# Noodle Extensions animation: overnight report

Work on `audit/fable-5.2`, carried out unattended from `docs/noodle-animation-brief.md` on
2026-11-12/13. Nothing was pushed, tagged or released; the keystore and the `keystore/*` export
fields were not touched; no settings defaults, cut feel, scoring or UI layout changed.

The semantics come from Heck's source code (Aeroluna/Heck, MIT, cloned read-only into a scratch
folder) and its documentation at heck.aeroluna.dev and the Heck wiki, not from memory: easings
from `Heck/Animation/Easings.cs`, interpolation from `PointDefinition.cs`, event timing from
`CoroutineEventManager.cs`, property combination from NoodleExtensions `AnimationHelper.cs`,
object lifetimes from `NoteUpdateNoodlifier.cs` / `ObstacleUpdateNoodlifier.cs`, parent and
player transforms from `ParentObject.cs`, `PlayerTrack.cs` and `TransformController.cs`.

## Commits

| Commit | What |
|---|---|
| `6e39bd8` | Step 1: point definitions and Heck easings |
| `86e0526` | Step 2: track registry, objects join tracks |
| `ae15a94` | Step 3: custom events AnimateTrack, AssignPathAnimation, AssignTrackParent, AssignPlayerToTrack |
| `153913a` | Version 0.7.28 (device build after step 3) |
| `4be0d5d` | Step 4: animation applied to notes, bombs and walls each tick |
| `fd74d47` | Step 5: per-object jump offset and speed, early spawn, disableNoteGravity |
| `440e969` | Step 6: MapSupport names only what is still missing; map-compatibility.md |
| `45ad083` | Fix: zero scale stays invertible; per-tick refresh only walks transform tracks |
| `b21040d` | Version 0.7.29 (final device build) |
| (last commit) | Changelog and this report |

Code: `game/noodle/` (NoodleEasing, NoodlePoints, NoodleTrack, NoodleTracks, NoodleObject,
NoodleEvents, NoodleAnim), hooks in `Cuttable.gd`, `BeepCube.gd`, `Bomb.gd`, `Wall.gd`,
`Playing.gd`, `Map.gd`, `NoteMotion.gd`, `MapSupport.gd`, the three info classes.
Harness: `tools/harness/verify_noodle.tscn` (213 checks, all against hand-computed values,
v2 and v3 spellings, plus three real fixture maps).

## What now works, against the census

Census of the 45 fixture maps (`python tools/dev/census.py`), Noodle-related rows. "Works"
means checked against Heck's formulas in `verify_noodle` and run through the real game loop
headless on the PC; no animated map has been seen on the headset yet (see Device testing).

| Census feature (maps) | State |
|---|---|
| requires Noodle Extensions (16) | Loads and plays the animation below |
| event AnimateTrack (12) | **Works**: offsetPosition, offsetWorldRotation, localRotation, scale, dissolve, interactable, and position/localPosition/rotation/localRotation/scale on parent and player tracks; duration, easing, repeat, null, overwrite, same-beat file order. Not applied: `time`, `dissolveArrow`, Chroma `color` (reported) |
| object animation (11) | **Works**: the object's own `animation` / `_animation` block replaces its tracks' paths per property, as in Heck |
| object track (11) | **Works**: `track` / `_track`, string or list, notes, bombs, walls |
| object noteJumpStartBeatOffset (11) | **Works** for notes, bombs and walls; such objects spawn earlier or later by their own half jump |
| object noteJumpMovementSpeed (10) | **Works** for notes (already), bombs and walls (new); wall length follows it |
| event AssignPlayerToTrack (9) | **Works** for the Root target, by moving the world around the player (see decisions). Head / LeftHand / RightHand: not applied, reported |
| event AssignTrackParent (9) | **Works**, nested parents included. `worldPositionStays` and the event's own static transform fields are not read |
| object disableNoteGravity (9) | Read; nothing to do: this game has no note gravity (notes fly straight in at their own height) |
| event AssignPathAnimation (8) | **Works**, including a timed blend from the previous path |
| object interactable (6) / uninteractable (1) | **Works**: such an object can be neither hit nor missed; walls lose their collision |
| object scale / localRotation / position / rotation / coordinates / worldRotation / size | Static, as before this work (0.7.3); animated scale multiplies the static scale |
| object fake (4) | Still filtered: decorative objects are not drawn |
| definitePosition (in object animation and paths) | **Works** (keeps x/y, replaces the travel, still offset by offsetPosition) |
| dissolve | Drawn as visibility: hidden below 0.5 (no fade shader). *Superseded: now a fade, see "Dissolve as a fade" below* |
| event AnimateComponent (2), AssignFogTrack (2) | Not done (Chroma; out of scope), reported |
| Vivify events (AssignObjectPrefab, InstantiatePrefab, DestroyObject, Blit, SetMaterialProperty, SetCameraProperty, SetRenderingSettings, CreateScreenTexture, SetGlobalProperty) | Not done (out of scope), reported as "Vivify events" |
| chroma environment objects (12) | Not done (out of scope), reported as "Chroma environment" |
| object disableNoteLook (1) | Not done (notes do not turn to face the player in this game anyway) |

Point definitions: inline and named (v3 `pointDefinitions` object, v2 `_pointDefinitions`
list), bare single points, all 32 Heck easings, `splineCatmullRom` for vectors; rotations slerp.

## What does not work, and why

- **The `time` property** (AnimateTrack): it re-times an object's whole lifetime, which needs the
  hit window and the miss to follow the animated time; not attempted in this pass. Reported.
- **dissolveArrow**: the arrow is drawn inside the note shader, with no separate visibility.
  Reported. *Superseded: now played, see "Dissolve as a fade" below.*
- **Dissolve as a fade**: notes are shown or hidden at 0.5, not faded. *Superseded: see below.*
- **Point bases and modifiers** (`baseHeadPosition`, `opAdd` ...): the definition is skipped and
  reported.
- **Player Head / hand targets**: would move the player's own body parts; skipped and reported.
- **Arcs and chains** do not follow an animated head note, and a head note with its own jump
  offset spawns in a different frame from its arc or chain, so the head lookup misses it.
  *Second half superseded: heads are linked at load, see "Noodle fixes" below.*
- **Fake (decorative) objects** are still not drawn, so maps that build scenery from fake notes
  look emptier than in Beat Saber. *Superseded: drawn, see "Fake objects drawn" below.*
- **v4 maps**: the v4-to-v3 expansion drops bomb and wall customData, so tracks, animation and
  jump overrides do not reach v4 bombs and walls (notes keep theirs). *Superseded: fixed below.*
- **Static Noodle rotation** (from 0.7.3, unchanged) adds the map's Euler angles directly, without
  the left- to right-handed conversion the animated rotations now use. A map that rotates an
  object both statically and by animation turns the static part the other way round. Left alone
  because changing static transforms was out of scope; worth a follow-up. *Superseded: converted,
  see "Noodle fixes" below.*
- **Track parents in 360 maps**: the parent transform is applied inside the object's lane, not
  outside it. Noodle maps rarely use 360 lanes.
- **Performance**: on the PC, Gloom (345 animated walls) runs with a p99 frame time of 14-15 ms
  against 12 ms before. Not measured on the headset (see device testing).

## Decisions made without the owner

1. **AssignPlayerToTrack moves the world, not the player.** The inverse of the player's track
   transform is applied to the game's Track root node, so notes, walls, arcs and lanes are drawn
   relative to the player. That is the same picture as moving the player for everything this game
   draws (the room is not animated), it never moves the player's view (no motion-sickness risk),
   and it keeps the elevator map 4a2b3 correct: its notes ride the same track as the player, and
   the harness checks they stay put relative to the player while the elevator rises 160 units.
2. **interactable < 1 means neither hittable nor missable**, as the brief asks, although Heck
   only disables cutting.
3. **Dissolve is visibility** with a threshold of 0.5. *Superseded by the fade below.*
4. **Easings are Heck's formulas**, not easings.net's (several differ); unknown easing names are
   linear (Heck would throw).
5. **Malformed or unsupported point definitions are skipped**, never an error.
6. **The animation clock follows the audio smoothly** (advanced by the tick, pulled toward the
   playback position, snapped after a jump of more than 0.1 s) rather than copying the raw
   playback position, which moves in mix-sized steps.
7. **Object travel is still integrated per tick** and the lifetime is derived from it, so an
   animated object moves as smoothly as an ordinary one; the hit window and the miss use that
   travel, not the animated position.
8. **Walls pivot on their front face** (Beat Saber's obstacle origin); their lifetime runs over
   the jump plus the wall's own duration, as in Heck.
9. **Scale is kept at least 0.0001** per axis so a hidden (scale 0) object stays invertible.
10. **Same-beat events keep file order** (explicit tie-break: Godot's sort is not stable).
11. **Durations are converted with the BPM at the event's beat**, as Heck does.
12. **Units**: offsetPosition and definitePosition in lanes (0.6 m); v3 parent/player positions in
    metres; v2 parent/player `_position` in lanes, turned by `_rotation` (Heck's v2 ParentObject).
13. **MapSupport takes counts as arguments** instead of reading the Noodle classes, to break a
    class dependency cycle that left MapData's loader threads null (caught by the harness).
14. **Device testing substitute**: when the headset could not complete a bot run (below), the same
    bench flag was run headless on the PC, at HEAD and at the pre-Noodle commit `43ba035`.
15. Version numbers: 0.7.28 after step 3, 0.7.29 after step 6 (two `-Bump` builds).
16. **Build tab stopped before `BUILD apk` printed.** Both exports wrote the APK and then the Godot
    process did not exit, so the script never reached its `BUILD apk` line. The task said to stop
    the tab after that line. I stopped it once the APK file existed and had stopped growing, then
    ran the script's own remaining steps by hand: `aapt2` manifest check for version and hand
    tracking, `adb install -r`, and `dumpsys package` to confirm the version.
17. **Actions on the headset beyond `botrun.ps1`:**
    - power-key and wake key events over ADB to wake it before each attempt;
    - one `logcat -G 16M`, which enlarges the log buffer and was not reset;
    - deleting my own unconsumed `bench.flag`;
    - a force-stop of the game and the proximity-override release at the end.
    No settings, no user data and no song files were touched.
18. **PC user-data files overwritten** by the substitute benches, in
    `%APPDATA%\Godot\app_userdata\Open Saber Q3\`: `bench.flag` (removed afterwards), and
    `bench.csv`, `bench_meta.txt` and `audio_hits.csv`, which now hold the last PC run. 4a2b3 was
    copied into that folder's `Songs` and removed again.

## Device testing

**No bot run completed on the headset.** Both builds exported and installed, but every
`botrun.ps1` attempt ended `BOTRUN FAIL` for reasons on the headset's side, not the game's. The
evidence, from logcat and the bench files:

- The headset sits on a desk and falls asleep (`mWakefulness=Asleep`). It was woken with the
  power key over ADB before each attempt.
- On launch, the Guardian boundary dialog opens over the game. At 23:01 it held the launch for
  2 min 50 s ("Launch is blocked because: a Guardian dialog is currently showing"), longer than
  the script's 165 s deadline. In the final attempt (23:50, 0.7.29) the game started, the
  Guardian dialog opened 3 s later and paused it (`OnPause`) before its main loop began, and it
  never resumed.
- `botrun.ps1` prints whatever `bench_meta.txt` holds. The scores it printed in the failed runs
  are stale: 52 hits / 0 wrong from another session's 21:17 run, then 0 / 0 from 23:00.
- **The 0-hit run is not a gameplay result.** At 22:57, just after the 0.7.28 install, a bench
  started and wrote 0 hits (`bench_meta.txt`, 23:00). The bench never played. Its
  `bench.csv` has 99 frames over 0.88 s (`elapsed_s=0.878`), and the metadata gives the reason:
  `exit_reason=song_end`, `song_stream=null`, `song_playing=false`, `first_note_ms=-1.0` (no note
  was ever spawned), with the display at 72 Hz instead of the 120 Hz requested. The headset was
  not in a focused session, so the song never loaded. The bench saw no song and stopped at once.
  For comparison, the 21:17 full run's `bench.csv` was 664 KB, against 12 KB here. ODDS has no
  Noodle data either way.
- **0.7.29 itself boots on the headset**: at the final launch the log shows
  `OnGodotMainLoopStarted`, the palette and perf-panel startup lines, and no script or parse
  errors. The APK contains `game/noodle/*.gdc`.
- My unconsumed `bench.flag` was removed from the headset afterwards, so the next normal launch
  does not start a bot run. The game was force-stopped and the proximity override released.
  Nothing else on the headset was changed and no user data was touched.

**Substitute: the same bench headless on the PC.** Same bench flag as `botrun.ps1` (bot on, miss
0 %), run with Godot 4.6.3 on the PC at HEAD and at `43ba035`, the commit before this work.
The bot's numbers vary between runs, so ranges are given:

| Map | HEAD | 43ba035 | Script errors |
|---|---|---|---|
| ODDS&ENDS ExpertPlus, 45 s (no Noodle) | 46-48 hits / 4-6 wrong | 46 / 6 | 0 |
| Gloom ExpertPlus, 60 s (345 animated walls, v2) | 15-47 / 57-89 | 8-26 / 78-96 | 0 |
| Turret Orchestra (4a2b3) Hard, 60 s (tracked notes, paths, parent and player track, own offsets; v3) | 11 / 38 | 11 / 38 | 0 |

4a2b3 was copied into the PC's song folder for this run and removed afterwards. On the PC, the
Gloom frame time is p99 14.1-15.5 ms at HEAD against 12.2 ms at 43ba035, and the run gets 1.4 %
fewer frames. ODDS and 4a2b3 show no difference worth naming.

## All 16 Noodle fixtures

Two checks over every Noodle fixture map (all 16, every difficulty), run headless on the PC
after the final commit of code:

- **Loading**: `map_dump` at HEAD and at `43ba035` (the commit before this work). All 16 dumps
  are byte-identical, so the static parse of these maps is unchanged, and there were 0 script
  errors. The dump tool segfaulted once on the *old* code (d7fa, retried), the known crash.
- **Animation sweep** (a temporary scene, not committed): each difficulty loaded through
  `Map.load_beatmap`, every custom event dispatched and animated at half-beat steps through the
  song, then every animated object evaluated at three lifetimes. 0 non-finite transforms and 0
  script errors in all 35 difficulties. Unknown event properties such as `height`, `startY` and
  `attenuation` come from Chroma fog animation on v2 maps. Per difficulty: events, animated
  objects, tracks, bad values, and what the pause menu will report:

```
1362d HardStandard.dat events=0 animated_objects=1598 tracks=0 bad=0 unsupported=[]
198f3 ExpertPlus.dat events=7 animated_objects=1675 tracks=7 bad=0 unsupported=["Chroma environment"]
1e6ff ExpertStandard.dat events=16867 animated_objects=4646 tracks=4013 bad=0 unsupported=["Chroma environment", "Chroma component/fog events", "arrow dissolve", "Chroma colour animation", "animated height", "animated startY", "animated attenuation"]
1e6ff ExpertPlusLawless.dat events=16868 animated_objects=4672 tracks=3797 bad=0 unsupported=["Chroma environment", "Chroma component/fog events", "arrow dissolve", "Chroma colour animation", "animated height", "animated startY", "animated attenuation"]
210e3 ExpertPlusStandard.dat events=448 animated_objects=279 tracks=360 bad=0 unsupported=["Chroma environment"]
23f6b ExpertPlusStandard.dat events=17311 animated_objects=3305 tracks=1650 bad=0 unsupported=["Chroma environment", "Chroma component/fog events", "Chroma colour animation", "animated startY"]
352d8 HardStandard.dat events=2 animated_objects=5332 tracks=4 bad=0 unsupported=["Chroma environment"]
352d8 ExpertStandard.dat events=13 animated_objects=5332 tracks=4 bad=0 unsupported=["Chroma environment"]
352d8 ExpertPlusStandard.dat events=16 animated_objects=5332 tracks=4 bad=0 unsupported=["Chroma environment"]
3bbb0 ExpertPlusStandard.dat events=9923 animated_objects=69 tracks=2995 bad=0 unsupported=["Chroma environment", "Chroma geometry materials", "Chroma component/fog events", "player head/hand tracks", "arrow dissolve", "Chroma colour animation"]
43a1f NormalStandard.dat events=868 animated_objects=160 tracks=98 bad=0 unsupported=["Chroma environment", "custom Unity assets", "Vivify events", "player head/hand tracks", "arrow dissolve"]
43a1f HardStandard.dat events=868 animated_objects=160 tracks=98 bad=0 unsupported=["Chroma environment", "custom Unity assets", "Vivify events", "player head/hand tracks", "arrow dissolve"]
43a24 HardStandard.dat events=129 animated_objects=40 tracks=243 bad=0 unsupported=["Chroma environment", "custom Unity assets", "Vivify events", "Heck point bases/modifiers", "player head/hand tracks"]
43a25 EasyStandard.dat events=43 animated_objects=123 tracks=20 bad=0 unsupported=["Chroma environment", "Chroma geometry materials", "custom Unity assets", "Vivify events"]
43a25 NormalStandard.dat events=43 animated_objects=145 tracks=20 bad=0 unsupported=["Chroma environment", "Chroma geometry materials", "custom Unity assets", "Vivify events"]
4968d ExpertStandard.dat events=1342 animated_objects=444 tracks=165 bad=0 unsupported=["Chroma environment", "custom Unity assets", "Vivify events", "arrow dissolve", "track time animation"]
4968d ExpertPlusLawless.dat events=2045 animated_objects=703 tracks=226 bad=0 unsupported=["Chroma environment", "custom Unity assets", "Vivify events", "arrow dissolve", "track time animation"]
4a2b3 HardStandard.dat events=17 animated_objects=107 tracks=4 bad=0 unsupported=["Chroma environment", "custom Unity assets", "Vivify events"]
4a2b3 ExpertStandard.dat events=17 animated_objects=149 tracks=4 bad=0 unsupported=["Chroma environment", "custom Unity assets", "Vivify events"]
4a2b3 ExpertPlusStandard.dat events=17 animated_objects=714 tracks=4 bad=0 unsupported=["Chroma environment", "custom Unity assets", "Vivify events"]
4a2b3 ExpertOneSaber.dat events=18 animated_objects=131 tracks=5 bad=0 unsupported=["Chroma environment", "custom Unity assets", "Vivify events"]
4a2b3 ExpertPlusOneSaber.dat events=18 animated_objects=612 tracks=5 bad=0 unsupported=["Chroma environment", "custom Unity assets", "Vivify events"]
4a2b3 EasyLawless.dat events=0 animated_objects=111 tracks=2 bad=0 unsupported=["custom Unity assets"]
4a2b3 NormalLawless.dat events=1 animated_objects=130 tracks=3 bad=0 unsupported=["custom Unity assets"]
4a2b3 HardLawless.dat events=0 animated_objects=153 tracks=2 bad=0 unsupported=["custom Unity assets"]
4a2b3 ExpertLawless.dat events=1 animated_objects=611 tracks=3 bad=0 unsupported=["custom Unity assets"]
4a2b3 ExpertPlusLawless.dat events=0 animated_objects=734 tracks=2 bad=0 unsupported=["custom Unity assets"]
4a2b3 ExpertPlusLightshow.dat events=19 animated_objects=0 tracks=6 bad=0 unsupported=["Chroma environment", "custom Unity assets", "Vivify events"]
5587c ExpertPlusStandard.dat events=0 animated_objects=0 tracks=0 bad=0 unsupported=[]
5587e ExpertPlusStandard.dat events=0 animated_objects=0 tracks=0 bad=0 unsupported=[]
L-55820 ExpertPlusStandard.dat events=0 animated_objects=0 tracks=0 bad=0 unsupported=[]
d7fa EasyStandard.dat events=0 animated_objects=610 tracks=0 bad=0 unsupported=[]
d7fa HardStandard.dat events=0 animated_objects=610 tracks=0 bad=0 unsupported=[]
d7fa ExpertStandard.dat events=0 animated_objects=610 tracks=0 bad=0 unsupported=[]
d7fa ExpertPlusStandard.dat events=0 animated_objects=345 tracks=0 bad=0 unsupported=[]
```

## Final check.ps1 output

`pwsh tools/dev/check.ps1` at `b21040d` (0.7.29), complete output:

```
ok    tools/harness/verify_parse.tscn
ok    tools/harness/verify_settings_schema.tscn
ok    tools/harness/settings_roundtrip.tscn
ok    tools/harness/verify_settings_panel.tscn
ok    tools/harness/verify_io_fixes.tscn
ok    tools/harness/verify_hand_path.tscn
ok    tools/harness/verify_scoring.tscn
ok    tools/harness/rotation_probe.tscn
ok    tools/tests/test_chain_cut.tscn
ok    tools/harness/verify_noodle.tscn
ok    boot (0 errors)
CHECKS PASS
exit 0
```

(`exit 0` is the wrapper echoing the script's exit code.)

The `map_dump` of `%TEMP%\toolchain\allsongs\3af66` (no Noodle data) was compared after every
step against the dump taken before the first change, and was byte-identical each time; final
comparison: `DUMP IDENTICAL`. One dump attempt (after step 3) wrote a truncated file, the
known intermittent crash of that tool on old code too; the retry was identical.

`verify_noodle.tscn` on its own at the same commit:

```
NOODLE checks=213 failed=0
NOODLE PASS
```

Twice in about 40 harness runs during the night, a run did not produce its `NOODLE PASS` line:
once inside `check.ps1` after step 2, and once standalone right after the final check. Both
outputs had been filtered, so it is not known whether the process printed nothing or died part
way, for example while loading a fixture map, like the known `map_dump` crash. Neither
reproduced on immediate reruns (6 of 6 and 6 of 6 passed). The first coincided with a script
being written mid-run. If `check.ps1` ever reports `verify_noodle` as FAIL with no NOODLE FAIL
lines under it, rerun it once before investigating.

## Final botrun.ps1 output

`pwsh tools/dev/botrun.ps1 -Map "ODDS" -DifficultyIndex 5 -Seconds 45` after installing 0.7.29,
complete output (the scores are stale, from `bench_meta.txt` of 23:00; see Device testing):

```
C:\Users\HTPC-A~1\AppData\Local\Temp\bench.flag: 1 file pushed, 0 skipped. 0.2 MB/s (127 bytes in 0.001s)
BOTRUN started 'ODDS' difficulty 5 for 45 s ...
  bot_score_points=0
  bot_score_right_notes=0.00
  bot_score_wrong_notes=0.00
  bot_score_full_combo=true
BOTRUN script errors: 0
BOTRUN FAIL
```

**Not `BOTRUN PASS`.** The game was paused by the Guardian dialog before its main loop started.

## Installed on the headset

**0.7.29** (versionCode 45), installed with `adb install -r` at about 23:47 on 2026-11-12;
`dumpsys package` reports `versionName=0.7.29`. APK: `F:\Dev\BeepSaberBin\OpenSaber-v0.7.29.apk`
(78.5 MB, manifest checked for version and hand tracking). 0.7.28 was installed in between.

## What to try first in the headset

1. **Run the bot check with the headset on your head** (or the Guardian boundary set up), since it
   could not complete overnight:
   `pwsh tools/dev/botrun.ps1 -Map "ODDS" -DifficultyIndex 5 -Seconds 45`. It should end
   `BOTRUN PASS` with about 52 hits and 0 wrong, as before. ODDS has no Noodle data, so it runs
   none of the new per-object code; if the hits drop, that points at the spawn loop change of
   step 5 (`spawn_lead`), the only change on that path.
2. **Then play Gloom ExpertPlus** if it is still in the library (it was benchmarked on the headset
   before; its 345 animated walls rotate and move with `_animation` / `_definitePosition`).
   Watch for walls that spin and slide into place, and for frame drops at the wall sections.
   The pause menu should no longer say "Chroma/Noodle animation".
3. **Then a map with animated notes.** The library could not be listed overnight (it is in the
   app's private storage), so no installed map with tracked notes was confirmed. Any BeatSaver
   map that requires Noodle Extensions and uses `AnimateTrack` / `AssignPathAnimation` on notes
   will do; the pause menu names whatever of it is not played. Avoid 4a2b3 "Turret Orchestra"
   as a first test: it is a Vivify map and sends its notes 60 m away at beat 320 on purpose,
   because Vivify draws them as something else.

## Dissolve as a fade (after 0.7.29, 2026-11-13)

Commits `bf6b050`, `49efb23`. Heck's source (`CutoutManager.cs`, `NoteUpdateNoodlifier.cs`):
dissolve 1 is fully drawn and 0 is gone. Heck passes `1 - dissolve` to Beat Saber's noise
cutout, not to transparency. `dissolveArrow` is a separate cutout for note arrows (not bombs).

What was done:

- **Notes**: new instance uniforms `note_dissolve` and `note_dissolve_arrow` (default 1) in
  `BeepCube.gdshader`. Below 1, pixels are discarded against object-space noise
  (`game/noodle/noodle_dissolve.gdshaderinc`) and the white inside faces are dropped.
  `dissolveArrow` scales the arrow/dot emission texture. A discard keeps notes in the opaque
  pass; alpha blending would move every note to the transparent pass, with overdraw and sorting.
  The shader already had a discard.
- **Bombs**: shader copies of the two `StandardMaterial3D`s (`game/Bomb/bomb_*dissolve.gdshader`)
  are swapped in only while dissolve is below 1, and the originals come back at 1 and on spawn.
- **Walls**: a `dissolve` instance uniform scales the alpha of the already-blended wall
  materials. The bench-only opaque material swaps to the blended one while a wall dissolves.
- At dissolve 0 the object is hidden, as before. Interactable behaviour is unchanged. Values are
  written only on change and reset on pooled reuse, with no per-tick allocation and no writes to
  shared materials. Also fixed: a wall that spawned at dissolve 0 was drawn until its next tick.
- Cost for ordinary maps: no new draw calls or materials. Each note pixel gains one instance
  uniform test, and the note arrow and wall alpha each gain a multiply by exactly 1.0, so the
  picture is unchanged.

Differences from Beat Saber, on purpose:

- A note at dissolve 0 hides its arrow too; Beat Saber can show an arrow alone.
- A partly dissolved note's arrow is cut by the body's noise.
- The floor reflection is not faded (its colour shares an instance slot with the note colour).
- Cut pieces of a dissolving note are whole.
- Walls fade by transparency.
- Chain links take no Noodle data, as before.

Checked on the PC:

- `check.ps1` ends `CHECKS PASS`.
- `verify_noodle` passes 236 checks (23 new). They cover the value reaching each object type,
  the defaults of 1, reuse, the shared material, and spawn() at dissolve 0.
- The 3af66 `map_dump` is byte-identical.
- The changed shaders and the real note and bomb scenes (mirror pass on) were drawn in a window
  with the mobile renderer, with no shader errors. Notes showed the fade and the arrow fade.
- The new include ships because every export preset uses `all_resources`.
- `verify_noodle` died part way through fixture loading in 2 of 7 runs, before the new checks.
  This matches the known intermittent loader crash.

Not verified (needs the headset):

- How the fade looks at 120 Hz, including noise cell size and shimmer.
- GPU frame time for ordinary and dissolve-heavy maps.
- Whether the bomb pops visibly when it swaps material at 1.
- A possible one-time pipeline hitch the first time a bomb dissolves.
- The new shader files have no `.uid` yet; the editor adds them.

What to look at first: a map whose notes dissolve in, comparing its frame time with 0.7.29, and
then an ordinary map's frame time with 0.7.29.

## Loader crash (after 0.7.29, 2026-11-13)

Commit `6e427e1`. **Cause, proven:** MapData's loader threads start and join their own helper
threads, so `Utils.thread_finished`, a plain GDScript Array, was appended to and removed from by
several threads at once. GDScript containers are not thread-safe. The race showed directly as
`The calculated index 7 is out of bounds (the array has 7 elements)` from `remove_at()` in
`custom_thread_wait_to_finish`, called from `load_arc_stack_v3` on a worker thread. It also
showed as crashes (exit codes 127 and 139) and truncated dumps.

**Fix:** a Mutex around the two bookkeeping containers. It is never held across a wait or a
call, so it cannot deadlock. Nothing else changed.

**Rate:** `map_dump` run headless on 3af66, 32693 and d7fa, 40 times each.

| | 3af66 | 32693 | d7fa | Total |
|---|---|---|---|---|
| Before | 20 of 40 failed | 23 of 40 | 3 of 40 | 46 of 120 (38 %) |
| After | 0 of 40 | 0 of 40 | 0 of 40 | 0 of 120 |

Every complete dump, before and after, is byte-identical for its map. The two silent
`verify_noodle` runs from the night died while loading fixture maps, which fits this cause. I
saw two more silent runs earlier today, before the fix. After it, every `verify_noodle` run I
made printed its result (10 of 10 in a row at the final commit, 272 checks each).

## Noodle fixes: v4 bombs and walls, arc/chain heads, static rotation (after 0.7.29)

- **v4 bombs and walls** (`8a88ca0`): the v4-to-v3 expansion now copies their customData, from
  the object entry or else its shared data entry, as it did for notes. Tracks, animation and jump
  overrides reach them.
- **Arc and chain heads across spawn frames** (`827efa2`): a note with its own jump spawns
  earlier or later than its arc or chain, but the head was only looked up among notes spawned in
  the same frame. Only on maps where notes have their own jumps, `NoodleTracks.link_heads` now
  links each arc and chain to its head, and each arc to its tail, at load, by beat, colour and
  grid position.
  - An arc or chain whose head has not spawned yet waits and spawns with it, or spawns without a
    head once its beat has passed.
  - Other maps take exactly the old path.
  - Arcs and chains still do not follow an animated head (out of scope).
  - Exercised at runtime by the bench on 43a25 "Lifelike" NormalStandard (47 linked arcs, 10
    linked chains, 57 heads with their own jump; copied into the PC song folder for the runs and
    removed afterwards). The runs had 0 script errors, and the arcs attached to their head cubes
    (the `ARC head off` probe, which needs a head cube, fired; before this change it never did).
    The bot's result is noise on this Vivify map: 20-42 right notes in three runs before the
    change, 20-39 in three runs after. ODDS ExpertPlus (no Noodle, 45 s) at the final code gave
    49 hits / 3 wrong with 0 script errors (baseline 46-48 / 4-6). Fixtures that link heads:
    3bbb0, 43a1f, 43a25 and 4a2b3.
- **Static rotation** (`9344eda` and `3251e0f`, **changes how existing maps look**): world and local rotation
  are now read separately and converted to the Godot frame with the same `euler_to_quat` as the
  animated rotations.
  - They are composed as Heck does: note = world × local × cut direction, wall = world × local.
  - A world rotation given as one number is a y turn.
  - x and y turns were mirrored before; z turns look the same.
  - A pooled note also no longer keeps the previous note's x/y turn.
  - The order follows Heck's source: `NoteInitNoodlifier` sets the note root to world × local,
    and Beat Saber turns the cut direction on a child (`3251e0f`; `9344eda` first had it the
    other way). A check with cut direction 3 tells the two orders apart.
  - Follow-up, not changed: `NoodleAnim` composes animated rotation as offsetWorldRotation ×
    (static rotation including the cut) × localRotation, so an animated localRotation also sits
    inside the cut turn. By the same source it should sit outside.
  - Still not done: a static world rotation turns the object but not its path around the player,
    as before.
- Harness checks: 4 for v4, 10 for head links, and 7 for rotation. The rotation checks compare
  against hand-computed axes, including one through `BeepCube.spawn()`.
- **Dumps:** none of these three changes any fixture dump. No fixture is a v4 map with bomb or
  wall customData; head links are runtime only; and the dump does not record rotation. The
  fixtures whose data contains rotation keys (static or animated) are 1362d, 198f3, 1dcf4,
  1e6ff, 210e3, 23f6b, 352d8, 3bbb0, 43a1f, 43a24, 43a25, 4968d, 4a2b3 and d7fa. Those with
  static x/y turns now look different.

## Fake objects drawn (after 0.7.29)

Commit `7dc902a`. Fake notes, bombs and walls are loaded, drawn and animated. This covers `fake`
/ `_fake`, and v3 `customData.fakeColorNotes` / `fakeBombNotes` / `fakeObstacles` merged into
the stacks by beat.

- They use the existing non-interactable path: never hittable, never missed, never scored, not
  in max score or combo (both are counted on cut and miss events, which fakes never raise).
- They are never an arc or chain end, and the bot skips them.
- Fake walls have their collision disabled, so no energy drain and no rumble.
- Maps without fakes: the v3 fake arrays return at once when absent, and the spawn loop gains
  one boolean test per spawned note.
- No settings key fits, so there is no toggle.
- Not read: v4 maps' fake arrays (the v4 expansion does not look for them).
- The harness checks that a fake object is not interactable, which is the flag the miss path
  tests (`_n_can_hit`). It does not drive an object past the miss line.
- Pool growth: 352d8 peaked at 270 live walls in its first 150 s, above the wall pool's presize
  of 256, so the pool grows during that map (its fake walls run to 300 s).
- 16 harness checks.

Fake objects per fixture (fake / all in the loaded stacks):

| Map | Difficulty | Notes | Bombs | Walls |
|---|---|---|---|---|
| 1e6ff | ExpertStandard | 1651 / 2543 | 0 / 8 | 0 / 3746 |
| 1e6ff | ExpertPlusLawless | 1771 / 2905 | 0 / 8 | 0 / 3530 |
| 210e3 | ExpertPlusStandard | 1079 / 1338 | 60 / 80 | 0 / 0 |
| 23f6b | ExpertPlusStandard | 827 / 1746 | 0 / 0 | 2386 / 2386 |
| 352d8 | Hard, Expert, ExpertPlus | 0 / 687 | 0 / 0 | 2753 / 5612 |
| 3bbb0 | ExpertPlusStandard | 51 / 1102 | 0 / 360 | 0 / 249 |
| 43a24 | HardStandard | 0 / 32 | 1 / 9 | 0 / 0 |
| 4968d | Expert, ExpertPlusLawless | 16 / 460, 16 / 719 | 0 | 0 |
| 4a2b3 | 8 difficulties | 1 to 31 per difficulty (12 / 12 in its Lightshow) | 0 | 0 / 473 |

Every other fixture has none.

**Dumps that change:** 1e6ff, 210e3, 23f6b, 3bbb0, 4968d and 4a2b3, each gaining NOTE lines for
their fake notes. Fake bombs are not dumped. Fake walls were already loaded (and skipped at
spawn) and dumped with `fake=true`, so 352d8 does not change although it gains the most drawn
objects. 3af66 is unchanged.

**PC frame time** (the same bench flag as `botrun.ps1`, run headless on the PC, so CPU only):
each map before (`9344eda`) and after (`7dc902a`), two 45 s runs each. The GPU cost of drawing
the fakes on the headset is not measured.

| Map (difficulty, 150 s from song start) | Fakes drawn in that span | Before p99 / p95 / mean (ms) | After p99 / p95 / mean (ms) |
|---|---|---|---|
| 352d8 Lend Me Your Voice (ExpertPlusStandard) | fake walls from 83 s; peak live walls 200 before, 270 after | 10.5 / 9.1 / 6.9 | 11.4 / 9.7 / 6.9 |
| 1e6ff Somewhere Out There (ExpertPlusLawless), run 1 | fake notes from 50 s | 69.5 / 13.6 / 8.7 (a spiky run: max 167 ms) | 16.3 / 12.9 / 7.2 |
| 1e6ff, run 2 | | 15.4 / 12.6 / 7.2 | 17.4 / 13.1 / 7.2 |

So on the PC, p99 rises by about 1 ms on 352d8 and about 1-2 ms on 1e6ff (ignoring the spiky
first 1e6ff run before). The mean is unchanged. The bot's wrong-note count did not rise (1e6ff
202/196 before/after, 352d8 37/40), which fits the fakes never being scored.

The first runs used 45 s and were discarded: neither map has a fake object in its first 45 s
(352d8 starts at 83 s, 1e6ff at 50 s). For the runs, 352d8 was copied into the PC song folder
and removed afterwards (1e6ff is already in the library). As before, the runs overwrote the PC
user-data files `bench.csv`, `bench_meta.txt` and `audio_hits.csv`, and also updated
`config.ini`, `highscores.json` and `play_count.json` there. No backups of those were taken.

Not verified (needs the headset): how the fakes look, and what they cost on the Quest's GPU. For
1e6ff that is about 1,800 extra notes; for 352d8, 2,753 extra walls, which are alpha-blended
panels and so overdraw.

What to look at first: 1e6ff "Somewhere Out There" ExpertPlusLawless, which is already in the
library. Check that the decorative notes appear, cannot be hit and never break combo, and watch
its frame time. Then a map with static x/y rotations (any fixture above), to judge the changed
static turns.

## Noodle CPU cost on 1e6ff (after 0.7.30)

Commits `e112ae2` (probe columns), `016dacb` (lazy evaluation) and `9915127` (evaluators).
Nothing looks different: every value read is the same as before, bit for bit (checked below),
and every fixture dump is byte-identical before and after.

**What the cost was, measured before changing anything.** `event_usec` on 1e6ff
ExpertPlusLawless is almost all `NoodleEvents.update()`: the new `noodle_update_usec` column is
within 2 % of `event_usec`, so lighting events are not the cost. The new `noodle_tweens` column
peaks at 516-522 animations running at once in the first 50 s. On the PC, update() took about
5.8-7.5 ms per physics tick. That is more than half the 8.3 ms a tick has at 120 Hz, so the game
fell into running 8 ticks per frame (`phys_ticks` 8.0), which is the spiral seen on the headset.
1e6ff has 16,869 events over 3,349 tracks, but its live notes use only a few of those tracks.

**1. Lazy evaluation** (`016dacb`). A running animation now sits on its track, at most one per
property, so stopping one is O(1) instead of a scan of every animation. It is stepped only when
something reads the track (an object's evaluate(), a parent chain, the player's track), at most
once per tick. Parent and player transforms are also computed only when read. update() now
only moves the clock and refreshes the player's root.

Why the values are identical: an animation's value depends only on the time it is stepped at
and on how many repeats earlier steps used up. While time moves forward, one late step uses up
the same repeats, with the same float additions in the same order. A finished animation leaves
its end value whenever it is stepped. A new animation of a property overwrites the old one's
value completely. When time goes backwards (an audio stall snap or a seek), every running
animation is first stepped at the old time, as the ticks in between would have done.

**2. Per-object cost** (`9915127`). The direction suggested caching objects whose tracks and
paths hold constant values. The data shows that would rarely hit on 1e6ff: 2,910 of its 2,913
notes and all 3,530 walls have their own 2-4-point `_animation` paths, which change with
lifetime every tick. Measured on the PC, a note's tick was about 40-60 us. evaluate() was most
of that; track syncing was about 2 us, and compose and the transform write about 2-4 us each.
The evaluate() cost was GDScript call overhead: five calls per animated value. The point
evaluators are now written out inline (same arithmetic, same order), linear easing skips its
call, and evaluate() skips rotations, dissolves and interactable when nothing sets them. A
1e6ff-like note with six animated properties went from about 34 to 18 us per evaluate() in a
PC microbenchmark.

**3. Ordinary maps.** Nothing changed for them: all of this is behind `NoodleTracks.active`, as
before.

**Checks** (verify_noodle, now 296):
- 5 checks run the 0.7.30 eager stepping (kept as `tools/harness/noodle_eager_ref.gd`) and the
  lazy one over the same uneven ticks. The fixtures are 1e6ff, 4a2b3, 198f3, 23f6b and 352d8,
  with two jumps back in time. At every third tick a few random tracks are read, and every
  track is read after each jump and every 500 ticks.
- Every value, path value, parent, transform and the player's root must be identical. On 1e6ff
  that is 2.9 million values, 0 different.
- A deliberately broken catch-up made the 1e6ff check fail (3 values different), so the check
  can catch that kind of bug.
- 4 checks compare the inlined evaluators with the 0.7.30 ones, bit for bit, on every point list
  of four fixtures: 6.1 million values, 0 different.

**PC bench.** 1e6ff ExpertPlusLawless (difficulty_index 1), 110 s from song start, run headless
with the bot (CPU only). "Before" is 0.7.30 code plus the probe columns; "after" is `9915127`.
Each was run twice, interleaved. The PC had about 77 % CPU load from unrelated processes
throughout, so single runs are noisy, and the before runs differ a lot from each other. Each
cell gives event / cuttable / wall (us per frame); frame p50 / p95 / p99 (ms); physics ticks per
frame.

| Song time | Before, run 1 | After, run 1 |
|---|---|---|
| 0-10 s | 15911 / 1371 / 1851; 7.4 / 99.7 / 109.7; 2.5 | 624 / 233 / 408; 6.9 / 10.1 / 11.1; 0.8 |
| 10-20 s | 62045 / 5387 / 8160; 93.9 / 103.4 / 111.4; 8.0 | 619 / 256 / 520; 6.9 / 10.4 / 11.1; 0.8 |
| 20-30 s | 59884 / 5005 / 7686; 88.7 / 104.5 / 118.7; 8.0 | 636 / 260 / 539; 6.9 / 10.4 / 11.1; 0.8 |
| 30-40 s | 62601 / 5593 / 8819; 94.3 / 103.0 / 108.0; 8.0 | 621 / 258 / 535; 6.9 / 10.3 / 11.2; 0.8 |
| 40-50 s | 60963 / 5879 / 7987; 92.4 / 102.8 / 104.7; 8.0 | 595 / 299 / 500; 6.9 / 10.3 / 11.1; 0.8 |
| 50-60 s | 2083 / 1366 / 2156; 7.7 / 17.1 / 32.4; 1.0 | 692 / 991 / 1744; 7.1 / 13.0 / 15.5; 0.9 |
| 60-70 s | 2102 / 1413 / 3127; 8.1 / 19.6 / 60.1; 1.2 | 662 / 947 / 2204; 7.1 / 13.4 / 16.3; 0.9 |
| 70-80 s | 1620 / 1442 / 1190; 7.3 / 13.9 / 17.0; 0.9 | 904 / 2019 / 1956; 7.8 / 16.7 / 26.2; 1.0 |
| 80-90 s | 1801 / 2139 / 993; 7.7 / 15.5 / 18.2; 0.9 | 871 / 2464 / 1558; 7.6 / 15.4 / 58.4; 1.0 |
| 90-100 s | 3681 / 3801 / 1762; 7.8 / 67.7 / 80.0; 1.6 | 656 / 1449 / 829; 6.9 / 12.5 / 14.0; 0.8 |
| 100-110 s | 1839 / 537 / 476; 7.0 / 12.3 / 14.9; 0.8 | 642 / 444 / 350; 6.9 / 10.2 / 11.4; 0.8 |
| whole run | mean 14.2; 7.6 / 87.1 / 99.9 | mean 7.2; 7.0 / 12.0 / 16.4 |

| Song time | Before, run 2 | After, run 2 |
|---|---|---|
| 0-10 s | 8204 / 502 / 691; 8.2 / 41.6 / 65.6; 1.7 | 731 / 278 / 475; 6.8 / 10.7 / 11.6; 0.8 |
| 10-20 s | 12409 / 728 / 1145; 9.5 / 59.4 / 77.2; 2.1 | 669 / 276 / 558; 6.8 / 10.6 / 11.3; 0.8 |
| 20-30 s | 56267 / 4324 / 6876; 84.5 / 108.3 / 113.6; 7.7 | 709 / 289 / 598; 6.9 / 10.9 / 11.7; 0.8 |
| 30-40 s | 67335 / 6543 / 10099; 97.1 / 138.8 / 174.6; 8.0 | 761 / 320 / 656; 6.9 / 11.2 / 12.2; 0.8 |
| 40-50 s | 60869 / 5736 / 7810; 91.2 / 108.2 / 116.6; 8.0 | 764 / 419 / 709; 6.9 / 11.6 / 12.9; 0.8 |
| 50-60 s | 5056 / 3373 / 5405; 8.7 / 74.0 / 96.3; 2.2 | 1867 / 3037 / 5682; 7.6 / 70.4 / 85.8; 2.0 |
| 60-70 s | 17668 / 14748 / 32424; 86.0 / 102.7 / 111.6; 8.0 | 8076 / 15954 / 37267; 84.7 / 102.5 / 105.0; 8.0 |
| 70-80 s | 4250 / 4081 / 3635; 8.4 / 78.3 / 92.8; 1.9 | 5948 / 14882 / 16109; 66.4 / 88.5 / 102.2; 5.7 |
| 80-90 s | 5547 / 7274 / 3401; 8.5 / 79.4 / 90.4; 2.5 | 6893 / 24326 / 15193; 67.2 / 85.8 / 97.6; 7.4 |
| 90-100 s | 2197 / 2027 / 933; 7.5 / 17.5 / 41.0; 1.0 | 1785 / 4544 / 2632; 7.8 / 69.4 / 80.8; 1.7 |
| 100-110 s | 1845 / 530 / 464; 7.0 / 12.1 / 16.7; 0.9 | 859 / 677 / 493; 6.9 / 11.4 / 13.6; 0.8 |
| whole run | mean 19.0; 8.1 / 87.6 / 107.1 | mean 10.7; 7.0 / 51.5 / 83.9 |

What this shows:
- **First 50 s** (no fake notes yet), where the headset spent 6.4-11.7 ms per frame in events:
  event time drops from 8-67 ms per frame to 0.6-0.8 ms, the spiral is gone in both after runs,
  and frame p99 falls from 65-175 ms to 11-13 ms.
- **50-90 s**: frame time is now set by the objects. Walls take about 1.5-4 ms per tick and notes
  about 2 ms; Noodle events are about 0.9 ms. In after run 2 this stretch still fell into the
  8-ticks-per-frame spiral, at the same per-tick cost as run 1. With the PC loaded as it was,
  this is where the tick budget runs out.
- **Whole run**: mean frame 14.2 / 19.0 ms before, 7.2 / 10.7 ms after; p99 100 / 107 ms before,
  16 / 84 ms after.

**Not verified:**
- The headset, where the owner's target is about 100 fps. Scaling the headset's 0.7.30 numbers,
  the 0-50 s event cost should drop from 6.4-11.7 ms per frame to under 1 ms. Whether the
  50-110 s part, now dominated by walls, holds 100 fps on the Quest is not known.
- The wall tick: its cost is evaluate() plus the transform write and the dissolve uniform
  write. It was sped up only through the shared evaluate(); it was not profiled separately.

**Notes:**
- `e112ae2` does not build on its own: its Playing.gd calls `NoodleEvents.live_tweens()`, which
  arrives in `016dacb`. Bisect over the pair.
- `noodle_tweens` now also counts animations that ended while no one read their track, until
  the track is next read, so after the change it reads 520-710.
- The bench runs again overwrote `bench.csv`, `bench_meta.txt`, `audio_hits.csv`, `config.ini`,
  `highscores.json` and `play_count.json` in the PC user data.
