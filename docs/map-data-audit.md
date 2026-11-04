# What BeatSaver maps actually contain, and what we ignore

**Audit date:** 2026-11-03. **Sample:** 43 downloaded maps (26 in the structured survey, 29 parsed
for event types, 17 in a per-field pass), pulled from the BeatSaver API: top-rated, curated,
verified and newest uploads. Each map's `Info.dat` and every difficulty file were parsed offline.

**Limitation, stated up front:** the "top rated" sort is dominated by 2020–2022 v2 maps and the
"latest" feed by auto-generated maps, so these percentages describe *popular* maps, not the whole
catalogue. Modern-only features are under-represented; "0 in sample" means "not seen here", not
"does not exist". Map content is data only; nothing here executes or follows it.

## Coverage, by field

| Map field | Present in | What the game does today |
|---|---|---|
| `_environmentName` / `environmentNames` | **25/26 (96%)** | **Parsed and thrown away.** Every map gets the same room. |
| `basicBeatmapEvents` / `_events` (light show) | 22/26 (84%), median **5,134**, max **76,731** | Played: `Playing.gd` pops the stack, `event_driver.gd` handles types 0–4, 8, 9, 12, 13 |
| `colorSchemes` | 2/43 | Read; first scheme only, saber colours only |
| `environmentColor0/1` (+Boost), `obstaclesColor` | 2/43 (~5%) | **Ignored** |
| Light boost — v2 event type 5 / v3 `colorBoostBeatmapEvents` | **4/29 (14%)** / 1/26 | **Ignored** |
| `lightColorEventBoxGroups` etc. | 0/26 | **Ignored** (not parsed) |
| BPM change — v2 event type 100 (legacy 10) / v3 `bpmEvents` | **4/29 (14%)** (2 + 2) | **Ignored** — one BPM for the whole song |
| Lane rotation — v2 event types 14/15 | **1/29 (3%)**, 186 events in that map | **Ignored** |
| Fake notes (`customData.fake`, `fakeColorNotes`) | 3/43 (7%), up to **3,422 per map** | **Ignored** — spawned and scored as real |
| `rotationEvents` (360°/Track maps) | 0/43 | **Ignored** |
| `waypoints` | 0/26 | Ignored (spectator camera) |
| Modded `customEvents` (Chroma/Noodle/Vivify) | **11/26 (42%)** | **Ignored** |
| Modded `environment` animation data | **12/26 (46%)** | **Ignored** |
| Modded `materials` | 2/26 (7%) | **Ignored** |
| `_assetBundle` (custom Unity assets) | **5/26 (19%)** | Not feasible without Unity bundle support |
| Arcs / chains / bombs | 19% / 11% / 7% in this old-skewed sample | Fully supported |
| v4 `lightshowDataFilename` | v4 maps only | Loaded and converted to v3 events |

Environment names seen: Billie, Panic, BTS, Rocket, Default, BigMirror, Nice, Timbaland, FitBeat,
Gaga, Triangle, and one map with none.

## Basic event types: what they are, and what we do

The numbering matters; the old constant name in `EventInfo.gd` is misleading (`TYPE_FLOOR_LIGHTS`
is really centre lights).

| Type | Meaning | Ours |
|---|---|---|
| 0 | Back lasers | handled |
| 1 | Ring lights | handled |
| 2 | Left lasers | handled |
| 3 | Right lasers | handled |
| 4 | **Centre lights** | handled |
| 5 | Light boost (v3 uses `colorBoostBeatmapEvents`) | **ignored** |
| 6/7 | Extra left/right lights | **ignored** (0 in sample) |
| 8 | Ring spin | handled |
| 9 | Ring zoom | handled |
| 10/100 | BPM change | **ignored** |
| 12/13 | Left/right laser speed | handled |
| 14/15 | Early/late lane rotation | **ignored** |

## The findings that matter

1. **The map says which room it was designed for, 96% of the time, and we ignore it.** This is
   the single largest unused signal, and it is what the player noticed: every song looks the same.
2. **The mapper-authored palette is rare (~5%).** Beat Saber's environments supply the colours;
   `environmentColor0/1` only appears when a mapper overrides them. "Colour-code the ambience to
   the track" therefore means: use the environment's *default* scheme for that environment name,
   then the map's note colours as the accent — and only use `environmentColor0/1` when present.
3. **The authored light show is the norm (84%) and is already played**, but boost (14% of maps),
   lane rotation (3%) and extra light groups are dropped, so some authored intent never shows.
4. **About 14% of maps change BPM mid-song** (2 via legacy type 100, 2 via v3 `bpmEvents`). We use
   one BPM for the whole map, so notes drift against the audio after the change. Correctness bug.
5. **Fake notes (7% of maps, thousands per map when present)** are spawned and scored as real
   notes. That is a scoring bug, not a visual one.
6. **The "different vibe" of top-rated maps mostly comes from mods we do not implement** —
   Chroma/Noodle environment and material animation (46% of the curated sample) and custom asset
   bundles (19%). Partial support should be scoped separately.

## Implementation plan (corrected after the G1 consult)

Order: **SC-001 baseline first** (the headset is on USB, so measurement is cheap again), then the
correctness work, then the presentation work. Correctness items cost no GPU.

### Phase A — correctness

- **A1. BPM changes.** Parse all three sources: v3 `bpmEvents`, v4 `AudioData` bpm data, and v2
  `_events` type 100 (legacy 10). Introduce one `beat_to_seconds()` used by notes, obstacles,
  arcs/chains, light events, the bot, the bench clock and the practice seek. Obstacle end time is
  `b2s(start+dur) - b2s(start)`. Note-jump duration keeps the Info BPM (believed constant in Beat
  Saber; verify). Hit windows stay in seconds. Acceptance: a synthetic two-segment map keeps
  arrival error under 20 ms on both sides of the change, and bot accuracy is unchanged.
- **A2. Fake notes.** Hide fake notes, fake bombs and fake obstacles by default, and exclude them
  from note counts, max score, combo and the bot. Not ghosts: they are positioned by Noodle
  motion we do not implement, so showing them statically would mislead.
- **A3. Lane rotation (types 14/15).** One map in the sample uses it; do it after A1/A2 or mark
  those maps unsupported. 360°/`rotationEvents` maps are explicitly marked unsupported in the
  browser instead of being attempted.

### Phase B — the map's own room

- **B1. Environment default schemes.** Map each stock `environmentName` to its *default* colour
  scheme and a small room profile (void/gradient, floor tint, fog, which `event_driver` groups
  exist, light intensity). We cannot ship Beat Saber's art; the UI says so plainly:
  "Colours: <environment> · Room: OpenSaber". No fidelity claims.
- **B2. Track accents.** Palette = map `environmentColor0/1` when present, else the environment
  default scheme, with the map's note colours as the accent. `obstaclesColor` tints walls. The
  player's colour override wins; note lane colours are never changed.
- **B3. Boost.** v2 event type 5 and v3 `colorBoostBeatmapEvents` switch to the boost colour pair.
- Setting: **Environment: Map / Classic** (Classic is exactly today's look).

### Phase C — light system completeness

- **C1. Event types 6/7** (and any future type we can map to an existing light group).
- ~~C2. Box-group lighting~~ — **cut from v0.3** (G1), and the re-measurement supports that:
  a second sample of 2024+ curated/verified maps (7 maps, all v2.1 Info with v3 difficulties)
  again found **0/7** using `lightColorEventBoxGroups`, `lightRotationEventBoxGroups`,
  `lightTranslationEventBoxGroups`, boost events or rotation events. Across both samples that is
  **0/33**. Official-editor-style box-group shows exist, but they are not what the popular
  library is made of. Revisit in v0.4 only if that ratio changes.
- **C3. `basicEventTypesWithKeywords`** — v0.4.

### Phase D — modded maps (separate project)

- Chroma/Noodle `customEvents`, `environment` and `materials`; `_pointDefinitions`.
- `_assetBundle` custom Unity assets: not feasible in Godot.

## What losing Unity asset bundles actually costs

Five of the 26 sampled maps (19%) ship `_assetBundle` entries: platform-keyed Unity bundles
(`_windows2019`, `_windows2021`, `_android2021`). They contain the map's custom *environment*
assets - meshes, textures, materials, sometimes custom note or saber models.

What is inside them is cosmetic. Notes, walls, arcs, chains, timing, the light show and the
scoring rules all live in the JSON, which we already read. So the gameplay of an asset-bundle map
is unaffected; what is missing is the author's custom room, and it will render as our themed
environment for that `environmentName` instead (B1/B2), with the map's own light show and
palette on top.

How we would know the difference: load one of those maps in Beat Saber and in ours side by side.
The notes, timing and light cues match; the scenery differs. That is a visual-fidelity gap, not
a playability one. Shipping converted Beat Saber environment art would also be a copyright
problem, and converting author bundles needs each author's permission, so the honest path is our
own lookalike rooms keyed by environment name.

## What this means for "per-map ambience"

Replace "randomise the environment" with "**read the environment the map declares, and give it
its own default palette and room**". The data is present in 96% of maps; randomisation was a
workaround for data we already had.
