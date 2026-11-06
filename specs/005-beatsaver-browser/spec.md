# Feature Specification: Rebuild the in-VR BeatSaver browser on the verified API

**Feature Branch**: `005-beatsaver-browser`

**Created**: 2026-11-01

**Status**: Draft

**Input**: User description: "Rebuild the in-VR BeatSaver browser on the verified API: cards, filters, sort, search, pagination"

The API contract is `specs/003-beatsaver-api-research/beatsaver-api-reference.md` (verified
against the live Swagger document, live responses and the server source). This sheet is the
testable form of the brief plus that reference; nothing about parameter names is re-derived here.

## Scoped change

- **Symptom**: the browser cannot find a playable map. It runs on the retired
  `beatsaver.com/api/maps/{list}/{page}` endpoints (`BeatSaverPanel.gd:133`), sorts by nothing,
  offers no filters, shows one line of text per map in an `ItemList`, and loads every cover
  serially on the main thread (`BeatSaverPanel.gd:349-356`).
- **Root cause**: it is built on the pre-2023 surface: fixed "plays" list, `sortOrder` alias,
  no filter parameters, no compact per-map information, no paging control.
- **Blast radius**: `game/ui/BeatSaverPanel/*` (script, scene, new API + cover-loader + card
  scripts), `game/Settings.gd` (eight new persisted keys), `game/scripts/HTTPRequestPool.gd`
  (cancel of bound callables). No audio, scoring, profile, performance or gameplay code.

## User Scenarios & Testing

### User Story 1 - Find a map I can actually play (Priority: P1)

A player opens Map Sources → BeatSaver, turns on `Playable only`, `Ranked`, Expert+, 2–4 min,
and gets maps that are (a) present at that difficulty on the Standard characteristic, (b) not
ranked-only on another mode, and (c) not built on Noodle / Mapping Extensions / Vivify.

**Why this priority**: "half-supporting those maps is worse than filtering them out" — the
browser's job is to hand the player a map they can finish.

**Independent Test**: with the filters above, every card shows a lit Expert+ pill, no
Maps-Ext/Noodle/Vivify badge, and a ranked star value for that difficulty.

**Acceptance Scenarios**:

1. **Given** `Playable only`, `Ranked`, Expert+, 2–4 min, **When** the page loads, **Then** all
   cards are `Ranked`-filtered server results that pass the client-side Expert+ and mod check.
2. **Given** a map whose only Expert+ diff needs Noodle Extensions, **When** `Playable only` is
   on, **Then** it is not shown; with the toggle off it is shown and carries the `Noodle` badge.
3. **Given** the same filters, **When** I press Next, **Then** the page counter advances, the
   previous page's cards are gone, and the new cover images arrive without a hitch in the panel.

### User Story 2 - Search and sort like the website (Priority: P1)

Typing in the search field narrows the list as I type (≈400 ms after I stop), and Sorting offers
Latest / Rating / Curated / Relevance, with Relevance only offered while a query exists.

**Acceptance Scenarios**:

1. **Given** an empty query, **When** I open the sort control, **Then** Relevance is not
   selectable; with text it is, and selecting it re-queries with `order=Relevance`.
2. **Given** I type "camellia", **When** I stop for 400 ms, **Then** exactly one request is made
   for that text; keystrokes typed while an older response is in flight never repaint the list
   with the older results.
3. **Given** a pasted map key (`q=557f4` style, server answers `{"redirect": …}`), **Then** the
   browser shows that single map instead of an empty list.

### User Story 3 - Choose well from the card (Priority: P2)

Each card carries cover, title, mapper, duration `m:ss`, BPM, up/down percentage, one pill per
difficulty (greyed when absent from Standard), small tags for 360/90/OneSaber characteristics,
and requirement badges for Noodle, Mapping Extensions, Chroma, Vivify.

**Acceptance Scenarios**:

1. **Given** a map with Easy/Hard/ExpertPlus on Standard and ExpertPlus on OneSaber, **Then**
   E/H/Ex+ pills are lit, N/Ex are greyed, and a `1S` tag is shown.
2. **Given** a card is tapped, **Then** the details pane shows that map, its preview plays, and
   `Download` adds it.

### Edge Cases

- `docs: []` (no matches, or a page past the end) → empty state with the query echoed, not an error.
- HTTP 500 (unknown `order` enum) → error state with Retry; never sent because the enum is
  validated client-side.
- No network / timeout (8 s) → error state with Retry; the previous page stays on screen until
  the new request succeeds.
- A server page reduced to < 20 by client-side filters → keep fetching server pages (≤ 4 per
  display page) so a display page is full, then stop.
- `info.pages` is computed with a hard-coded 20/page → never trust it.
- Maps missing `stats.upvotes`/`downvotes` → fall back to `stats.score`, then to `–`.
- A map with no `versions` or no `diffs` → card still renders, with no pills.

## Requirements

### Functional Requirements

- **FR-001**: All browsing MUST use `https://api.beatsaver.com/search/text/{page}` with a
  descriptive `User-Agent`; the legacy `/api/maps/{list}/{page}` paths MUST be gone.
- **FR-002**: The query MUST be built from the reference's parameter names only: `q`, `order`,
  `minDuration`/`maxDuration` (seconds), `minNps`/`maxNps`, `curated`, `verified`,
  `leaderboard=Ranked`, `pageSize=20`; absent parameters MUST be omitted, never sent as 0.
- **FR-003**: `order` MUST be validated against `Latest | Relevance | Rating | Curated` and
  Relevance MUST only be sent while `q` is non-blank (blank + Relevance is a 500 / silent Latest).
- **FR-004**: A map card MUST show cover, title, mapper, `metadata.duration` as `m:ss`,
  `metadata.bpm`, up/down percentage, one pill per difficulty, characteristic tags, and the four
  requirement badges. `versions[].diffs[].length` MUST NOT be used as a duration.
- **FR-005**: Difficulty pills MUST reflect `characteristic == "Standard"`; a difficulty present
  only in another characteristic is rendered greyed. A difficulty filter (any of E/N/H/Ex/Ex+)
  MUST be applied client-side over the Standard diffs.
- **FR-006**: `Playable only` MUST exclude maps where any diff of the shown version sets `ne`,
  `me` or `vivify`. It MUST be a client-side filter: the server accepts only one `X=false` mod
  filter per request (verified 2026-11-01: `noodle=false&me=false` returns the `me` result set,
  adding `vivify=false` returns the vivify set), so it cannot be expressed server-side.
- **FR-007**: Search text MUST be debounced by ~400 ms, each query MUST carry a monotonically
  increasing sequence number, stale responses MUST be dropped, and in-flight browse requests
  MUST be cancelled when a new query starts.
- **FR-008**: Pagination MUST be explicit (prev / `Page n of m` / next), with `m` computed as
  `ceil(total / pageSize)`, and MUST keep a per-display-page record of how many server pages it
  consumed so Back walks pages exactly.
- **FR-009**: The next page's first server response and its covers MUST be prefetched after a
  page renders, and reused when Next is pressed; a query change MUST invalidate the prefetch.
- **FR-010**: The panel MUST show a loading state, an empty state, and an error state with a
  `Retry` button; Retry MUST re-run the current query.
- **FR-011**: The last sort, filter toggles, duration bucket, NPS preset and difficulty chips
  MUST be persisted through `Settings` (`user://config.ini`) and restored at startup.
- **FR-012**: Cover images MUST be decoded off the main thread (`WorkerThreadPool`) and cached by
  URL (URLs are per-hash and immutable), with concurrent downloads capped by `HTTPRequestPool`.
  No file writes and no image decoding may occur in `_process`.
- **FR-013**: Downloading a map, the details pane, the preview audio, and the "Maps by" jump MUST
  keep working, as MUST `_show()`/`_hide()` for `MapDownloadPanel`.
- **FR-014**: A top-level `{"redirect": "<id>"}` search response MUST resolve via
  `/maps/id/{id}` and render as a single-map page.
- **FR-015**: `godot --headless --path . --quit` MUST finish with no SCRIPT ERROR / Parse Error.

### Key Entities

- **Browse query**: `{q, order, page, curated, verified, ranked, playable_only, duration_bucket,
  nps_preset, difficulties}`.
- **Map record (parsed)**: id, name, mapper, uploader id/name/verified, bpm, duration, upvotes,
  downvotes, score, cover/preview/download URL, hash, diffs[] (characteristic, difficulty, nps,
  seconds, stars, blStars, ne/me/chroma/vivify), flags (curated, ranked, blRanked, automapper).
- **Display page**: cards rendered for one page, plus `server_page_start` and `server_pages_used`.

## Success Criteria

- **SC-001**: With `Ranked` + `Playable only` + Expert+ on, 100 % of visible cards pass the
  client-side check (no mod badge, lit Expert+ pill); spot-checked against the raw JSON.
- **SC-002**: Typing a six-character query produces exactly one browse request, and no response
  older than the latest sequence number ever repaints the list (log-verifiable).
- **SC-003**: Page 2 shows different maps than page 1 and `Page n of m` matches
  `ceil(info.total/20)`, not `info.pages`.
- **SC-004**: A second launch restores the sort and filter set from `config.ini`.
- **SC-005**: `godot --headless --path . --quit` prints no SCRIPT ERROR / Parse Error.
- **SC-006**: No `Image.load_*_from_buffer` and no `FileAccess` write appears inside any
  `_process` in `game/ui/BeatSaverPanel/`.
- **SC-007** (device, verified 2026-11-02): the download chain completes *on the headset* -
  search `HTTP 200` -> first result -> download `HTTP 200` -> zip written ->
  unzipped into `user://OpenSaber/Songs/<name>/` -> `Map.load_map_info()` parses the result.
  Measured with the bench-only probe `[bench] beatsaver_probe=true`, which runs the same
  `BeatSaverApi` URL/parse functions and the same destination layout as the panel: search
  200 / 73 798 bytes, map `55831` "Void Hornet", download 200 / 5 106 825 bytes, parsed as
  v2.1.0 with 2 difficulties. Recorded in `perf/captures/beatprobe.meta.txt`.
  This supersedes the "no Quest in this session" scope note above for the data path only;
  the panel's button handling is still verified by compile + code inspection, not by a
  wearer pressing it.

## Assumptions

- Search text still comes from the shared in-world keyboard (`Keyboard_online_search`); no
  system IME. The panel therefore debounces `TextEdit.text_changed` and also accepts Enter.
- One HTTP request in flight for browse JSON (reference's practical policy); four for covers.
- Covers are the 256 px CDN thumbnails; a small texture cache (≈60) is enough for a page plus
  prefetch and keeps video memory bounded.
- Cards are rebuilt per display page (20 cards); this happens on page change, never per frame.

## Out of scope

- Map detail pages, playlists, tags/genre multi-select, environments, date-range presets,
  audio preview streaming (the existing whole-file preview is kept), WebSocket live feed.
- ScoreSaber / BeatLeader direct APIs (BeatSaver mirrors what is shown).
- Any change to audio, profiles, scoring, or the 120 Hz performance work.
- Exporting, installing, or device/VR verification (no Quest in this session).

## Open questions

- None blocking. Recorded deviations: `Playable only` is client-side (FR-006, forced by the
  server); the difficulty filter is client-side (no server parameter exists).

## Consultation Log

| Gate | Question | Verdict | Follow-up |
|------|----------|---------|-----------|
| G0+G1 PLAN CONSULT | spec + plan review before implementation | **GO WITH CHANGES** | Fixed pool of 20 reused cards instead of rebuilding nodes; paging cursors instead of whole server pages; `Page n` without "of m" while client filters run; Relevance collapses to Latest when `q` is blank; covers delivered deferred with `wait_for_task_completion` once per task; Settings writes coalesced; votes as percentage plus raw counts. |
| G4 (implementation) | Is the rebuild correct against the verified API, and does the async cover path deliver? | **SHIP** | Unit tests: 76 checks OK. Live smoke: 20 rows of 124,432 total (6,222 pages), Noodle badge correct on `557f4`, and **20/20 covers decoded and cached** after a 4 s wait — the earlier 0/20 reading was taken before the deferred delivery ran, and the test now waits for it. Server-side filters: `q`, `order`, `curated`, `verified`, `leaderboard=Ranked`, `min/maxDuration`, `min/maxNps`, `pageSize`. Client-side: Playable-only (the server accepts only one `X=false` mod filter per request — verified that `noodle=false&me=false` returns the me result set), difficulty chips, characteristic pills. |

