# OpenSaberQ3

Open-source rhythm game for Meta Quest 3. Plays BeatSaver custom maps in v2, v3 and v4 formats at
120 Hz, with an in-VR map browser and BeatLeader scores. A fork of
[BeepSaber](https://github.com/leandrodreamer/BeepSaber).

[![Release](https://img.shields.io/github/v/release/testyfishy/OpenSaberQ3?label=release)](https://github.com/testyfishy/OpenSaberQ3/releases)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Godot](https://img.shields.io/badge/Godot-4.6.3-478cbf)](UPSTREAM.md)
[![Quest 3](https://img.shields.io/badge/Meta-Quest%203-1c1e21)](https://www.meta.com/quest/quest-3/)

![OpenSaberQ3](docs/images/banner.png)

**v0.6.2** — [download the APK](https://github.com/testyfishy/OpenSaberQ3/releases/latest) ·
[install](#download-and-install). Built on BeepSaber and its lineage
([credits](ATTRIBUTION.md), [pinned upstream](UPSTREAM.md)).

## Since the fork

| | BeepSaber upstream (2025-03) | OpenSaberQ3 v0.6.2 |
|---|---|---|
| **Engine** | Godot 4.3; 72 Hz, 60 Hz physics | **Godot 4.6.3**, 120 Hz with physics matched to the display, Performance / Balanced / Quality presets ([perf](docs/performance.md)) |
| **Maps** | v2 | **v2, v3 and v4**, including the hybrid BeatSaver serves and v4's split beatmap/lightshow ([43-map audit](docs/map-data-audit.md)) |
| **Library** | local folders | **In-VR BeatSaver browser** (search, sort, filter, download), a source tag on every map, **filter by source**, automatic backfill ([spec 020](specs/020-libs-leaderboards/spec.md)) |
| **Leaderboards** | none | **BeatLeader** top 10 for the selected map and difficulty, in the menu ([v0.6 report](docs/v0.6-report.md)) |
| **Hit feedback** | one hit sound | Layered hit samples, **L/R audio verified on device**, music ducking, per-event haptics, in-game analyser ([spec 011](specs/011-v03-polish/spec.md)) |
| **Hit registration** | sub-threshold swings dropped | Analytic swept-blade test; a swing that crosses the note is a hit ([spec 006](specs/006-swing-hit-sweep/spec.md)) |
| **Chains** | detached plates, spawn pop-in | Continuous links that span each segment; cut order and score covered by a test ([spec 019](specs/019-chains-dense/spec.md)) |
| **UI and settings** | HUD overlap, scroll stalls | HUD/end-card layout, smooth BeatSaver scrolling, **52 persisted settings** ([spec 016](specs/016-scroll-ui-cleanup/spec.md)) |
| **Measurement** | none | Bot and **human-play** captures, p99/max/spike metrics, release/rollback artifacts ([PERF.md](PERF.md)) |

## What's new

### v0.6.2

- **The screenshot shortcut is both triggers, not grips.** Quest 3 has no usable squeeze input;
  hold both index-finger triggers for half a second **in menus** (during a song, use Pause →
  Screenshot).

### v0.6.1

- **Screenshots from the headset.** In menus, hold both triggers for half a second; during a song,
  press **Screenshot** in the pause menu. 1920×1080 PNGs land in the app's files folder for
  `adb pull`.
- **The bundled demo is gone.** TheFatRat “Time Lapse” is no longer distributed; a library that
  still has the exact bundled copy loses it once.
- **New icon and menu logo**, the sliced-cube mark from `docs/brand/`.

### v0.6.0

- **Every map knows its source.** BeatSaver, uploaded, local or unknown, stored in a sidecar that
  survives upgrades. Filter the library by source from the main menu.
- **Old maps tag themselves.** The level hash is recomputed from the map's files, looked up on
  BeatSaver and written back. Map files are never modified.
- **BeatLeader top 10 in the menu** for the selected map and difficulty. Read-only, no account.
  Maps without a hash show a clear message.
- **Chains are one continuous line.** v0.5.1 removed the spawn animation that shrank every link
  to a dash.
- **Dense maps hold 120 fps.** 2,913 notes at 9.64 NPS: 120 fps median, 0.14% dropped
  (Quest 3, Performance preset, bot play).

![Library filtered to BeatSaver](docs/images/v06-library.png)

**Next, 0.6.3:** BeastSaber `.bplist` playlist import. The `beastsaber` tag is already in the
schema.

## Performance

| | |
|---|---|
| Dense reference map | **Somewhere Out There ExpertPlus**, 2,913 notes, 9.64 NPS |
| Delivered | **120 fps** median, App 5.0 ms, GPU 0.85 of budget |
| Dropped frames | **0.14%** steady, p99 11.4 ms |
| ODDS&ENDS ExpertPlus after the stutter fix | 0.01% dropped (2 frames in 21,348), 76.6% on time, p99 9.97 ms |
| Stress case | Gloom, 12,340 walls: **2.14% dropped**, down from 24% before wall pooling |

*Quest 3, 120 Hz, Performance preset, bot on the real collision path unless noted. Dropped = a
frame that missed a vsync slot (>= 1.5x period); on time = within 1.05x.
[Full results](docs/performance.md).*

## Download and install

The latest signed APK is on the [releases page](https://github.com/testyfishy/OpenSaberQ3/releases).
Enable **Developer mode** on the headset, then sideload with SideQuest or run:

```sh
adb install -r OpenSaberQ3-0.6.2.apk
```

Launch **Open Saber Q3** from *Unknown Sources*. Installs alongside upstream BeepSaber; songs and
scores stay separate. Upgrading over 0.5.x keeps maps, scores and settings. Builds are test-signed,
not store builds. The 0.6.2 APK carries the new icon and menu logo. Screenshots are in
`/sdcard/Android/data/io.github.testyfishy.opensaberq3/files/screenshots/`:

```sh
adb pull /sdcard/Android/data/io.github.testyfishy.opensaberq3/files/screenshots
```

The Quest Files app cannot open `Android/data`; use adb. The first capture in a session can stall
for about a second while the renderer compiles; Pause → Screenshot is the reliable still.

## Documentation

| | |
|---|---|
| [v0.6.0 release report](docs/v0.6-report.md) | Library sources, BeatLeader, device evidence, upgrade test |
| [Performance](docs/performance.md) | Frame-time trace, stutter fix, per-map walls, dense notes |
| [Changelog](docs/changelog.md) | Every release from v0.1.0 to v0.6.0 |
| [v0.3 report](docs/v0.3-report.md) | Feedback, sky, audio and layout |
| [Upstream and toolchain](UPSTREAM.md) | Pinned commit, build steps, reproducibility gaps |
| [Attribution](ATTRIBUTION.md) | Authors and asset provenance |
| [Benchmarking](tools/perf/benchmark.md) | Capture method |

## Build from source

Godot **4.6.3** + JDK 17 + Android SDK 34/36, export preset **`Oculus Quest (RELEASE)`**.
Versions, commands and known gaps: [UPSTREAM.md](UPSTREAM.md).

## Known limitations

- **No HRTF.** Left/right is stereo panning; above/below is not reproduced.
- **Quest 3 speakers roll off below ~150–200 Hz**, so hit weight sits at 200–800 Hz.
- **360°/90° lane rotation** is parsed but not applied; v4 event-box groups and VFX boxes are
  ignored. Basic lighting events are supported.
- The white highlights at chain joints are cosmetic.

## Credits and license

**Artwork:** logo, icon and banner are AI-generated vector artwork created with AI assistants
(DeepSeek V4 Flash and Claude Opus 5.5) from a design brief, reviewed by the owner; sources,
palette and provenance are in [docs/brand.md](docs/brand.md).

MIT — [LICENSE](LICENSE) retains the original copyright (© 2020 Holger Dammertz). Contains no Beat
Saber assets and does not use the Beat Saber name, logo or branding. Not affiliated with or
endorsed by Beat Games, Meta, BeatSaver or BeatLeader.
