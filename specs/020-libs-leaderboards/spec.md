# Feature Specification: map source tags, library filters, BeastSaber and BeatLeader

**Feature Branch**: `020-libs-leaderboards`

**Created**: 2026-11-06

**Status**: In progress - source tags/filter and the read-only BeatLeader board are implemented; BeastSaber import pending the player's answer

**Input**: Player: "Maybe add beastsaber as well - but making sure there is a tag on each song in the
library to identify the source library and a way to sort and filter the downloaded libraries. We
should integrate beatleader as well. Why do we need quest modding or tooling? Why do we need
mapping stuff? Why do we need camera/streaming stuff? The focus is gameplay experience."

## Intent

Make the downloaded library sortable/filterable by where each map came from, add BeastSaber as a
map source, and show BeatLeader leaderboards in game. The other ecosystem items in the earlier
answer (Quest modding, mapping editors, camera/streaming) are **not** needed for this standalone
game: they serve Beat Saber modding, map authoring or capture, not play.

## Facts found before the spec

- BeatSaver's map record carries the map id and the version **hash** (`versions[0].hash`); the
  download flow already has the record, it just does not keep either.
- The level hash IS recoverable: SHA-1 over the bytes of `Info.dat` followed by each difficulty
  file in the order `Info.dat` lists them. Verified against Phoenix (`bf2c367d...`) on the corpus;
  `GET https://api.beatsaver.com/maps/hash/{hash}` then returns the map id (also verified).
- BeatLeader's API is public and works for reads:
  `GET https://api.beatleader.xyz/leaderboard/{hash}/{difficulty}/{mode}` (confirmed with the
  Phoenix hash; returns the leaderboard and its scores). Reads need no auth; score submission is
  a different, account/replay-gated path.
- BeastSaber is a **curation site over BeatSaver**; it links to BeatSaver maps and publishes
  playlists (`.bplist`). It has no documented public API for a map browser. A "BeastSaber source"
  therefore means a map obtained through a BeastSaber playlist, not a second map API.

## Requirements

- **FR-001**: Every map folder MAY carry a sidecar `OpenSaber.meta` (INI) with `source`
  (`beatsaver`, `beastsaber`, `uploaded`, `local`, `unknown`), `map_id` and `hash`. Downloads write
  it (`beatsaver`/`beastsaber` + id/hash), uploads write `uploaded`, and any map without one reads
  as `unknown`. `MapInfo` exposes the three values.
- **FR-002**: The main-menu library MUST show each song's source and MUST offer a source filter
  (All / BeatSaver / BeastSaber / Uploaded / Local / Unknown) in addition to the existing
  playlists. Existing maps without a sidecar appear under Unknown; re-downloading a BeatSaver map
  tags it. Filtering MUST be a pure list operation (no per-frame cost).
- **FR-003**: BeastSaber maps MUST be obtainable by importing a BeastSaber `.bplist` playlist:
  resolve each entry through BeatSaver, download it, and write `source=beastsaber` with the
  BeatSaver id/hash. No scraping of bsaber.com pages.
- **FR-004**: A read-only BeatLeader leaderboard MUST be available for the selected map and
  difficulty when the map has a hash: top N scores (player name, score, accuracy, modifiers) from
  `GET /leaderboard/{hash}/{difficulty}/{mode}`. Without a hash the entry point says the map needs
  re-downloading from BeatSaver. No account, no score submission.
- **FR-005**: Network failures/timeouts MUST be reported on the panel and MUST NOT block the menu
  or the library; no request is made per frame; results are cached per map/difficulty for the
  session.
- **FR-006**: Existing behaviour (play, download, library) MUST not regress; the release build
  still cannot run the bench; no new per-frame work on the gameplay path.
- **FR-007**: Existing maps MUST be backfilled once, in the menu background: compute the level
  hash, look it up through BeatSaver, and write `source=beatsaver` with its id on a hit, or
  `source=unknown` with the hash on a miss. A map whose files were edited stays Unknown.
- **FR-008**: No network work while playing: every request is menu-initiated, asynchronous, with
  a timeout, and stops when the menu is left (the backfill is one-shot per session). A bench run
  with the menu opened and closed beforehand MUST show no frame regression.
- **FR-009**: The sidecar MUST be written atomically (temp file + rename), carry a schema version,
  and a missing/corrupt sidecar MUST read as Unknown without crashing or losing the map.
- **FR-010**: BeatLeader requests MUST map the local difficulty and characteristic names to the
  API (`ExpertPlus`, `Standard`, `OneSaber`, ...), lower-case the hash, and show distinct states
  for offline, map-not-found and no-scores. Fixture tests cover each response.

## Success criteria

- **SC-001**: A sidecar round-trip test writes/reads all five sources and defaults to unknown; a
  library filter test returns exactly the matching maps; UI screenshots show the source tag and the
  filter.
- **SC-002**: Importing a BeastSaber `.bplist` (fixture) downloads its maps and tags them
  `beastsaber`; an offline/failed entry is reported and does not abort the rest.
- **SC-003**: The BeatLeader panel shows the Phoenix ExpertPlus top scores from the live API on
  device, with the hash from a BeatSaver download; a map without a hash shows the explanatory
  message.
- **SC-004**: `aapt`/settings/audio/map gates still pass; the player's library stays playable.
- **SC-005**: A source-filter test covers every library entry and the selection persists across a
  restart; the main-menu screenshot shows the source tag and no overlap.
- **SC-006**: `test_map_source` writes/reads all sources, rejects a corrupt sidecar, and the
  Phoenix hash check matches `bf2c367d...` on the corpus.

## Results so far (2026-11-06)

### Source tag and library filter (FR-001, FR-002, FR-007, FR-009, SC-001, SC-005, SC-006)

- Sidecar `OpenSaber.meta` (INI, `schema`/`source`/`map_id`/`hash`) is written into the map folder
  by BeatSaver downloads, manual uploads and the bench probe, atomically (temp + rename). A
  missing, corrupt or future-schema sidecar reads as `unknown`; the map still loads.
- `Map.load_map_info` applies it to the three new `MapInfo` fields (`source`, `source_id`,
  `level_hash`), so the library sees the tag without a second file scan.
- The level hash is SHA-1 over `Info.dat` + every difficulty file in declared order. Verified
  against Phoenix (`bf2c367d...`); `GET /maps/hash/{hash}` returns map id 32693.
- Backfill runs once per menu session, one map at a time with a frame between maps, only while the
  menu is visible, and stops on map start. On this PC's real library it tagged FitBeat, Gloom,
  ODDS&ENDS, Somewhere Out There and RAMFEAR as BeatSaver; TheFatRat Timelapse stayed Unknown
  (its files are not the published version).
- The main menu has a `SourceFilter` dropdown (All Sources / BeatSaver / BeastSaber / Uploaded /
  Local / Unknown) next to the playlist selector, and every row and the Song Info panel show the
  source. The selection persists through `Settings.library_source_filter`. Filtering is a pure
  list operation and sorts the filtered view by author/title. Screenshots:
  `visual_menu.png`, `visual_menu_filtered.png` (`tools/menu_visual_check.tscn`, desktop).
- `MAPSOURCETEST PASS`: five-source round trip, missing/corrupt/future sidecar, the filter and
  sort, and the Phoenix hash.

### BeatLeader read-only board (FR-004, FR-005, FR-010, SC-003)

- Two documented reads, no auth: `/leaderboard/{hash}/{difficulty}/{mode}` for the board id, then
  `/leaderboard/{id}?page=1&count=10&sortBy=rank&order=desc` for the top ten. (`order=asc` sorts
  the rank number upward and returns the worst scores, so `desc` is the top.)
- New `BeatLeaderPanel` canvas with a `Leaderboard` button in the main menu. It shows rank,
  player, score, accuracy, PP and modifiers; distinct messages for no hash, unsupported
  characteristic, not found, no scores and offline; results are cached per hash/difficulty/mode
  for the session; every request is menu-initiated with a 10 s timeout, and nothing runs on the
  gameplay path.
- `BEATLEADERTEST PASS` on a trimmed live Phoenix fixture plus URL/mode/format/characteristic
  checks. Desktop live check: `visual_leaderboard.png` shows the real top 10
  (OlbmaPhlee 1,247,685 / 98.07% / 662.78 pp, ...) and `visual_leaderboard_nohash.png` shows the
  no-hash explanation.

### Still open

- FR-003 (BeastSaber `.bplist` import) waits on the player's answer to the first open question.
- Device check of the panel and the filter at VR scale (the desktop render proves layout and
  data, not headset legibility).

## Out of scope

- BeatLeader score submission, login and replays (needs an account/OAuth and a replay format
  agreement); ScoreSaber; scraping BeastSaber; Quest modding tools, mapping editors, camera or
  streaming features.
- Recovering hashes for maps downloaded before this change (the BeatSaver hash is the zip hash and
  cannot be recomputed from the unpacked files); they show Unknown until re-downloaded.

## Open questions

- [NEEDS CLARIFICATION: BeastSaber has no public map API. Is the `.bplist` playlist import
  (FR-003) the right interpretation of "add BeastSaber", or is a source **label** for maps the
  player already has enough?]
- [NEEDS CLARIFICATION: Is a read-only BeatLeader leaderboard (top scores, no submission/account)
  enough for "integrate BeatLeader", or is score submission expected?]

## Consultation Log

| Gate | Asked | Verdict | Action taken |
|---|---|---|---|
| G0 | Scope of BeastSaber/BeatLeader, source-tag storage, phasing | GO WITH CHANGES: hash is recoverable (verified); add backfill FR-007, menu-only networking FR-008, atomic/schema sidecar FR-009, BeatLeader mapping/states FR-010; ask the player what BeastSaber means before the import; ship slices as v0.6.0, not 0.5.2 | Slice 1 (sidecar, backfill, source filter) starts; BeastSaber import waits on the player's answer; BeatLeader read-only next |
