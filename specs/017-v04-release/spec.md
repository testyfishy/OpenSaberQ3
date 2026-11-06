# Feature Specification: v0.4 release cut

**Feature Branch**: `017-v04-release`

**Created**: 2026-11-05

**Status**: Done - tagged `v0.4.0-q3`, `godot-4-port` fast-forwarded, not pushed

**Input**: Player: "bump", "proper. the debug version is only for us", "not yet" (no upload),
"whatever makes more sense and safer" (branch/tag), "it's a backup" (rollback APK stays).

## Why

The UI cleanup (spec 016, parts 1-4) is complete, approved and verified on the device. The next
step is a release build of the code that is now on `v4/cleanup`, because the APK on the headset is
a debug build labelled 0.3.0. Parts 5-9 of the cleanup start after this release.

## Requirements

- **FR-001**: The project and both Android export presets MUST report version name `0.4.0` and
  version code `7` (up from `0.3.0` / `6`), so the release installs over the current build.
- **FR-002**: The shipped artifact MUST be an export of the **`Oculus Quest (RELEASE)`** preset to
  `F:\Dev\BeepSaberBin\OpenSaber-v04.apk`. The debug preset is a development artifact and MUST NOT
  be the release file.
- **FR-003**: The APK MUST be verified before it is called a release: version name/code read back
  from the package, the signing certificate is the one the installed build already uses (so
  `adb install -r` upgrades in place), it installs and launches on `2G0YC1ZF9J0G2V`, and the
  reported version on device is `0.4.0`.
- **FR-004**: The version bump MUST be committed on `v4/cleanup`, tagged **`v0.4.0-q3`**
  (annotated; `v0.4` is an upstream BeepSaber tag and must not be reused), and `godot-4-port`
  fast-forwarded to that commit. No merge commit, no history rewrite, and **no push**. Record
  `godot-4-port`'s old SHA (`7fff5d36208d5a9c891222ddd55926e519057a49`) so the merge is
  reversible. The fork's 0.4.0 is below upstream's 0.5.0; that is fine, the package id differs.
- **FR-005**: The v0.3 rollback APK and its pulled user data MUST be left untouched. The release
  preset's signing key (currently `debug.keystore`) MUST be recorded as "test-signed, not for
  distribution"; changing keys would force an uninstall and break the upgrade, so the real key is
  a separate decision before any public upload.
- **FR-006**: The release APK is not debuggable, so `adb run-as` no longer works on it. Frame/bench
  captures MUST stay on the `Oculus Quest (DEBUG)` preset; `tools/perf/benchmark.md` MUST say so,
  and any capture attempted on the release build MUST be recorded as unsupported if `run-as`
  fails.

## Success criteria

- **SC-001**: `F:\Dev\BeepSaberBin\OpenSaber-v04.apk` exists, is a RELEASE export, and
  `aapt dump badging` reports `versionName='0.4.0'`, `versionCode='7'`.
- **SC-002**: `adb install -r` succeeds over the installed debug build and the app launches; the
  device reports the same version name.
- **SC-003**: `git tag --list v0.4` shows an annotated tag on the bump commit, and
  `git rev-list --count godot-4-port..v4/cleanup` is 0 after the fast-forward.
- **SC-004**: The rollback APK hash is unchanged; no upload or push was performed.
- **SC-005**: `aapt dump badging` shows no `application-debuggable`; `apksigner` reports the same
  certificate SHA-256 as the installed debug build; `install -r` preserves settings and
  `user://OpenSaber/Songs`; the device reports 0.4.0; a bundled map plays to the end with no
  script/resource errors in logcat; one release stutter capture is compared with the debug
  baseline (or recorded as unsupported under FR-006).

## Release verification findings (0.4.0)

- **Startup crash (fixed, `db60313`)**: the first RELEASE export segfaulted on launch. The particle
  sword extends `DefaultSaber` but has no `LightSaber_Mesh/Halo`; the required-node `@onready`
  failed, left null materials, and the release build crashed where debug only logged. Halo nodes
  are now optional and the setters guard them. The rebuilt APK installs and launches.
- **First-call meta log noise (fixed, `5f58b7b`)**: `CanvasRefresh.of()` used
  `get_meta(name, null)`, which still logs "does not have any meta values" on a fresh viewport.
  `has_meta` makes it silent. This is in the tree but not in the installed test APK.
- **Installed test build**: `OpenSaber-v04.apk`, versionCode 7 / versionName 0.4.0, release export,
  test-signed with the debug keystore, installed over the debug build (settings and songs kept),
  launched and confirmed as the top activity.
- **Release capture works (FR-006)**: the external flag path (`/sdcard/Android/data/.../files`)
  works on the non-debuggable release build, so `run-vrapi.ps1` needs no `run-as`. One 30 s ODDS
  run: **120 fps median, App 5.01 ms, GPU 0.78 %** - better than the debug baseline (111 fps,
  5.39 ms, 0.81 %). Perf runs may stay on DEBUG for convenience; they are not blocked on release.
- **Play test (player)**: scroll good, BeatSaver panel good, settings good. Particle sword not
  checked by hand; the fixed build launches with it selected and logs no node/material error.
- **Final build**: `OpenSaber-v04.apk`, 83,525,217 bytes, SHA-256 prefix `223C753B468FAD0A`,
  versionCode 7 / 0.4.0, release export, test-signed, installed over the debug build (data kept),
  launched and confirmed as the top activity with a live process and no script errors.
- **Tag/merge**: annotated `v0.4.0-q3` at `bd6340d`; `godot-4-port` fast-forwarded from
  `7fff5d3` to `bd6340d`; no push. Rollback APK hash unchanged
  (`288100C3E294DBBE5C899990C5462C69A1154D0223AE068E215DE98F02BD0D68`).

## Out of scope

- Uploading to itch/SideQuest or any store (player: "not yet").
- Creating a new release signing key or changing package identity.
- Cleanup parts 5-9 (view state, audio, pooling, map loading, bench tooling).

## Open questions

None - the player answered the release questions: bump the version, ship a proper RELEASE build,
no upload yet, use the safest branch route, keep the rollback as a backup.

## Consultation Log

| Gate | Asked | Verdict | Action taken |
|---|---|---|---|
| G0 | Release mechanics: version/code bump, release export with the existing debug keystore, tag + fast-forward policy, verification steps | GO WITH CHANGES: `v0.4` is taken by upstream, use `v0.4.0-q3`; versionCode 7 correct; tag + FF safe with the old SHA recorded; release loses `run-as`, so perf stays on DEBUG; debug keystore is test-only; add badging/cert/data-preservation/logcat/release-capture checks | Applied; tag `v0.4.0-q3`, FF `7fff5d3` -> `bd6340d`, release capture works via the external path |
