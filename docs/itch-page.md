# itch.io page copy

**Target build:** 0.77.1. It is 0.77.0 with a signing-password change only; the gameplay is the
same. Features and limits come from the README (What's new v0.77.0, Map compatibility, Known
limitations, Performance) and [changelog.md](changelog.md). Publish gate and upload steps:
[itch-push.md](itch-push.md). The SideQuest version of this copy is in
[sidequest-page.md](sidequest-page.md).

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
| AI disclosure | Yes — Graphics, Code (use the category names itch shows on the form) |
| Links | GitHub source, GPL-3.0 licence, GitHub Issues for feedback |

## Tagline

> Free, open-source rhythm game for Meta Quest 3. Play BeatSaver custom maps at 120 Hz, including
> animated maps.

## Short description

> Sideloadable and GPL-3.0. Plays BeatSaver maps in v2, v3 and v4 at 120 Hz, with an in-VR map
> browser, BeatLeader scores and per-song modifiers.

## Full description

> **OpenSaberQ3** is a free, open-source rhythm game for Meta Quest 3. You cut blocks to the beat
> of custom maps from BeatSaver.
>
> This project is vibe coded. It was built as a hobby with multiple AI coding agents, from the
> original BeepSaber fork, in the Godot engine. Not every line has been reviewed by a human.
>
> **What it does**
>
> - **120 Hz**, with physics matched to the display. Performance, Balanced and Quality presets.
> - **BeatSaver maps in v2, v3 and v4**, including the hybrid format BeatSaver serves.
> - **Animated maps.** Noodle Extensions tracks, path animation, parent tracks, dissolve and fake
>   objects play. Animated maps have a badge and a filter in the song list.
> - **Notes move the way the map says.** Each difficulty's own note jump speed and spawn distance
>   are used. Notes fly in from the distance, then jump.
> - **Per-song modifiers.** Note Speed, Strict cuts and No Fail are set on each song. Making a
>   song easier lowers the score multiplier, shown before you start.
> - **Arcs** follow their curve between two notes and are drawn over walls.
> - **An in-VR map browser.** Search, sort, filter and download maps without a PC.
> - **BeatLeader top 10** for the selected map and difficulty. Read-only, no account.
> - **A compatibility badge on every map**: Supported, Partial or Visuals limited.
>
> **Performance**
>
> On Quest 3 at 120 Hz with the Performance preset, played by the bot:
>
> - a 2,913-note map (Somewhere Out There ExpertPlus) runs at a 120 fps median with 0.14%
>   dropped frames;
> - ODDS&ENDS ExpertPlus drops 2 frames in 21,348 (0.01%).
>
> Full results: <https://github.com/testyfishy/OpenSaberQ3/blob/godot-4-port/docs/performance.md>
>
> **Install**
>
> 1. Turn on **Developer Mode** for the headset in the Meta Horizon app.
> 2. Download `OpenSaber-v0.77.1.apk` below.
> 3. Install it with SideQuest, or run `adb install -r OpenSaber-v0.77.1.apk`.
> 4. Launch **Open Saber Q3** from *Unknown Sources*.
>
> itch only hosts the file. It does not install Android apps for you, so sideloading is required.
> Quest 3 is the tested headset. Others may work but are untested.
>
> **Known issues**
>
> - Above/below sound uses a simple elevation cue, not full HRTF.
> - Animated maps: player (head and hand) tracks, the `time` property and Chroma environment
>   objects are not played. Arcs and chains do not follow an animated head note. Vivify maps play
>   their notes without the bundled visuals.
> - Hundreds of walls in one beat can still drop a few frames. The busiest animated stretches run
>   near 105 fps rather than 120.
> - v4 per-object rotation and VFX event boxes are not read.
> - The white highlights at chain joints are cosmetic.
>
> **Feedback**
>
> Bugs, map problems and ideas go to GitHub Issues:
> <https://github.com/testyfishy/OpenSaberQ3/issues>
>
> **Credits and licence**
>
> OpenSaberQ3 is GPL-3.0. It is a fork of [BeepSaber](https://github.com/leandrodreamer/BeepSaber)
> (MIT), which descends from NeoSpark314's BeepSaber and the Godot Oculus Quest Toolkit. The
> original MIT notice is kept and still covers the upstream code. The full chain is in the
> repository's `UPSTREAM.md` and `ATTRIBUTION.md`.
>
> The logo, app icon and cover are AI-generated vector artwork, reviewed by the owner. Sources and
> provenance are in `docs/brand.md`.
>
> No Beat Saber assets are included. Not affiliated with or endorsed by Beat Games, Meta,
> BeatSaver or BeatLeader.
>
> Source code: <https://github.com/testyfishy/OpenSaberQ3>

## Screenshot captions

The current stills come from an older build (0.7.3x, an animated map). Use these captions under
them, and swap in the menu captions once 0.77 captures exist:

1. `still-40.jpg`: **An animated map**. Notes fly in through the map's own scene.
2. `still-80.jpg`: **The map's scene changes colour** mid-song.
3. `still-160.jpg`: **A burst of notes**, with combo and accuracy on the HUD.
4. `still-88.jpg`, `still-280.jpg`: spares.

For later 0.77 captures:

- **BeatSaver browser**: search results with covers.
- **Song panel**: Note Speed, Strict cuts, No Fail and the score multiplier.
- **BeatLeader**: the top 10 for the selected map.

## Assets

| asset | spec | status |
|---|---|---|
| Cover | 630×500 | `docs/images/itch-cover.png` — ready |
| Banner | 1280×640 | `docs/images/banner.png` — ready |
| Icon | 512×512 | `docs/images/logo.png` — ready |
| Screenshots | 3–5, 16:9, 1280×720 or larger | local `store-media/still-40.jpg`, `still-80.jpg`, `still-88.jpg`, `still-160.jpg`, `still-280.jpg` (1920×1080) — provisional; replace with 0.77 footage when available |
| Gameplay clip | 15–30 s, optional but recommended | local `store-media/gameplay-clip.mp4` (27 s, 1080p60, game audio) — provisional; replace with 0.77 footage when available |
| Upload | Android APK, 0.77.1 | `OpenSaber-v0.77.1.apk` |

The clip and stills are cut from the owner's headset recording of an older build (0.7.3x, an
animated map). They are kept in `store-media/`, which is excluded from git. The renders in
`docs/images/` other than the cover, banner and icon are desktop captures, not store screenshots.
