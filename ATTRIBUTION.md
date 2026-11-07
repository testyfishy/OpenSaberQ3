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
| "Time Lapse" demo track (removed in 0.6.1) | TheFatRat | **not distributed** | bundled through 0.6.0 by upstream; no licence grant is recorded here. Removed from the repository, the 0.6.1 APK and matching existing libraries. Do not reintroduce without permission. |
| BeepSaber UI art and saber models (the old BeepSaber logo/icon is replaced by the artwork below) | upstream authors | MIT unless noted | inherited; see `LICENSE` |
| Logo, app icon, banner and wordmarks | AI-generated vector artwork created with AI assistants (DeepSeek V4 Flash wrote the SVG; Claude Opus 5.5 wrote the design brief), via OpenCode; reviewed by the project owner | MIT | original SVG in `docs/brand/`; no image-generation model, stock image or third-party artwork; text set in Roboto and converted to paths |
| Roboto Medium | Google | **Apache-2.0** | wordmark typeface, `OQ_Toolkit/OQ_UI2D/theme/Roboto-Medium.ttf`; only glyph paths are embedded in the brand SVGs |
| Nightsky skybox | ESO / S. Brunier | **CC-BY-4.0** | `https://www.eso.org/public/images/eso0932a/` — attribution required. Present in `arpruss/OpenSaberPlus`, **not** in this fork's base. If cherry-picked, this credit must ship with it |
| Hit-feedback one-shots — `game/data/hits/{soft,hard,dull}_0{1,2,3}.wav`, `accent_01.wav` (9 files) | generated for this fork by `tools/audio/gen_hitsounds.py` | **MIT** (same as this repository) | No third-party samples, so no attribution obligation. Synthesised from scratch (deterministic seeds); regenerating produces byte-identical files. Provenance: created 2026-11-01 for `specs/002-hit-audio-research` |

Retired hit stream: `game/data/beepcube_cut.ogg` had no provenance record (violating the rule
below), so it was removed 2026-11-01 and replaced by the generated one-shots above.
`game/sabers/particles/sword_clash.{8a,10}.ogg` are inherited from upstream BeepSaber and are
still referenced by the particle saber's animation track; no upstream provenance record exists
for them either — they are no longer used for hit feedback.

The current logo, app icon, banner and wordmarks are AI-generated vector artwork: an AI coding assistant (DeepSeek V4 Flash) wrote the SVG from a design brief by Claude Opus 5.5 (Anthropic), both via OpenCode. The sources, the render script and the provenance note are in `docs/brand/` and `docs/brand.md`. They contain no third-party images.

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
