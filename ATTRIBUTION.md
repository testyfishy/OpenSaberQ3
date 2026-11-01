# Attribution

This fork exists because of work other people did and gave away. Their terms travel with the
code, and this file is the record of them.

## Code lineage (MIT)

| Project | Author | License | Role |
|---|---|---|---|
| Godot Oculus Quest Toolkit | Holger Dammertz (NeoSpark314) | MIT | original VR toolkit + demo that became BeepSaber |
| BeepSaber | Holger Dammertz (NeoSpark314) | MIT | standalone Godot game, `OQ_Toolkit/` in this tree |
| BeepSaber `godot-4-port` ("Open Saber", 0.5.0) | Leandro Dreamer (leandrodreamer) | MIT | **direct upstream of this fork** |
| Godot Engine | Godot contributors | MIT | engine, export templates |

The MIT permission notice in `LICENSE` is retained unmodified. Forking, renaming, and
redistribution are permitted by that licence provided the notice is kept — which it is.

## Creative assets

| Asset | Author | License | Notes |
|---|---|---|---|
| "Time Lapse" demo track | TheFatRat | per upstream `LICENSE`/credits | bundled demo song, not part of the engine work |
| BeepSaber logo, UI art, saber models | upstream authors | MIT unless noted | inherited; see `LICENSE` |
| Nightsky skybox | ESO / S. Brunier | **CC-BY-4.0** | `https://www.eso.org/public/images/eso0932a/` — attribution required. Present in `arpruss/OpenSaberPlus`, **not** in this fork's base. If cherry-picked, this credit must ship with it |

If an asset's provenance cannot be established, it does not ship. See spec FR-029.

## Explicitly excluded

- No asset, audio, font, shader, level, or UI element is extracted from **Beat Saber** or any
  other commercial title.
- No commercial binary was decompiled to produce any change in this repository.
- The name "Beat Saber" is not used in the app name, icon, store listing, or repo description,
  and this project claims no affiliation with Beat Games or Meta (spec FR-028).

## Upstream credit on every release

Releases link to `leandrodreamer/BeepSaber` and `NeoSpark314/BeepSaber` and state which commit
this fork descends from. See `UPSTREAM.md`.
