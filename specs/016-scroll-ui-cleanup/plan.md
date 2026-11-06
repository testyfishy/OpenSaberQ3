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

Known debt, accepted at G4: `_query` is a read-only getter over `query.data` (two names until the
reads move), and both views build their controls in code with the original absolute rects (a
`.tscn` version is a separate change). `CanvasRefresh.of()` sets its viewport meta before adding
the node and defers the add on a Window, so a desktop `_ready()` cannot trip the busy-parent error.

## Remaining parts (after the UI)

**Performance rule (player, 2026-11-05):** if a part regresses the measured performance, do not
revert on sight. Consult the advisor on buying the performance back *with the feature still on*;
if a viable fix exists, keep the feature and implement it. Only if no acceptable fix exists,
revert that part and keep the rest of the work. Every part still needs its own before/after
numbers (fps median, App ms, GPU %, p99/max frame interval) and must leave the game playable.

### Overnight 2026-11-05 (after the v0.4.0 release)

7. **Pooling - closed, already unified.** `PooledNode3D` owns `_is_released`/`release()`,
   `ScenePool` owns presize/acquire/free-list, and both pooled scene types (`Wall`, `Cuttable`)
   extend it. No second lifecycle implementation exists; `specs/013` FR-008's "five types" is
   stale. No code change.

8. **Map loading - slice 1 done.** `MapTimer.gd` (121 lines) owns the BPM state and the four
   conversions; `Map.gd` dropped from 716 to 625 lines and keeps thin static wrappers, so call
   sites and `bpm_segments` for the dump are unchanged. `load_bpm_events()` starts from an
   explicit `reset()`, as FR-007 requires for static state. Gate: `BPMTEST PASS` (120->180 BPM,
   four conversions, four round trips through the facade). Device, release build, 30 s ODDS:
   **120 fps, App 4.99 ms, GPU 0.77 %** against the tagged release's 120 / 5.01 / 0.78 -
   no regression. The canonical map-dump gate is **unavailable on this machine**: `src_data` is
   absent, the v0.3 backup's `Songs` folders are empty, and the device's maps are in app-internal
   storage that a release build cannot `run-as` into. Pull a corpus (or install a debug build and
   copy them out) before slice 2.
   
   **Slice 2 done.** `MapPalette.gd` (78 lines) owns the note/room/wall colour rules, the Classic
   override, map/difficulty custom data and the FR-028 readability guards. `Map.gd` keeps
   `set_colors_from_custom_data()` as a facade and passes its info/difficulty in, so the palette
   does not depend on the loader; note, chain, wall, event-driver and game reads use
   `MapPalette.*`. `Map.gd` is now 580 lines (from 716). Gate: the hardened dump is
   **byte-identical** across 21 maps / 260,156 lines, PALETTE lines included.

   **The dump harness needed fixing first** (`da33454`). Two sources of false diffs: the stacks
   are filled by two threads so append order varied, and a process that crashed mid-map still
   left a non-empty file the batch accepted. Categories are now sorted and every run ends with an
   `END` sentinel that the batch requires (three attempts). The corpus lives at
   `F:\Dev\BeepSaberBin\map-corpus\Songs` (21 maps pulled from the headset with a debug build
   and `run-as`).

   **Slice 3 (MapSupport) done**: unsupported features and fake filtering in `MapSupport.gd`, with
   `SUPPORTTEST` on synthetic maps; dump byte-identical.
   **Slice 4 (MapData) done**: the six stacks, twelve threads, v2/v3 loaders and the v4 expansion
   moved in two commits, all call sites on `MapData.*`. `Map.gd` is now **99 lines** (716 before
   the split) and only keeps metadata, version normalisation, BPM/palette/support and dispatch.
   Gates: 21-map dump byte-identical after both commits; `RELOADTEST` (two loads, same sizes,
   reset empty); grep shows no stack/Thread left in Map.gd. Known gap: no before/after load-time
   number (the old build had no timestamp); correctness is the dump plus the reload test.

5. **View state - planned, not started.** The six `game/scripts/GameState/*.gd` classes repeat a
   ~20-line show/hide block, but the differences matter: Paused deliberately leaves the sabers
   untouched, Settings leaves swingcast alone, NewHighscore adds two keyboards. A declarative view
   mask is a behavioural change that has to be judged by driving the menus, which is not possible
   headless. Do it with the player available, one state per commit.

6. **Audio - instrument done, finding recorded.** `game/scripts/AudioProbe.gd` records two mixer
   taps to 16-bit WAVs, Master (music + SFX + hit limiter) and SFX (hits without the music);
   `tools/perf/audio_probe.py` reports RMS, body (150-800 Hz) and transient (2-6 kHz) bands and
   transients above the local bed; `run-vrapi -MissPercent` gives a no-hit A/B. The mic idea was
   considered: it measures room + speakers + AGC, so it is a sanity check, not the instrument.
   Probe cost when enabled: App 5.67 ms vs 5.01 (bench-only, two captures + PCM conversion).
   Measured on device (ODDS, 15 s, 19 right notes):
   - SFX hits peak **-4.1 dBFS** (at the -1 dB limiter) and the transient band reaches +5.9 in
     the FFT metric;
   - at hit windows the music's transient-band median is -28.9 dB, a ~35 dB margin.
   **Level is not the problem.** The hit voice is the saber's `AudioStreamPlayer3D`, not the cube
   (FR-020 asks for the cube), and the timbre is the old classic set; both match the complaint
   better than "too quiet".
   **Both fixes are in and measured (2026-11-06).**
   - `HitAudio.gd`: 16 preallocated `AudioStreamPlayer3D` voices on the SFX bus, oldest-first
     steal, each placed at the cube's `global_position`; distance attenuation and doppler off so a
     cube a metre away is not quieter than the saber; panning kept at 0.85; 1/sqrt(n) inside 30 ms.
   - Ducking: a per-frame envelope on the Music bus (3 dB, 80 ms hold, 25 dB/s release), with the
     `audio_ducking` setting on the Audio tab (default true after the measurement). HitAudio is the
     only Music-bus writer.
   - Device: SFX peak **-4.1 dBFS**, same as v0.4.0; duck off `audio_duck_min_db=0.00` / 0 frames,
     duck on **-3.00 dB** / 361 frames; App 5.63 ms with the probe on in both arms, and the tagged
     release measured 5.68 ms in the same session (cooler runs read ~5.0, so compare like with
     like). L/R: 4/4 non-silent lateral windows (>0.3 m) put the energy on the cube's side; 9 of
     13 lateral windows were silent in the SFX tap (capture/log timing) so the sample is small.
   - FR-036: `HitAudio.stop_all()` stops every voice and releases the duck; Paused, MapComplete and
     MapSelection call it, and the node processes always, so a pause or a menu cannot leave the
     music down. Found by the G4 review (`d3df6d2`).
   - Known gaps: the attack is one frame (8-14 ms at 72-120 Hz), not the 3 ms in spec 011 FR-017;
     the L/R check has 4 usable lateral windows (the rest were silent in the SFX tap), so it agrees
     with x but is not a large sample; ducking is read as applied bus gain (361 ducked frames in
     15 s, ~30%, not a constant duck) because a bus capture is pre-volume. All recorded.
   - Part 6 is closed. The part-6 build is installed on the headset; v0.4.0 remains tagged.

9. **Bench tooling - deferred on purpose.** The plan says it is the instrument the other gates use,
   and it is 1262 lines. Splitting it now would invalidate the instrument while parts are still
   open. `specs/013` FR-004 (exclude from release) also conflicts with a capability the v0.4.0
   verification proved useful: a release build still runs captures through the external flag path.

## Verification assets

- `tools/ui_shots.tscn` - settings panel at three scroll positions, in a SubViewport.
- `tools/harness/map_dump.tscn` + `map_dump_all.ps1` - 45-map canonical dump.
- `tools/harness/settings_roundtrip.tscn` - defaults, legacy config, missing key.
- `tools/perf/frame_stats.py`, `run-vrapi.ps1`, `feature-ab.ps1` - device frame/GPU numbers.
- The `ui_scroll_probe` bench mode - per-frame scroll deltas.
