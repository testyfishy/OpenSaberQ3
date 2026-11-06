# Plan: scroll hitch and the part-by-part cleanup

**Spec**: `specs/016-scroll-ui-cleanup/spec.md`. **Order** follows the G0 consult: the scroll fix
first, then UI-1 (the same plumbing, consolidated), then the rest by risk. Every part must leave
the game playable and is proven against a gate before the next one starts.

## Part 0 - Scroll hitch (this session)

**Diagnosis from the consult** (verified in code): `_input_update()` does no ray work; it requests
a redraw (`OQ_UI2DCanvas.gd:98`). With `update_only_on_input`, each call starts an `update_once`
coroutine that waits three frames, so a scroll that calls it every frame leaves several coroutines
alive sharing one `frames_since_last_update` counter. Frames where the viewport was DISABLED at
render time show the previous scroll position - judder with fine frame time.

**Fix**: while the stick is moving, put the owning SubViewport in `UPDATE_ALWAYS`; when movement
stops, set `UPDATE_DISABLED` and request exactly one update. Implemented in `vr_slider.gd`
(`_set_live`).

**Gate**: the UI scroll probe (`ui_scroll_probe=true`) before and after, same session.

Measured on the Quest 3 (60 s probe, Performance preset pinned):

| | before | after |
|---|---|---|
| XR samples | 1 | 2 |
| fps median | 110 | 118 |
| App median | 6.22 ms | 5.78 ms |
| GPU% median | 0.97 | 0.86 |
| scroll frames / moved / zero | 120 / 117 / 3 | 120 / 117 / 3 |
| max step | 46 px | 48 px |

The scroll step sequence is unchanged, which is expected - the steps come from the same stick
policy. The redraw cost did not rise; if anything it fell, but with one or two XR samples that is
direction, not a number. The stale-texture count is the thing this probe cannot see; the player's
eyes are the final judge on that.

## BeatSaver panel cost - measured

`panel_cost` in the bench meta, 60 live scroll frames, Quest 3, Performance preset:

| | mean | p95 |
|---|---|---|
| CPU | 0.298 ms | 0.875 ms |
| GPU | 0.380 ms | 1.204 ms |

VrApi for the same run: fps 119, App 6.13 ms, **GPU 0.89** (in-game baseline with the panel closed
is ~0.75-0.78).

Conclusion: the per-frame redraw is **under the adviser's 0.5 ms GPU mean threshold**, so the
"panel redraw is the hitch" theory is only partly right. What is left is the panel's own fill: a
896x856 textured quad with `transparent_bg = true`, drawn into a VR scene. The texture-offset list
would remove the redraw but **not** that fill, so it would not close the 0.89 -> 0.78 gap.

Next, in order of expected return:
1. `transparent_bg = false` on the BeatSaver canvas if the panel is fully opaque (removes blending
   across a large screen area).
2. Check the viewport for mipmaps/MSAA/HDR-2D left on (none found in the scene, worth re-checking
   after any OQ update).
3. Only then consider lowering the panel texture resolution, which costs text sharpness.

### Opaque canvas - after

| | before | after |
|---|---|---|
| App median | 6.13 ms | 5.85 ms |
| GPU% median | 0.89 | 0.88 |
| redraw CPU mean / p95 | 0.298 / 0.875 ms | 0.201 / 0.329 ms |
| redraw GPU mean / p95 | 0.380 / 1.204 ms | 0.494 / 1.517 ms |

The CPU-side redraw cost halved and App time came down ~0.28 ms; GPU% did not move. That settles
it: the panel's cost is its fill (an 896x856 opaque quad in VR), not its redraws. **Retire this as
the cost of a full-screen VR menu** - it is not on the gameplay path - and spend the effort on the
cleanup instead. The opaque change stays: it is a small, measured CPU win and verified visually
(the panel paints its own background).

## UI-1 - One canvas refresh helper

Replace the three separate refresh paths (`vr_slider._request_refresh`, `BeatSaverPanel._canvas_input_update`,
the settings panel's equivalent) with one helper exposing `begin_live()`, `end_live()` and
`request()`, and remove the `update_once` re-entrancy.

Done, then fixed after the combined G4 review:

- The first version called `begin_live()` only on the false->true transition, so the 0.5 s watchdog
  treated a held stick as a lost owner and stopped rendering after half a second. It now runs on
  every moved frame and doubles as the heartbeat; the one-time measurement reset only happens on
  the transition.
- `OQ_UI2DCanvas._input_update()` now routes to the viewport's `canvas_refresh` meta when one
  exists, so `helper_UIArea`'s per-pointer-move call no longer starts the old `update_once`
  coroutine alongside the authority. The main menu's direct call does the same; `vr_slider`'s dead
  `canvas`/`canvas_path` members are gone.
- Owners are tracked by instance id rather than `is_connected(bound_callable)`, and the canvas
  exposes `render_frames` (frames it told the viewport to draw) because measured render time keeps
  its last value when idle and cannot prove a scroll stayed lit.

Gates: `VERIFYCANVAS bad=0` (heartbeat past the window, silence stops it, re-register recovers,
end_live disables + one final frame); device scroll probe holds the stick 3 s and counts rendered
moving frames: **289/290 = 0.997**, 348 render frames total (map ODDS, 112 fps median, App 5.50 ms);
UI screenshots unchanged; frame CSV unchanged.

## UI-2 - Scene-unique names

Replace `$ScrollContainer/VBox/...` paths with `%Name` where the node shares the panel's owner
scene (they do, both panels), leaving exported NodePaths where they do not. Mechanical.

Gate: UI screenshots and the settings round-trip test.

## UI-3 - Settings schema

Done. `Settings.gd` has one `const SCHEMA`: key -> default plus optional min/max/step, in the
historical insertion order. Everything else reads from it:

- `default_values` is derived in `_derive_defaults()` and initialised in its declaration (not in
  `_ready()`), so a load before `_ready()` still sees the table; the order is preserved and only
  the platform patch writes into it, never into `SCHEMA`;
- the loader reads `default_values` through `_default()`, not `SCHEMA`, because the Web patch
  writes platform defaults there (`saber_tail`, `cube_cuts_falloff`, `events` are off on Web);
  `SCHEMA` supplies ranges and the fallback for a key outside the table;
- `cast_or_default()` clamps every loaded value through `clamp_to_schema()`, so a hand-edited
  `config.ini` cannot store a value the panel could never produce;
- the setters that had hand-written `clampi` calls (`perf_preset`, `sky_style`, `hit_sound`,
  `glow_mode`, `environment_mode`) plus the other ranged numerics call the same clamp;
- the panel takes its six slider ranges (`thickness`, `ui_volume`, `render_scale`, master, sfx,
  music) and the option-button maxima (sky, glow, environment, hit sound, foveation, preset)
  from `Settings.SCHEMA`.

Typed properties and their setters stay: the audio setters push bus volumes as a side effect and
~40 call sites read `Settings.x` directly, so replacing them with a generic accessor would be
churn without a player-visible win. The type is `typeof(default)` - no separate column to drift.

Gate results: `SETTINGSTEST PASS` (defaults round-trip + legacy config with unknown/missing
keys), `VERIFYSCHEMA keys=49 bad=0` (order frozen against the historical list, property
coverage both ways, type match, range sanity, clamp behaviour, `changed` contract),
`VERIFYPANEL nulls=0 range_bad=0 ranges=6`, UI screenshots with the same scroll extent (507).

## UI-4 - Split the BeatSaver panel

Done in five buildable commits. `BeatSaverPanel.gd` went from 1048 to 928 lines and now only owns
what a shell should: the search/filter bar, paging, the request pools, the cover cache, selection,
downloads and show/hide. The API client (`BeatSaverApi`) was already pure; the new parts are:

| File | Lines | Owns |
|---|---|---|
| `BeatSaverQuery.gd` | 88 | query dict, preset tables/bounds, difficulty parse/serialise, settings keys, sort list |
| `BeatSaverDetailView.gd` | 84 | cover, SongData, Download, Maps-by; signals only |
| `BeatSaverResultsView.gd` | 103 | card scroll, 20-card pool, status line, Retry; signals only |

Both views are full-panel Controls with `MOUSE_FILTER_IGNORE`, so every child rect and raycast
target is unchanged. They never touch `BeatSaverApi`, an `HTTPRequest` or the cover cache: the
panel asks `set_rows()` for the cover requests and pushes textures back. The scroller points at
`../ResultsView/CardsScroll`, and the panel exposes `get_results_view()` / `get_cards_list()` /
`get_list_slider()` so harnesses stop depending on the layout.

Gates:
- `tools/beatsaver_shots.tscn`: eight states (loading, list, detail, downloading, downloaded,
  error, empty, paging) built from the checked-in BeatSaver sample through the real parser, with a
  stub cover source. All eight are **byte-identical** to the pre-split baseline after every step.
- `VERIFYPANELBS bad=0`: every object-typed script variable resolves, both views exist at full
  panel size and ignore the mouse, a card press selects index 0 and a Download press queues.
- `VERIFYQUERY bad=0`, `beatsaver browser test: OK (76 checks)`, `SETTINGSTEST PASS`,
  `VERIFYCANVAS bad=0`, `VERIFYPANEL nulls=0`, `VERIFYSCHEMA keys=49 bad=0`.
- Device 3 s hold probe: **281/282 moving frames rendered (0.996)**, 111 fps median, App 5.39 ms,
  GPU 0.81 %, panel redraw CPU 0.226 ms - no worse than the 0.997 / 112 fps / 5.50 ms baseline.

## Remaining parts (after the UI)

5. **View state** - the game-state scripts.
6. **Audio** - saber pool, ducking, analyser.
7. **Pooling** - `PooledNode3D` unification.
8. **Map loading** - the `Map.gd` split already specified in `specs/013-code-quality`.
9. **Bench tooling** - last, because it is the instrument the other gates use.

## Verification assets

- `tools/ui_shots.tscn` - settings panel at three scroll positions, in a SubViewport.
- `tools/harness/map_dump.tscn` + `map_dump_all.ps1` - 45-map canonical dump.
- `tools/harness/settings_roundtrip.tscn` - defaults, legacy config, missing key.
- `tools/perf/frame_stats.py`, `run-vrapi.ps1`, `feature-ab.ps1` - device frame/GPU numbers.
- The `ui_scroll_probe` bench mode - per-frame scroll deltas.
