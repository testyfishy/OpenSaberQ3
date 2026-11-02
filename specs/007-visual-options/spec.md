# Feature Specification: Eleven advisor visual improvements, each behind its own persisted setting

**Feature Branch**: `007-visual-options`

**Created**: 2026-11-02

**Status**: Draft

**Input**: User description: "Eleven advisor visual improvements, each behind its own persisted setting"

## Context

`specs/001-quest3-saber-perf` established the analytic floor light (FR-045), the halo
shells (FR-046), the mirrored copies (FR-047), bloom (FR-048) and the rule that every
visual addition is a switchable setting gated on measurement (FR-049). This sheet covers
the second round of visual work: eleven items, each with its own persisted setting, and
two items that remove or bound cost rather than add it.

Two of the eleven are already implemented and are therefore *verified* here rather than
re-implemented: the additive saber trail ribbon (item 7) exists as `Settings.saber_tail`
(`game/sabers/default/tail.tscn`: `blend_mode = 1` additive, `shading_mode = 2` unshaded,
`depth_draw_mode = 2` never, age-driven UV gradient in `tail.gd`), and the foveation row
(item 10) exists and calls a method the engine really has
(`ClassDB` probe: `OpenXRInterface.is_foveation_supported/set_foveation_level/
get_foveation_level/set_foveation_dynamic`). Duplicating either would add draws for no
gain, so both are verified, documented and (for foveation) made real from the panel.

## Scoped change

Symptom: the game reads flat next to modern VR titles — notes have no glow of their own
(the glow is a second shell mesh), a cut has no light burst, map colours only tint whole
note families, the floor is a plain quad, the background is a single panorama, walls are
opaque noise panels and debris is unbounded. Cost: one full-viewport render per frame in
`OQ_UI2DLabel.tscn` (`render_target_update_mode = 4`) that the label's own script
immediately downgrades, so any frame before `_ready()` pays for it.

Root cause of the visual gap: every effect that would fix it was assumed to need a pass.
Round 1 showed the cheap forms (analytic light, emission in an existing pass). This round
applies the same rule to the remaining items.

Blast radius: note/chain-link material and scene, floor shader + script, event driver,
saber script, wall material selection, particle cap, settings panel, project settings.
No scoring, hit-detection, audio or benchmark code is touched.

## User Scenarios & Testing

### User Story 1 - Notes glow without a second draw (P1)

A player sees the note's edges emit light. There is no halo shell mesh: the glow is inside
the note's own shader, so the note costs the same draw it did before and the separate
halo material (one per note) is gone.

**Independent Test**: `BeepCube.tscn` has no `Halo` node; `BeepCube.gdshader` adds an
edge-masked EMISSION term; the note material has no `resource_local_to_scene`, so live
notes share one material.

### User Story 2 - A cut feels solid (P1)

On a cut the floor lights up briefly (≈80 ms) where the blade met the note. The decay is
a float in `Floor._process`; no node, tween or per-frame allocation is created.

**Independent Test**: cut a note with `hit_flash` on: a burst appears at the cut's floor
position and fades; with it off nothing appears.

### User Story 3 - The map's own colours reach the notes (P2)

A map that colours individual notes (`_customData._color`) shows those colours; maps that
do not keep the current left/right colours, which already come from the map's colour
scheme (`_colorLeft`/`_envColorLeft*`) or from settings when the map has none.

**Independent Test**: load a map with a per-note `_color`; that note is tinted, its
neighbours are not, and no new material resource is created per note.

### User Story 4 - The room reacts to the map (P2)

Map light events tint the floor streak (and the saber halos) through global shader
parameters, so an event that lights the level red also tints the light the blades throw.

**Independent Test**: a map with light events; the floor streak's tint follows the event
colour and never goes fully black (a saber always lights the floor).

### User Story 5 - The floor reads as a floor (P3)

A faint anti-aliased grid (`fract` + `fwidth`) stays clean at distance and costs one extra
`fwidth` per floor pixel, in the pass the floor already runs.

### User Story 6 - A static gradient sky (P3)

A `shader_type sky` gradient replaces the panorama when the setting is on; it has no
texture fetch and `radiance_size` is the smallest the engine offers (32), so the ambient
cubemap is generated once and is cheaper to filter.

### User Story 7 - Optional, measurable extras (P4, default OFF)

A fresnel wall material that fades when the camera is inside it, a hard debris-particle
cap, and a foveation row that actually applies and reports its level.

### Edge Cases

- A map with no colour scheme: `Map.color_left/right` fall back to `Settings.color_*`
  (existing behaviour) and every new tint follows the same value.
- `disable_map_color` on: per-note and scheme colours are both suppressed; settings win.
- Floor light, grid, flash and mirror all off: the floor goes back to the untouched
  `StandardMaterial3D` (no shader at all).
- A blade held below the floor: the existing guard keeps the streak off; the flash is
  clamped to the floor plane and cannot produce a NaN.
- A wall the player is standing inside: the fresnel variant fades to zero within 0.6 m of
  the camera instead of filling the screen with additive overdraw.
- Foveation on a runtime without `XR_FB_foveation`: the row stays hidden (existing code).

## Requirements

### Functional Requirements

- **FR-001**: The note MUST carry the neon edge glow as EMISSION in `BeepCube.gdshader`
  using the same box-edge mask as `neon_halo.gdshader`, and the note halo shell (node,
  material, script reference and `note_halo` setting) MUST be removed.
- **FR-002**: The per-note varying uniforms (`color`, `is_dot`, `is_chain_head`, box
  half-extent) MUST become `instance uniform`s and the note `ShaderMaterial` MUST NOT be
  `resource_local_to_scene`, so live notes share one material.
- **FR-003**: A cut MUST raise a short (≈80 ms) emissive burst on the floor at the cut
  point, driven by a uniform, with no node creation and no per-frame allocation.
- **FR-004**: A note with a colour in its own `_customData` MUST use it; otherwise the
  map's scheme colour, otherwise the setting. This MUST be applied through an instance
  uniform, never a unique material.
- **FR-005**: Map light-event colours MUST reach the floor streak and the saber halos
  through global shader parameters, clamped so blade light never disappears.
- **FR-006**: The floor MUST offer a faint `fract`/`fwidth` grid, clean at distance.
- **FR-007**: A static gradient sky MUST be available, updating only on load/setting
  change, with the smallest radiance size.
- **FR-008**: The additive saber trail ribbon MUST exist and stay switchable (verified:
  `Settings.saber_tail`, `tail.tscn`). No second ribbon is added.
- **FR-009**: A fresnel wall material MUST be switchable (default OFF) and MUST fade with
  camera proximity so a wall at the face cannot flood the screen with additive fill.
- **FR-010**: Debris/slice particles MUST be capped by a setting (default OFF) and be
  unshaded.
- **FR-011**: Fixed foveation MUST be selectable (Off/Low/Medium), applied through the XR
  interface, read back and logged, and described as a GPU saving in the panel.
- **FR-012**: No `SubViewport` in the shipped scenes MUST be left at `UPDATE_ALWAYS`.
- **FR-013**: Every item MUST have its own persisted setting in `Settings`, default ON for
  items 1-6 and OFF for items 8-9, changeable at runtime from the settings panel.
- **FR-014**: Every shader variant MUST be proven to compile by running the game on
  desktop with all visual settings off and all on, with no `SHADER ERROR` in the output.

### Key Entities

- **Settings keys**: `note_edge_glow`, `hit_flash`, `note_map_colors`, `event_tint`,
  `floor_grid`, `sky_gradient`, `wall_fresnel`, `debris_cap` (+ existing `saber_tail`,
  `foveation_level`).
- **Global shader parameters**: `event_left_tint`, `event_right_tint` (vec3, default
  white) beside the existing four saber endpoints.

## Success Criteria

- **SC-001**: A desktop run with every visual setting off logs no `SHADER ERROR` and no
  missing-parameter error.
- **SC-002**: A desktop run with every visual setting on logs no `SHADER ERROR`.
- **SC-003**: Live notes share one `ShaderMaterial` (no `resource_local_to_scene`), and
  no per-note material is created at spawn.
- **SC-004**: The note halo is gone from scene, script, settings and panel.
- **SC-005**: No `UPDATE_ALWAYS` remains in a shipped scene.
- **SC-006**: The panel exposes every new setting with a player-readable label and a
  tooltip stating its cost.

## Out of scope

- Measuring any of this on a headset (none is attached; the sheet records what is
  unverified).
- Scoring, hit detection, audio, the benchmark harness, the map format beyond reading a
  per-note colour.
- Changing the existing `saber_tail` default or the existing bloom default.

## Open questions

- Does the gradient sky (default ON) look right next to the panorama it replaces? Only a
  headset run answers this; the setting is the escape hatch.

## Assumptions

- `instance uniform` supports `vec4` + `float` in Forward Mobile on the pinned 4.6.3
  toolchain, and `GeometryInstance3D.set_instance_shader_parameter` accepts a `Color`.
- A per-note `_customData._color` (Chroma) is `{r,g,b}` floats; other formats are ignored
  and fall back.

## Consultation Log

| gate | question | verdict | follow-up |
|------|----------|---------|-----------|
| G0/G1 | See below | | |
