# Feature Specification: Every map format (v2/v3/v4) + switchable local upload server

**Feature Branch**: `008-map-formats`

**Created**: 2026-11-02

**Status**: Done (G4 self-review; device-verified)

**Input**: "Fix it now so it supports any map. Whats the difference anyway" + "the local
server - make it a toggle-able option in settings."

## Scoped change

**Symptom.** `Map.load_map_info()` accepted only Info.dat files containing `_version`
(v2). Any file with a top-level `version` key (v3 and v4) was logged as "unsupported beatmap
version" and the map disappeared from the library.

**Root cause.** Only `MapInfo.new_v2()` existed. The *difficulty* loaders already understood
v3 note/event/obstacle/arc/chain collections (`load_*_stack_v3`), so the gap was the Info
layer plus v4's index-based collections and its separate lightshow file.

**Blast radius.** `MapInfo`, `DifficultyInfo`, `Map.load_beatmap`/`load_map_info`,
`BeepSaber_Game.start_map`, `Settings`, `settings_Panel`, `song_uploader`.

## Requirements

- **FR-001**: `Info.dat` with `_version` MUST load exactly as before (v2, no behaviour change).
- **FR-002**: `Info.dat` with `version` 3.x MUST load: `song.*`, `audio.*`,
  `coverImageFilename`, `environmentNames`, `difficultyBeatmaps[]`.
- **FR-003**: `Info.dat` with `version` 4.x MUST load, including per-beatmap
  `beatmapAuthors.mappers` and v4 hex colour schemes (`"C81414FF"`).
- **FR-004**: v4 beatmap files MUST load, resolving `colorNotes`/`bombNotes`/`obstacles`/
  `arcs`/`chains` through their `...Data` index collections.
- **FR-005**: v4 lightshow files MUST be loaded for lighting events
  (`basicEvents` + `basicEventsData`), because v4 keeps them out of the beatmap file.
- **FR-006**: A v2 Info.dat that points at v3 difficulty files MUST keep working (this is what
  BeatSaver actually serves).
- **FR-007**: Unsupported future versions MUST still be rejected with a clear log line.
- **FR-008**: The local map-upload HTTP server MUST be switchable in Settings, take effect
  without a restart, and when off MUST close the port rather than merely ignore requests.
- **FR-009**: The upload-server setting MUST persist in `config.ini`.

## Success criteria

- **SC-001**: A converted v3 map loads and plays on device (song name, difficulties, notes).
  **MET**: `Converted v3` loaded on the Quest, Expert difficulty, 9 notes live at peak, bot cut
  19/19 with 0 wrong, full combo (`perf/captures/fmt-v3.meta.txt`).
- **SC-002**: A converted v4 map (index-based beatmap + separate lightshow) loads and plays.
  **MET**: `Converted v4` - same numbers, 19/19 cuts, full combo
  (`perf/captures/fmt-v4.meta.txt`).
- **SC-003**: An existing v2 map still loads and plays. **MET**: `ODDS&ENDS` (bundled v2) on
  the Quest, ExpertPlus, 4 notes live at peak, bot cut 19/19 with full combo
  (`perf/captures/fmt-v2b.meta.txt`). An 8 s run showed 0 cuts only because that map's first
  notes arrive after the 8 s window.
- **SC-004**: Headless parse: 0 SCRIPT ERROR, 0 Parse Error. **MET**.
- **SC-005**: With the setting off, nothing is listening on port 45800; with it on, the
  upload page answers again, in the same session. **MET**: probed from this PC against the
  headset for both arms - see the consultation log.

## Out of scope

- 360/90 degree lane rotation (`spawnRotations`, `r` fields) — parsed but ignored, exactly as
  v3 was before this change.
- Event-box groups, VFX boxes and NJS events (v4 lighting features with no counterpart here).
- Per-beatmap colour-scheme selection: the loader merges all characteristics into one
  difficulty list, so only the first scheme is applied.

## Open questions

- Does any real map in the wild use a v4 Info.dat with `lightshowDataFilename` pointing at a
  file that is itself v4 index-based? Verified against a converted map only.

## Assumptions

- Field names are taken from the BSMG map-format pages (Info / Beatmap / Lightshow), not from
  memory of the format.

## What the formats actually differ in

| | v2 | v3 | v4 |
|---|---|---|---|
| Info metadata | flat `_songName`, `_beatsPerMinute` | `song{}`, `audio{}` | same as v3, hex colours |
| Difficulty list | `_difficultyBeatmapSets[]._difficultyBeatmaps[]` | flat `difficultyBeatmaps[]` | flat, per-beatmap authors |
| Notes | `_notes` with `_time/_lineIndex/_type` | `colorNotes` with `b/x/y/c/d` | `colorNotes` of `{b,r,i}` + shared `colorNotesData` |
| Walls | `_obstacles` (`_type` 0/1 legacy heights) | `obstacles` with `x/y/w/h` | `obstacles` of `{b,r,i}` + `obstaclesData` |
| Arcs / chains | `_sliders`, `_burstSliders` | `sliders`, `burstSliders` | `arcs`, `chains` referencing note data |
| Lighting | `_events` in the beatmap | `basicBeatmapEvents` in the beatmap | separate lightshow file, `basicEvents` + data |

## Consultation Log

| Gate | Question | Verdict | Follow-up |
|---|---|---|---|
| (spec) | Field names and per-version structure for Info/Beatmap/Lightshow | Consulted the BSMG map-format reference directly instead of inferring | Done before coding; differences table above |
| verify | Does the v4 index expansion produce a playable map, or only a parse-able one? | Converted an installed v3 map to v4 (index arrays + separate lightshow) and ran it on the headset | 19/19 cuts, 0 wrong, full combo; the same source converted to v3 gave identical numbers, and the original v2 map still plays |
| verify | Does the upload setting close the port, or only ignore requests? | Probed port 45800 from this PC against the headset for both arms of the same build | `upload_server=false` -> connection actively refused; `upload_server=true` -> HTTP 200 |
| note | BeatSaver serves v3 *difficulty* files under a v2.1.0 `Info.dat` | Observed in all 18 maps sampled | FR-006 covers it: the beatmap loader keys off the difficulty file's own `version`, not the Info's |
