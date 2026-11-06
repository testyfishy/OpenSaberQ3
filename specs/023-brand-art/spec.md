# Feature Specification: brand artwork and the itch.io launch plan

**Feature Branch**: `023-brand-art`

**Created**: 2026-11-06

**Status**: In progress (G0 approved with changes)

**Input**: Player: "Can we develop a better logo for this app and also a better banner. Use AI and
make it clear that it was made with AI - can use the advisor for creation too. Then plan out
itch.io push."

## Intent

Replace the magnifying-glass icon and the plain title-card cover with an original logo system and
banner made for this game, disclose plainly that the artwork is AI-generated, apply it to the app
and the public pages, and produce a complete itch.io launch plan. Publishing to itch is a separate
go/no-go.

## Constraints found first

- **There is no image-generation model available in this environment** (`opencode.models type=image`
  returns none) and no image-generation tool. The AI-made artwork is therefore original **vector
  artwork authored by the AI assistant** (this session), with the SVG source and the design brief
  committed. That is what the disclosure says; it does not claim a diffusion model or a human
  designer.
- The app icon paths are `icon.png`, `icon_192.png`, `icon_adaptive_fg_432.png`,
  `icon_adaptive_bg_432.png`; the in-menu logo is `game/data/beepsaber_logo.png`; the public hero is
  `docs/images/cover.png`.
- The current icon is a cyan magnifying glass with an orange saber handle. It reads as "search",
  not as the game.
- Godot can rasterise SVG (`Image.load_svg_from_string`), so the masters can be SVG and every PNG
  export can be regenerated.

## Requirements

- **FR-001**: A new **logo mark** MUST be original, use the project palette (deep navy, cyan,
  orange, note red/blue accents), avoid Beat Saber's name/logo/branding and any third-party asset,
  and stay legible at 32-48 px and on dark and light backgrounds.
- **FR-002**: A **wordmark lockup** MUST pair the mark with "OpenSaberQ3" in a typeface already
  available to the project (Roboto Medium or similar), in horizontal and stacked forms.
- **FR-003**: The **app icon set** MUST be replaced from the new master at the existing sizes and
  paths (`icon.png`, `icon_192.png`, `icon_adaptive_fg_432.png`, `icon_adaptive_bg_432.png`,
  `game/data/beepsaber_logo.png`) with no layout regressions in the Android export.
- **FR-004**: A **banner** MUST be produced in two compositions from the same art system:
  `docs/images/banner.png` at **1280x640** for GitHub/README/itch header, and
  `docs/images/itch-cover.png` at **630x500** for the itch cover. Text MUST be legible at the
  intended display size and keep a safe margin.
- **FR-005**: The artwork MUST have a repeatable pipeline: SVG masters under `docs/brand/`, a
  `tools/brand/render_brand` script that exports every PNG size, and a short `docs/brand.md`
  describing the design, palette and how to re-render.
- **FR-006**: The AI provenance MUST be explicit in at least: the README (near the credits), the
  `ATTRIBUTION.md` artwork section, `docs/brand.md`, and the itch page copy. Wording MUST say the
  logo/icon/banner are **AI-generated vector artwork** made for the project, with no stock or
  third-party assets.
- **FR-007**: An **itch.io launch plan** MUST exist in `docs/itch-push.md` (and the existing
  `docs/itch-page.md` MUST be refreshed to the v0.6 state): project fields, tags, pricing, the full
  page copy in the current voice, the AI disclosure, asset checklist (cover, banner, screenshots,
  icon), build/upload steps, known issues, and a go/no-go list. It MUST state that publishing needs
  the owner's account and explicit confirmation.
- **FR-008**: The artwork files MUST land in the repo now; the **next APK (0.6.1)** carries the new
  icon and menu logo. Do not re-cut or re-upload the v0.6.0 release in this slice.
- **FR-009**: The advisor MUST run a G0 design-direction review (as brand/design lead) and a G4
  visual review of the rendered assets. Verdicts and chosen direction go in the Consultation Log.
- **FR-010**: No game behaviour may change. The logo replacement must not break the menu or the
  Android build; run `--import`, a desktop menu render, and the usual link/asset checks.
- **FR-011**: The itch plan MUST include a trademark and licence checklist covering the page
  title, tags, artwork, screenshots and every song bundled in the APK. The current APK ships the
  upstream TheFatRat demo track; the plan MUST block the upload until its licence is confirmed or
  the track is removed from the itch build.

## Success criteria

- **SC-001**: The master SVGs and every PNG export exist; a contact sheet shows the icon legible at
  512, 192 and 48 px.
- **SC-002**: The banner and itch cover render with unclipped text and safe margins; both are under
  1 MB.
- **SC-003**: The app icon files are replaced, `godot --headless --import` passes, and a desktop
  menu screenshot shows the new mark.
- **SC-004**: The AI disclosure appears in the README, ATTRIBUTION, `docs/brand.md` and the itch
  copy.
- **SC-005**: `docs/itch-push.md` is complete enough that the owner can fill in the account fields
  and upload without writing new copy; it names the build, version and go/no-go items.
- **SC-006**: The advisor approves the final art at G4.
- **SC-007**: The repo changes are pushed; no release/tag/APK is altered.
- **SC-008**: The contact sheet includes 512/192/48/32 px and circle/squircle adaptive masks; the
  SVG sources contain no filters or text elements; `docs/itch-push.md` carries the trademark and
  song-licence gate.

## Publication evidence (2026-11-06)

- Commit `6454c44` pushed to `origin/godot-4-port`; `git ls-remote` matches local HEAD.
- The rendered README uses `docs/images/banner.png`; the banner and the brand contact sheet return
  HTTP 200 from `raw.githubusercontent.com` on `godot-4-port`. Link check: 0 broken relative links
  across README, performance, changelog, the v0.6 report, brand and both itch pages.
- `icon.png` (512), `icon_192.png`, the adaptive pair (432), `game/data/beepsaber_logo.png`, the
  banner, itch cover and 512 logo are replaced; `godot --headless --import` and a desktop menu
  render pass, showing the new mark in the menu's default cover and boot splash.
- No APK, tag or GitHub release changed. 0.6.1 carries the new icon/menu logo.
- The itch plan blocks the upload on the unlicensed TheFatRat demo track in the current build and
  on real headset screenshots; no itch project was created or published.

## Out of scope

- Using an external image-generation service (no model/tool is available), and any claim that one
  was used.
- Publishing the itch page (plan only; no account credentials in this session).
- Rebuilding or re-uploading v0.6.0, and the 0.6.1 build itself.
- Renaming the app or changing the package id.

## Open questions

None. The only judgement call is the art direction, which the G0 advisor review decides.

## Consultation Log

| Gate | Asked | Verdict | Action taken |
|---|---|---|---|
| G0 | Brand direction, logo concept, banner/cover composition, AI disclosure, APK timing | GO WITH CHANGES: chosen direction A, a rounded note cube cut on a 35° diagonal with red/blue halves, a cyan blade and orange hilt on a navy tile; banner left mark 340 px + name/tagline/chips, no numbers, no "Beat-saber style"; itch cover 630x500 with the mark above the name; name the AI tool and show the SVG source; assets now, new icon/menu logo in 0.6.1, 0.6.0 untouched | Implemented as vector SVG + Godot rasterisation; contact sheet, banner, cover, wordmarks and the itch plan produced |
