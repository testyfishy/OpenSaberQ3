# Sharing this project

Notes for posting OpenSaberQ3 publicly. Written to be usable as-is, not as a plan to refine later.

## Before posting: the honest state

Say these things up front, because they are true and because getting caught overclaiming is worse
than being unexciting:

- **It is a fork** of BeepSaber, MIT, no Beat Saber assets. Credit is in the README and
  `ATTRIBUTION.md`.
- **Quest 3 only for now.** 120 Hz with a measured frame budget; other headsets work but are
  untested.
- **What is solid:** every map format (v2/v3/v4), the in-VR BeatSaver browser, the benchmark
  harness and its published numbers.
- **What is in flux:** wall-heavy maps still stutter (fix implemented, verification pending), the
  HUD has overlap bugs, and hit audio is being redesigned. Say so — bug reports from people who
  know that are useful; bug reports that "the game stutters on Gloom" are not news.
- **Ask for the thing you want:** play tests on dense/wall-heavy maps, and reports of the
  intermittent red dot at screen centre.

## Ready-to-use blurb

> **OpenSaberQ3 — a Quest 3 focused fork of BeepSaber (MIT)**
>
> A Beat Saber-style rhythm game built in Godot 4.6, tuned for the Quest 3: 120 Hz with a measured
> frame budget, native panel resolution, v2/v3/v4 map support, and an in-game BeatSaver browser so
> you can download maps without a PC.
>
> It is measured rather than asserted. The repo publishes the harness, the raw numbers and the
> failures — including the optimisation I thought worked that turned out to be inside the noise.
> Current default holds 120 fps with **0.01% dropped frames** over three minutes.
>
> Free, MIT, sideload the APK. No Beat Saber assets, not affiliated with Beat Games or Meta.
>
> Known rough edges: wall-heavy maps stutter (being fixed), some HUD text overlaps, and hit audio
> needs another pass. Play tests very welcome.

## Where to post, in rough order of value

| place | why | notes |
|---|---|---|
| **BSMG Discord** (`discord.gg/beatsabermods`) | the people who actually care about map formats and modding | introduce it in a project/showcase channel, not in support channels |
| **r/OculusQuest** | the largest Quest user base; sideloaded projects get attention | follow self-promotion rules; post as a free project with a video GIF |
| **r/oculus** | broader VR audience | lower hit rate but wider reach |
| **SideQuest** | users who sideload by default; a listing is a durable discovery channel | needs an APK upload and a cover image |
| **r/vrdev** | developers who will appreciate the measurement angle | lead with the benchmark harness, not the game |
| **Hacker News** (Show HN) | the "measured, not asserted" angle travels well there | needs a short, non-hyped title; expect scrutiny of the fork's lineage |
| **r/beatsaber** | the obvious audience | check rules first — many subreddits restrict non-Beat-Saber game posts |

Avoid posting to several at once on the same day: the same text appearing everywhere reads as spam
and gets removed.

## Assets worth having before the first post

1. **A 15–30 s clip** of real play on a dense map. A screenshot does not sell a VR rhythm game.
2. **A cover image** for SideQuest (square, 1024×1024).
3. **The frame-time figure** from the README — it is the differentiator, and it invites the
   "how did you measure that?" conversation that is the whole point.

## What to ask for

- Which maps feel bad, with names. The per-map matrix exists precisely to act on that.
- Headset model if it is not a Quest 3.
- Whether the red dot appears, and when.

## What not to claim

- "Beat Saber alternative" — different lineage, different feature set, and it invites a comparison
  the project does not win yet.
- "Optimised" without the number: say 120 fps / 0.01% dropped / p99 9.97 ms.
- "Supports all maps" before the wall fix is verified. Say v2/v3/v4 formats and name the known
  wall-heavy problem.
