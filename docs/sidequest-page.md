# SideQuest listing copy

**Target build:** 0.77.1 (versionCode 58), the same APK as the itch page: `OpenSaber-v0.77.1.apk`.
It is 0.77.0 with a signing-password change only. The content matches
[itch-page.md](itch-page.md); this file shapes it for a SideQuest listing.

Nothing has been submitted. SideQuest's form changes over time, so the field names below are
descriptive. Where a limit or image size is not written here, **check on the form**; nothing here
is a confirmed SideQuest number.

## Fields

| field | value |
|---|---|
| App name | OpenSaberQ3 |
| Package name | `io.github.testyfishy.opensaberq3` (read from the APK on upload) |
| Version | 0.77.1 |
| Price | Free |
| Category | Games (check on the form for a rhythm or music sub-category) |
| Tags | VR, Rhythm, Music, Open Source, Free (pick the closest the form offers; check on the form) |
| Supported headsets | Quest 3 (tested). Other Quest headsets: untested, so do not tick them unless tested. |
| Source code / website | <https://github.com/testyfishy/OpenSaberQ3> |
| Support / feedback | <https://github.com/testyfishy/OpenSaberQ3/issues> |
| Licence | GPL-3.0 |
| AI-generated content | If the form asks: yes, the artwork and the code (check on the form for the wording) |

## Short description

Check on the form for the character limit. Two lengths:

> Free, open-source rhythm game for Meta Quest 3. Play BeatSaver custom maps at 120 Hz, including
> animated maps.

> Open-source rhythm game. BeatSaver maps at 120 Hz.

## Long description

> **OpenSaberQ3** is a free, open-source rhythm game for Meta Quest 3. You cut blocks to the beat
> of custom maps from BeatSaver.
>
> This project is vibe coded. It was built as a hobby with multiple AI coding agents, from the
> original BeepSaber fork, in the Godot engine. Not every line has been reviewed by a human.
>
> **What it does**
>
> - 120 Hz, with physics matched to the display. Performance, Balanced and Quality presets.
> - BeatSaver maps in v2, v3 and v4, including the hybrid format BeatSaver serves.
> - Animated maps: Noodle Extensions tracks, path animation, parent tracks, dissolve and fake
>   objects play. Animated maps have a badge and a filter in the song list.
> - Notes move the way the map says: each difficulty's own note jump speed and spawn distance.
> - Per-song modifiers: Note Speed, Strict cuts and No Fail. Making a song easier lowers the score
>   multiplier, shown before you start.
> - Arcs follow their curve between two notes and are drawn over walls.
> - An in-VR map browser: search, sort, filter and download maps without a PC.
> - BeatLeader top 10 for the selected map and difficulty. Read-only, no account.
> - A compatibility badge on every map: Supported, Partial or Visuals limited.
>
> **Performance**
>
> On Quest 3 at 120 Hz with the Performance preset, played by the bot, a 2,913-note map runs at a
> 120 fps median with 0.14% dropped frames. Full results are in the repository.
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
> Quest 3 is the tested headset. Others may work but are untested.
>
> **Feedback**
>
> Bugs, map problems and ideas go to GitHub Issues:
> https://github.com/testyfishy/OpenSaberQ3/issues
>
> **Credits and licence**
>
> OpenSaberQ3 is GPL-3.0. It is a fork of BeepSaber (MIT), which descends from NeoSpark314's
> BeepSaber and the Godot Oculus Quest Toolkit. The original MIT notice is kept and still covers
> the upstream code. The logo, app icon and cover are AI-generated vector artwork, reviewed by the
> owner.
>
> No Beat Saber assets are included. Not affiliated with or endorsed by Beat Games, Meta,
> BeatSaver or BeatLeader.
>
> Source code: https://github.com/testyfishy/OpenSaberQ3

## Media

| media | what to upload | size |
|---|---|---|
| App icon | `docs/images/logo.png` | 512×512 as made; check on the form for the required size |
| Cover / banner | `docs/images/banner.png` (or `docs/images/cover.png`, same size) | 1280×640 as made; check on the form for the required size and crop |
| Screenshots | `store-media/still-40.jpg`, `still-80.jpg`, `still-160.jpg` (spares: `still-88.jpg`, `still-280.jpg`) | 1920×1080; check on the form for count and size |
| Video | `store-media/gameplay-clip.mp4` (27 s, 1080p60, game audio); the form may want a YouTube link instead | check on the form |
| APK | `OpenSaber-v0.77.1.apk` | 82,473,900 bytes |

The clip and stills are provisional; replace them with 0.77 footage when available. They are cut
from the owner's headset recording of an older build (0.7.3x, an animated map) and are kept in
`store-media/`, which is excluded from git. Screenshot captions are in
[itch-page.md](itch-page.md#screenshot-captions).

## Before submitting

- Same gate as [itch-push.md](itch-push.md) section 1: APK checks, copy, no Beat Saber name in
  the app name, tags or media, conditions on every performance number.
- Do not use "Beat Saber" as a tag or keyword.
- Submit only after the owner signs off on the listing preview.
