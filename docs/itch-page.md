# itch.io page copy

**Target build:** 0.6.3. Arcs connect and match the note colours; BeatLeader sits on the left
of the menu and BeastSaber (curated) on the right. The 0.6.0 APK still uses the previous icon and
contains the demo, so do not upload it. Publish gate and
upload steps: [itch-push.md](itch-push.md).

## Project fields

| field | value |
|---|---|
| Title | OpenSaberQ3 |
| Project URL | `open-saber-q3` |
| Classification | Game |
| Kind of project | Downloadable |
| Pricing | No payments (free) |
| Release status | In development |
| Platforms | Android |
| Genre | Rhythm |
| Tags | `vr`, `meta-quest`, `rhythm`, `open-source`, `sidequest`, `beatsaver` |
| AI disclosure | Yes — Graphics |
| Links | GitHub source, MIT licence |

## Tagline

> Open-source rhythm game for Meta Quest 3. BeatSaver maps at 120 Hz, with an in-VR browser and
> BeatLeader scores.

## Short description

> Free, MIT-licensed and sideloadable. Plays BeatSaver custom maps in v2, v3 and v4 at 120 Hz,
> filters the library by source, and shows BeatLeader scores in the menu.

## Full description

> **OpenSaberQ3** is an open-source rhythm game for Meta Quest 3, built in Godot 4.6 and based on
> [BeepSaber](https://github.com/leandrodreamer/BeepSaber) (MIT).
>
> - **120 Hz** with physics matched to the display, and Performance / Balanced / Quality presets.
> - **BeatSaver maps in v2, v3 and v4**, including the hybrid format BeatSaver serves.
> - **An in-VR map browser**: search, sort, filter and download without a PC.
> - **Source tags and a source filter** for the library, with automatic backfill for old maps.
> - **BeatLeader top 10** for the selected map and difficulty, read-only, no account.
> - Layered hit audio, per-event haptics and an optional in-game analyser.
> - **In-game screenshots**: triggers in menus, Pause → Screenshot during a song; 1920×1080 for
>   `adb pull`.
>
> Benchmark harness and raw captures: <https://github.com/testyfishy/OpenSaberQ3/blob/godot-4-port/PERF.md>.
> The shipped default holds **120 fps with 0.01% dropped frames** over three minutes (2 frames in
> 21,348), and a 2,913-note map holds **120 fps at 0.14% dropped** on Quest 3 at the Performance
> preset.
>
> **Credits.** The game, engine port and content pipeline are the work of the BeepSaber authors
> and the projects it descends from — NeoSpark314's BeepSaber and the Godot Oculus Quest Toolkit.
> This fork tunes and fixes. The full chain is in the repository's `UPSTREAM.md` and
> `ATTRIBUTION.md`.
>
> **AI-generated content: Graphics.** The logo, app icon and cover are AI-generated vector artwork,
> created with AI assistants from a design brief; the sources and provenance are in `docs/brand/`.
> The code is human-directed with AI assistance.
>
> **Install**
>
> 1. Enable **Developer Mode** for the headset in the Meta Horizon app.
> 2. Download the APK below.
> 3. `adb install -r OpenSaberQ3-0.6.3.apk`, or use SideQuest.
> 4. Launch **Open Saber Q3** from *Unknown Sources*.
>
> itch is a download host: it does not install Android apps for you. Sideloading is required.
> To take a screenshot in a menu, hold both triggers for half a second. During a song, press
> **Screenshot** in the pause menu. The PNGs are in the app's files folder for `adb pull`.
>
> **Known issues**
>
> - White highlights at chain joints are cosmetic.
> - After a long idle the headset's audio session can freeze; reboot the headset.
> - No HRTF: left/right is stereo panning, above/below is not reproduced.
> - 360°/90° lane rotation is parsed but not applied; v4 event-box groups and VFX boxes are
>   ignored.
>
> Quest 3 is the tested target. Other headsets may work but are untested.
>
> No Beat Saber assets are included. Not affiliated with or endorsed by Beat Games, Meta,
> BeatSaver or BeatLeader.
>
> Source, issues and the full measurement log: <https://github.com/testyfishy/OpenSaberQ3>

## Screenshot captions

Use these under the real captures, in this order:

1. **Mid-song on a dense map** — sabers, notes and HUD.
2. **BeatSaver browser** — search results with covers.
3. **Library by source** — the source filter and tags.
4. **BeatLeader** — the top 10 for the selected map.
5. **Settings** — the Performance preset and visual toggles.
6. **End-of-map card** — the score summary.

## Assets

| asset | spec | status |
|---|---|---|
| Cover | 630×500 | `docs/images/itch-cover.png` — ready |
| Banner | 1280×640 | `docs/images/banner.png` — ready |
| Icon | 512×512 | `docs/images/logo.png` — ready |
| Screenshots | 3–5, 16:9, 1280×720 or larger | `docs/media/gameplay-1.png` .. `gameplay-4.png` — ready |
| Gameplay clip | 15–30 s, optional but recommended | `docs/media/gameplay-0.6.3.mp4` — 24 s 1080p60 with audio |
| Upload | Android APK, 0.6.3 | built with the new icon |

The gameplay clip and stills in `docs/media/` are cut from the owner's headset recording (1920x1080,
60 fps, game audio). The menu and leaderboard renders in `docs/images/` are desktop captures with the simulator overlay;
they are not store screenshots. The gameplay clip and stills are real headset captures.
