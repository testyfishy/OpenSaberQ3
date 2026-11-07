# Feature Specification: Arc geometry/colour from the headset video, BeatLeader left, BeastSaber tab

**Feature Branch**: `025-arcs-menu-beast`

**Created**: 2026-11-06

**Status**: 0.6.3 released; in-VR checks (SC-002..SC-005) pending

**Input**: User description: "The arcs that connect between the boxes are never correct - they never connect correctly between the boxes, the arc colours are never correct. Now that you have the video you might see what I see. On the main screen the right side has BeatSaver; put BeatLeader on the left, and add another tab for BeastSaber to download songs from BeastSaber. Use the video for smooth short clips and UI stills for itch.io."

## Evidence

- **Video A** `F:\Dev\BeepSaberBin\arc_song.mp4`: 5:23, 1920x1080, 60 fps, AAC stereo. Full play
  of one map. This is the arc evidence.
- **Video B** `F:\Dev\BeepSaberBin\arc_menu.mp4`: 2:14, 1920x1080, 60 fps, AAC. Menu, a song, the
  pause menu, and a second song. Source for UI stills.
- **Frame at 150 s** (`f025/song_150.png`, crop `f025/z150.png`): notes are pink and blue; a thin
  **white** ribbon leaves a pink note, passes through/behind a blue note and the accuracy ring, and
  leaves the frame. White is the map's *environment* colour, not either note colour.
- **Synthetic render** (`f025/arc_straight.png`, `arc_mid_cw.png`, `arc_mid_ccw.png`): the current
  `Arc.spawn()` drawn with white/amber endpoint markers and a green straight line between them.
  - Mode 0 (straight) connects the two markers with a smooth bulge of about 1.3 m on a 4 m chord.
  - Mode 1 (clockwise) and mode 2 (counter-clockwise) **loop**: the recorded curve points for a
    4 m chord are `(0.96, 2.31, 3.0)`, `(1.11, -0.81, 2.0)`, `(-1.56, -1.11, 1.0)` in tail-local
    space, i.e. it zig-zags +1.5 m / -1.1 m either side of the chord and crosses itself.
- **Colour code path**: `game/BeepSaber_Game.gd:559-561` `_apply_map_colours()` calls
  `update_left_color(MapPalette.env_left)` and `update_right_color(MapPalette.env_right)`, and those
  same functions write the arc shader colour (`:616-617`, `:627-628`). Notes instead use
  `MapPalette.color_left/right` (`game/BeepCube/BeepCube.gd`, `spawn()`). So every arc is painted in
  the room/environment palette, which is why the video shows a white arc between pink and blue notes.

## Scoped change (arcs)

- **Symptom**: arcs do not visually join the notes they belong to and are the wrong colour.
- **Root cause**: (a) `Arc.spawn()` builds mid-anchor points by rotating the head cut vector by `PI`
  or `TAU` and adds the same offset at three points, then smooths them, producing a self-crossing
  path; (b) the arc materials are updated from `MapPalette.env_*` in `_apply_map_colours()`.
- **Blast radius**: `game/Arc/Arc.gd`, `game/BeepSaber_Game.gd` colour application, docs; the note,
  wall and event paths are untouched.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Arcs join the notes and match their colour (Priority: P1)

As a player, the ribbon between two same-colour notes starts at the first note and ends at the
second, and it is the same red/blue (map note colour) as those notes.

**Why this priority**: This is a repeated complaint across builds and is visible in every arc map.

**Independent Test**: Open any map with sliders, pause mid-song, and compare each arc's colour and
endpoints with its notes; the synthetic probe also asserts endpoints and monotonic Z.

**Acceptance Scenarios**:

1. **Given** a map with sliders, **When** an arc spawns, **Then** its first point is within 1 cm of
   the head note's centre and its last point within 1 cm of the tail note's centre.
2. **Given** a slider with `midAnchorMode` 1 or 2, **When** it is drawn, **Then** the path bows to
   one side and never crosses itself or leaves the head-to-tail bounding box by more than 0.6 m.
3. **Given** a map whose notes are pink and blue, **When** arcs are drawn, **Then** the left arc is
   the same pink and the right arc the same blue, not the room's env colour.
4. **Given** the player changes saber colours in Settings, **When** they return to play, **Then**
   arcs follow the note colours again (map palette unless `disable_map_color`).

### User Story 2 - BeatLeader on the left, BeastSaber on the right (Priority: P2)

As a player standing in front of the song list, the left side has a BeatLeader sign that opens the
leaderboard, and the right-side online panel now offers BeatSaver and BeastSaber.

**Why this priority**: Menu symmetry requested by the owner; independent of the arc fix.

**Independent Test**: In VR, look left and press the BeatLeader sign; then use the right panel to
open BeastSaber, pick a curated playlist, download it, and see the maps in the library.

**Acceptance Scenarios**:

1. **Given** the main menu, **When** the player looks left, **Then** a BeatLeader launcher is there
   and opens the existing `BeatLeaderPanel`; closing it returns to the menu.
2. **Given** the right "Online Map Sources" panel, **When** it opens, **Then** it shows BeatSaver and
   BeastSaber entries.
3. **Given** the BeastSaber panel, **When** it opens, **Then** it lists curated BeastSaber/BeatSaver
   playlists with name, curator and song count.
4. **Given** a playlist, **When** the player presses Download, **Then** every song is fetched from
   BeatSaver and unpacked into `Songs/`, tagged `beastsaber`, with a progress line; the library
   refresh shows them.
5. **Given** no network, **When** the panel loads, **Then** it shows a readable error and a Retry
   button; nothing is written to `Songs/`.

### User Story 3 - Itch assets from the new video (Priority: P3)

As the owner, I get a short smooth gameplay clip and clean UI stills from the 5-minute recording,
ready for the itch page.

**Why this priority**: Needed for the itch listing, but the listing is published separately.

**Independent Test**: Inspect the exported files; the clip plays with audio at 1080p60 and the stills
show no menu glare, guardian grid or hand occlusion.

**Acceptance Scenarios**:

1. **Given** `arc_song.mp4`, **When** the clip is cut, **Then** a 15-30 s 1920x1080 60 fps MP4 with
   audio exists and loops cleanly.
2. **Given** the same video, **When** stills are grabbed, **Then** 3-5 PNGs at 1920x1080 show the
   note lane and HUD without the pause menu or guardian.
3. **Given** video B, **When** UI stills are grabbed, **Then** the main menu, BeatSaver panel and
   pause menu are captured for the itch gallery.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Arc ribbons MUST use the map's note colours (`MapPalette.color_left/right`), both the
  normal and magnet materials, including when `disable_map_color` is set (then the settings
  colours), and MUST update whenever note colours change (map load, settings change).
- **FR-002**: Arc geometry MUST start at the head note centre and end at the tail note centre with a
  smooth, single-valued path whose Z is monotonic; it MUST NOT loop or self-intersect. Handle length
  MUST follow `mu`/`tmu` scaled by a fraction of the chord, with a cap at 0.6 of the chord as the
  explicit guard against loops (not an arbitrary clamp).
- **FR-003**: Control points MUST use the map's `mu`/`tmu` (head/tail control-point length
  multiplier) and `tc` (tail cut direction): `P1 = head + headDir * mu * k`, with the tail side
  mirrored.
- **FR-004**: `midAnchorMode` MUST change the bow only when the head is a dot (direction 8) or the
  head and tail directions are about 180 degrees apart; otherwise it MUST be ignored. When active,
  it MUST rotate the bow by +/-90 degrees around Z, not by PI/TAU.
- **FR-005**: A probe (`tools/harness/arc_probe`) MUST render all three modes with endpoint markers
  and print path points so the fix is verifiable without the headset.
- **FR-006**: The visible arc MUST stay a thin ribbon (about 8 cm) and MUST NOT add per-frame cost.
- **FR-007**: A BeatLeader launcher MUST sit on the left of the main menu, mirrored from the right
  side "Online Map Sources" canvas with its own pointer collider, and open the existing read-only
  `BeatLeaderPanel`. Its SubViewport MUST not update while hidden.
- **FR-008**: The right-side "Online Map Sources" panel MUST offer a **BeastSaber (curated)** entry
  alongside BeatSaver.
- **FR-009**: The BeastSaber panel MUST list curated playlists from
  `https://api.beatsaver.com/playlists/search/{page}?curated=true` (name, curator, map count,
  duration) with paging; it MUST NOT parse HTML or devalue payloads.
- **FR-010**: Downloading a playlist MUST fetch `downloadURL` (`.bplist`), then each song's map by
  hash via `https://api.beatsaver.com/maps/hash/{hash}`, unpack into `Songs/`, tag
  `MapSource.SOURCE_BEASTSABER`, refresh the library, and show progress.
- **FR-011**: Failures MUST leave no partially unpacked song and MUST show an error; the panel's
  Download button is the retry. A zip without `Info.dat` MUST NOT create a library folder or a tag.
  A map already installed with the same hash MUST be counted as "already present", not downloaded.
- **FR-012**: A 15-30 s 1080p60 gameplay clip with audio and 3-5 gameplay stills MUST be cut from
  `arc_song.mp4`, plus menu stills from `arc_menu.mp4`, and referenced in the itch docs.
- **FR-013**: The itch page and push plan MUST be updated for the new version and assets; publishing
  remains out of scope without the owner.

### Key Entities

- **ArcInfo**: existing head/tail beat, line, layer, cut direction, control multiplier, mid-anchor
  mode.
- **BeastSaberPlaylist**: playlist id, name, curator, description, image, song count, map hashes.
- **ItchAsset**: clip/still path, timestamp, purpose (hero, gallery, README).

## Success Criteria *(mandatory)*

- **SC-001**: Probe: every arc endpoint is within 1 cm of its note centre in scene space, the sampled
  path's Z is monotonic, and the path never crosses itself (sampled 2D chord-frame segments have no
  pair of crossings).
- **SC-002**: With the arc and its notes moving at the real NJS, the head and tail stay within 1 cm of
  the note centres on every sampled frame (not only at spawn).
- **SC-003**: On device, a paused frame shows a pink arc from pink notes and a blue arc from blue
  notes; the arc hue matches the note within 10 degrees.
- **SC-004**: In VR, the left BeatLeader sign opens the panel in one press and closes back to the
  menu; the panel still loads rows for a known map.
- **SC-005**: The BeastSaber panel lists at least 10 curated playlists and downloads one playlist of
  at least 5 maps into the library, tagged `beastsaber`, on the headset.
- **SC-006**: The exported clip is 15-30 s, 1920x1080, ~60 fps, with an audio stream, starts and ends
  on a beat boundary (or a <=0.5 s crossfade); the stills are 1920x1080 PNG with no guardian grid or
  pause overlay.

## Out of Scope

- Publishing to itch.io (owner account and go-ahead required).
- BeatLeader write actions, accounts or uploads.
- Chroma per-note `customData.color` on arcs (notes already honour it; arcs follow the palette).
- BeastSaber web UI beyond curated playlists; no HTML or devalue scraping.
- Any 0.6.0 asset/history rewrite.
- Matching Beat Saber's arc shader pixel-for-pixel; the target is correct connection and colour.

## Open Questions

- [NEEDS CLARIFICATION: should BeastSaber also allow single-map search, or are curated playlists
  plus "download all" enough for this build?] — assumed playlists only.
- [NEEDS CLARIFICATION: is a "download whole playlist" (possibly 20+ maps) acceptable in VR, or
  should each playlist download one selected map at a time?] — assumed whole playlist with progress.

## Assumptions

- The headset recording (Video A) is the map the owner played; no map files are needed to prove the
  arc defect because the probe reproduces it from the shipped code.
- BeatSaver's playlist endpoints need no auth; curated playlists are `?curated=true`.
- BeatLeader panel already works; only a launcher and placement are added.
- The owner will review the clip before any upload.

## Verification evidence (2026-11-07)

- `tools/harness/arc_probe.tscn` (writes `F:\Dev\BeepSaberBin\f025\arc_*.png`):
  - `arc_straight`: head_err 0.0000, tail_err 0.0000, z_mono true, crossings 0, bulge 1.062 m on a
    4.09 m chord.
  - `arc_short` (0.25 beat): bulge 0.204 m, no loop.
  - `arc_mid_cw` / `arc_mid_ccw`: bulge 1.107 m, z_mono true, crossings 0.
  - `arc_mid_opposed`: bulge 1.062 m, crossings 0.
- `tools/harness/beastsaber_probe.tscn`: 20 curated playlists on page 1; the smallest playlist
  `.bplist` had 8 songs; `/maps/hash/{hash}` returned 200 with a download URL; zip guard
  `good=true bad=false`; a real map installed (`first=0`, source `beastsaber`, hash match) and a
  second install of the same map returned `SKIPPED`.
- `tools/harness/ui_preview.tscn`: launcher, BeastSaber and Online Map Sources panels render at
  1536x960 / 720x470 with the expected rows and tiles.
- 0.6.3 APK: 78,146,219 bytes, SHA-256
  `F123F07D30EBD38E8324303F6E31409DFD58778EB9F4A422EB9659F58DAD2D43`, versionName 0.6.3,
  versionCode 13, same signer, no demo/benchmark assets; installed over 0.6.2 and running.
- Pending: in-VR arc look, left sign press, BeastSaber download of a real playlist.

## Consultation Log

| Gate | Question | Verdict | Follow-up |
|------|----------|---------|-----------|
| G0 | Is this spec (arc colour+geometry, left BeatLeader, BeastSaber playlists, itch assets) the right scope and order? | **GO WITH CHANGES** | Adopted: mu/tmu control points, mid-anchor only for dot/opposed directions, drop the 0.6 m cap, in-scene endpoint SC, curated playlists via the BeatSaver JSON API (no devalue), left canvas gets its own collider and updates only when visible; Chroma per-note colour declared out of scope. |
| G4 + G5 (0.6.3) | Final diff: is it shippable and does it match the sheet? | **CHANGES NEEDED, fixed** | FR-011 drift: a bad zip created an empty tagged folder. Fixed: `ZIPReader` checks for `Info.dat` before unpacking, failed folders are deleted, tags written only on success, same-hash maps counted as "already present", different maps with the same name keep both. FR-002 reworded: the 0.6 chord cap is the loop guard. Arc handles named constants, tuning still open in VR. SC-002..SC-005 stay pending until the headset pass. |
