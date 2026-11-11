# Changelog

Every Quest 3 build of this fork. The upstream BeepSaber lineage is pinned in
[UPSTREAM.md](../UPSTREAM.md). GitHub releases carry the signed APKs; the `-q3` suffix exists
because upstream already uses tags such as `v0.4` and `v0.5`.

## Unreleased - audit branch `audit/fable-5.2`

Code audit of 0.7.9; not built or installed. Full findings: [audit report](audit-fable-5.2.md).

- **Hands**: pinch now works with the controllers asleep; hand swings score swing travel and cut
  on the right plane; cuts use the blade pose of the same tick; a parked saber no longer cuts.
- **360/90 maps**: objects keep their lane-local position when they change lane.
- **Storage**: the confirmed delete actually deletes. **BeatSaver**: Back restores the previous
  search. **Zips**: subfolders extract, `../` entries are refused.
- **Upload page**: a client that connects and sends nothing can no longer freeze the game.
- **Maps**: a malformed v2 `_notes` entry no longer hangs the loader; an unreadable difficulty file
  no longer starts an empty song.
- Boot log: the glow-level, BeatSage node-path and `canvas_refresh` errors are gone.
- Removed: the broken WallBatch path and two scripts that could not parse.

## v0.7.9 - 2026-11-07

**Quick settings on the main menu.** A pinned panel at the top of the menu carries the three settings
that matter most in one place: **Hands** (hand tracking on/off), **120 Hz** (on = 120, off = 90) and
**Lights** (map light show). Turning Hands off hides the rendered hands and returns the sabers to the
controllers without a restart; the states are read before their signals connect, so loading the menu
cannot write a different value back. `Settings.hand_tracking_enabled` is the new persisted key
(schema 58 keys).

[Spec](../specs/030-hand-tracking/spec.md)

The installed APK is OpenSaber-v079.apk, SHA-256
DABA74C80A933D34E917DFD7D907B27F8F2AE21E6E1C128761D8E52A5C9704D8.

## v0.7.8 - 2026-11-07

**Rendered hands that hold the sabers.** The MIT Godot demo hand models are drawn at
`/user/hand_tracker/left|right` with `XRHandModifier3D` (rotation-only) and hidden when a hand is
not tracked. Quest does not implement the OpenXR hand interaction profile, so the sabers no longer
wait for it: while hand data is live each blade takes its pose from the same palm transform the hand
mesh uses, and pinch is computed from the thumb-tip/index-tip distance (press 30 mm, release 50 mm)
to drive the existing UI-ray click. The controller path and the persisted saber offset are unchanged
when hands are not live; haptics remain suppressed for hands.

Hand models: Godot demo projects, MIT, `game/hands/`.

[Spec](../specs/030-hand-tracking/spec.md)

## v0.7.7 - 2026-11-07

**Quest 3 hand tracking as swords, pinch clicks the UI.** With the controllers set down, each hand's
OpenXR hand interaction aim pose drives the existing `left_hand`/`right_hand` trackers, so the sabers,
cuts, walls and arcs need no separate rig. A pinch (float `pinch_ext/value`, press at 0.8, release
below 0.5) drives the existing UI ray click, so a button fires once per pinch and again after a
release. The hand mapping only runs while `/user/hand_tracker/<side>` reports live joint data, so
controller play is unchanged; there is no hand mesh and no hand haptics in this build. The custom
action map now carries the hand interaction profile (default/aim/grip pose plus pinch) because Godot
only auto-creates it for its built-in map. Meta's Quest runtime does not activate that profile; 0.7.8 moves the hand pose and pinch to the joint data.

[Spec](../specs/030-hand-tracking/spec.md)

The installed APK is OpenSaber-v077.apk, SHA-256
7E026C4C5FCD96BF6F32782501DD8D398E981DDC19D31DA1967B52960EBF0B4C.

## v0.7.6 - 2026-11-07

**Map wall colour with red option, pooled bombs, brighter arcs.** Walls use the map's authored
obstacle colour by default (Hand in Hand is black by design); a "Walls: map colour" toggle on the
song selection page switches to classic red. The exported Wall.scn cache bug that kept an old noise
shader is fixed by clearing `.godot/exported` before export. Bombs are pooled instead of
instantiated/freed per bomb, the arc ribbon is wider/brighter and a missing head attaches to the
saber, saber-vs-saber contact pulses the controllers and throws a spark, and the benchmark records draw calls, objects, render CPU/GPU and wall/lightshow timers. The
default refresh rate is **120 Hz** (90 Hz remains in Settings); a one-time migration moves the
previous 90 default back to 120 without blocking a later choice.

[Release](https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.7.6-q3) -
[Spec](../specs/027-v07-map-compat/spec.md)

## v0.7.5 - 2026-11-07

**Wall growth and rim, cheaper lightshows, arc head position.** Walls now keep their bottom edge on
the floor while they rise, and ordinary walls have the v0.6 bright rim back; Noodle, Mapping
Extensions and off-grid walls keep the flat panel so wall art does not stripe. Group lighting is
merged per beat and light type (Hand in Hand: 27,669 -> 8,022 events) and the event driver runs one
interpolation state per light type instead of allocating a tween per event. Arcs take their head
position from the spawned head cube, logging the first ten mismatches. `bench.flag` now runs in
release builds too, so device frame time can be measured without a debug APK.

[Release](https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.7.5-q3) -
[Spec](../specs/027-v07-map-compat/spec.md)

## v0.7.4 - 2026-11-07

**Box-group fades/extends, group-id folding, Noodle cut angle.** A v3/v4 group event with `i:1`
now emits the basic fade-to-colour value, and `i:2` extends the previous event instead of starting
a new one. Group ids above 4 are folded onto the room's five light types (`id % 5`) rather than
being dropped; the fold is logged per map. The cut pieces of a note or chain link derive their
angle from the object's basis, so a Noodle x/y rotation splits along the visible plane. `s=0` is
still an instant off (there is no basic fade-to-black), and a v3 transition ends at its event beat,
which is one gap later than the authored fade. `SUPPORTTEST` now expects 360/90, box groups and
static Noodle to be supported.

[Release](https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.7.4-q3) -
[Spec](../specs/027-v07-map-compat/spec.md)

## v0.7.3 - 2026-11-07

**Noodle static transforms, box-group colours, audio recovery.** Notes and walls honour Noodle
`_position`/`_rotation`/`_scale` and the v3 `coordinates`/`localRotation`/`size` spellings; pooled
objects reset their transform, so a Noodle note cannot leak into a vanilla one. v3/v4 light colour
box groups are converted to the room's basic lights (colour and brightness at the beat; transitions,
filters, distributions and groups above id 4 are not modelled). On app resume the music stream is
re-seated and the mixer poked, so a suspended headset does not return silent. Hit sounds get an
above/below spectral cue (EQ bus + small pitch), not convolution HRTF. Noodle animation tracks and
custom Chroma environment objects remain.

[Release](https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.7.3-q3) -
[Spec](../specs/027-v07-map-compat/spec.md)

## v0.7.2 - 2026-11-07

**360/90 lane rotation.** Rotation events (v3 `rotationEvents`, v2 types 14/15, v3 basic events
14/15) now put each object in a lane rotated by the event in force at its own beat, so notes,
bombs, walls, arcs and chains come from the sides while the player turns. Objects already in flight
keep their lane. Early/late execution is respected; v4 per-object rotation is not read yet. The ME
precision work from 0.7.1 is included.

[Release](https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.7.2-q3) -
[Spec](../specs/027-v07-map-compat/spec.md)

## v0.7.1 - 2026-11-07

**Mapping Extensions precision.** Note, bomb, wall, arc and chain placements decode the ME
coordinates (1000 = lane 0, 2000 = lane 1, 1/1000-lane steps), precision cut angles (1000-1360 =
0-360 degrees, 2000-2360 any-direction, angle not scored), precision wall widths, and the 4001+
wall height/start type. Vanilla maps are unchanged. Validated on a real ME wall map (55/400
sampled notes fractional, 6,631 walls parsed) plus the synthetic probe.

360/90 rotation, Noodle and Chroma follow.

[Release](https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.7.1-q3) -
[Spec](../specs/027-v07-map-compat/spec.md)

## v0.7.0 - 2026-11-07

**Library cards and sorting; depth-based wall grow.** The main menu gains a Cards view: All,
BeatSaver, each BeastSaber playlist, BeastSaber (other), Uploaded and Local, with count and size;
sort by Name, Artist, Mapper, Date added, Size or Play Count, persisted. BeastSaber playlist
membership lives in `Songs/.playlists.json` (many-to-many) and starts with downloads made in 0.7 or
later; sidecar v2 caches `added_unix` and `bytes` (the first launch scans the folders once). Wall height is now a function of depth (10% at 16 m to full at 8 m), so wall art stays
continuous while it still rises into view.

Map compatibility (Mapping Extensions, 90/360, Noodle, Chroma, box groups) follows in 0.7.1.

[Release](https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.7.0-q3) -
[Spec](../specs/029-v07-library/spec.md)

## v0.6.5 - 2026-11-07

**Walls, long arcs, BeatLeader in the high-score panel.** Walls spawn at full height with no rim, so
one-lane wall art reads as a surface instead of a torn/striped curtain. The arc far fade now starts
beyond the 16 m spawn distance and the tip fade is off, so a long gap stays visible. The left
high-score panel gains Local and BeatLeader tabs; the overlapping BeatLeader sign is removed and the
menu's Leaderboard button opens the tab, which loads lazily and drops stale responses. A debug-only
miss probe records the closest blade distance on a miss.

[Release](https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.6.5-q3) -
[Spec](../specs/028-v065-fixes/spec.md)

## v0.6.4 - 2026-11-07

**Storage manager and bulk delete.** A Storage button in the main menu opens a panel with every
map's size on disk and its source tag. Tick several maps and delete them, or choose a source and
delete every map from it; both ask for the count and size first. Deleting removes the folder
recursively (subfolders included), plus the map's high scores and play counts, then refreshes the
library. The same recursive delete now backs the single map Delete button, and any path that is not
a direct child of `Songs/` is refused.

Repository housekeeping: the owner's gameplay captures were removed from the working tree and all
history, and the absolute Windows keystore path was replaced with the tracked `bin/debug.keystore`.

[Release](https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.6.4-q3) -
[Spec](../specs/026-storage-manager/spec.md)

## v0.6.3 - 2026-11-07

**Arcs, BeatLeader on the left, BeastSaber playlists.** Slider ribbons are now one cubic curve from
the head note centre to the tail note centre, so they connect and never loop; they take the map's
note palette instead of the room's environment colour. A BeatLeader sign on the left of the menu
opens the existing top-10 panel, and the right-hand online panel gains a **BeastSaber (curated)**
tab that downloads a whole curated playlist from BeatSaver, tagged `beastsaber`.

The build also stops shipping old benchmark capture files and the bundled demo (already gone since
0.6.1). A 24 s 1080p60 gameplay clip and four stills are kept locally for the itch page (not committed).

**Known:** the in-VR arc look and the two new menu entries still need a pass on the headset.

[Release](https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.6.3-q3) -
[Spec](../specs/025-arcs-menu-beast/spec.md)


## v0.6.2 — 2026-11-06

**Screenshot shortcut fix.** Quest 3 controllers have no usable squeeze input, so the 0.6.1 grip
hold could never fire. In menus, **both index-finger triggers held for 0.5 s** now take the shot;
during a song, use Pause → Screenshot (the triggers are clenched while swinging). The pause button
and F12 are unchanged. The setting and help text say trigger; the old `screenshot_grip`
key is ignored and `screenshot_trigger` defaults on.
[Release](https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.6.2-q3) ·
[Spec](../specs/024-shot-demo-061/spec.md)

## v0.6.1 — 2026-11-06

**Screenshots and a clean build.** In-game capture: hold both grips for 0.5 s or press
**Screenshot** in the pause menu; 1920×1080 PNGs are saved for `adb pull` (F12 on desktop). The
bundled TheFatRat “Time Lapse” demo is removed from the build, and a library that still holds the
exact bundled copy loses it once. The sliced-cube icon and menu logo ship here.
[Release](https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.6.1-q3) ·
[Spec](../specs/024-shot-demo-061/spec.md)

## v0.6.0 — 2026-11-06

**Library sources and BeatLeader.** A source tag on every map (BeatSaver, BeastSaber, uploaded,
local, unknown) written to a sidecar, a source filter in the main menu, and an automatic backfill
that recomputes the Beat Saber level hash and looks old maps up on BeatSaver. Read-only BeatLeader
top 10 for the selected map and difficulty, with no account. Both were verified on the headset;
the dense map still holds 120 fps with 0.14% dropped (Quest 3, default preset).
[Release](https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.6.0-q3) ·
[Report](v0.6-report.md) · [Spec](../specs/020-libs-leaderboards/spec.md)

## v0.5.1 — 2026-11-06

**Chains connect.** The translucent line between notes was made of detached plates because the
authored spawn animation shrank every link to 10% and pulled it 2 m back. Links now span their
exact segment, the hitbox matches, and a test cuts a whole chain in head-to-tail order. The same
release verified a 2,913-note, 9.64 NPS map at 120 fps instead of guessing at the reported stutter.
[Release](https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.5.1-q3) ·
[Spec](../specs/019-chains-dense/spec.md)

## v0.5.0 — 2026-11-06

**Map data and audio direction.** The map-data audit checked 43 real BeatSaver maps across v2, v3
and v4; the loader now honours the data those maps actually declare. Hit audio was verified on the
headset: 13 of 13 lateral hits put more energy on the cube's own side, with music ducking and an
in-game analyser. v2, v3 and v4 maps all load on device.
[Release](https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.5.0-q3) ·
[Spec](../specs/018-v05-release/spec.md)

## v0.3 work (shipped in v0.4.0) — 2026-11-05

**Feedback, sky and frame stability.** Layered hit samples and per-event haptics replaced the
single buzz; the sky became selectable (void default) with explicit ambient light; HUD/end-card
layout was fixed; the real stutter bug (two `global_transform` reads per note per tick) was found
and fixed; walls moved to a pool. The full write-up is the [v0.3 report](v0.3-report.md) and
[performance page](performance.md).

## v0.4.0 — 2026-11-05

**UI and code quality.** HUD overlap and the end-of-map card were rebuilt, the BeatSaver list
scrolls smoothly (measured as a per-frame delta sequence), and the codebase went through the
quality pass. A miss now draws a 28 pt red X at the miss point; the old 6 pt marker was the
reported "red dot". Version code 7; upgrade over 0.3 kept settings and songs.
[Release](https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.4.0-q3) ·
[Spec](../specs/017-v04-release/spec.md)

## v0.2.0 — 2026-11-02

**Every map format, a BeatSaver browser and a real 120 Hz default.** v2/v3/v4 maps, including the
hybrid BeatSaver serves and v4's split beatmap/lightshow; in-VR search/download; a LAN upload page;
ten visual options; bloom removed. 120 Hz with physics matched to the display.
[Release](https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.2.0-q3)

## v0.1.1 — 2026-11-02

**Recenter fix.** The Meta recenter button now re-orients the play space and menu instead of
leaving them rotated.

## v0.1.0 — 2026-11-02

**Quest 3 baseline.** The fork's first release: Quest 3 toolchain, hit-registration fixes, layered
audio research, the benchmark harness, and the first measured Quest 3 numbers.

## Next

- **0.6.3** — BeastSaber playlist (`.bplist`) import.
- **0.6.x** — home-test findings and cosmetic chain joints.
