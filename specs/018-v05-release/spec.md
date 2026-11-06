# Feature Specification: finish the v0.5 verification and cut the release

**Feature Branch**: `018-v05-release`

**Created**: 2026-11-06

**Status**: In progress (G0 approved with changes)

**Input**: Player: "Finish the mapdata and audio L/R sample first. Then prepare a finalized shipped
build as v5. Then I can test it at home."

## Why

Parts 1-9 of the cleanup are done, but two verification items were left open and the shipped APK
is still the v0.4.0 tag from before the audio, MapData, view-state and bench work. This release
closes the two gaps and makes the finished tree the artifact the player tests at home.

## Requirements

- **FR-001**: The post-release build MUST load a **v2, a v3 and a v4** map on the headset with no
  script/loader errors, and record the map load time and the time from load end to the first
  spawned note for each. These numbers are the new baseline (the old build had no timestamp).
- **FR-002**: The audio L/R check MUST have a meaningful sample: at least **10 lateral hits**
  (`|x| > 0.3 m` in the camera frame) inside the capture window, and at least **90%** of them must
  put more energy on the channel that matches the cube's side (sign of L-R equals sign of x). The
  capture window MUST cover the whole run whose hits are counted (a 25 s probe on a 30 s run, or
  an explicit filter).
- **FR-003**: The release MUST report version name `0.5.0` and version code `8` in project.godot
  and both Android presets, and be exported with the `Oculus Quest (RELEASE)` preset.
- **FR-004**: The APK MUST be verified (badging: 0.5.0 / 8 / not debuggable; same signing key;
  `install -r` over 0.4.0 keeps data; boots and logs no script errors) before it is called final.
- **FR-005**: The version bump MUST be committed on `v4/cleanup`, tagged **`v0.5.0-q3`**
  (annotated; `v0.5.0` is upstream's), and `godot-4-port` fast-forwarded to it. No push.
- **FR-006**: The v0.3 rollback and v0.4.0 APK MUST be kept. The known deviations stay recorded:
  bench scripts ship but are unreachable in release (Godot does not apply `exclude_filter` to
  resources), and the ducking attack is one frame (8-14 ms).
- **FR-007**: The **release** APK MUST ignore the bench: with a valid flag file on the device, a
  fresh launch writes no bench meta/CSV and logs no `BENCH` line.
- **FR-008**: The upgrade MUST keep user data: the same signing key, `install -r` over 0.4.0 with
  no uninstall, and the existing 49-key config MUST load with the new keys at their defaults
  (`audio_ducking` true, `audio_analyser` false). The config is read back on the debug build of
  the same commit; the release build then installs over it.
- **FR-009**: The bench numbers for FR-001/FR-002 MUST come from the **debug** build of the tagged
  commit (the release build intentionally cannot run benches); the shipped file is the release
  export of the same commit.

## Success criteria

- **SC-001**: Three device runs (v2, v3, v4) complete with `exit_reason=duration`, non-zero
  samples, no loader errors, and record `map_load_ms` / `first_note_ms` in the bench meta.
- **SC-002**: The L/R analysis reports n >= 10 lateral hits and >= 90% agreement.
- **SC-003**: `aapt dump badging` shows 0.5.0 / 8 and no `application-debuggable`; the device
  reports 0.5.0 after `install -r`; the app launches.
- **SC-004**: `git tag --list v0.5.0-q3` shows the annotated tag; `git rev-list --count
  godot-4-port..v4/cleanup` is 0; no push.
- **SC-005**: The device reports versionName 0.5.0 / versionCode 8 and not debuggable; the menu or
  package dump shows 0.5.0; the release launch with a bench flag writes nothing.

## Out of scope

- Uploading to a store, a new signing key, and any further feature work.
- Re-running the player's menu/analyser eye-check (the player does that at home).

## Open questions

None.

## Consultation Log

| Gate | Asked | Verdict | Action taken |
|---|---|---|---|
| G0 | Verification scope and release mechanics for v0.5.0 | GO WITH CHANGES: add FR-007 (release ignores bench), FR-008 (upgrade keeps data/config), SC-005 (version visible); benches run on the DEBUG build of the same commit; log first-note scheduled beat and a spawn-lag bound; L/R must drop overlapping-hit windows | Added as FR-007..FR-009 and SC-005; plan unchanged otherwise |
