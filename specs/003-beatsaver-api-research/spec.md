# Feature Specification: BeatSaver API + alternative map sources research (in-VR map browser, Godot/Quest 3)

**Feature Branch**: `003-beatsaver-api-research`

**Created**: 2026-11-01

**Status**: Done (G4)

**Deliverable**: `specs/003-beatsaver-api-research/beatsaver-api-reference.md` (453 lines) +
`samples/` (5 raw API captures).

**Input**: User description: "Research BeatSaver API and alternative map sources for an in-VR map browser in Godot" — exact endpoints, filter/sort parameters, per-map fields, auth/rate limits, an honest verdict on BeatSaver alternatives, and the browsing information hierarchy a VR panel should replicate.

## Intent

Produce an implementation-ready reference so that a Godot 4.x/Quest 3 map browser can be
written against the live BeatSaver API without guesswork: exact endpoint paths, exact
query-parameter names and accepted values, the map object field list mapped to the filters
those fields enable, and a sourced verdict on which other community services (BeastSaber,
ScoreSaber, BeatLeader, ModelSaber, newer indexes) are worth integrating.

This session writes **documentation only**. No gameplay, network or UI code is changed.

## Requirements *(mandatory)*

- **FR-001**: The brief MUST document the BeatSaver API base URL and version, and for each
  browser-relevant endpoint (`search/maps`, `maps/latest`, `maps/uploader`, `maps/id`,
  `playlist/id`, and any collaborator/versions endpoint) give method, path, and **every**
  query parameter with type and accepted values.
- **FR-002**: The brief MUST separate parameters into *filtering* (narrow the result set) and
  *sorting*, and MUST explicitly answer, per concept, whether a parameter exists: free-text,
  duration, min/max NPS, min/max BPM, rating/score range, upload date, tags, genre,
  curated, required mods (chroma/noodle/mapping extensions/cinema), ranked/qualified,
  automapper/AI, "match exact"/similarity.
- **FR-003**: The brief MUST list supported sort orders with their exact enum spellings, and
  pagination semantics: page size, max page/offset, `nextPage`, total-results field.
- **FR-004**: The brief MUST give the per-map field list, calling out exactly where
  **duration in seconds**, BPM, per-difficulty NPS and note counts, votes/score/rating,
  download count, upload date, cover URL, preview URL, map id/version hash, and any
  automapper/AI flag live.
- **FR-005**: The brief MUST state auth requirements (API key or not), rate limits, CORS
  behaviour, and any documented policy for third-party clients, citing a primary source
  where one exists and marking UNVERIFIED where none does.
- **FR-006**: The brief MUST evaluate BeastSaber, ScoreSaber, BeatLeader, ModelSaber and at
  least one newer map index on: hosts downloadable maps vs metadata only, public API,
  extra data over BeatSaver, and ToS-acceptability for a third-party client.
- **FR-007**: The brief MUST state whether "curated"/"staff-picked" and "ranked" status are
  exposed by BeatSaver itself, and where a client would have to source them otherwise.
- **FR-008**: The brief MUST summarise the BeatSaver website's browsing information
  hierarchy (filter controls, sort control, card contents) as a model for a VR panel.
- **FR-009**: The brief MUST give VR-specific list/pagination/legibility/input guidance,
  each item labelled VERIFIED (primary doc/spec) or PLAUSIBLE (inference from general HCI
  or platform guidance).
- **FR-010**: Every non-obvious claim MUST carry a source URL; anything not confirmed MUST be
  labelled UNVERIFIED. No invented parameter names.
- **FR-011**: Endpoint paths MUST be taken from the live OpenAPI document, not assumed. Where
  the live document disagrees with prose docs or with a captured response, the captured
  response wins and the disagreement is noted in the doc.
- **FR-012**: "Ranked" MUST be disambiguated: the doc states which ranking system (ScoreSaber,
  BeatLeader, or BeatSaver's own `leaderboard` enum) each filter and field refers to, and
  which one the SC-001 worked example uses.

## Success Criteria *(mandatory)*

- **SC-001**: A Godot implementer can build the search request for "ranked, expert+, 2–5 min,
  6–12 NPS, newest first" from the brief alone, with no further documentation lookup.
- **SC-002**: Zero query parameters or sort enums are listed that are not present in a
  fetched primary source (docs, API schema, or a live response).
- **SC-003**: At least five candidate sources are scored integrate/do-not-integrate with a
  one-line reason each.
- **SC-004**: The brief fits as one reference document (target ≤ ~450 lines) and is linked
  from the session's spec directory.
- **SC-005**: For every FR-002 concept the brief marks it **server-side** (exact parameter),
  **client-side** (field to filter on in the response), or **third-party** (needs another API),
  so a filter that does not exist is still actionable.

## Out of scope

- Writing Godot networking, UI or download code — later feature.
- BeatSaver account/OAuth flows, uploading maps, or moderation APIs.
- Legal advice; only a summary of published terms with citations.
- Reverse-engineering BeatSaver's private/undocumented internal endpoints.

## Open questions

- Whether the parent feature needs a **leaderboard overlay** (ScoreSaber/BeatLeader) inside
  the panel at v1, or only ranked-status badges. Assumed: badges at v1, leaderboards later.
- Whether offline caching of index pages is required on Quest 3. Assumed: out of scope for
  research; noted as a design consideration only.

## Findings that change the parent feature's design

1. **The API cannot express "ExpertPlus only" or "this difficulty's NPS".** `minNps`/`maxNps`
   match any difficulty and `minDuration` buffers per *map*. Client-side filtering is mandatory and
   pages come back short (~4 usable of 20 in the sampled query). Budget for pagination loops.
2. **The existing `game/ui/BeatSaverPanel/BeatSaverPanel.gd` is on the legacy surface**
   (`beatsaver.com/api/maps/{list}/{page}`, `sortOrder=`). §10 has the three-line migration map.
3. **"Ranked" is two systems.** Same map, same difficulty: ScoreSaber 6.51★ vs BeatLeader 8.35★.
   The UI must name which one it shows.
4. **No published rate limit and no rate limiter in the server code** — treat it as fragile:
   no polling, one request in flight, and the WebSocket for new-map ticks.
5. **Text entry is the open UX risk**, not the API: the project already ships an in-world keyboard
   (`OQ_Toolkit/OQ_UI2D/OQ_UI2DKeyboard.tscn`), and the Android IME is not proven to work in an
   immersive session.

## Assumptions

- Target client is a Godot 4.x Quest 3 app making plain HTTPS GETs (`HTTPRequest`), no
  server-side proxy.
- BeatSaver's public API is used read-only and anonymously.
- The map *file* download path (`.zip` from `versions[].downloadURL`) is already understood
  by the parent feature; this brief documents it but does not design the downloader.

## Consultation Log

| Gate | Asked | Verdict | Action taken |
|------|-------|---------|--------------|
| G0 | Spec review before research/writing | **GO WITH CHANGES** | Endpoint names from the live schema (`search/text/{page}`, cursor `maps/latest`); added FR-011 (schema vs live-response precedence), FR-012 (disambiguate ScoreSaber vs BeatLeader "ranked"), SC-005 (server/client/third-party labelling); no requested filter dropped — missing ones became "NOT A QUERY PARAM" rows; raw samples saved under `samples/`; CORS noted as irrelevant to native Godot. |
| G4 | Final review + drift check | **APPROVE WITH FIXES** | Applied all seven: (1) §3.3 rewritten — the "ranked/expert+/2–5 min/6–12 NPS" query over-counts (1007 server hits; 1 in 5 sampled maps had ExpertPlus NPS outside the band), so the client filters on one diff row and pages the API until a display page fills; (2) the immersive-session virtual-keyboard claim moved to UNVERIFIED with the in-world keyboard named as the real option; (3) Meta dp/px figures labelled as 2D-panel guidance; (4) unverified "Random is repeatable without a seed" claim deleted; (5) `maps/latest` `automapper` semantics live-checked (true → 48/100 AI, false → 0/100); (6) evidence bar now names server source as a third accepted class; (7) capture count normalised to ~40. Drift: FR-001..012 and SC-001..005 all met; SC-004 at 453 lines. |
