# Feature Specification: v4 release preparation

**Feature Branch**: `014-v4-release`

**Created**: 2026-11-04

**Status**: Draft

**Input**: The player skipped v0.3 testing and asked for v4 to be finished and prepared for a live
headset test in a few hours: "finish everything up and prepare the v4 for me".

## Intent

v4 currently carries the v0.3 feature set plus three verified changes (one speed formula, one
Chroma colour parser, a rebuilt wall material). The full refactor (Map split, pooled nodes,
scene-unique names, settings schema) is multi-session work. This sheet scopes the session to what
the player can actually test tonight: a stable v4 build, installed, with the maps they know, and a
checklist for the live session.

## Requirements

- **FR-001**: `v4/cleanup` MUST compile cleanly (no parse or shader errors) and pass the harness
  gates it already has: the 45-map dump, the settings round-trip, and the replay determinism check.
- **FR-002**: The new wall material's worst-case fill MUST be measured or explicitly deferred with
  the reason recorded (scroll `SC-014` in `specs/013-code-quality/spec.md`).
- **FR-003**: An APK MUST be built from `v4/cleanup` and installed on the Quest 3, replacing the
  v0.3 build (the player has approved skipping v0.3).
- **FR-004**: The app MUST launch on the headset and play ODDS without script errors; the four
  bench maps (ODDS, Gloom, Somewhere Out There, Empires) MUST be present.
- **FR-005**: A short live-test checklist MUST exist covering: walls look, wall visibility of notes
  through walls, glow setting, debris, environment palette per map, hit sound, end card.
- **FR-006**: The docs MUST state plainly which refactor slices are in this build and which are
  still pending, so the test build is not mistaken for the finished refactor.
- **FR-007**: Before installing, the headset's `user://` data MUST be backed up (`adb pull`) and the
  v0.3 APK kept on disk for rollback; the install MUST use `adb install -r` with the same package
  id so downloaded maps and scores survive.
- **FR-008**: A settings file written by v0.3 MUST load in v4 without errors, ignoring unknown keys
  and defaulting new ones (glow, debris, environment).
- **FR-009**: A device frame capture (p99, max, frames over 1.5x period) MUST exist for a 30 s ODDS
  bot run on the installed v4 build, and the worst-case wall run MUST be measured at the same time;
  if p99 regresses by more than ~10% against the recorded baseline, the wall cost comes down before
  the player sees it.

## Success criteria

- **SC-001**: `godot --headless --quit` reports zero script/shader errors on `v4/cleanup`.
- **SC-002**: Map dump over 45 maps is identical to the recorded baseline. CLEAN BASELINE
  REGENERATED 2026-11-04: 45/45 maps, 0 failures, SHA256
  `E2E7AFC83971745B991632710E92EE4EC3DB81B6ACB7B0C1049769FD4684A123`.
- **SC-003**: Settings round-trip prints `SETTINGSTEST PASS`.
- **SC-004**: Replay three consecutive runs produced IDENTICAL logs on 2026-11-04
  (SHA256 `3078AB2F19031D22CA8736D0B3C8A634D9F331065217E8ED9A41DEDD63E51C00`, 1,441 frames,
  22 events). The earlier divergence was not reproduced; the gate is green.
- **SC-005**: APK installs, launches, and a 30 s bot run on ODDS completes with no script errors.
- **SC-006**: The wall check renders as a translucent panel with a rim (visual evidence).
- **SC-007**: The live-test checklist is committed and points at the maps on the device.
- **SC-008**: The device capture exists and p99 is within ~10% of the recorded v0.3 baseline.
- **SC-009**: Debug overlays, the audio analyser and bench UI are off in the release build.
- **SC-010**: A v0.3 `config.ini` loads in v4 with known keys preserved.

## Out of scope

- The `Map.gd` split, `PooledNode3D` unification, scene-unique names and the settings schema -
  these are the remaining v4 slices and are not required for a playable test build.
- Bench tooling exclusion from the export (build-size work, no gameplay effect).
- Any change to map format support or scoring.

## Open questions

- Closed by G0: measure the wall worst case on the headset immediately after install; if p99
  regresses more than ~10% against the baseline, reduce wall alpha/rim cost before the live test.

## Consultation Log

| Gate | Asked | Verdict | Action taken |
|---|---|---|---|
| G0 | Scope of a same-day v4 test build | GO WITH CHANGES: acceptable as a documented partial refactor; back up user data and keep v0.3 for rollback; install with `-r`; verify a v0.3 settings file loads; capture a 30 s ODDS frame run and the worst-case wall run, with a 10% p99 threshold; debug overlays off | FR-007..009, SC-008..010 added; open question closed |
