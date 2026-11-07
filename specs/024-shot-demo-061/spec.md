# Feature Specification: 0.6.1 screenshots and demo removal

**Feature Branch**: `024-shot-demo-061`

**Created**: 2026-11-06

**Status**: 0.6.2 released (trigger correction); home tests pending

**Input**: "The bundled TheFatRat 'Time Lapse' demo has no documented licence" -> "Remove it
completely in v0.61"; "Real headset screenshots are still needed" -> "Build the ability to take
screenshots into the game please".

## Intent

Ship 0.6.1 with two changes: the unlicensed TheFatRat demo track is removed from the repository,
the APK and existing libraries that still have the bundled copy; and the game gains its own
screenshot capture so real headset screenshots (gameplay and menus) can be taken for itch.io
without the system screenshot gesture.

## Facts found before the spec

- The demo is `game/data/maps/Songs/TheFatRat_Timelapse` (song `song_q1.egg`, SHA-256
  `303F764B259F309F9DEB1AC077524B1A4995AFD7B691CD48C194FD8FB7606C16`). It is copied into
  `user://OpenSaber/Songs/` on first run by `BeepSaberMainMenu._load_playlists`.
- Bench capture uses `get_viewport().get_texture().get_image()`. The code records that this is
  black on the headset because the XR eye buffers belong to the runtime swapchain.
- The OpenXR action map already defines `grip_click` (`squeeze/click`) for both hands; the
  controller script does not read it. Grips are otherwise unused by gameplay.
- Godot 4 has no `get_external_data_dir()`. The bench derives
  `/storage/emulated/0/Android/data/<package>/files` from `OS.get_user_data_dir()`; that directory
  is app-owned and readable over adb without storage permission.
- The pause menu is `game/Pause_Panel.tscn` (640x576), with Continue / Restart / Main Menu buttons
  and free space on the right.
- Other places still reference the demo: `game/HighscorePanel.tscn` loads its cover as an
  ext_resource, `game/data/maps/Playlists.json` lists it, and both menu scenes use TheFatRat
  placeholder text. The bench defaults to `map="Timelapse"` in `tools/perf/bench.ps1` and
  `tools/perf/benchmark.md`.
- 0.6.0 is the current tag/release; 0.6.1 / code 11 is the next version. The new brand icon and
  menu logo were committed after 0.6.0 and still need a build.

## Requirements

### Remove the demo

- **FR-001**: The `TheFatRat_Timelapse` folder MUST be removed from the repository and from the
  0.6.1 APK; no sample song is copied on first run. The `Songs/.gitignore`, the copy-on-first-run
  block, `HighscorePanel.tscn`'s cover ext_resource, `Playlists.json`, the placeholder text in both
  menu scenes, and the bench default map MUST be updated. `grep -ri "TheFatRat\|Timelapse" game/
  tools/` MUST return nothing, and the export MUST build with no missing-resource errors.
- **FR-002**: On 0.6.1 first launch, an existing `user://OpenSaber/Songs/TheFatRat_Timelapse` MUST
  be deleted only when its `song_q1.egg` SHA-256 matches the removed bundled copy above. A player's
  own download that differs MUST be kept. The cleanup MUST run once; a marker prevents re-checking
  every launch. Highscore and play-count rows are invisible once the map is gone and MUST be left
  untouched (deleting user data is not recoverable).
- **FR-003**: `ATTRIBUTION.md` MUST record that the demo was removed in 0.6.1 and is no longer
  distributed; the itch plan's demo-song blocker MUST be marked resolved for 0.6.1. The owner
  directed: skip the old builds — do not rewrite history, delete the 0.6.0 asset or edit its notes;
  document the removal as a 0.6.1 change only.
- **FR-003a**: A fresh install has no songs, so the library MUST show an explicit empty state
  that points at the in-VR BeatSaver browser, not the generic source-filter message.

### Screenshots

- **FR-004**: A screenshot MUST capture the current view at **1920x1080** into a PNG, using a
  dedicated capture camera in a SubViewport that shares the game `World3D` (not the XR swapchain
  and not the system gesture). It MUST copy the XR camera's `cull_mask`, environment and
  attributes, use a ~75 degree vertical FOV at 16:9 (60 cropped the sabers/HUD), render with `UPDATE_ONCE` and wait two
  `RenderingServer.frame_post_draw` frames before reading the texture. The image MUST be non-black
  on the headset.
- **FR-005**: The capture MUST work from gameplay and from any menu/panel (main menu, BeatSaver,
  Leaderboard, Settings). The screenshot action is **both grips held together for 0.5 s**, with a
  2 s cooldown, plus a **Screenshot** button in the pause menu. A `screenshot_grip` setting
  (default on) MUST disable the grip action. F12 MUST take one on desktop.
- **FR-006**: The pause-menu button MUST hide the pause overlay for the shot and restore it after;
  the trigger action captures whatever is on screen in menus. The toast MUST be shown after the grab so it is
  not in the image; it names the saved file, and the full path MUST be logged.
- **FR-007**: Screenshots MUST be saved to the app's external files directory on Android
  (`/sdcard/Android/data/<package>/files/screenshots/`) and to `user://screenshots/` on desktop,
  with unique timestamped names and the directory created on demand. The path MUST be documented
  for `adb pull`; no storage permission is requested.
- **FR-008**: The feature MUST add no per-frame work beyond a two-button hold check per physics
  tick, and MUST not allocate or render until the action fires. The PNG buffer MUST be written on
  `WorkerThreadPool`, not on the main thread; the one capture frame may hitch and that MUST be
  documented. A failure MUST show a clear message and must not crash or pause the game.
- **FR-009**: The existing bench `screenshot=true` path MUST use the new capture service, so the
  same code is verified on the headset during a debug bench.

### Release and docs

- **FR-010**: Version name **0.6.1**, version code **11**, RELEASE export; install over 0.6.0
  keeping maps, scores and settings; the new app icon/menu logo are in the build; the demo is not.
  Tag `v0.6.1-q3`, fast-forward `godot-4-port`, attach the APK + SHA-256 to a GitHub release.
- **FR-011**: The README/itch plan MUST explain how to take and retrieve a screenshot (grips, pause
  button, `adb pull` path) and mark the itch demo blocker resolved. `docs/itch-page.md` stays the
  page copy; `docs/itch-push.md` stays the go/no-go.
- **FR-012**: A desktop automated test MUST load the game scene, open the menu, call the capture,
  and assert a PNG of the expected size and non-zero content; a headset bench MUST save a PNG that
  can be pulled and inspected.

## Success criteria

- **SC-001**: The repo contains no `TheFatRat_Timelapse` folder and `grep -ri "TheFatRat\|Timelapse"
  game/ tools/` returns nothing; a clean install has no sample song and shows the empty state; the
  0.6.1 APK's asset list contains no `song_q1.egg`; the cleanup removes the known demo copy and
  leaves a different copy untouched (covered by the hash check); the bench default map is not the
  demo.
- **SC-002**: On the headset, the capture produces a 1920x1080 PNG that is not black and shows the
  current scene/panel; both grips held 0.5 s and the pause button each produce one; the toast
  appears and is absent from the image; a second squeeze during the cooldown does nothing.
- **SC-003**: The file exists in the external screenshots directory, has a unique name, and is
  readable after `adb pull`.
- **SC-004**: The pause overlay is absent from a pause-button shot and restored afterwards; the
  game continues normally.
- **SC-005**: The 0.6.1 APK reports 0.6.1 / 11, is not debuggable, installs over 0.6.0 with data
  kept, launches, and the new icon/menu logo are present.
- **SC-006**: Desktop capture test passes; `--import`, the settings/audio/map gates and the map
  dump still pass; no per-frame regression.
- **SC-007**: README/itch docs explain the feature and the demo removal; links resolve; the
  GitHub release and tag are published; the itch plan's demo item is marked resolved.
- **SC-008**: The screenshot action is discoverable in the pause menu and documented; a player can
  take gameplay and menu screenshots without a PC.

## Results (0.6.1)

- **Capture**: the SubViewport camera returns a 1920×1080 PNG on the headset. Device bench on
  ODDS: `screenshot_ok=true`, 309 KB, external screenshots dir, pulled and inspected. The frame
  shows the map from the player's pose; near notes/HUD/sabers were not in that particular 15 s
  frame (sparse moment + eye-line framing). The desktop menu test is non-black and shows the
  menu/source tags. FOV was raised 60° → 75° after 60° cropped the play space (departure from the
  G1 advice, recorded here).
- **Demo**: repository folder gone; HighscorePanel cover, Playlists.json, placeholders, bench
  default, PERF note updated; APK `OpenSaber-v061.apk` has no `TheFatRat`/`Timelapse`/`song_q1`
  entry (771 entries, 77,933,281 bytes). On device the folder was removed, the marker written and
  the highscore rows left in place. 0.6.0 history/asset untouched per the owner.
- **Release**: 0.6.1 / code 11, same cert `d204a2…`, no `application-debuggable`, new icon
  textures, installed over the debug 0.6.1 and launched (pid 13541). SHA-256
  `2B12DDAE091E6D1F7E4A8FACAF6D040A1F8637B39B95875B0FDC3D0480938F9E`.
- **Gates**: schema 53, panel, roundtrip, RELOAD/BPM/SUPPORT/HITAUDIO/ANALYSER, chain
  geometry/cut, mapsource, beatleader, desktop screenshot PASS. The headless screenshot test is
  expected to hang (no renderer); the windowed run passes.

### 0.6.2 scoped change: trigger combo

- **Symptom**: Quest 3 has no squeeze/grip button; the 0.6.1 grip hold cannot fire. The pause
  button and the capture service work.
- **Fix**: poll both `trigger` buttons (already used by the UI) for 0.5 s, latch/cooldown as
  before; rename `screenshot_grip` to `screenshot_trigger`; update the pause hint, README, release
  notes and the 0.6.1 release body. Version 0.6.2 / code 12.
- **SC-013**: In a menu, holding both triggers produces one 1920×1080 capture; during a song the
  same hold does nothing and the pause button captures; the setting disables the trigger combo.
- **SC-014**: The old `screenshot_grip` key is ignored (no error) and `screenshot_trigger`
  defaults to on; schema/panel gates pass with the renamed key.
- **SC-015**: 0.6.2 is installed, tagged and released; the 0.6.1 notes point to the corrected
  shortcut.

### Home tests (not proven in this session)

- In a menu, both triggers held 0.5 s produces exactly one capture; the 2 s cooldown blocks a second; the toast
  is visible and absent from the image.
- The pause-menu button captures without the pause canvas/rays and restores them.
- A 0.6.0 -> 0.6.1 upgrade (this install came over a 0.6.1 debug build) does not crash highscore or
  menu views with the demo's old rows.

## Out of scope

- Publishing to itch.io (plan only; real screenshots are now possible).
- Deleting the public 0.6.0 release or its asset (the user has not asked for that).
- BeastSaber import, leaderboard changes, other 0.6.x fixes.
- Removing the demo from a player's library when it does not match the bundled files.

## Open questions

- Resolved by the owner (2026-11-06): skip the old builds/history, document the removal as a
  0.6.1 change. The egg remains in v0.6.0 history and its public asset; no rewrite, no deletion.

The capture method is a dedicated camera; if the headset renders the SubViewport black, that is a
failed FR-004 and the plan is revisited at G1/G4, not silently replaced with a system capture.

## Consultation Log

| Gate | Asked | Verdict | Action taken |
|---|---|---|---|
| G0 | Demo removal scope, screenshot capture design, interaction, storage, 0.6.1 release | GO WITH CHANGES: remove every reference (HighscorePanel cover, Playlists.json, placeholder text, bench default), empty-state message, copy-on-first-run removal; keep highscore/play-count rows; SubViewport camera works (copy cull_mask/env/attributes, fov 60, two frame_post_draw waits, toast after, worker-thread PNG); grip hold 0.5 s + 2 s cooldown + setting; external app dir; one 0.6.1 release | Spec updated; G1 next |
| G2 | Owner decision on the old build/history | Skip the old builds/history; document the demo removal as a 0.6.1 change | FR-003/open question updated; no rewrite, no 0.6.0 asset change |

| G1 | Capture implementation (SubViewport camera/world), grip combo, cleanup, build plan | GO WITH CHANGES: encode/save on the worker; service/toast PROCESS_MODE_ALWAYS; toast on a culled layer; hide UI rays; camera added/current before pose; own_world false/MSAA; first capture may stall; bench default ODDS; marker; remove empty playlist; 53 keys; publish 0.6.1; add APK-content/pause/cooldown/highscore SCs | Implemented; spec updated |

| G4 | final review 0.6.1 @ea76a67 | APPROVE: add stall/adb/highscore lines to the release notes; tag and release | Release notes updated with the three lines; tagged/released |

| G2 | Quest 3 has no usable squeeze input; owner prefers triggers | Use both index-finger triggers; menus only (players clench them in play), pause button for gameplay; rename setting/docs; cut 0.6.2 | Implemented, installed; 0.6.2 tagged/released |

| G5 | drift FR-001..012 / SC-001..012 | Matches spec except home tests: trigger hold+cooldown, toast, pause capture, highscore after a 0.6.0 upgrade | 0.6.1 released; trigger correction in 0.6.2 |
