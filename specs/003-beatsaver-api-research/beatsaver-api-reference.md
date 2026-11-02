# BeatSaver API + map-source reference (Godot 4.x / Quest 3 in-VR browser)

**Status**: research complete (FR-001..FR-012). Every parameter, enum and field below was read
from the live OpenAPI document or observed in a live response; anything inferred is labelled.
**Captured**: 2026-11-02 UTC. Raw samples in `samples/`.

**Evidence bar** (G0 ruling): a parameter/enum/field is accepted if it appears in the live schema,
in a live response, **or in the server source** (`github.com/beatmaps-io/beatsaver-main`). Where
the schema and a response disagree, the response wins and the disagreement is noted. Prose docs
are not used for parameter names. Rows marked "source" are server-code evidence (the `@Ignore`
parameters are deliberately missing from the schema).

---

## 1. Hosts, versions, auth, CORS, rate limits (FR-005)

| Item | Value | Source |
|---|---|---|
| Base URL | `https://api.beatsaver.com` | `https://api.beatsaver.com/docs/swagger.json` |
| Spec | Swagger 2.0, `title: "BeatSaver API"`, `info.version: "0.1"`; also served at `https://beatsaver.com/api/...` (verified `200`, identical body). Swagger UI only at `https://api.beatsaver.com/docs/` | spec + live |
| WebSocket | `wss://ws.beatsaver.com/maps`, message `{"type":"MAP_UPDATE","msg":<map object>}` | spec `info.description` |
| Auth | **No key, no OAuth, for any read in this doc.** `optionalAuthorization` on search means a token only unlocks `followed`, `me`, `bookmarked` | source `src/jvmMain/kotlin/io/beatmaps/api/search.kt` + live 200s anonymously |
| CORS | `Access-Control-Allow-Origin: *` on both hosts | response headers |
| Rate limits | **UNVERIFIED — no published limit found.** No `RateLimit-*`/`Retry-After` headers on any captured response; no 429 observed; the server code has no rate limiter (Cloudflare fronts the API) | ~40 live responses + repo search |
| Practical policy | Send a descriptive `User-Agent`, one request in flight, ≤ 1 req/s sustained, exponential backoff on 5xx/429. The spec itself says: use the WebSocket "instead of making 100s of requests" | spec `info.description` |

**Third-party policy** (`https://beatsaver.com/policy/tos`, updated 2025-01-06): no API clause.
Prohibited: "commercializing content available on the site", blockchain/NFT, and "republishing or
use of another user's content… without explicit written permission". Reading the index and
downloading a `.zip` for local play is normal; **mirroring or redistributing map zips is not**.
AI/auto-mapped uploads may be purged after 90 days. CORS only matters for a web client.

---

## 2. Endpoints a browser needs (FR-001)

`{page}` is a 0-based **page index**, not an offset.

| Purpose | Method | Path | Returns |
|---|---|---|---|
| Search / browse | GET | `/search/text/{page}` | `{docs, info}` — **primary endpoint** |
| Legacy search | GET | `/search/v1/{page}` | same shape, Postgres-backed, fewer filters |
| Version router | GET | `/search/v2/{page}` | 302 → `text` or `v1` (site uses this) |
| New-map feed | GET | `/maps/latest` | `{docs}` only, **cursor**-paged |
| By uploader | GET | `/maps/uploader/{id}/{page}` | `{docs}`, fixed 20/page |
| Collaborations | GET | `/maps/collaborations/{id}` | `{docs, info}` |
| One map | GET | `/maps/id/{id}` | map object |
| Many maps | GET | `/maps/ids/{ids}` | object keyed by id (≤ 50, comma-separated) |
| By hash | GET | `/maps/hash/{hash}` | object keyed by hash (≤ 50) |
| Playlist | GET | `/playlists/id/{id}/{page}` | `{playlist, maps}` |
| Playlists containing a map | GET | `/playlists/map/{mapId}/{page}` | `{docs, info}` |
| Playlist search / latest / by user | GET | `/playlists/search/{page}`, `/playlists/latest`, `/playlists/user/{userId}/{page}` | `{docs, info}` or `{docs}` |
| Playlist as `.bplist` | GET | `/users/id/{id}/playlist` (JSON) or `/playlists/id/{id}/download` | file |
| User | GET | `/users/id/{id}`, `/users/name/{name}`, `/users/search/{page}` | user object |

`ids` and `hash` responses are **objects keyed by the requested value**, not arrays — e.g.
`{"4063": {...}, "32693": {...}}`. Order is not guaranteed; keep a client-side lookup.

### 2.1 `/search/text/{page}` — every parameter

All types are from the Kotlin route (`SearchApi.Solr`) and match the live spec. Absent ≠ false:
the numeric ones are `OptionalProperty`, so omit them rather than sending 0.

| Parameter | Type | Accepted / meaning | Verified |
|---|---|---|---|
| `q` | string | Free text. See §2.2 for syntax. Empty = match all | live + source |
| `order` | enum | `Latest \| Relevance \| Rating \| Curated \| Random \| Duration` | spec + live |
| `ascending` | bool | Inverts `order`. Default `false` | source |
| `pageSize` | int | Default 20, **coerced to 1..100** (150 silently returns 100) | source + live |
| `minNps`,`maxNps` | float | Notes-per-second band | live |
| `minBpm`,`maxBpm` | float | BPM band | live |
| `minDuration`,`maxDuration` | int | **Seconds** | live |
| `minRating`,`maxRating` | float | `stats.score`, 0..1 | live |
| `minVotes`,`maxVotes` | int | up+down | source |
| `minUpVotes`,`maxUpVotes` | int | upvotes | source |
| `minDownVotes`,`maxDownVotes` | int | downvotes | source |
| `minSsStars`,`maxSsStars` | float | ScoreSaber stars | source |
| `minBlStars`,`maxBlStars` | float | BeatLeader stars | source |
| `from`,`to` | date-time | Upload window, ISO-8601 (`2026-10-01T00:00:00Z`) | live |
| `tags` | string | Tag query: `a,b` = AND, `a\|b` = OR, `!a` = exclude | spec + live |
| `characteristics` | string | CSV of `Standard \| OneSaber \| NoArrows \| 90Degree \| 360Degree \| Lightshow \| Lawless \| Legacy` (all 8 verified live) | live |
| `environments` | string | CSV of Beat Saber environment enum names, e.g. `BigMirrorEnvironment` (full enum: `EBeatsaberEnvironment` in the source) | live |
| `collaborator` | string | CSV of user ids; map has any of them | source |
| `curated` | bool | Curated by staff | live |
| `verified` | bool | Uploader is a verified mapper | live |
| `fullSpread` | bool | All standard difficulties present | live |
| `chroma`,`noodle`,`me`,`cinema`,`vivify` | bool | Requires that mod (`me` = Mapping Extensions) | live, all five |
| `leaderboard` | enum | `All \| Ranked \| BeatLeader \| ScoreSaber` — see §6 | spec + live |
| `automapper` | bool | `true` = human **and** AI, `false` = **AI only**, absent = **human only** | spec + live (145 552 / 21 122 / 124 430) |
| `followed` | bool | Only maps by mappers you follow — **needs auth**, otherwise empty | source |
| `mapper` | int | **Undocumented in the spec**, filters by uploader user id | source |
| `curator` | int | **Undocumented**, filters by curator user id | source |
| `seed` | string | **Undocumented**, makes `order=Random` reproducible | source + live |
| `ranked` | bool | **Undocumented legacy**, `true` = ranked by *either* system | source |

`/search/v1/{page}` accepts a subset (no votes/star ranges, no `characteristics`,
`environments`, `ascending`, `me`, `vivify`, `pageSize`, `collaborator`). Treat as a fallback
path only.

### 2.2 `q` syntax (undocumented, from source)

- `mapper:name` — restricts to that mapper (part of the query, not a separate param).
- `key:557f4` and `!bsr 557f4` — return `{"redirect": "<id>"}` instead of `docs`. **A browser
  should handle `redirect` at the top of the response**, or a pasted key will render an empty list.
- `"quoted phrase"` — kept whole; everything else is split on spaces.
- `& | ! ( ) { } ^ ~ * ? : \` are stripped before the Solr query.
- `order=Relevance` is only honoured when `q` is non-blank; otherwise the server falls back to
  `Latest`. Send `order` only when it differs from `Relevance` (the site does exactly that).

### 2.3 `/maps/latest` (different pagination model)

| Parameter | Type | Notes |
|---|---|---|
| `pageSize` | int | 1..100, default 20 |
| `before` | date-time | Upload time of the last map you have → next page |
| `after` | date-time | Maps newer than the supplied time |
| `sort` | enum | `FIRST_PUBLISHED \| UPDATED \| LAST_PUBLISHED \| CREATED \| CURATED` (different enum from `order`!) |
| `automapper` | bool | Spec text: `true` = **both**, `false` = **no AI** (unlike search). Live check on 100 maps: `true` → 48 AI, `false` → 0 AI, absent → 0 AI |

No `info`, no total, no `nextPage`: hold the last map's `uploaded` value and pass it as `before`.

---

## 3. Filtering vs sorting, and what does **not** exist (FR-002, SC-005)

| Concept | Server-side parameter | Notes |
|---|---|---|
| Free text | `q` | Solr; `mapper:`/`key:`/quotes supported |
| Duration | `minDuration`,`maxDuration` (s) | |
| Min/max NPS | `minNps`,`maxNps` | Matches if **any** difficulty is in the band — 8/8 sampled maps had exactly one diff inside. Not "the map's max". |
| Min/max BPM | `minBpm`,`maxBpm` | |
| Upload date | `from`,`to` | ISO-8601 |
| Tags / genre | `tags` | Genre is a tag family (`pop`, `rock`, `anime`…); there is no separate `genre` param |
| Curated / verified | `curated=true`, `verified=true` | verified = uploader is a verified mapper |
| Required mods | `chroma`, `noodle`, `me`, `cinema`, `vivify` | all five exist |
| Ranked / qualified | `leaderboard=Ranked\|BeatLeader\|ScoreSaber` | **qualification has no filter**, only the `qualified` field |
| Automapper / AI | `automapper` | inverted booleans, see §2.1 |
| Rating / votes / stars | `minRating`,`maxRating` (0..1); `minVotes`,`maxVotes`,`minUpVotes`,`maxUpVotes`,`minDownVotes`,`maxDownVotes`; `minSsStars`,`maxSsStars`,`minBlStars`,`maxBlStars` | `stats.score` for rating; stars are per-system |
| Difficulty (Expert+ etc.) | **NOT A QUERY PARAM** | client-side over `versions[].diffs[].difficulty` |
| Match exact / similarity | **NOT SUPPORTED** | no similarity threshold, no `matchExact`; `q` is Solr full-text |
| Uploader / collaborator / curator | `mapper` (hidden), `collaborator`, `curator` (hidden) | |
| "New this week" style presets | **NOT A PARAM** | compose `order=Rating&from=<7 days ago>` (what the site does) |

### 3.1 Sort enums (FR-003)

`order` (search): `Latest`, `Relevance`, `Rating`, `Curated`, `Random`, `Duration` — exact
PascalCase. `Curated` sorts by curation date (returns curated maps first; combine with
`curated=true`). `Random` is stable for a given `seed` (two calls with `seed=abc` returned the
same five ids; `seed=xyz` returned different ones). `sortOrder` is still accepted as a legacy
alias of `order` (`@Ignore` in the schema) — the app's existing panel uses it.
**An unknown enum value returns HTTP 500, not 400** — validate before sending.

`sort` (`/maps/latest` only): `FIRST_PUBLISHED`, `UPDATED`, `LAST_PUBLISHED`, `CREATED`,
`CURATED` — SCREAMING_SNAKE, a different enum. Do not mix the two.

### 3.2 Pagination semantics (FR-003)

- `page` is a 0-based index; item offset = `page * pageSize`.
- `pageSize` is clamped to 1..100 (default 20). Verified: `pageSize=150` → 100 docs.
- `info = {total, pages, duration}`. **`info.pages` is always computed with 20/page** regardless
  of `pageSize` (6222 for 124 430 total at pageSize 50 and 100 too) — compute
  `ceil(total / pageSize)` yourself.
- There is **no `nextPage`/`prevPage`** in the current API (older write-ups show one).
- A page past the end returns `200` with `docs: []`, not an error. Deep paging works
  (page 5000 = offset 100 000 returned 20 docs).
- `info.duration` is the server's search time; unit not documented → **UNVERIFIED** (values
  0.000–0.05 are consistent with seconds).
- `/maps/uploader/{id}/{page}` is fixed at 20/page; `pageSize` is ignored.
- Batch endpoints cap at 50 ids/hashes per call.

### 3.3 SC-001 worked example — "ranked, expert+, 2–5 min, 6–12 NPS, newest first"

```text
GET https://api.beatsaver.com/search/text/0
      ?leaderboard=ScoreSaber               # "ranked" — see §6 for the other two flavours
      &minDuration=120&maxDuration=300      # seconds
      &minNps=6&maxNps=12
      &order=Latest
      &pageSize=20
```
Verified live: `total: 1007`. Sample of 5: `samples/search-sc001.json`.

But **`total: 1007` is an over-count for this query** and the client must finish the job:

1. `minNps`/`maxNps` match *any* difficulty, and `minDuration`/`maxDuration` match the *map's*
   duration — neither is "ExpertPlus, NPS 6–12". Of a 5-map sample all had exactly one
   ExpertPlus diff, but one (`5116a`) had ExpertPlus NPS 12.92 — outside the band — while its
   durations were inside. So ~1 in 5 server results is wrong for the stated query.
2. `expert+` is client-side: keep docs that have a diff with
   `difficulty == "ExpertPlus"` **and** `nps >= 6 and nps <= 12` **and** `seconds >= 120 and seconds <= 300`,
   all on that *same* diff row (optionally `characteristic == "Standard"`).
3. For ranked display, read `stars` off that same diff row — ranking is per difficulty, so a map
   can be ranked on one mode and not on the one you are showing.

Practical consequence: a page of 20 can yield far fewer than 20 displayable rows. Fetch successive
server pages until the display page is full (and stop when `docs` is empty), rather than assuming
one server page = one screen.

Sample: `samples/search-sc001.json`.

---

## 4. Map object (FR-004)

Field list from the live schema, confirmed against `samples/maps-id-4063.json`.
**Null fields are omitted from the JSON**, not sent as `null` — treat every optional field as
missing-able.

### 4.1 Top level

| Field | Type | Notes |
|---|---|---|
| `id` | string | **Opaque.** Legacy maps look numeric (`"4063"`); new maps are hex (`"557f4"`). Do not parse or reformat; `/maps/id/fdf` is 404. |
| `name` | string | Display title ("Calm Snow - I See Stars") |
| `description` | string | Mapper blurb, may be empty |
| `uploader` | object | `id` (int), `name`, `avatar`, `type`, `admin`, `curator`, `seniorCurator`, `curatorTab`, `verifiedMapper`, `playlistUrl` |
| `metadata.bpm` | float | e.g. `90.0` |
| **`metadata.duration`** | **int** | **Whole song, seconds** — use this on the card |
| `metadata.songName`,`songSubName`,`songAuthorName`,`levelAuthorName` | string | |
| `stats.plays`,`downloads`,`upvotes`,`downvotes` | int | Plays/downloads were 0 in every capture → **do not rely on them** |
| `stats.score` / `scoreOneDP` / `reviews` / `sentiment` | float / float / int / string | `score` is 0..1 (what `minRating` filters); `sentiment` e.g. `VERY_POSITIVE` (full enum **UNVERIFIED**) |
| `uploaded`,`createdAt`,`updatedAt`,`lastPublishedAt` | ISO-8601 | `uploaded` is the one you feed to `from`/`before`; the rest are version bookkeeping |
| `automapper` | bool | True for AI-generated maps |
| `declaredAi` | string | `None`, `Uploader`, `Admin`, `SageScore` observed. Prefer this over `automapper` for labelling *why* |
| `ranked`,`qualified` | bool | **ScoreSaber** status |
| `blRanked`,`blQualified` | bool | **BeatLeader** status |
| `curator` | object | Present **only** when curated; same shape as `uploader` |
| `curatedAt` | ISO-8601 | Present only when curated |
| `collaborators` | array | Present when there are collaborators |
| `nsfw` | bool | Present when flagged |
| `tags` | array | Tag **slugs**, e.g. `["challenge","speed"]` |
| `versions` | array | Usually one; newest first |

### 4.2 `versions[]`

`hash` (SHA-1, 40 hex — the game's song hash), `key` (sometimes absent on old maps), `state`
(`Published`), `createdAt`, `sageScore`, `downloadURL` (`https://r2cdn.beatsaver.com/<hash>.zip`),
`coverURL` (`https://cfcdn.beatsaver.com/<hash>.jpg`), `previewURL`
(`https://cfcdn.beatsaver.com/<hash>.mp3`), `diffs`, `testplays`, `feedback`, `scheduledAt`.
CDN paths are per-hash → immutable, safe to cache aggressively.

### 4.3 `versions[].diffs[]` — the per-difficulty record

| Field | Type | Notes |
|---|---|---|
| `characteristic` | enum | `Standard`, `OneSaber`, `NoArrows`, `90Degree`, `360Degree`, `Lightshow`, `Lawless`, `Legacy` |
| `difficulty` | enum | `Easy`, `Normal`, `Hard`, `Expert`, `ExpertPlus` |
| `nps` | float | **notes ÷ seconds** (verified 5062/136.764 = 37.013) |
| `notes`,`bombs`,`obstacles`,`events` | int | Raw counts |
| `seconds` | float | Playable length after the offset |
| `length` | float | **BEATS, not seconds** — 136.764 s × 175.046 BPM / 60 = 399.0 ✔ (2/2 maps). Semantics undocumented → derived |
| `njs` | float | Note jump speed |
| `offset` | float | Note jump offset |
| `maxScore` | int | |
| `stars` | float | **ScoreSaber** star rating; absent if not SS-ranked |
| `blStars` | float | **BeatLeader** star rating; absent if not BL-ranked |
| `chroma`,`me`,`ne`,`cinema`,`vivify` | bool | Per-difficulty mod usage (`ne` = Noodle Extensions) |
| `environment` | string | e.g. `DefaultEnvironment`, `NiceEnvironment` |
| `label` | string | Custom difficulty name |
| `paritySummary` | object | `{errors, warns, resets}` |

**Duration rules of thumb**: card → `metadata.duration`; "can I play this difficulty" → that
diff's `seconds`; NPS display → that diff's `nps`. Do not use `length`.

---

## 5. Playlist object

`GET /playlists/id/{id}/{page}` → `{playlist, maps}`; `maps` is the normal map array (20/page).
`playlist`: `playlistId` (int), `name`, `description`, `playlistImage`, `playlistImage512`,
`owner` (user object), `stats` (`totalMaps`, `mapperCount`, `totalDuration`, `minNps`, `maxNps`,
`upVotes`, `downVotes`, `avgScore`), `createdAt`, `updatedAt`, `songsChangedAt`, `downloadURL`,
`type` (`Public`…), plus `curator`/`curatedAt` on curated playlists.

---

## 6. Curated and ranked: what BeatSaver actually exposes (FR-007, FR-012)

| Concept | Where it lives | How to read it |
|---|---|---|
| **Curated / staff-picked** | **BeatSaver itself** | field `curator` + `curatedAt`; filter `curated=true`; sort `order=Curated`. BeastSaber's old curation is the same programme now, mirrored from BeatSaver. |
| **"Ranked" — ScoreSaber** | BeatSaver mirrors it | `ranked` / `qualified` on the map; `stars` per diff; filter `leaderboard=ScoreSaber`; range `minSsStars`/`maxSsStars` |
| **"Ranked" — BeatLeader** | BeatSaver mirrors it | `blRanked` / `blQualified`; `blStars` per diff; filter `leaderboard=BeatLeader`; `minBlStars`/`maxBlStars` |
| **"Ranked" — either** | `leaderboard=Ranked` | Server sets both flags (`RankedFilter.Ranked`); live check returned a `blRanked=true, ranked=false` map, so it really is an OR |
| Verified mapper | BeatSaver | `uploader.verifiedMapper`, filter `verified=true` |
| AI / automapper | BeatSaver | `automapper`, `declaredAi` |

There is **no single community-wide "ranked" standard**: two independent PP systems rate the same
maps differently (sample map `32693`: SS 6.51★ on Expert+, BL 8.35★ on one-saber Expert+). A
client must pick one to display or show both. **This doc's SC-001 example uses ScoreSaber.**
"Qualified" = approved but not yet ranked; it has no filter, only the field.

---

## 7. Alternative / complementary sources (FR-006, SC-003)

| Source | Hosts map files? | Public API? | Adds over BeatSaver | ToS for a third-party client | Verdict |
|---|---|---|---|---|---|
| **BeatSaver** | **Yes** — `.zip` on r2cdn/cfcdn | Yes, open, no key | Everything; the authoritative index | Forbids redistribution/commercial use, not reading | **Integrate — the only repository** |
| **ScoreSaber** | No — metadata + leaderboards; `bsid` = BeatSaver key | `https://scoresaber.com/api/openapi.json` — v2 `/api/v2/maps`: `page`, `limit`≤100, `status=UNRANKED\|RANKED\|QUALIFIED\|LOVED`, `minStars`/`maxStars`, `search`, `sortBy=createdAt\|latestRankedAt\|highestStars\|totalScores\|trending` | SS stars + per-difficulty leaderboards | Public read API, no auth in spec; rate limit UNVERIFIED | **Optional** — BeatSaver already has `stars`/`ranked` |
| **BeatLeader** | No — `downloadUrl` points at `cdn.beatsaver.com` | `https://api.beatleader.xyz/swagger/blapi/swagger.json`; `/maps` filters `stars_from/to`, `acc/pass/techrating_*`, `duration_from/to`, `date_from/to`, `mode`, `difficulty`, `mappers`, `playlistIds` | BL stars, acc/pass/tech ratings, leaderboards | Public API, no auth on reads | **Optional** — only for BL-specific ratings |
| **BeastSaber** | No — links out to `beatsaver.com/maps/<id>` | **No** — `wp-json` and `/api` 404 | Curation migrated **into BeatSaver**; only editorial left (Map of the Week, Beasties) | Not machine-readable | **Do not integrate** |
| **ModelSaber** | No (models, never maps) | Gone — `modelsaber.com` **301s to `beatmods.com`** | Sabers/platforms | n/a | **Irrelevant** |
| **AccSaber** | No | `api.accsaber.com` → **401** (auth required) | Accuracy-category rankings | Needs credentials | **Skip at v1** |
| **BeatSaver WebSocket** | n/a | `wss://ws.beatsaver.com/maps` | Live `MAP_UPDATE` feed | Same ToS | **Nice-to-have** ticker |

Bottom line: **BeatSaver alone is sufficient for a map browser.** ScoreSaber/BeatLeader are only
worth adding when you want scores or a leaderboard overlay, and both duplicate metadata BeatSaver
already carries.

---

## 8. The BeatSaver site's browsing hierarchy (FR-008)

From the live page and the frontend source (`modules/shared/.../index/main.kt`, `search.kt`,
`beatmaptable.kt`, `beatmapInfo.kt`, `rankedStatus.kt`).

**Top nav → "Find Maps"** shortcuts (each is just a URL):
`Curated` (`?curated=true&order=Curated`) · `From Verified Mappers` (`?verified=true`) ·
`Ranked Maps` (`?leaderboard=Ranked`) · `Top this week/month/year` (`order=Rating&from=…`) ·
`Newest` (`order=Latest`).

**Search bar** (free text + Search button) sits above everything; **filters** are one collapsed
dropdown whose button shows the *names of active filters*:
- **GENERAL**: AI (`All` / `Human` / `AI`), Ranked (`All` / `Ranked` / `BeatLeader` / `ScoreSaber`),
  Curated, Verified Mapper, From Mappers You Follow (only when signed in), Full Spread.
- **REQUIREMENTS**: Chroma, Noodle Extensions, Mapping Extensions, Cinema, Vivify.
- **Tags** (multi-select, grouped): *Style* — Tech, Dance, Speed, Balanced, Challenge, Accuracy,
  Fitness, Poodle; *Genre* — Swing, Nightcore, Folk & Acoustic, Kids & Family, Ambient,
  Funk & Disco, Jazz, Classical & Orchestral, Soul, Speedcore, Punk, R&B, Holiday, Vocaloid,
  J-Rock, Trance, Drum and Bass, Comedy & Meme, Instrumental, Hardcore, K-Pop, Indie, Techno,
  House, Video Game, TV & Film, Alternative, Dubstep, Metal, Anime, Hip Hop & Rap, J-Pop, Dance,
  Rock, Pop, Electronic, AI. (Alt-click excludes; these slugs are exactly the `tags` values.)
- **Characteristics** and **Environments** multi-selects.

**Always-visible controls**: NPS slider 0..16 (0.1 steps), date-range picker with presets
(Last 24h / week / month / 3 months / All), sort select + ascending toggle.

**Results**: infinite scroll, **20 items per page**, 2 cards per row on wide screens / 1 below
992 px, 155 px row height.

**Card contents** (in order): cover art with inline audio preview play button · thumbs up/down +
score to 1 dp · title + map key · uploader (with verified/curator marks) · difficulty icons ·
ranked/curated badges (ScoreSaber and BeatLeader shown separately, "Ranked" or "Qualified") ·
key · duration (`m:ss`) · BPM (2 dp) · download / one-click links. Card accent colour encodes
Ranked → Curated → Verified.

---

## 9. VR-specific guidance (FR-009)

**VERIFIED** (Meta Horizon OS design requirements, `developers.meta.com/vr/documentation/android-apps/design-requirements`,
and Godot docs). **Caveat on every dp/px figure below: that page is the requirement set for *2D
Android panel apps* on Horizon OS.** There is no public Meta number for world-space text on an
immersive panel, so treat these as a floor to exceed, not a target.
- Hit targets ≥ **48 × 48 dp**, ≥ **60 × 60 dp** for primary controls, with hit slop. In a
  world-space panel, size the ray-cast collider to the same physical area, not to the text bounds.
- Text: ≥ **14 px** readable, ≥ **18 px** comfortable; contrast ≥ **4.5:1** for body text, ≥ 3:1
  for headings; avoid pure `#FFFFFF` on pure `#000000` (use `#DADADA` or darker backgrounds).
- **No system back button** — the panel must own its back/close affordance.
- Godot `HTTPRequest` on Android requires the `INTERNET` export permission
  (`export_presets.cfg` here already has `permissions/internet=true`) and must not be reused for
  concurrent requests; set `timeout` 1–10 s for API calls, 0 for downloads.
- Prefer a font with a high x-height and large counters (Inter is Meta's recommendation).

**UNVERIFIED — text entry in an immersive session.** `DisplayServer.virtual_keyboard_show()` exists
and is implemented on Android (Godot class reference, `virtual_keyboard_*` family), but whether
the Android IME renders on top of an OpenXR immersive session on Quest 3 was **not** verified here,
and normal expectation is that it does not. Do **not** plan around it. The realistic options are:
reuse this project's in-world keyboard — `OQ_Toolkit/OQ_UI2D/OQ_UI2DKeyboard.tscn` (plus
`controls/VirtualKeyboard.tscn`), already used by the highscore/settings screens — or adopt Meta's
virtual keyboard / system keyboard extension through the Godot OpenXR vendor plugin (not currently
present: `addons/` contains only `stopwatch`). Search entry can also be avoided entirely by
browsing presets first.

**PLAUSIBLE** (inference, not from a primary spec):
- Panel at 1.5–2.0 m, ~1.6–2.2 m wide, 4–6 rows visible: larger panels force head movement and
  lose the peripheral scan that makes a list readable.
- **Pagination beats infinite scroll in VR.** Infinite scroll is invisible below the fold; a VR
  user cannot see "there is more" the way a mouse user can. Use explicit pages of 20 with
  "Page 2 of 51" / "Load 20 more", keep scroll position, and show the total (`info.total`).
  Caveat: with client-side filtering (§3.3) one server page is not one screen — page the *API*
  until the display page is full and report the filtered count, not `info.total`.
- Thumbstick: continuous scroll snapped to row height, one row per notch, velocity capped so a
  flick cannot throw the list past the viewport.
- One accent colour + one badge row per card; demote BPM/NPS/key to a details page, and load
  covers lazily, cached by version hash forever (the URL is per-hash and immutable).

---

## 10. Godot implementation notes

```gdscript
var q := "leaderboard=ScoreSaber&minDuration=120&maxDuration=300&minNps=6&maxNps=12&order=Latest&pageSize=20"
var url := "https://api.beatsaver.com/search/text/%d?%s" % [page, q]
var req := HTTPRequest.new(); add_child(req)
req.timeout = 8.0            # seconds; 0 = never (use for .zip downloads)
req.request_completed.connect(_on_done)
req.request(url, ["User-Agent: OpenSaberQ3/0.2 (+your-contact)"])
```
- `accept_gzip` is on by default — a 20-map search page measured ~82 KB raw; compression matters
  on a 100-item page (~430 KB).
- Parse with `JSON.new().parse(body.get_string_from_utf8())`; check `result == HTTPRequest.RESULT_SUCCESS`
  **and** `response_code`.
- `q` must be `String.uri_encode()`d; tags contain `|` and `!`.
- Handle `docs: []` (end of list) and HTTP 500 (bad enum) distinctly from 404 (unknown id).
- `{"redirect": "..."}` at the top level of a search response means the user pasted a key — jump
  to that map.
- One `HTTPRequest` node per in-flight request; a queue beats `use_threads` for 1–2 requests/s.

**Existing panel in this repo** (`game/ui/BeatSaverPanel/BeatSaverPanel.gd`) is built on the old
surface and should be evolved, not replaced: `:133` `beatsaver.com/api/maps/{list}/{page}` →
`/maps/latest` (cursor) or `/search/text/{page}?order=…`; `:137`
`api/search/text/{page}?q=…&sortOrder=Relevance&automapper=true` → `/search/text/{page}` with
`order=`, keeping `automapper=true` only if AI maps should appear; `:141`
`api/maps/uploader/{id}/{page}` → unchanged (20/page). It runs four `HTTPRequest` nodes with
`use_threads = true` (`:43-46`, `:72-75`) — fine for downloads, unnecessary for browse JSON.

---

## 11. Gaps and UNVERIFIED items

| Item | Status |
|---|---|
| Rate limits / 429 behaviour | **UNVERIFIED** — no documented figure, no headers, none observed |
| `info.duration` unit | **UNVERIFIED** (looks like seconds) |
| `diff.length` = beats | Derived from two maps (exact match); not documented |
| `stats.sentiment` enum | Partial — `VERY_POSITIVE` seen |
| Full `environments` enum | Not enumerated here; list lives in `EBeatsaberEnvironment` (source) |
| Solr `nps` field vs per-diff | Behaviour verified empirically (any diff in band), internals not |
| `maps/uploader` page size | Observed fixed at 20 |
| BeastSaber ever shipping an API | No evidence either way; `wp-json` disabled |
| ScoreSaber/BeatLeader/AccSaber rate limits | UNVERIFIED |

## Sources

- `https://api.beatsaver.com/docs/swagger.json` (fetched; 63 KB, Swagger 2.0)
- Live responses on 2026-11-02 (samples saved in `samples/`)
- `https://github.com/beatmaps-io/beatsaver-main` — `src/jvmMain/kotlin/io/beatmaps/api/search.kt`,
  `.../search/SearchParams.kt`, `.../search/SolrSearchParams.kt`,
  `modules/shared/src/jsMain/kotlin/io/beatmaps/shared/search/*.kt`,
  `modules/shared/src/jsMain/kotlin/io/beatmaps/index/*.kt`
- `https://beatsaver.com/` (nav + filter UI), `https://beatsaver.com/policy/tos`
- `https://scoresaber.com/api/openapi.json`, live `/api/v2/maps`
- `https://api.beatleader.xyz/swagger/blapi/swagger.json`, live `/maps`
- `https://bsaber.com/` (links to beatsaver.com; `wp-json` 404)
- `https://modelsaber.com/` → 301 → `https://beatmods.com/`
- `https://api.accsaber.com/maps` → 401
- `https://bsmg.wiki/mapping` ("BeatSaver is the public repository…"; BeastSaber mirrors the 8
  most recently curated maps)
- `https://developers.meta.com/vr/documentation/android-apps/design-requirements`
- `https://docs.godotengine.org/en/stable/classes/class_httprequest.html`,
  `.../class_displayserver.html`
