# Feature Specification: Storage manager with bulk map deletion

**Feature Branch**: `026-storage-manager`

**Created**: 2026-11-07

**Status**: Draft (G0 pending)

**Input**: User description: "Could we build a storage management system to bulk delete songs and stuff" — clarified as: multi-select maps plus "delete all from a source", opened from a Storage button in the main menu, with a count-and-size confirmation.

## Scoped change (why this exists)

The library currently deletes one map at a time through the main menu's `Delete` button, and the
player has no idea which maps are using space. BeatSaver/BeastSaber downloads make it easy to
accumulate tens of maps. This adds a single panel that shows every map with its size and source,
lets the player tick several (or a whole source), and deletes them after a count + size
confirmation. It reuses the existing delete semantics (folder, high scores, play counts).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Bulk delete selected maps (Priority: P1)

As a player, I open Storage, see how much each map takes, tick several, and delete them in one go
after being told how many maps and how much space that is.

**Why this priority**: This is the request; it replaces repeated single deletes.

**Independent Test**: Open Storage, tick three maps, press Delete twice, and confirm the three
folders are gone, the library refreshes, and the total drops by their summed size.

**Acceptance Scenarios**:

1. **Given** the Storage panel, **When** it opens, **Then** every library map is listed with name,
   source tag and size, and the header shows the map count and total size.
2. **Given** two maps ticked, **When** Delete is pressed once, **Then** the button reads
   "Sure? Delete 2 maps (X MB)" and nothing is deleted; a second press within 5 s deletes them.
3. **Given** no map ticked, **When** the panel opens or the selection is cleared, **Then** Delete is
   disabled.
4. **Given** the last map is deleted, **When** the list refreshes, **Then** the panel shows an empty
   state and the main menu shows "No songs yet".

### User Story 2 - Delete a whole source (Priority: P2)

As a player who tried BeastSaber and wants the space back, I pick a source and delete every map
from it without ticking each one.

**Why this priority**: The fastest real cleanup, and the reason sizes and source tags share a view.

**Independent Test**: Download/tag maps from two sources, delete one source, and confirm only those
folders are gone.

**Acceptance Scenarios**:

1. **Given** maps from BeatSaver and BeastSaber, **When** the source picker is opened, **Then** it
   lists All sources plus each source with its count.
2. **Given** "BeastSaber (7)" selected, **When** Delete all from source is pressed twice, **Then**
   exactly the seven `beastsaber` folders are removed and every other map stays.
3. **Given** a source with zero maps, **When** it is selected, **Then** the delete button is disabled
   and the row count says 0.

### Edge Cases

- A map folder with subdirectories must be removed completely, not just its top-level files (the
  current single-delete loop is one level deep).
- A folder that cannot be deleted (permissions, in use) stays in the list with an error line; the
  other maps in the batch are still deleted.
- Deleting the map currently selected in the menu must clear the menu selection and cover; it must
  not leave Play/Leaderboard pointing at a deleted map.
- High-score and play-count rows for deleted maps are removed (matching the current Delete); rows
  for other maps are untouched.
- Opening Storage while a map is loading/playing is out of scope: the button lives in the menu and
  the panel is hidden outside the map-selection state.
- Size reads must not block the UI for a second on a large library; the panel fills as it reads.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The main menu MUST have a **Storage** button beside Users/Settings/Exit. Pressing it
  MUST hide the menu and show the Storage panel; Back MUST return to the menu.
- **FR-002**: The panel MUST list every map in the library with its name, source label, and size on
  disk (recursive, formatted MB/GB), sorted by size descending by default.
- **FR-003**: The header MUST show the number of maps and the total size of the library.
- **FR-004**: Each row MUST have a checkbox; Select all / Clear MUST work, and the footer MUST show
  "Selected: N maps (X MB)".
- **FR-005**: Delete MUST require a second press within 5 s: the first press changes the label to
  "Sure? Delete N maps (X MB)" and deletes nothing; the second deletes.
- **FR-006**: The panel MUST offer a source picker (All sources + each source with its count) and a
  "Delete all from source" action with the same count + size confirmation; it MUST delete only maps
  with that source tag.
- **FR-007**: Deletion MUST remove the map folder recursively, remove its high scores and play
  counts, and refresh both the panel and the main menu library.
- **FR-008**: A failed deletion MUST leave that map listed and show an error; it MUST NOT abort the
  rest of the batch or report a size/count it did not delete.
- **FR-009**: Delete buttons MUST be disabled when the selection is empty or the chosen source has
  no maps; the panel MUST NOT offer to delete bundled/read-only content.
- **FR-010**: The panel MUST only be reachable from map selection; the game MUST hide it on leaving
  that state (play, pause, settings, leaderboard).
- **FR-011**: A verification probe MUST compute sizes and group by source on a synthetic tree, and
  exercise the recursive delete, without the headset.

### Key Entities

- **MapInfo**: `song_name`, `filepath`, `source`, `source_id`, `level_hash`.
- **StorageRow**: map reference, display name, source label, byte size, selected flag.
- **Deletion batch**: rows to delete plus their total count and size for the confirmation.

## Success Criteria *(mandatory)*

- **SC-001**: On the headset, ticking 3 maps and confirming deletes exactly those folders; the
  header total drops by the sum of their sizes and the library refreshes.
- **SC-002**: "Delete all from source" removes exactly the tagged maps and leaves the rest intact.
- **SC-003**: One press never deletes; the confirmation names the correct count and size.
- **SC-004**: High scores and play counts for the deleted maps are gone; other maps keep theirs.
- **SC-005**: The probe reports correct sizes, source grouping, and recursive deletion on a
  synthetic tree (nested folder included).

## Out of Scope

- Deleting screenshots, temp files or logs (not selected for this slice).
- Orphaned high-score cleanup (rows whose map is already gone).
- Moving maps between storage locations, SD-card management, cloud sync.
- Per-map confirmation dialogs, undo/trash, background deletion while playing.
- Any change to the download or import paths.

## Open Questions

- [NEEDS CLARIFICATION: none blocking. Scores/play counts are removed with the map to match the
  existing Delete button; keeping them for a re-download would be a later option.]

## Assumptions

- The library list in the menu (`_all_songs`) is the source of truth; a map hidden by a filter still
  exists and MUST appear in Storage.
- Android has no free-space API exposed to Godot here, so the header shows library usage, not the
  device's free bytes.
- Map folders are inside `user://OpenSaber/Songs/` and are writable by the app.

## Consultation Log

| Gate | Question | Verdict | Follow-up |
|------|----------|---------|-----------|
| G0 | Is the storage panel scope and the delete/confirm design right? | pending | send with the plan |
