# Changelog

Every Quest 3 build of this fork. The upstream BeepSaber lineage is pinned in
[UPSTREAM.md](../UPSTREAM.md). GitHub releases carry the signed APKs; the `-q3` suffix exists
because upstream already uses tags such as `v0.4` and `v0.5`.

## v0.6.1 — 2026-11-06

**Screenshots and a clean build.** In-game capture: hold both grips for 0.5 s or press
**Screenshot** in the pause menu; 1920×1080 PNGs are saved for `adb pull` (F12 on desktop). The
bundled TheFatRat “Time Lapse” demo is removed from the build, and a library that still holds the
exact bundled copy loses it once. The sliced-cube icon and menu logo ship here.
[Release](https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.6.1-q3) ·
[Spec](../specs/024-shot-demo-061/spec.md)

## v0.6.0 — 2026-11-06

**Library sources and BeatLeader.** A source tag on every map (BeatSaver, BeastSaber, uploaded,
local, unknown) written to a sidecar, a source filter in the main menu, and an automatic backfill
that recomputes the Beat Saber level hash and looks old maps up on BeatSaver. Read-only BeatLeader
top 10 for the selected map and difficulty, with no account. Both were verified on the headset;
the dense map still holds 120 fps with 0.14% dropped (Quest 3, default preset).
[Release](https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.6.0-q3) ·
[Report](v0.6-report.md) · [Spec](../specs/020-libs-leaderboards/spec.md)

## v0.5.1 — 2026-11-06

**Chains connect.** The translucent line between notes was made of detached plates because the
authored spawn animation shrank every link to 10% and pulled it 2 m back. Links now span their
exact segment, the hitbox matches, and a test cuts a whole chain in head-to-tail order. The same
release verified a 2,913-note, 9.64 NPS map at 120 fps instead of guessing at the reported stutter.
[Release](https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.5.1-q3) ·
[Spec](../specs/019-chains-dense/spec.md)

## v0.5.0 — 2026-11-06

**Map data and audio direction.** The map-data audit checked 43 real BeatSaver maps across v2, v3
and v4; the loader now honours the data those maps actually declare. Hit audio was verified on the
headset: 13 of 13 lateral hits put more energy on the cube's own side, with music ducking and an
in-game analyser. v2, v3 and v4 maps all load on device.
[Release](https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.5.0-q3) ·
[Spec](../specs/018-v05-release/spec.md)

## v0.3 work (shipped in v0.4.0) — 2026-11-05

**Feedback, sky and frame stability.** Layered hit samples and per-event haptics replaced the
single buzz; the sky became selectable (void default) with explicit ambient light; HUD/end-card
layout was fixed; the real stutter bug (two `global_transform` reads per note per tick) was found
and fixed; walls moved to a pool. The full write-up is the [v0.3 report](v0.3-report.md) and
[performance page](performance.md).

## v0.4.0 — 2026-11-05

**UI and code quality.** HUD overlap and the end-of-map card were rebuilt, the BeatSaver list
scrolls smoothly (measured as a per-frame delta sequence), and the codebase went through the
quality pass. A miss now draws a 28 pt red X at the miss point; the old 6 pt marker was the
reported "red dot". Version code 7; upgrade over 0.3 kept settings and songs.
[Release](https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.4.0-q3) ·
[Spec](../specs/017-v04-release/spec.md)

## v0.2.0 — 2026-11-02

**Every map format, a BeatSaver browser and a real 120 Hz default.** v2/v3/v4 maps, including the
hybrid BeatSaver serves and v4's split beatmap/lightshow; in-VR search/download; a LAN upload page;
ten visual options; bloom removed. 120 Hz with physics matched to the display.
[Release](https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.2.0-q3)

## v0.1.1 — 2026-11-02

**Recenter fix.** The Meta recenter button now re-orients the play space and menu instead of
leaving them rotated.

## v0.1.0 — 2026-11-02

**Quest 3 baseline.** The fork's first release: Quest 3 toolchain, hit-registration fixes, layered
audio research, the benchmark harness, and the first measured Quest 3 numbers.

## Next

- **0.6.2** — BeastSaber playlist (`.bplist`) import.
- **0.6.x** — home-test findings and cosmetic chain joints.
