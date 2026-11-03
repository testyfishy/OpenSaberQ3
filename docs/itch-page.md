# itch.io page — draft

Everything below is ready to paste. The one thing still needed is **screenshots from the headset**;
the desktop simulator shot has a keyboard overlay and does not represent the game.

## Project fields

| field | value |
|---|---|
| Title | OpenSaberQ3 |
| Project URL | `open-saber-q3` |
| Classification | Game |
| Kind of project | Downloadable |
| Pricing | No payments (free) |
| Release status | Released (or In development until the wall fix is verified) |
| Platforms | Android |
| Tags | `vr`, `oculus-quest`, `rhythm`, `godot`, `beat-saber-like`, `open-source`, `sideload` |

## Tagline (itch allows ~120 characters)

> A Beat Saber-style rhythm game for Quest 3, built in Godot: 120 Hz, every map format, maps
> downloaded in-headset.

## Short description

> Free, MIT-licensed, side-loadable. Native Quest 3 rendering at 120 Hz, v2/v3/v4 Beat Saber map
> support, and a built-in BeatSaver browser so you can search and download maps without a PC.

## Full description

> **OpenSaberQ3** is an open-source rhythm game for the Meta Quest 3, forked from
> [BeepSaber](https://github.com/leandrodreamer/BeepSaber) (MIT) and rebuilt around a measured frame
> budget rather than guesswork.
>
> **What it does**
>
> - Runs at **120 Hz** with the render resolution, MSAA and physics tuned per headset, and a
>   Performance / Balanced / Quality preset if you prefer a different trade.
> - Loads **v2, v3 and v4 Beat Saber maps**, including the mixed format BeatSaver actually serves.
> - **Searches and downloads BeatSaver maps from inside the headset** — no PC, no cable.
> - Has a **local upload page** if you would rather drop a zip in from a browser on your network.
> - Ten visual options, each with its own switch, applied without restarting.
>
> **How it is measured**
>
> Every claim in the repository has a capture behind it, taken with the project's own benchmark
> harness on a Quest 3. The shipped default holds **120 fps with 0.01% dropped frames over three
> minutes** (2 frames in 21,348), p99 frame time 9.97 ms against an 8.33 ms budget. The harness, the
> raw numbers and the failures are all published in the repo.
>
> **Known rough edges** — please read before downloading
>
> - **Wall-heavy maps stutter.** Maps with thousands of obstacles (e.g. "Gloom", "Somewhere Out
>   There") drop frames on the current release. A fix is implemented and being verified.
> - Some HUD text overlaps at the bottom right, and the end-of-map card does not lay out cleanly.
> - Hit audio is serviceable but still being redesigned; haptics were reworked recently.
> - Quest 3 is the tested target. Other headsets will probably work, but are untested.
>
> **Install**
>
> 1. Enable Developer Mode for your headset in the Meta Horizon app.
> 2. Download the APK below.
> 3. `adb install -r OpenSaberQ3.apk`, or use a sideloading tool.
> 4. Launch **Open Saber Q3** from Unknown Sources.
>
> No Beat Saber assets are included, and this project is not affiliated with Beat Games or Meta.
>
> Source, issues and the full measurement log: <https://github.com/testyfishy/OpenSaberQ3>

## Assets

| asset | spec | status |
|---|---|---|
| Cover image | 630×500 minimum (itch recommends 630×500) | `docs/images/itch-cover.png` — done |
| Screenshots | 3–5, 16:9, 1280×720 or larger | **needs headset capture** |
| Gameplay GIF/video | optional but strongly recommended | needs headset capture |
| Upload | `build/OpenSaberQ3-<version>.apk` (~84 MB) | built per release |

Screenshot list worth taking, in order:

1. Mid-song on a dense map, sabers and notes visible, HUD readable.
2. The BeatSaver browser with results and covers.
3. Settings, showing the Performance preset and the visual toggles.
4. End-of-map score card.

## Publish checklist

- [ ] Headset capture: screenshots + a 15–30 s clip.
- [ ] Tag the release in git and rebuild the APK from that tag.
- [ ] Verify the APK installs cleanly on a headset that already has an older build.
- [ ] Confirm the known-issues text matches what is actually true at that commit.
- [ ] Upload the APK, set the version string, mark Android.
- [ ] Paste the description above, add tags, set the cover image.
- [ ] Publish, then link the itch page from the GitHub README and the release notes.

## Notes

- itch.io does not install Android apps for the user; it is a download host. Say "sideload" plainly
  so nobody expects a store install.
- Do not claim "all maps supported" until the wall fix is verified.
- If the page goes up before v0.3 lands, set **Release status: In development** and say which
  release the download is.
