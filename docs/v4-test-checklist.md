# v4 live test checklist

**Build:** `F:\Dev\BeepSaberBin\OpenSaber-v4-test.apk` (89,547,695 bytes, 2026-11-04 12:18, branch `v4/cleanup`).
The APK contains `NoteMotion`, `PaletteResolver` and the exported `wall_shared` material (681 entries).
**Rollback:** `F:\Dev\BeepSaberBin\OpenSaber-v03-rollback.apk` plus the pulled user data in
`F:\Dev\BeepSaberBin\v03-backup-*`. Reinstall with `adb install -r`, then push the `files` folder
back if anything is lost.

## What is in this build

- Everything from v0.3: map data (BPM changes, fake notes, environment palettes, boost, Chroma
  colours, Noodle note coordinates), cut debris, the glow setting, the settings/UI layout fixes.
- Three v4 changes: one note-speed formula (`NoteMotion`), one Chroma colour parser
  (`PaletteResolver`), and the rebuilt wall material (translucent panel, metric rim, gradient,
  near-camera fade).

## What is NOT in this build (pending slices)

`Map.gd` split, pooled-node unification, scene-unique names, settings schema, bench tooling out of
the export. None of them change behaviour; this is a test build of the features plus the wall and
refactor work done so far.

## Before playing

- [ ] `adb devices` shows the Quest; `adb install -r` the APK (keeps maps/scores).
- [ ] Launch once, confirm no "script error" dialog.
- [ ] Settings still show your values (audio, colours, refresh rate). A v0.3 config must load.
- [ ] Maps present: ODDS, Gloom, Somewhere Out There, Empires.

## Play

1. **Walls** (Gloom, or any wall map): do they read as translucent panels with a bright frame, not
   static? Can you still see notes through them? Do they block the view when they pass your face?
2. **Chains** (Somewhere Out There): continuous, no gaps between links?
3. **Debris**: shards fly the way you slice (horizontal vs diagonal), tumble and fall away.
4. **Glow** (settings → Glow): Subtle by default; try Full and Off. Does Subtle look right? Any
   haze or washed-out notes?
5. **Environment**: load two maps with different environments (e.g. Gloom = Rocket, Somewhere =
   BTS). Do the room and note colours differ per map? Does Classic reproduce the old look?
6. **Hit sound**: audible over the music, left/right distinguishable, no machine-gun effect in
   streams.
7. **End card**: score, record and combo readable, nothing hidden behind a saber.
8. **Frame feel**: any stutter, especially in wall-heavy sections.

## Gate status at build time

- Parse/shader errors: none.
- Settings round-trip: PASS (48 keys, plus a legacy config with unknown keys).
- Replay: byte-identical pair achieved earlier; a later pair diverged with identical frame/event
  counts, so replay is recorded as a known flaky gate, not a green one.
- Map dump: the 45 maps dump with zero failures, but the stored baseline hash was produced by an
  interrupted earlier run and no longer matches line-for-line. Two maps re-dumped and compared
  section-by-section were identical. The baseline needs regenerating from a clean run.

## Known limitations to expect

- Box-group-only lightshows, 360/lane-rotation maps and Chroma/Noodle animation are detected and
  flagged as "not fully supported" rather than rendered.
- Maps with custom Unity asset bundles use our environment instead of the author's scenery.
- Fake walls are skipped entirely (a Noodle decorative wall will not appear).

## If something is wrong

Note the map, the difficulty and what you saw. The frame capture for the session is being recorded
by the build's bench mode; the log will be pulled after the test.
