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

## UI-1 - One canvas refresh helper

Replace the three separate refresh paths (`vr_slider._request_refresh`, `BeatSaverPanel._canvas_input_update`,
the settings panel's equivalent) with one helper exposing `begin_live()`, `end_live()` and
`request()`, and remove the `update_once` re-entrancy. Fully mechanical: every call site keeps its
current semantics.

Gate: UI screenshots pixel-diff within tolerance; scroll probe identical; frame CSV unchanged.

## UI-2 - Scene-unique names

Replace `$ScrollContainer/VBox/...` paths with `%Name` where the node shares the panel's owner
scene (they do, both panels), leaving exported NodePaths where they do not. Mechanical.

Gate: UI screenshots and the settings round-trip test.

## UI-3 - Settings schema

Move the per-setting boilerplate (setter, clamp, default, emit) into a data table plus generated
accessors, and have the panel build rows from it. This starts the settings/schema part of the
cleanup.

Gate: settings round-trip test including a legacy config, UI screenshots, no change in emitted
signal order (logged before/after).

## UI-4 - Split the BeatSaver panel

`BeatSaverPanel.gd` is ~1,000 lines mixing API calls, list building and the detail view. Split into
an API client, a list view and a detail view, keeping the public surface. This is the closest to a
rewrite, so it goes last among the UI parts.

Gate: screenshots of every panel state (list, search, detail, download) plus the scroll probe.

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
