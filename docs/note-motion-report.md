# Note motion: the fly-in before the jump (0.7.37)

On 0.7.36 the owner said that notes on an ordinary map seemed to "spawn 3 or 4 meters in front of
me", too fast. In Beat Saber they "pop into field 5-10 meters ahead". For that song the game
logged `MAP motion: njs=11.2 m/s spawn=2.29 beats ahead, 8.0 m away`, which is 0.716 s from a note
appearing to its hit at 192 BPM.

There were two causes, and this change addresses both:

1. **The fly-in was missing.** Beat Saber creates every object half a second before its jump
   starts, 100 m beyond the jump start. The object flies in at 200 m/s and only then travels at
   the map's NJS. We made each object appear at the jump start with nothing before it.
2. **The note's spawn "pop" ran during the whole jump.** Every note and bomb plays its
   `AnimationPlayer` "Spawn" animation (`BeepCube.tscn`, `Bomb.tscn`) when it is spawned, at
   `NJS / 9` speed:
   - The mesh stays at 10 % scale and is turned -180° until 0.3 s.
   - It grows to full size and turns to its cut direction by 0.8 s, with a 0.5 m hop at 0.6 s.

   On the owner's map (speed x1.244) the note was a speck until 5.3 m and reached full size only
   0.8 m from the hit plane, so it effectively appeared about 4-5 m out, as the owner describes.

   The pop is now timed by the jump, not by NJS / 9. It is over by the jump start when the object
   flies in, and by 1/8 of the jump without a fly-in, which is where Beat Saber has its note at
   its "middle" rotation (see "What changes on screen").

## What the sources say

Read from primary or open sources, not from memory:

- **Heck / Noodle Extensions**: [Aeroluna/Heck](https://github.com/Aeroluna/Heck) at `3bbcaf6`
  (MIT), cloned read-only.
- **Beat Saber's own constants**: the il2cpp codegen headers in
  [QuestPackageManager/bs-cordl](https://github.com/QuestPackageManager/bs-cordl), for game
  version 1.46.0_34060. They hold the constant values and field names but no method bodies.
- **An open reimplementation**: BeatLeader's web replay viewer,
  [BeatLeader/BeatSaber-Web-Replays](https://github.com/BeatLeader/BeatSaber-Web-Replays)
  (`src/components/beat-generator.js`, `beat.js`, `src/utils.js`).

### The move phase (fly-in)

| What | Value | Where |
|---|---|---|
| Move duration | **0.5 s** | bs-cordl `VariableMovementDataProvider::kMoveDuration{0.5f}`; BeatLeader `moveDuration: 0.5` |
| Move distance | **100 m** | bs-cordl `VariableMovementDataProvider::kMoveDistance{100.0f}` |
| Move speed | **200 m/s** (100 / 0.5) | bs-cordl `kInitMoveSpeed{200.0f}`; BeatLeader `BEAT_WARMUP_SPEED = 200` |
| Spawn ahead time | `kMoveDuration + halfJumpDuration` | Heck `NoodleMovementDataProvider.InitObject`, `SpawnDataManager.GetSpawnAheadTime` |
| Move start | `centerPos + forward * (kMoveDistance + halfJumpDistance)` | Heck `NoodleMovementDataProvider` (`_moveStartPositionOverride`); pre-1.40 path `SpawnDataManager.GetNoteJumpValues` |
| Move end = jump start | `centerPos + forward * halfJumpDistance` | same |
| Jump end | `centerPos - forward * halfJumpDistance` | same |
| Motion during the move | linear: `Vector3.Lerp(startPos, endPos, t / moveDuration)` | Heck `NoteFloorMovementNoodlifier` (transpiled line of `NoteFloorMovement.ManualUpdate`); walls `Vector3.LerpUnclamped(startPos, midPos, time / moveDuration)` in `ObstacleUpdateNoodlifier` |
| Look during the move | at its start layer, start rotation, full size (no scale in the move) | BeatLeader `beat.js` (`newY = startPos.y` while in the warm-up) |
| Noodle during the move | evaluated, at a **negative** lifetime (`(songTime - moveDuration) / ...` for walls; `elapsed / jumpDuration` from the jump start for notes); a definite position is taken at time 0 and the move offset added | Heck `ObstacleUpdateNoodlifier`, `NoteUpdateNoodlifier`, `NoteFloorMovementNoodlifier.DefiniteNoteFloorMovement` (`GetDefinitePositionOffset(..., 0, ...)`) |

Conflict:

- BeatLeader's web viewer declares `moveDuration: 0.5` but animates its warm-up with
  `BEAT_WARMUP_TIME = 0.3` (60 m).
- We follow the game's constants: 0.5 s and 100 m.

### The jump, re-checked

| What | Beat Saber (source) | Ours (`game/NoteMotion.gd`) |
|---|---|---|
| Half jump rule | start at 4 beats, halve while `njs * beatSec * beats > 18`, add the offset, minimum 0.25 beats (BeatLeader `calculateHalfJumpDuration`; Heck calls `CoreMathUtils.CalculateHalfJumpDurationInBeats(_startHalfJumpDurationInBeats, _maxHalfJumpDistance, njs, oneBeatDuration, offset)`, whose body is not in any source I could read) | the same, but halving while `> 17.999` |
| Player "reaction time" (Static jump type) | `NoteJumpValueType.JumpDuration`: half jump = the player's fixed duration (Heck `NoodleMovementDataProvider`: `_halfJumpDurationOverride = spawnOffset`) | not offered |
| NJS 0 | the difficulty default (BeatLeader uses 10 for `njs <= 0.01`) | 10 / 12 / 16 by difficulty rank |
| Gravity | `2 * (highestJumpPosY - lineYPos(startLayer)) / halfJumpDuration²` (Heck `CalculateCurrentNoteJumpGravity`, `NoteJumpGravityForLineLayer`) | none |
| Heights | line y `0.25 + 0.6 * layer` (bs-cordl `kBaseLinesYPos 0.25`, `kNoteLinesDistance 0.6`); jump peak `0.525 * layer + 0.858333 + jumpOffsetY` (Heck's regression) or `0.6(layer+1) + 0.05(5 - layer - [layer>1])` (BeatLeader) | `0.8 + 0.6 * layer` |
| Where z = 0 is | the note reaches the player's head z at its beat. BeatLeader `getZPos` adds `headOffsetZ * min(1, 2t)` and subtracts `SWORD_OFFSET = 0.9` | the track origin, fixed |
| Rotation in the jump | from the start rotation via a random "middle" rotation (±20°) to the cut direction in the first quarter (`sin(t·4π)`, `sin((t-0.125)·2π)` slerps), then a look toward the head until mid-jump (BeatLeader `beat.js`) | the Spawn pop: -180° to the cut direction about z |
| Horizontal | from the flip lane to the lane in the first quarter (`InOutQuad`), plus a flip y avoidance (BeatLeader) | none |
| Walls | full height during the move and jump (BeatLeader `wall.js` sets the size once and only moves the wall) | grow from 10 % height between the spawn distance and half of it (`Wall._apply_grow`, specs/029) |
| Spawn effect | an optional flash at the jump start (`hideNoteSpawnEffect` in bs-cordl `PlayerSpecificSettings`) | none |

What differs, all left as they were in this change:

- **The 17.999 m threshold.** Ours halves when a half jump comes to exactly 18 m (for example
  NJS 18 at 120 BPM: 2 beats = 18 m; Beat Saber keeps 2 beats, we use 1). The value dates from
  0.7.26 (`81ebdda`) with no reason recorded.
- **No gravity arc and no start layer.** Notes travel at their final height.
- **z = 0 does not follow the head.**
- **No jump rotation or look-at.** The Spawn pop stands in for them.
- **No flip-lane move.**
- **Walls grow.**
- **No reaction-time option.**

## What changed

`game/NoteMotion.gd` holds the constants:

- `MOVE_DURATION_S = 0.5` and `MOVE_DISTANCE_M = 100`.
- `fly_in_seconds()` is 0.5 when a map has configured the motion, and 0 when it has not.
  Harness scenes therefore keep the legacy numbers.
- `fly_in_speed()` is 200 m/s.
- The A/B switch `fly_in_enabled` is driven by the bench key `fly_in` (default true).

**Spawning** (`Playing._process_map`):

- An object is spawned when `seconds_to_beat(song + 0.5) + half jump` passes its
  `beat - spawn_lead`. That is half a second before its own jump starts, so Noodle per-object
  jumps keep their lead.
- `fly_in(rem)` is then called, where `rem` is the time to its jump start.
- Arcs and chains use the same look-ahead, so they still find their head among the notes spawned
  in the same pass.
- Chain links fly in with the same `rem` and speed as their head, so the chain keeps its shape.
- Arcs do not fly in. Their ribbon is built at the travel position: `Arc.spawn` subtracts the
  head's `fly_offset()`. The ribbon's distance fade hides it until it reaches the jump start
  distance.

**Flying** (`Cuttable`, `Wall`):

- The travel is integrated exactly as before, starting from the earlier spawn.
- Only the drawn z is pushed further out, by `(200 / speed - 1)` metres per metre of travel
  left before the jump start. An object therefore comes in at 200 m/s from 100 m beyond its jump
  start, and from the jump start on it is drawn at its travel position with no flying state left.
- An un-animated object flying in costs one float add and one transform write per tick. It skips
  the hit window, the miss, the wall grow and the inside fade.
- **Noodle objects** are posed in the frame pass at lifetime 0, as Heck does: point definitions
  read a negative time as their first point.
  - A definite position is pushed by the whole 100 m lead.
  - An offset rides on the travel.
  - The push goes inside the world rotation and the parent (`NoodleAnim.compose(..., fly_z)`).
  - A flying wall is never posed every tick (`_needs_tick_pose`).
- **Not hittable while flying.** A note, bomb or link never enables its hit while flying, even
  when a quarter-beat jump puts its travel inside the hit window. A wall's front stays beyond its
  jump start distance, so it cannot reach the player. Misses start from the jump on.
- **Pools** are sized with the fly-in (`MapData.peak_live(..., fly_sec)`, converted with the
  tempo at each object).

The `MAP motion` log line now ends with `fly-in 0.50 s from <jump distance + 100> m`.

### What changes on screen

- From the jump start on, the root of every note, bomb, wall and chain link is where 0.7.36 drew
  it (see the checks below).
- **The spawn pop of notes and bombs plays during the fly-in.**
  - `Cuttable.play_spawn_anim`: speed = animation length / time to the jump start, set in
    `fly_in()`.
  - The note is full size, unturned and settled at the jump start, 8-10 m out. In 0.7.36 it
    finished 0.8 m (owner's map) or 2.8 m (ODDS Hard) from the player.
  - With the fly-in off, or for an object spawned with less than 0.1 s of fly-in left, the pop
    ends `SPAWN_SETTLE_JUMP_FRACTION` = 1/8 of the jump after its start, at any NJS. This is the
    point where Beat Saber 1.8 `NoteJump` has its note at the "middle" rotation (cut direction
    plus up to ±20°); its final cut direction comes at 3/8.
  - The roll, hop and growth are kept as a flourish; none of it runs later than 1/8 of the jump.
  - This is the one visible change after the jump start: in 0.7.36 the pop was still running
    there.
  - Chain links never played it.
- **Walls fly in at the grow's 10 % height** and grow as before once they pass the spawn
  distance.

Stills (`%TEMP%\opensaber_previews\`, from `tools/harness/motion_preview.tscn`):

- `motion_fly_<ms>.png` and `motion_nofly_<ms>.png` at the same song times, on the owner's map
  motion (NJS 11.2, 192 BPM, 8.0 m).
- `motion_strip.png` puts them side by side.

## Cost

Peak live objects (`tools/harness/peak_live_probe.tscn`, `MapData.peak_live` as the pools are
sized):

| Map, difficulty | NJS, jump | Before (notes / bombs / walls / arcs) | With the fly-in |
|---|---|---|---|
| ODDS&ENDS ExpertPlusStandard | 17.0, 9.5 m | 10 / 12 / 6 / 4 | 14 / 20 / 9 / 5 |
| ODDS&ENDS ExpertStandard | 16.0, 10.0 m | 8 / 8 / 8 / 5 | 11 / 12 / 9 / 5 |
| ODDS&ENDS HardStandard | 14.0, 10.0 m | 8 / 4 / 8 / 6 | 10 / 4 / 9 / 8 |
| Somewhere Out There ExpertPlusLawless (1e6ff) | 19.0, 10.7 m | 82 / 8 / 397 / 0 | 99 / 8 / 575 / 0 |

Pools grow to these at load. `instantiated` stayed 0 in every bench run.

Per-tick cost of an object flying in:

- An un-animated one: one float add and one transform write. No hit, miss, grow or inside-fade
  work.
- A Noodle one: posed once per drawn frame at lifetime 0, as Heck evaluates it. The pose cache
  mostly hits.
- A flying wall has its collision shape off (`Wall._sync_shape`). That change was added after the
  first bench pairs below.

PC benches (headless, bot, `bench.flag` key `fly_in`). The PC was at 66-100 % load from other
processes (qbittorrent, python) throughout, so single runs are noisy:

| Run | Mean frame | p99 | > 25 ms | Physics step mean | Wall work / frame | Max notes live |
|---|---|---|---|---|---|---|
| 1e6ff, pair 1, fly-in off | 7.60 ms | 17.1 | 69 | 3024 us | 567 us | 74 |
| 1e6ff, pair 1, fly-in on | 8.12 ms | 23.1 | 212 | 3619 us | 676 us | 94 |
| 1e6ff, pair 2, fly-in off | 7.12 ms | 14.5 | 6 | 2251 us | 467 us | 74 |
| 1e6ff, pair 2, fly-in on | 7.11 ms | 14.5 | 12 | 2548 us | 579 us | 96 |
| ODDS E+, 120 s, fly-in off | 6.90 ms | 8.1 | 1 | 514 us | 2 us | 6 |
| ODDS E+, 120 s, fly-in on | 6.90 ms | 7.9 | 0 | 453 us | 2 us | 10 |

- Pair 2 is the cleaner one: on 1e6ff the fly-in costs about +0.3 ms of physics step and +0.1 ms
  of wall work per frame on the PC.
- ODDS shows no measurable cost.
- **Not run:**
  - A third pair (with the wall shape fix) ran at 96 % machine load. Its fly-in arm (11.3 ms mean,
    with untouched note code 1.6x slower too) is not usable and is not reported as a result.
  - The fourth pair was stopped before it ran.
  - So the shape fix is unmeasured, and the headset numbers are still to come.

## Checks

- **`tools/harness/verify_note_motion.tscn`** (new, in `check.ps1`): 65 checks, MOTION PASS. Each
  object runs from one map clock twice, flying in from 0.5 s before its jump and spawned at its
  jump start as before.
  - **Constants and switch:** 0.5 s, 200 m/s, and no fly-in when switched off or unconfigured
    (legacy 16 m).
  - **Plain note:**
    - created at -110 m for a 10 m jump start;
    - moves exactly 200 m/s x dt per tick while flying;
    - lands on the first tick at or after its jump start, at its travel z (continuous);
    - never hittable while flying;
    - drawn identically to the old spawn from then on (max difference 0.000000 m).
  - **Quarter-beat jump at 2 m:** the travel crosses the hit window while flying with no hit
    enabled, and the hit is enabled on the tick the jump starts.
  - **Noodle notes,** offset path and definite position:
    - posed at life 0 and pushed 100 m;
    - not hittable;
    - dissolve at the path's first point;
    - life 0 at the jump start (within one tick);
    - drawn as before from the jump start on (max 0.000019 m).
  - **Own NJS 20** (own half jump 1 beat): the spawner's time left, the -110 m creation, the jump
    starting at its own 1.5 s, and its own 10 m jump distance.
  - **Walls,** plain and Noodle: the front is created 100 m beyond its jump start and never comes
    closer while flying; position and grow are identical from the jump start on; a flying Noodle
    wall is never posed per tick.
  - **Chain:** a link keeps its distance to its head through the fly-in.
  - **Wall collision:** a flying wall's shape is off, and it is back on after the jump start.
  - **Spawn pop:** notes and bombs are at scale 1, rotation 0 and position 0, at the jump start
    with the fly-in, or at 1/8 of the jump without it. Tested for NJS 10, 14, 17 and 23 at 100 %
    and NJS 14 at 50 % Note Speed (ODDS&ENDS Hard tempo and offset).
  - **Pools:** `peak_live` counts the fly-in.
- **`pwsh tools/dev/check.ps1`:** CHECKS PASS.
- **Fixture dumps:** all 45 maps (3af66 included) are byte-identical to the 0.7.36 dump. The dump
  is parsed map data and does not depend on spawn timing.
- **ODDS&ENDS ExpertPlus replay** (fixed 120 Hz clock, bot, 60 s; each arm run twice and
  identical to itself):
  - Fly-in on: 114 cuts, 0 misses, score 32837.
  - Fly-in off: 114 cuts, 0 misses, score 32839.
  - Every note spawns exactly 60 frames (0.5 s) earlier.
  - 110 of 114 cuts are identical (frame, angle, distance, accuracy). The other 4 (beats 40, 122,
    123, 124) are cut one frame apart. They follow from an existing effect, not from the fly-in:
    - A pooled note enabled during a physics frame is sometimes ticked in that frame and sometimes
      not. This depends on which pool node it got (most likely its place in the processing order
      after `TrackLanes.place` reparents it).
    - The trace for beat 40 shows the old spawn ticked in its spawn frame and the fly-in's node
      not (`TRACE0 f=1433` vs the first tick at `f=1374` for a spawn at `f=1373`).
    - The note therefore runs one tick (0.14 m at NJS 17) behind or ahead, as some notes already
      did in 0.7.36.
    - Hit windows, scoring and the miss are unchanged.

## Harder or easier than Beat Saber?

Owner: "I just want to be sure that we aren't making it harder ourselves based on the designs we've
chosen." Every default of ours that changes difficulty against Beat Saber, with our value and Beat
Saber's.

Sources:

- the Beat Saber 1.46 constants (bs-cordl, above);
- a decompile of Beat Saber 1.8 ([toanlcgift/BS1.8.0RE](https://github.com/toanlcgift/BS1.8.0RE),
  `Main/`);
- BeatLeader's web replay viewer;
- Heck.

Two caveats on the 1.8 decompile:

- It shows method bodies and the code defaults of serialized fields.
- Unity scenes can override those defaults, so a "code default" is not proof of the shipped value.

Example map: the owner's ODDS&ENDS Standard Hard. NJS 14, offset -1.714 beats, 192 BPM; half jump
2.29 beats = 0.714 s = 10.0 m.

| # | What | Ours | Beat Saber | Verdict |
|---|---|---|---|---|
| 1 | Lead before the jump (fly-in) | none before 0.7.37; now 0.5 s from 100 m beyond the jump start at 200 m/s | 0.5 s, 100 m (1.46 `kMoveDuration`, `kMoveDistance`); 1.8 code: 200 m/s for 1 s | **was harder; fixed in 0.7.37** |
| 2 | Note spawn pop | before: mesh at 10 % size and -180° roll until 0.3 s, full size and final turn at 0.8 s, played at NJS / 9. On ODDS Hard (x1.56) a speck until 7.3 m and still turning and growing until 0.2 s before the hit, 2.8 m away. Now: over by the jump start (10 m) with the fly-in, or by 1/8 of the jump without it, at any NJS | full size from creation. Rotation: identity while moving in, then to a "middle" (cut direction + up to ±20° per axis) by 1/8 of the jump, to the cut direction by 3/8, blended toward the head by 1/2 (1.8 `NoteJump.ManualUpdate`) | **was harder; fixed in 0.7.37** |
| 3 | Jump distance rule | 4 beats halved while > 17.999 m, + offset, ≥ 0.25 beats | halve while > 18 m (1.8 code `_maxHalfJumpDistance = 18f`, BeatLeader); minimum 1 beat in 1.8 code, 0.25 in BeatLeader | neutral. Ours is shorter only where a half jump comes to exactly 18 m (one halving more: harder there). Faithful: `> 18` |
| 4 | Wall grow | a wall is 10 % tall at the spawn distance and full height only at half of it (5 m on ODDS Hard) | full size from creation (1.8 `ObstacleController`; BeatLeader `wall.js`) | **harder** (walls read late). Faithful: no grow |
| 5 | Note size | 0.5 m cube (mesh 0.5 m; the pop ends at mesh scale 1.0; the scene's resting scale is 0.8 = 0.4 m) | not in code (prefab); BeatLeader draws 0.4 m | unknown |
| 6 | Lane / row spacing | lanes x = -0.9, -0.3, 0.3, 0.9 (0.6 apart); rows y = 0.8, 1.4, 2.0 | lanes 0.6 apart, same x (1.8 `GetNoteOffset`, `_noteLinesDistance 0.6`); rows at the beat 0.85, 1.4, 1.9 (1.8 `_base/_upper/_topLinesHighestJumpPosY`) | neutral (top row 0.1 m higher) |
| 7 | Good-cut hitbox | 0.8 x 0.5 x 1.0 m, dots 0.8 tall, centre 0.25 m behind the note | 0.8 x 0.5 x 1.0, dots 0.8 (BeatLeader `toBigBox`) | neutral (the 0.25 m offset is unverified) |
| 8 | Bad-cut box (other saber) | 0.375 m cube | 0.35 m (BeatLeader comment "Actual hitbox is 0.35x0.35x0.35") | slightly harder (marginal) |
| 9 | Where the note is at its beat | z = 0 at the player's origin | the jump's centre, with the head's z followed during the jump; BeatLeader places it `SWORD_OFFSET = 0.9` m in front of the head | unknown (unverified in Beat Saber's code) |
| 10 | Miss | 2.5 m past z = 0, any NJS (0.18 s at NJS 14, 0.11 s at NJS 23) | 0.15 s after the beat (1.8 `NoteJump.kMissedTimeOffset`) | neutral at NJS 14 (a little easier below NJS 16.7, harder above). Faithful: 0.15 s |
| 11 | Hit window opens | from 3 m out (`Cuttable.ENABLE_Z`) | not found | unknown |
| 12 | Cut direction tolerance | ±60° (`strict_cuts`: dot ≥ 0.5) | ±60° (1.8 `NoteBasicCutInfo`: angle in (-150°, -30°), `kCutAngleTolerance 60`) | neutral |
| 13 | Minimum blade speed | 2 m/s (`STRICT_MIN_SPEED_MPS`) | 2 m/s (`kMinBladeSpeedForCut`) | neutral |
| 14 | Other bad cuts | wrong saber, wrong direction or too slow (strict on) | the same, plus a "stab" along the note's z (more than 10x the sideways part) | neutral (we have no stab rule: slightly easier) |
| 15 | Gravity arc | none: notes travel at their final height | they rise from their start row to their row with gravity over the first half of the jump | neutral to easier: a straight path is easier to track, but Beat Saber's rise is part of its readability |
| 16 | Rotation in the jump, and look at the player | now settled by the jump start; no look-at | a small random wobble, then the cut direction by 3/8, turned toward the head until mid-jump | unknown. Without the look-at, arrows on the outer lanes and top row are seen at an angle close up |
| 17 | Head in wall | a 0.07 m sphere around the head | the head point inside the wall's bounds (1.8 `PlayerHeadAndObstacleInteraction`) | slightly harder (7 cm) |
| 18 | Bomb volume | a sphere of radius 0.154 m | not in code (prefab) | unknown |
| 19 | Energy | start 50 %; good +1 %, bad -10 %, miss -15 %, bomb -15 %, wall -130 %/s | 1.8 code defaults: start 50 %, good +5 %, bad -10 %, miss -10 %, bomb -15 %, wall -10 %/s. These are serialized fields; the shipped scene values are not in the decompile (ours are the commonly documented ones) | unknown |
| 20 | No Fail | default on; energy is not shown | 1.8: with No Fail energy never changes (`AddEnergy` returns) | neutral |

**What makes the game harder than Beat Saber, and the faithful value:**

1. Before 0.7.37, the missing fly-in and the late spawn pop (1, 2). Both are fixed now.
2. Wall grow (4). Faithful: full size from creation.
3. The bad-cut box is 0.375 m against 0.35 m (8). Faithful: 0.35 m.
4. The head-in-wall sphere has a 0.07 m radius against a point (17). Faithful: radius 0.
5. Possibly the hit plane at the player (9) and the missing look-at (16). Both are unverified.

Nothing above was changed except the fly-in and the spawn pop; the owner decides the rest.

## Per-song modifiers (0.7.38)

The owner asked for these on the song itself rather than in Settings: you select a song and change
its defaults (speed, cut strictness), as subjective variables that reduce the score when they make
the song easier.

**Where they are.**

- **The song panel's Modifiers row.** It sits in the bottom-right strip between Play and Exit,
  styled like the pinned quick settings; nothing else moved. It has:
  - Note Speed, a button that cycles 100 → 90 → … → 50 %, the existing choices;
  - Strict, a toggle;
  - No Fail, a toggle;
  - the resulting multiplier, "Score x0.70".
- **Controller and hand pointers** work through `UI_AudioEngine.attach_button`, like the
  neighbouring buttons.
- **Remembered per song,** keyed like the high scores (`MapInfo.get_key()`), in
  `user://song_modifiers.json` (`game/scripts/SongModifiers.gd`). Each change is saved at once.
- **Defaults.** A song with no saved choice uses the Settings keys `note_speed_percent` (100),
  `strict_cuts` (on) and `no_fail` (on), which are unchanged. Their rows are gone from Settings >
  Gameplay, so there is one place to change them. The schema and `EXPECTED_ORDER` are untouched.
- **When they apply.** `Map.load_beatmap` activates the song's choices before the motion is
  configured, so the menu, Repeat and bench runs all play with them. Gameplay reads
  `SongModifiers.strict_cuts` / `no_fail` / `note_speed_percent` instead of the Settings keys.

**Note Speed keeps the map's spawn distance** (`NoteMotion.configure`):

- The half jump lasts `1 / speed` times as long at `NJS x speed`, so a slower note starts its jump
  at the same distance and is seen for longer. On ODDS&ENDS Hard at 50 %: NJS 7, still 10.0 m,
  1.43 s instead of 0.71 s.
- The fly-in is the same 0.5 s from 100 m beyond the jump start.
- A Noodle object at the map's NJS stretches the same way; one with its own NJS keeps its own
  speed and jump.

**Score multiplier** (constants in `SongModifiers`):

| Choice | Effect |
|---|---|
| Note Speed | -0.10 per 5 % below 100 % (90 % x0.80, 85 % x0.70, 50 % 1 - 1.00 → floor) |
| Strict cuts off | -0.15 |
| No Fail | -0.50, only if energy actually reached zero during the song (`Scoreboard.energy_emptied`) |
| Combined | 1 + the sum of the penalties, never under x0.10 |

- The modified score is `floor(points x multiplier)`.
- It is what the HUD shows during the song (the No Fail penalty appears the moment energy runs
  out) and what the results screen shows. The results screen also names the modifiers on one
  line, for example "Note Speed 80/100, Strict cuts off: score x0.45".
- Accuracy and rank are computed from the unmodified points as before. The accuracy ring already
  says so by showing the unmodified percentage; there was no room on the results panel for a
  longer note.

**High scores.**

- A record stores the modified `score` (what is ranked and shown) plus `raw_score`, `multiplier`
  and `modifiers` (speed, strict, no_fail, no_fail_used).
- Older records have none of these fields and read as unmodified. The file format only gains
  fields.
- Moving a record to another profile keeps them.
- The local high-score rows show "(x0.70)" after a modified score.
- The BeatLeader tab is read-only and unchanged.

**Beat Saber's own rules, checked:**

| Rule | Source | Our numbers |
|---|---|---|
| Multipliers add: `1 + sum(multiplier)`, floored at **0** | Beat Saber 1.8 decompile, `GameplayModifiersModelSO.GetTotalMultiplier` | add; floor **x0.10** (owner's choice) |
| Modified score = `floor(raw x multiplier)` | 1.8 `ScoreModel.GetModifiedScoreForGameplayModifiersScoreMultiplier` | same |
| No Fail -0.50, only after energy reached 0 (since 1.13.2) | [BSMG ranking guide](https://bsmg.wiki/ranking-guide.html) (in 1.8 code, No Fail stops energy changing at all) | same |
| Slower Song (85 %) -0.30 | BSMG ranking guide | 85 % gives -0.30; Beat Saber has only that one slow step, we have 90-50 % in 10 % steps at -0.10 per 5 % |
| Strict cuts | Beat Saber has no "lenient cuts" modifier (its "Strict Angles" is 0.00 and makes cuts stricter) | ours: -0.15 for turning strict rules off |

Two places where Beat Saber differs, both kept as asked: the floor is 0 in Beat Saber, and
Beat Saber has no penalty for turning strict rules off (it has no such option).

**Checks.**

- **`tools/harness/verify_modifiers.tscn`** (new, in `check.ps1`): 40 checks, MODIFIERS PASS.
  - multiplier arithmetic and the floor;
  - modified-score rounding;
  - the results line;
  - per-song persistence round trip, in a file of its own, and the player's file is untouched;
  - defaults from Settings;
  - No Fail penalty only after energy ran out;
  - stored record fields, kept on a profile move;
  - an old record reads as unmodified;
  - Note Speed 50 % keeps the 10.0 m and doubles the time;
  - the Settings rows are gone.
- **Previews** in `%TEMP%\opensaber_previews\`: `songlist_modifiers.png` (the row at 80 %, strict
  off: Score x0.45) and `results_modifiers.png`.
- **`verify_scoring`'s Note Speed check** was updated to the new rule (same distance, twice the
  lead time).

**On the headset** (0.7.38 built from `ef43696`; bot run, ODDS&ENDS ExpertPlus, 60 s, at the
owner's 80 % Note Speed default):

- `MAP motion: njs=13.6 m/s spawn=2.23 beats ahead, 9.5 m away, fly-in 0.50 s from 109.5 m`.
  0.7.37 gave 7.6 m at the same setting, so the distance rule works on the device.
- Mean 8.35 ms, p99 10.4 ms; 114 hits, 0 wrong; 0 script errors.

## The Note Speed setting (0.7.37 analysis; changed in 0.7.38)

`note_speed_percent` (50-100 %) scales NJS and keeps the map's half jump time
(`NoteMotion.configure`). Slower notes therefore appear closer: at 50 % on the owner's map the jump
starts at 4.0 m instead of 8.0 m.

Beat Saber has **no player option that changes NJS** (bs-cordl 1.46 `PlayerSpecificSettings`).
Its jump options change only where and when notes appear:

- **`noteJumpDurationTypeSettings = Dynamic`** (the default). The map's NJS and half jump rule,
  plus the player's `noteJumpStartBeatOffset`.
- **`= Static`**, with `noteJumpFixedDuration`: a fixed "reaction time". The half jump lasts that
  many seconds at the map's NJS, so the distance is NJS x reaction time. This is Heck's
  `NoteJumpValueType.JumpDuration` branch: `halfJumpDuration = noteJumpValue`.
  - A Noodle object with its own NJS or offset falls back to the beat-offset rule
    (`NoodleMovementDataProvider.InitObject`).

So in Beat Saber a player who wants more time chooses a longer reaction time: notes appear farther
away at the same speed. The two Note Speed options compare like this:

- **Keep our setting as it is:** slower notes, closer, and visible for the same time. Beat Saber
  has nothing like it.
- **Keep the map's spawn distance while slowing** (the change under consideration): slower notes,
  as far away, and visible for longer. For the player that equals Beat Saber's Static reaction
  time of `distance / slowed NJS` together with a lower NJS. Beat Saber cannot lower the NJS.
- **The option closest to Beat Saber** would be a separate reaction-time or jump-distance setting
  that leaves NJS alone.

## Unverified

- The bodies of `CoreMathUtils.CalculateHalfJumpDurationInBeats` and Beat Saber's `NoteJump` /
  `NoteFloorMovement`. The half jump rule is from BeatLeader's reimplementation and Heck's call
  site; the jump shape is from BeatLeader.
- `centerPos`: where the jump's middle is relative to the player. BeatLeader's `SWORD_OFFSET =
  0.9` m and head-z follow are one reimplementation's reading.
- Whether Beat Saber hides or scales a note during the move. BeatLeader draws it at full size.
  That 0.5 s and 100 m are the 1.46 constants is verified; older versions are not.
- The value ranges of Beat Saber's reaction-time and offset options, and whether its song-speed
  modifiers change NJS.
- **Not played by a person, and not run on the headset.**

## Follow-ups

- **The one-tick spawn ambiguity above.** Anchoring an object's travel to the song clock on its
  first tick would make every note's z independent of pool order. That changes some notes by one
  tick against 0.7.36, so it is a separate decision.
- **The chain link pool is presized to 100 at startup, not per map** like the note, bomb and wall pools. The fly-in adds live links on chain-heavy maps.
- **Owner decisions:** the Spawn pop timing, the Note Speed semantics, and whether to add the
  jump's gravity arc and rotation (listed above and not changed).
