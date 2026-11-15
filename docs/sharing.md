# Sharing this project

Notes for posting OpenSaberQ3 publicly.

## Before posting: the current state

- **It is a fork** of BeepSaber (MIT); this fork is GPLv3. No Beat Saber assets. Credit is in the README and
  `ATTRIBUTION.md`.
- **Quest 3 only for now.** 120 Hz with a measured frame budget; other headsets work but are
  untested.
- **What is solid:** v2/v3/v4 map formats, the in-VR BeatSaver browser, source tags and the source
  filter, BeatLeader top 10, and the benchmark harness with its published numbers.
- **What is in flux:** the BeastSaber `.bplist` import is next (0.6.1); v0.6.0 is the current
  build. Home-test findings go into 0.6.x.
- **Ask for:** play tests on dense and wall-heavy maps, map names for anything that stutters, and
  whether the source filter and leaderboard behave on the headset.

## Ready-to-use blurb

> **OpenSaberQ3 - a Quest 3 focused fork of BeepSaber (MIT)**
>
> A Beat Saber-style rhythm game built in Godot 4.6, tuned for the Quest 3: 120 Hz with a measured
> frame budget, v2/v3/v4 map support, an in-game BeatSaver browser, source tags, and BeatLeader
> scores.
>
> The repo publishes the harness, the raw numbers and the failures. The current default holds
> 120 fps with **0.01% dropped frames** over three minutes, and a 2,913-note map holds 120 fps at
> **0.14% dropped**.
>
> Free, GPLv3, sideload the APK. No Beat Saber assets, not affiliated with Beat Games or Meta.
>
> Known rough edges: no HRTF; the white highlights at chain joints are cosmetic; audio can freeze
> after a long idle and needs a headset reboot. Play tests very welcome.

## Where to post, in rough order of value

| place | why | notes |
|---|---|---|
| **BSMG Discord** (`discord.gg/beatsabermods`) | the people who actually care about map formats and modding | introduce it in a project/showcase channel, not in support channels |
| **r/OculusQuest** | the largest Quest user base; sideloaded projects get attention | follow self-promotion rules; post as a free project with a video GIF |
| **r/oculus** | broader VR audience | lower hit rate but wider reach |
| **SideQuest** | users who sideload by default; a listing is a durable discovery channel | needs an APK upload and a cover image |
| **r/vrdev** | developers who will appreciate the measurement angle | lead with the benchmark harness, not the game |
| **Hacker News** (Show HN) | the "measured, not asserted" angle travels well there | needs a short, non-hyped title; expect scrutiny of the fork's lineage |
| **r/beatsaber** | the obvious audience | check rules first - many subreddits restrict non-Beat-Saber game posts |

Avoid posting to several at once on the same day: the same text appearing everywhere reads as spam
and gets removed.

## Assets worth having before the first post

1. **A 15-30 s clip** of real play on a dense map. A screenshot does not sell a VR rhythm game.
2. **A cover image** for SideQuest (square, 1024x1024).
3. **The frame-time figure** from the README - it is the differentiator, and it invites the
   "how did you measure that?" conversation that is the whole point.

## What to ask for

- Which maps feel bad, with names. The per-map matrix exists precisely to act on that.
- Headset model if it is not a Quest 3.
- Whether the source filter and BeatLeader behave on the headset.

## What not to claim

- "Beat Saber alternative" - different lineage, different feature set, and it invites a comparison
  the project does not win yet.
- "Optimised" without the number: say 120 fps / 0.01% dropped / p99 9.97 ms.
- "Supports every map" without checking. Say v2/v3/v4 formats; the per-map numbers are on the
  tested maps.
