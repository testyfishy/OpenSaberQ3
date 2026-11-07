# Map compatibility policy

OpenSaber's goal is to play every BeatSaver map's **gameplay** faithfully. This page defines what
that means, how a map is classified, and what is still missing. It is a living document; the
measured rate is filled in by the corpus harness described below.

## Tiers

| Badge | Meaning |
|---|---|
| **Supported** | The map loads, and every scorable note and wall is at the right time and place. Nothing gameplay-changing is missing. |
| **Partial** | The map loads and is playable, but a gameplay feature is missing (for example 360° rotation, Noodle note movement, or per-object note speed). The pause menu names what is missing. |
| **Visuals limited** | Gameplay is correct; lighting, environment or bundled effects are skipped. |

Missing colours, lighting or environment are warnings, never a downgrade to Partial. Missing
**movement, rotation or placement** is Partial, because it changes where or when you play.

## Classification

The badge is computed from:

1. The map's own `_requirements` / `_suggestions` in `Info.dat` `customData` (the mapper's declared
   needs).
2. Features detected in the difficulty files: precision positions, rotation events, Noodle keys,
   Chroma events, v4 box groups, asset bundles.
3. The loader's own support table (`game/scripts/MapSupport.gd`).

A map that requires an unimplemented feature is Partial even if it happens to load; a map that
merely suggests one is Supported with a warning.

## Support matrix (0.6.4)

| Feature | State |
|---|---|
| v2, v3, v4 beatmaps; v4 lightshow | Supported |
| Notes, bombs, walls, arcs, chains, BPM changes | Supported |
| Fake notes / fake walls | Filtered as decorative, not scored |
| Chroma per-note colour | Supported |
| Basic light events | Supported |
| Noodle `_coordinates` note position | Partial |
| Mapping Extensions precision (encoded positions, float walls) | **Not yet** — parsed as ints, positions snap to the grid |
| 90° / 360° rotation events | **Not yet** — parsed, not applied |
| Noodle rotation, scale, animation tracks, per-object speed/offset | **Not yet** |
| Chroma light/environment events | **Not yet** |
| v4 box-group lighting / VFX event boxes | **Not yet** |
| Vivify, Cinema, Heck, custom environments (Unity asset bundles) | **Not yet**; maps load as Visuals limited |

## Measurement

The corpus harness loads a sample of BeatSaver maps headless through the real loader and records
the tier and the missing features per map. The sample covers:

- top-rated maps (the ones players actually play),
- latest uploads (the formats being produced now),
- 90°/360°, OneSaber and Lightshow characteristics.

The published number is the share of the sample that reaches **Supported**, with Partial and
Visuals-limited counts beside it. Only the harness result counts; hand-picked examples do not.

## Roadmap for 0.7

1. Corpus harness and classifier; publish the measured rate.
2. Fix silent corruption: Mapping Extensions precision, enforce `_requirements` badges, apply
   per-object note speed/offset.
3. 90°/360° lane rotation.
4. Noodle static transforms (position, rotation, scale), then animation tracks.
5. Chroma light/environment events, then v4 box-group lighting.
6. Unity asset bundles only where an open-source parser is practical; otherwise Visuals limited.

Nothing in this plan requires a closed-source SDK, asset or service. Map content stays the
mapper's; the engine only reads the formats.

## Notes

- Quest Beat Saber can play Noodle/Chroma/Mapping Extensions through community mods (BMBF,
  QuestPatcher), and Vivify has Android bundle variants. "Beat Saber cannot either" is not a valid
  excuse and is not used here.
- A map that loads but requires an unimplemented feature is reported, never silently half-played.
