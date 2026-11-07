# Feature Specification: 0.7 local library — cards per source and BeastSaber playlist, sort and filter

**Feature Branch**: `029-v07-library`

**Created**: 2026-11-07

**Status**: Draft (G0 pending)

**Input**: Owner: "BeastSaber saves the files as playlists, but our local directory has no playlist
sorting. For the local system in front of us, add an option to view as folders or cards: BeatSaver
inside a single card, BeastSaber in its own cards, and every BeastSaber playlist as a card with its
songs. BeatSaver has no prerequisite grouping, so add basic sorting/filtering by artist vs creator,
date added and other things, making one UI for a local directory of maps that works with both
sources."

## Context

- The library is flat on disk: `user://OpenSaber/Songs/<map>/`, tagged by `OpenSaber.meta`
  (`source`: beatsaver / beastsaber / uploaded / local / unknown). BeastSaber downloads are tagged
  but the playlist they came from is not recorded.
- The main menu is an `ItemList` with a source filter and a playlist selector; there is no card view,
  no per-playlist grouping, no size/date/metadata sort.
- `MapInfo` carries `song_author_name`, `level_author_name`, `source`, `level_hash`, `filepath`, but
  no added date or playlist.
- 0.6.5 already has the Local/BeatLeader tabs in the score panel; this spec is the library list, not
  the scores.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Cards per source and playlist (Priority: P1)

As a player, I open the library and see cards: BeatSaver, each BeastSaber playlist, Uploaded and
Local. Choosing a card shows only the maps in it.

**Acceptance**:
1. A card per source with the map count and total size; BeastSaber has one card per downloaded
   playlist, plus "BeastSaber (other)" for maps with no playlist tag.
2. The BeatSaver card contains every `beatsaver` map; the Local card the `local` maps.
3. Selecting a card filters the list; selecting "All" restores it.
4. A map downloaded from BeastSaber is written with its playlist id/title in the sidecar and appears
   under that playlist card; a map with no playlist tag appears under "other".

### User Story 2 - Sort and filter (Priority: P1)

As a player, I sort by song name, artist, mapper, date added, size or play count, and filter by source
card and text.

**Acceptance**:
1. Sort menus: Name, Artist, Mapper, Date added, Size, Play count; ascending/descending; the choice
   persists across launches.
2. Date added comes from the sidecar; old maps fall back to the folder modification time.
3. Text filter narrows within the selected card; clearing restores.
4. Play/Delete/Leaderboard always act on the visible selection.

### User Story 3 - No regression (Priority: P2)

The list, card view and sorting do not change the map files, the source tags, the score panel or the
download paths.

**Acceptance**:
1. Existing maps without the new sidecar fields still load and appear under their source.
2. The card view uses no network and no extra map scans beyond the existing library load.
3. Re-downloading a map keeps one entry and updates its playlist/added metadata.

## Requirements *(mandatory)*

- **FR-001**: `MapSource` schema 2 MUST add `playlist_id`, `playlist_title` and `added_unix` to the
  sidecar; v1 sidecars MUST read with empty/0 values (no failure).
- **FR-002**: The BeastSaber downloader MUST write the playlist id/title into every map it installs
  and set `added_unix` for new installs.
- **FR-003**: Existing libraries MUST backfill `added_unix` from the map folder's modification time;
  missing playlist tags MUST group as "BeastSaber (other)", never be dropped.
- **FR-004**: The library MUST offer a **Cards** view and the existing **List** view. Cards MUST be
  one per source and one per BeastSaber playlist, showing a cover, the map count and the total size.
- **FR-005**: Selecting a card MUST filter the songs to that source/playlist; "All" MUST clear it.
  The selection MUST survive a list rebuild when the map still exists.
- **FR-006**: Sorting MUST support Name, Artist, Mapper, Date added, Size and Play count, ascending
  and descending, with the choice persisted in `config.ini`.
- **FR-007**: A text filter MUST narrow within the selected card; it MUST debounce or apply on
  submit, not per keystroke on the headset.
- **FR-008**: Play, Delete and Leaderboard MUST use the visible list and clamp the selection exactly
  as today; an empty card MUST disable them.
- **FR-009**: The card covers MUST come from local data only (map cover, stored playlist image, or a
  source icon); no network request in the library.
- **FR-010**: Re-downloading an existing map MUST update its sidecar (playlist/added) without
  creating a second row or folder.
- **FR-011**: A headless probe MUST verify sidecar v2 round-trip, the card grouping (source +
  playlist), and the sort comparators on a synthetic library.

### Key Entities

- **MapSource sidecar v2**: source, map_id, hash, playlist_id, playlist_title, added_unix.
- **LibraryCard**: kind (source/playlist/all), label, key, count, bytes, cover.
- **LibraryQuery**: card key, sort field, direction, text.

## Success Criteria *(mandatory)*

- **SC-001**: On the headset, the BeatSaver and each BeastSaber playlist appear as separate cards
  with the correct counts and sizes; selecting each shows exactly its maps.
- **SC-002**: Sorting by artist, mapper, date added and size produces the expected order; the choice
  survives a relaunch.
- **SC-003**: A BeastSaber playlist downloaded before 0.7 shows its maps under "BeastSaber (other)"
  and still plays.
- **SC-004**: The probe passes sidecar v2 round-trip, grouping and comparator tests; no network is
  used by the card view.
- **SC-005**: Play/Delete/Leaderboard act on the filtered selection; no vanilla maps change.

## Out of Scope

- Physical per-playlist folders on disk (cards are metadata over the flat library).
- A general tag/collection system beyond source + BeastSaber playlist.
- Cloud sync, moving maps between storage, editing map metadata by hand.
- The map-compat and wall-grow work (separate 0.7 specs).

## Open Questions

- [NEEDS CLARIFICATION: should the BeatSaver card also group by mapper or upload date?] — assume no;
  those are sort/filter options, not cards.
- [NEEDS CLARIFICATION: is the playlist image worth downloading at playlist-install time (one file
  per playlist) or should the card use the first map's cover?] — assume first map cover until a
  playlist image is stored.

## Assumptions

- A map belongs to one downloaded playlist; re-download updates the tag.
- `open` sidecars are written atomically and can gain fields without a migration step.
- The existing `ItemList` remains the List view; Cards is a new grid in the same menu panel.

## Consultation Log

| Gate | Question | Verdict | Follow-up |
|------|----------|---------|-----------|
| G0 | Are the card/playlist metadata model, sort set and list/card toggle the right 0.7 library slice? | pending | send with the sidecar and menu evidence |
