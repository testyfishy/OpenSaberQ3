# Code audit of 0.7.9 — Fable 5.2

- **Base**: `godot-4-port` at `e176b52` (0.7.9, versionCode 25).
- **Branch**: `audit/fable-5.2`, 22 commits, nothing pushed, tagged, exported or installed.
- **Method**: static reading plus headless Godot 4.6.3 runs. No headset was used, so nothing here
  is an on-device result.
- **Three things need the owner before anything else**: S-1 (release keystore password is in the
  repository), H-1 (the 0.7.9 APK does not declare hand tracking), and the four fixes marked
  **BEHAVIOUR CHANGE** below (H-6, S-4, G-1, G-3).

## 1. Project map

**Boot to menu.** `project.godot` autoloads (`Constants`, `Utils`, `Scoreboard`, `Settings`, `vr`,
`Highscores`, `ProfileManager`, `PlayCount`, `StopwatchFactory`, `UI_AudioEngine`,
`GlobalReferences`) → `game/BeepSaber_Game.tscn` → `BeepSaber_Game._ready()` presizes the cube,
link, wall and bomb pools, calls `vr.initialize`, applies refresh rate / render scale / MSAA /
foveation from `Settings`, then enters `gamestate_mapselection`. The states in
`game/scripts/GameState/` are plain objects that only set overlay, HUD and saber visibility.

**Map load to results.** `BeepSaberMainMenu._load_map_and_start` emits `start_map` →
`BeepSaber_Game.start_map` reads the difficulty JSON (plus the v4 audio and lightshow files) →
`Map.load_beatmap` fills the `MapData` stacks → `GameStatePlaying._process_map` pops them into
pooled objects each physics tick and places each in its 360 lane (`TrackLanes`) → `LightSaber`
detects hits (ray fan by default, analytic resolver optional) → `Cuttable.cut` → `Scoreboard` →
`BeepSaber_Game._on_song_ended` writes the highscore and shows `EndScore`.

**Settings.** `Settings.SCHEMA` is the single table of keys, defaults and ranges. Each property
setter clamps, writes the in-memory `ConfigFile` (a default is stored as "absent") and emits
`changed(key)`. `reload()` replays every key in schema order; `save()` is explicit. Listeners:
the game (render, glow, sky), both sabers, the menu's quick toggles, the settings panel.

**XR input.** Each `XRController3D` runs `BeepSaberController`, which polls buttons in
`_physics_process`. `UIRaycast` is a child of the saber and reads `trigger_just_pressed`.
Hands: the joint tracker `/user/hand_tracker/<side>` supplies the palm pose and the pinch
(thumb-tip to index-tip distance, 30 mm press / 50 mm release); `LightSaber` goes `top_level` and
follows the palm; `RenderedHand` draws the hand from the same tracker.

## 2. Findings

Severity: P0 crash / data loss / broken core; P1 reproducible wrong behaviour; P2 leak, dead code,
fragile path; P3 docs and naming. "Fixed" names the commit. Line numbers are at `e176b52`.

### Security

| ID | Sev | Where | What | Status |
|---|---|---|---|---|
| S-1 | P0 | `export_presets.cfg:499-501` | The release preset's `keystore/release`, `release_user` and `release_password` are non-empty in a tracked file, and `origin` is a GitHub repository. Anyone with the repo history has the signing password. | **Not touched** (the brief forbids touching the keystore). Owner action: blank the three fields, supply them through `GODOT_ANDROID_KEYSTORE_RELEASE_*`, and treat the password as disclosed. |
| S-2 | P2 | `.gitignore:25` | Only `bin/release.keystore` is ignored; there is no `*.keystore` / `*.jks` rule. `bin/debug.keystore` is tracked. | Proposal. |
| S-3 | P1 | `game/scripts/Utils.gd:48` | Zip entry names were joined to the destination unsanitised, so a `../` entry from a download or the LAN upload page could write outside the song folder. `verify_io_fixes` writes the escaped file on the old code. | Fixed, `3065f1a`. |
| S-4 | P0 | `game/scripts/SongUploader/song_uploader.gd:68` | The upload server (on by default) read request headers on the main thread in an unbounded loop. A LAN client that connects and sends nothing froze the game permanently. Repro: `verify_io_fixes.tscn` on the old code never returns. | Fixed, `334758d`. **BEHAVIOUR CHANGE**: an upload that stalls for 2 s is dropped. Residual: the read still blocks the frame while data is flowing; a proper fix is a per-connection state machine. |

### Hand tracking

All of H-2..H-6 follow from one fact: with the controllers asleep, `XRController3D.get_is_active()`
is false and the node keeps its last transform. `tools/harness/verify_hand_path.tscn` reproduces
that state with a synthetic `XRHandTracker` and no `left_hand` tracker.

Before. The first four lines are from an earlier revision of the harness run against the game
code at `e176b52`; the committed harness calls `cut_origin()`, which does not exist there, so to
reproduce them check out `e176b52` for `game/` and drop that one check. The last three were
measured with the committed harness on the commit just before their fix (`f9cc6a4` for the parked
blade, `11d84f8` for the dropout):

```
HANDPATH FAIL cut segment has no one-frame lag behind the hand  (worst 0.050 m)
HANDPATH FAIL pinch presses the trigger with the controller asleep
HANDPATH FAIL swing travel follows the hand  (longest axis 0.00 m)
HANDPATH FAIL cut plane origin is the hand  (uses controller.global_transform.origin, 0.88 m from the hand)
HANDPATH FAIL a parked blade cuts nothing  (cuts=31)
HANDPATH FAIL a dropout mid-pinch releases the trigger
HANDPATH FAIL a hand that returns still pinched does not click
```

After: `HANDPATH PASS` (30 checks).

| ID | Sev | Where | What | Status |
|---|---|---|---|---|
| H-1 | P1, effect unverified | `export_presets.cfg:218-223`, `android/build/src/main/AndroidManifest.xml` | Both Android presets have `xr_features/hand_tracking=0`, the vendors addon is not installed, and the local Gradle manifest has no hand-tracking entry. I dumped the manifest of `OpenSaber-v079.apk` in `F:/Dev/BeepSaberBin` with `aapt2`: it is 0.7.9 / code 25 and contains neither `com.oculus.permission.HAND_TRACKING` nor `oculus.software.handtracking`. Meta documents both as required for an app to receive hand data. **This conflicts with the brief**, which says the hand joints are live on the device. I cannot tell from here which is right; the brief's evidence (logcat showing the system switching to hands) does not by itself show joints reaching the app. | **Not fixed**: `android/build/` is gitignored, so the fix cannot live in the repo as it stands. If the rendered hands do not appear on the headset, check this first. |
| H-2 | P1 | `BeepSaberController.gd:134` | Buttons, including the joint pinch, were only updated inside `if get_is_active()`. With the controllers asleep a pinch could never click. | Fixed, `f9cc6a4`. |
| H-3 | P1 | `BeepSaberController.gd:101`, `BeepCube.gd:219` | `movement_aabb` tracked the sleeping controller, so `travel_distance_factor` was 0 for every hand cut. That term can double a note's score. | Fixed, `f9cc6a4`. |
| H-4 | P1 | `LightSaber.gd:254` | The cut plane hinged on the sleeping controller's origin, which skews `cut_distance_accuracy` and the debris split. | Fixed, `f9cc6a4`. |
| H-5 | P2 | `LightSaber.gd:130` | The hand pose was written only in `_process`, which runs after the frame's physics ticks, so cuts were resolved against the previous frame's blade. The controller path has no such lag. | Fixed, `f9cc6a4`. |
| H-6 | P1 | `LightSaber.gd:248` | A parked saber (hand data lost, no controller) still cut every note that flew into it: 31 cuts in 30 ticks in the harness, in the shipped ray-fan mode. | Fixed, `5167a5d`. **BEHAVIOUR CHANGE**: a parked blade cuts nothing. It is still drawn; hiding it is your call. |
| H-13 | P1 | `BeepSaberController.gd` (introduced by `f9cc6a4`, caught in review) | With the gate opened only by live hand data, a pinch held at the moment of a dropout stayed pressed. | Fixed, `e520994`. |
| H-7 | P2 | `BeepSaberController.gd:64` | Buttons were read from the tracker even when the controller was not tracked. | Fixed, `f9cc6a4`. |
| H-8 | — | `BeepSaberController.gd:159` | The `UNKNOWN` tracking-source allowance is safe as configured: the project requests only the unobstructed data source (`project.godot:212`), and the harness confirms `CONTROLLER`-sourced data is rejected. | No change. |
| H-9 | — | `RenderedHand.gd:51` | `visible` is written every frame and `show_when_tracked` also writes it on pose changes. `_process` runs after the XR server's pose delivery and before drawing, so the script always has the last word: no flicker. `show_when_tracked` is redundant. | No change. |
| H-10 | P3 | `game/hands/hand.png.import:29`, `RenderedHand.gd:42` | The material asks for `LINEAR_WITH_MIPMAPS` but the texture is imported without mipmaps, so it samples as plain linear (possible shimmer at distance). | Proposal: turn mipmaps on in the import, or say `TEXTURE_FILTER_LINEAR`. |
| H-11 | P3 | `openxr_action_map.tres` | The brief's note is not what the file shows: `pinch` has only `/user/hand/left|right`. The Vive-tracker path lists are on `default_pose` and `haptic`, as before. The one unintended change in `1390c66` is `palm_pose` rebound from `palm_ext/pose` to `grip_surface/pose` on eight profiles; nothing reads `palm_pose`. (Subagent diff; I did not re-diff it.) | No change. |
| H-12 | P2 | menu | With Hands off and the controllers asleep, nothing can turn Hands back on. Also, both pinches held for 0.5 s in a menu trigger the screenshot combo. | Proposal: keep the pinch alive for the quick-settings panel only, or accept "pick up a controller". |

Residual risk for the whole group: the "controller asleep" state is simulated. The fixes are
written so that controller mode reads exactly what it read before (the harness asserts
`swing_origin() == controller.global_transform.origin` there), but hand play itself still needs
the headset.

### Gameplay and maps

| ID | Sev | Where | What | Status |
|---|---|---|---|---|
| G-1 | P1 | `game/scripts/TrackLanes.gd:41` | `reparent(lane)` keeps the global transform, but `spawn()` has already written lane-local coordinates. Moving into a rotated lane cancelled the rotation; a pooled node returning to Lane0 after a 360 map stayed rotated in the next normal map. `rotation_probe.tscn`: FAIL before, PASS after. | Fixed, `93c6ab6`. **BEHAVIOUR CHANGE** in a guarded area (map compatibility): 360/90 maps will look different. Maps with no rotation events never change lane. Not seen on a headset, and G-11 becomes more exposed. |
| G-2 | P1 | `game/scripts/MapData.gd:96` | A bare `continue` in a manual `while` loop: one non-object entry in a v2 `_notes` array hung the loader for good. | Fixed, `9fc67ee`. |
| G-3 | P2 | `game/BeepSaber_Game.gd:131` | `vr.load_json_file` returns `{}` on failure, so the null check was dead and an unreadable difficulty file played the song with no notes. | Fixed, `d438a6b`. **BEHAVIOUR CHANGE**: the map does not start. |
| G-4 | P2 | `game/BeepSaber_Game.gd:555, 573` | Glow levels were indexed 1..7; the API takes 0..6. Two engine errors per boot and on every glow change. | Fixed, `ede8e9f`, without changing which levels are written. Note for you: Subtle keeps index 4, which the inspector calls level 5; index 0 is never written. If "level 4" was the intent, that is a look change and yours to make. |
| G-5 | P2 | `game/BeepSaber_Game.gd:778` | The end screen divided 0 by 0 (NaN %) when a song ended with nothing scored. | Fixed, `52efa87`. |
| G-6 | P2 | `game/Scoreboard.gd:43` | The accuracy percentage normalises the running **total** (`points`) by 80, not the points of this cut, so after the first cut or two every hit counts as 100 %. The percentage is effectively hits / (hits + misses). | **Proposal only**: fixing it changes every player's displayed accuracy. |
| G-7 | P1 | `game/Chain/ChainLink.gd:142` | Chain links share one material resource, so all live links take the colour of the last chain spawned. (Subagent finding, read but not reproduced by me.) | Proposal: make `color` an instance uniform as `BeepCube` does. |
| G-8 | P2 | `game/Bomb/Bomb.gd:50` | `hide_bomb` never clears `_collision_enabled`, so with analytic detection plus enable-once a reused bomb is never hittable again. Harmless in the shipped ray mode. | Proposal. |
| G-9 | P2 | `game/Arc/Arc.gd:84` | A missed head note leaves a one-shot `cutted` connection on a pooled cube; the next note that reuses the cube flips the old arc. Narrow trigger. | Proposal. |
| G-10 | P2 | `game/BeatmapInfo/MapSource.gd:206` | v4 maps read `beatmapFilename` (v4 uses `beatmapDataFilename`), so their level hash is empty and BeatLeader lookups cannot match. | Proposal: needs a v4 fixture with a known hash. |
| G-11 | P2 | `game/BeepCube/BeepCube.gd:205, 222` | Beat and angle accuracy read global z / global basis, which is wrong inside a rotated lane. 360 maps only. | Proposal, together with on-device 360 testing of G-1. |
| G-12 | P2 | `project.godot:221` vs `README.md:27` | The README says hit registration is the analytic swept-blade test. The project ships `swing_hit/detection="rays"`. One of the two is stale. | Owner decision; I changed neither. |
| G-15 | P1, suspected | `game/scripts/Utils.gd:80-97`, `game/scripts/MapData.gd` | The map loader dies intermittently on fixture map `32693` (a native crash, no script error; the harness README already notes "thread teardown" deaths). It predates this branch. The likely cause is `Utils.custom_thread_call` / `custom_thread_wait_to_finish` mutating one shared array from worker threads and the main thread, but I did not prove that. If it happens on the headset it is a crash on map load. | **Not fixed.** Worth its own investigation with that map as the fixture. |
| G-13 | P3 | `game/BeepCube/BeepCube.gd:148` | The bench `notes_off` flag is overridden a few lines later, so any A/B that used it measured nothing. | Proposal. |
| G-14 | P3 | `default_saber.tscn` | Three animations reference a missing `Halo:mesh:size` track (warnings on every saber load). | Proposal. |

Map-format safety: the loader change (G-2) was checked against the 45-map fixture set with
`tools/harness/map_dump_all.ps1`, before and after. See section 5.

### UI, storage and network

| ID | Sev | Where | What | Status |
|---|---|---|---|---|
| U-1 | P1 | `game/ui/StoragePanel/StoragePanel.gd:201, 221` | The confirmed delete passed `_pending` to `_execute`, which cleared that same array before iterating it: "Deleted 0 maps", always. | Fixed, `07830f5`. |
| U-2 | P1 | `game/scripts/Utils.gd:48` | `unzip` aborted on the first entry in a subfolder (`store_buffer` on null), dropping the rest of the archive. | Fixed, `3065f1a`. |
| U-3 | P2 | `game/scripts/HTTPRequestPool.gd:45, 60, 76, 84` | Finished requests were removed from the tree but never freed (one orphan per cover image); a queued request restarted under a new token. | Fixed, `c294d8a`. |
| U-4 | P1 | `game/ui/BeatSaverPanel/BeatSaverPanel.gd:487` | Back assigned to a getter-only property and so re-ran the current search. | Fixed, `54fa0e0`. No automated test (needs the panel and a network stub). |
| U-5 | P2 | `game/ui/BeatSageUI/BeatSageUI.gd:47` | `get_node("")` on every boot: the scene override was lost in `a2b4137` when the export was renamed. | Fixed, `9eecc37`. |
| U-6 | P2 | `OQ_Toolkit/OQ_UI2D/scripts/OQ_UI2DCanvas.gd:103` | `get_meta(key, null)` logs an error for every canvas without a `CanvasRefresh`, at boot and on each pointer event. | Fixed, `a2a7329` (one-line `has_meta` guard in the vendored file). |
| U-7 | P2 | `game/BeepSaberMainMenu.gd:576` | `focus_exited` was connected to a handler that requires an argument; every emission only logged an error. | Fixed, `44768ad`, by removing the connection. Making the keyboard close on focus loss would be a UI change. |
| U-8 | P1 | `game/ui/BeatSaverPanel/BeatSaverPanel.gd:869` | A failed download (non-200, or a corrupt zip) is still tagged and reported as downloaded. (Subagent finding.) | Proposal: require 200 and an `Info.dat`, as the BeastSaber panel does. |
| U-9 | P1 | `game/scripts/MapSourceBackfill.gd:149` | `stop()` leaves a coroutine awaiting; a later `start()` lets it resume and write one map's id onto another. (Subagent finding.) | Proposal: a generation token, as `BeatLeaderPanel` uses. |
| U-10 | P2 | `game/ui/BeatSageUI/`, `game/ui/YouTubeUI/` | The BeatSage and YouTube dialogs are reachable but cannot work: an `OK` result treated as failure, Godot 3 property names, the old `user://BeepSaber/` path. | Proposal: hide the button or remove both dialogs. |
| U-11 | P2 | `game/Settings.gd:494` | `load_old_config()` (a pre-ini `config.dat`) sets only the legacy keys. Every newer key is left at its type zero (`render_scale` 0, `audio_music` 0, `hand_tracking_enabled` false) for that session. Read, not reproduced. | Proposal: apply the schema defaults first. |

Settings checks that came back clean: every property is in `SCHEMA` (`VERIFYSCHEMA keys=58
bad=0`), a missing key loads its default, out-of-range values clamp, and the main menu sets its
quick toggles before connecting, so loading it writes nothing.

### Landmines from the brief with no finding, and what was not checked

- **Object pools** (cube, link, wall, bomb): acquire/release is symmetric, the double-release
  guard holds, and `_clear_track` returns pooled nodes rather than freeing them. Read by a
  subagent; no runtime pool-invariant test was added.
- **`GlobalReferences` / `vr` autoloads**: the only forward reference in autoload order is
  `Settings` calling `vr.log_file_error` on error paths, and `vr`'s log self-initialises. Null
  access during a scene change was not exercised (the game has one scene).
- **Main-menu library state**: `_card_key`, `_sort_field` and `_sort_desc` are copies of three
  settings, written back on every change; I found no path where they drift. Read only.
- **Settings migrations**: the 120 Hz migration is guarded by a marker key and the preset
  migration by the key's presence, so both run once. `default_values` is derived from `SCHEMA`
  in the same order. Covered by the two settings harness scenes; U-11 is the one gap.
- **Not checked at all**: `BenchmarkRunner.gd` beyond the WallBatch flag, `BotDriver.gd`,
  `event_driver.gd` and the environment profiles beyond a subagent's read, the shaders, the
  `.tscn` layouts, and anything that needs a GPU or the headset.

### Dead code and docs

| ID | Sev | What | Status |
|---|---|---|---|
| D-1 | P2 | `WallBatch`: broken, off by default, but `setup()` still ran on every boot and its node was freed by the first `_clear_track()`. | Removed, `448d064`. It cannot be shown working with the headless dummy renderer. |
| D-2 | P2 | `HighscoreTableTest.gd` (19 parse errors; repaired, it would overwrite the real highscore file) and `launcher_preview.gd` (preloads a scene deleted in `dfac0d7`). | Removed, `3f6e6a5`. |
| D-3 | P3 | Three unused scene loads in `GameStatePlaying`; a copy-paste `left_saber` check in `update_right_color`. | Fixed, `52efa87`. |
| D-4 | P3 | README "52 persisted settings"; ATTRIBUTION listed a `dull_03.wav` that does not exist; harness README "48 keys". | Fixed, `11d84f8`. |
| D-5 | P3 | Spec 030: FR-003/004, FR-010, "out of scope" and one assumption were contradicted by the code since 0.7.8. | Marked superseded and FR-018..022 added, `11d84f8`. |
| D-6 | P3 | Left alone because the right wording is yours: `README.md:214` ("Next, 0.6.5"), `:231-234` ("Where 0.7.2 stands"), `:285` ("v0.1.0 to v0.6.0"); `docs/changelog.md:62, 153, 168` link to tags that do not exist (`v0.7.6-q3`, `v0.6.5-q3`, `v0.6.4-q3`); `:271` ("Next: 0.6.3"); `specs/029:7` ("tag pending"); `UPSTREAM.md:98`. | Proposal. |
| D-7 | P3 | `project.godot` carries dead Godot 3 keys (`[gdnative]`, `rendering/quality/*`) and two OpenXR keys the engine does not read. Three tracked GIFs are 5–7 MB each. | Proposal. |

## 3. Safe cleanups applied

Behaviour-preserving: `52efa87` (hit-rate helper, unused loads), `448d064` (WallBatch),
`3f6e6a5` (orphan scripts), `a2a7329`, `44768ad`, the hand-tracker name cache and the "why"
comments on the XR pose spaces in `f9cc6a4`.

## 4. Behaviour fixes applied

One commit each, oldest first:

| Commit | Fix | Proof |
|---|---|---|
| `27cf465` | Parse gate harness | Reported the two known bad scripts on the base tree. |
| `f9cc6a4` | H-2, H-3, H-4, H-5, H-7 | `verify_hand_path`: 4 FAIL → PASS. |
| `5167a5d` | H-6 (**behaviour change**) | `verify_hand_path`: 31 cuts → 0. |
| `e520994` | H-13 | `verify_hand_path`: 2 FAIL → PASS. |
| `ede8e9f` | G-4 | Boot log error gone. |
| `9eecc37` | U-5 | Boot log error gone. |
| `a2a7329` | U-6 | Boot log error gone. |
| `44768ad` | U-7 | Boot log error gone. |
| `07830f5` | U-1 | `verify_io_fixes`: "Deleted 0 maps" → folder removed. |
| `3065f1a` | U-2, S-3 | `verify_io_fixes`: script error → all entries extracted, `../` refused. |
| `c294d8a` | U-3 | `verify_io_fixes`: 4 orphan nodes → 0; token 2 → token 1. |
| `334758d` | S-4 (**behaviour change**) | `verify_io_fixes`: never returned → returns in 2.0 s. |
| `54fa0e0` | U-4 | Before/after reading only. |
| `93c6ab6` | G-1 (**behaviour change**) | `rotation_probe`: FAIL → PASS. |
| `9fc67ee` | G-2 | `verify_io_fixes`: never returned → 1 note loaded. |
| `d438a6b` | G-3 (**behaviour change**) | Before/after reading only. |

## 5. Verification

Godot is `%LOCALAPPDATA%\Godot\4.6.3\Godot_v4.6.3-stable_win64_console.exe`, run from the repo
root at the tip of `audit/fable-5.2`.

| Command | Result |
|---|---|
| `--headless --path . --quit` | exit 0; no `SCRIPT ERROR` and no engine `ERROR` apart from the expected OpenXR-runtime lines and the dummy renderer's exit-time leak notices |
| `res://tools/harness/verify_parse.tscn` | `PARSECHECK files=181 bad=0` (base tree: `files=183 bad=2`) |
| `res://tools/harness/verify_settings_schema.tscn` | `VERIFYSCHEMA keys=58 bad=0` |
| `res://tools/harness/settings_roundtrip.tscn` | `SETTINGSTEST PASS` |
| `res://tools/harness/verify_hand_path.tscn` | `HANDPATH PASS` |
| `res://tools/harness/verify_io_fixes.tscn` | `IOFIX PASS` |
| `res://tools/harness/rotation_probe.tscn` | `LANEPROBE local transform kept: ... PASS` |
| `map_dump_all.ps1` over the 45-map set, loader before vs after | 44 of 45 maps byte-identical in one pass each. The 45th (`32693`) is byte-identical when its dump completes, but the dump process dies intermittently on it with **both** loaders (complete 4 of 6 runs on the old loader, 2 of 6 on the new; too few runs to call a difference). See G-15. |

Not run: an export, an install, anything on the headset, the benchmark matrix.

New harness scenes: `verify_parse`, `verify_hand_path`, `verify_io_fixes`; `rotation_probe`
gained one assertion. The harness runs rewrite `user://config.ini` and probe folders under
`user://` on this PC only.

## 6. Suggested order for the owner

1. S-1: rotate the keystore password.
2. H-1: confirm the APK manifest declares hand tracking before reading anything into an on-device
   hands test.
3. Review the four behaviour changes (H-6, S-4, G-1, G-3), then build and run the 0.7.9 validation
   list from spec 030 on this branch.
4. Decide G-6 (accuracy maths), G-12 (rays vs analytic), H-12 (Hands fallback), U-10 (BeatSage).
