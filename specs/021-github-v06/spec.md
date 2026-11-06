# Feature Specification: publish v0.6.0 to GitHub with a showcase README

**Feature Branch**: `021-github-v06`

**Created**: 2026-11-06

**Status**: Done - v0.6.0 published on GitHub

**Input**: Player: "Lets push this v6 to github and update the whole thing. The readme is a big
too big. I just want enough detail to showcase the work and improvements from prior work and
emphasize how much progress we have made on the main page readme. The further details and
comparisons can be inside subpages with links. Update a release version of v0.6 there as well.
I'll play a few games once I head home and we can test things. Fixes can come on v0.61 or
something later."

## Why

The repository's main page still describes the v0.2/v0.3 state: it says v0.2 is released, v0.3 is
in progress, and most of the page is deep performance analysis. Since then the fork shipped v0.4,
v0.5, v0.5.1 and v0.6, and 103 commits are sitting only on the local `godot-4-port` branch. The
public face of the project is out of date and does not show the progress that has been made.

## Requirements

### Main README (showcase)

- **FR-001**: `README.md` MUST be at most ~200 lines and lead with the project, the v0.6 release
  and the progress story, not the measurement detail. It MUST contain: a one-line pitch and
  badges; a hero image; "What's new in v0.6"; a compact "progress since v0.2" table; a handful of
  headline measured numbers; install/download; a documentation index; a short build section;
  current known limitations; license and upstream credit.
- **FR-002**: The main page MUST link out for detail instead of carrying it: a performance page, a
  full changelog and the v0.6 release report. No section may duplicate the subpages' tables.
- **FR-003**: Every claim and number on the main page MUST be traceable to an existing record
  (`PERF.md`, `specs/019-chains-dense/spec.md`, `specs/020-libs-leaderboards/`,
  `docs/device-evidence.md`, the release artifacts). No new measurements are invented for the
  README.

### Subpages

- **FR-004**: `docs/performance.md` MUST carry the detailed performance story moved out of the
  README: the frame-time trace, the v0.2 shipped-default table, the real stutter defect, the
  per-map wall matrix, and the v0.6 dense-map numbers, with links to `PERF.md` and
  `docs/v0.3-report.md`.
- **FR-005**: `docs/changelog.md` MUST list every released version (`v0.1.0`, `v0.1.1`, `v0.2.0`,
  `v0.3`/`v0.4.0`, `v0.5.0`, `v0.5.1`, `v0.6.0`) with its headline and links to the tag and the
  report/spec where one exists. It MUST distinguish the v0.6 release from the deferred BeastSaber
  import (planned 0.6.1).
- **FR-006**: `docs/v0.6-report.md` MUST be the release write-up: source tags + filter + backfill
  (with the device numbers), BeatLeader read-only, the 0.5.1 chain fix and dense-map result as the
  base it builds on, the Android export JSON finding and its workaround, install/upgrade notes and
  the release artifact hash. It MUST link to the specs and the evidence file.
- **FR-007**: Screenshots for v0.6 (source-filtered library, BeatLeader top scores) MUST be added
  under `docs/images/` and used in the report; the frame-time chart stays in the performance page.
  Images MUST have alt text and a sensible file size.

### Publish

- **FR-008**: `godot-4-port` MUST be fast-forwarded to the v0.6.0 work (no merge commit, no
  rewrite) and pushed to `origin`. The release tags not yet on `origin` — `v0.4.0-q3`,
  `v0.5.0-q3`, `v0.5.1-q3`, `v0.6.0-q3` — MUST be pushed. No force push, no branch deletion.
- **FR-009**: A GitHub release MUST be published for `v0.6.0-q3` from the existing annotated tag:
  title naming v0.6.0 and its theme, notes drawn from the report (highlights, measured results,
  install, known limits, upgrade from 0.5.1), and the release APK attached as
  `OpenSaberQ3-0.6.0.apk` together with a `.sha256` file. It MUST be a normal (non-draft,
  non-prerelease) release and become the latest.
- **FR-010**: The repository description and topics MUST be updated to the current project (Quest 3
  Beat Saber-compatible game on Godot 4.6, BeatSaver library, source tags, BeatLeader). Existing
  releases and assets MUST be left untouched; `v0.5.1` stays available as the fallback.
- **FR-011**: No game code may change in this slice. If a doc claim is wrong, fix the doc; do not
  change behaviour to match it.
- **FR-012**: Before the push, a hygiene scan of every unpushed commit MUST pass: no keystore or
  `export_credentials.cfg`, no tokens/API keys, no APKs or unexpected large binaries, no `.godot/`
  caches, and no personal data in tracked text or images (headset serial, Windows user paths,
  Wi-Fi/LAN addresses). Anything found MUST be redacted in a new commit; never force-push. The
  debug keystore used by the release MUST be backed up offline and the backup location recorded.
- **FR-013**: The release notes MUST include: install via SideQuest or `adb install -r`; that
  upgrading over 0.5.x keeps maps, scores and settings; the full SHA-256; the 0.5.1 fallback;
  known issues (white chain joints, audio stalling after a long idle until a headset reboot; the
  old red dot is recorded as the resolved miss X); that BeatLeader is read-only and the project is not affiliated; and
  the upstream BeepSaber credit + MIT licence.

## Success criteria

- **SC-001**: `README.md` is <= 200 lines, contains the progress table and the documentation
  index, and every relative link resolves to a tracked file.
- **SC-002**: `docs/performance.md`, `docs/changelog.md`, `docs/v0.6-report.md` exist, are linked
  from the README and cross-link each other; the v0.6 report uses the two new screenshots.
- **SC-003**: `git ls-remote origin refs/heads/godot-4-port` equals the local `godot-4-port` SHA,
  and all four release tags are present on `origin`.
- **SC-004**: `gh release view v0.6.0-q3` shows the release as latest with
  `OpenSaberQ3-0.6.0.apk` and the `.sha256`; a downloaded asset's SHA-256 equals
  `ACCAA169C8DF85067600C33BF199C37C91C18AD4B1407E45F4D479C04074FB5A`.
- **SC-005**: The GitHub repository description/topics show the new text; old releases are still
  listed.
- **SC-006**: Working tree clean, no game-code diff in this slice, and the local gates from 0.6.0
  still pass (no need to re-run the device).
- **SC-007**: Every relative link in the README and the new docs resolves to a tracked file; the
  rendered README is checked on GitHub after the push; each new screenshot is under 500 KB.

## Publication evidence (2026-11-06)

- Branch: `godot-4-port` pushed `7fff5d3..d1df410` (the code/docs commits; no force). Tags
  `v0.4.0-q3`, `v0.5.0-q3`, `v0.5.1-q3`, `v0.6.0-q3` pushed; `git ls-remote` confirms all four and
  the branch SHA.
- Release: <https://github.com/testyfishy/OpenSaberQ3/releases/tag/v0.6.0-q3>, latest, not draft.
  Assets `OpenSaberQ3-0.6.0.apk` (83,624,298 bytes) and `OpenSaberQ3-0.6.0.apk.sha256`; a fresh
  download hashes to `ACCAA169C8DF85067600C33BF199C37C91C18AD4B1407E45F4D479C04074FB5A`.
- The first upload kept the local file name (`OpenSaber-v060.apk`) although the label was the
  release name; the asset was replaced so the download file is `OpenSaberQ3-0.6.0.apk`.
- Repository description, homepage (latest release) and topics (`beatsaver`, `beatleader`) updated;
  the earlier topics are kept. Old releases and assets untouched.
- Rendered README fetched through the GitHub API matches HEAD; the cover, library, leaderboard and
  frame-time images return HTTP 200 from `raw.githubusercontent.com` on `godot-4-port`.
- Hygiene: the serial, Windows user path and LAN address were redacted in `4b5d2af` before the
  push; no key material, tokens or APKs were in the unpushed tree. `bin/debug.keystore` is
  upstream's public debug key from the initial import (already on origin); the release keystore is
  outside the repo and backed up at `F:\Dev\BeepSaberBin\keystore-backup\debug.keystore`
  (SHA-256 `E80806A0ED2CF556E9D9E77E97EE2941CFF1A62BF2775F06F3E0B5F33EE6150`). The pre-existing
  `export_presets.cfg` path/password was already public and was left to keep exports working.

## Out of scope

- v0.6.1 fixes, the BeastSaber import, and any gameplay change.
- Rewriting history, squashing, changing the package id or signing key.
- GitHub Pages, a website, or publishing to other stores.

## Open questions

None. The player's instruction is explicit; the only choice made here is to attach the APK to the
release, which matches the existing v0.2 release and the "download the APK" link.

## Consultation Log

| Gate | Asked | Verdict | Action taken |
|---|---|---|---|
| G5 | 021 spec drift after publishing | SC-001..SC-007 met: README 85 lines, links 0 broken, docs + screenshots live, branch/tags/release verified, asset SHA matched, description/topics updated | Spec marked Done; follow-ups (0.6.1 BeastSaber, home-test fixes) remain |

| G4 | 021 GitHub v0.6 publish (49a38e1 / e4afae3) | APPROVE: push branch + 4 tags and publish v0.6.0-q3; serial/LAN in history already public on origin, HEAD clean; qualify every perf claim with its conditions, add the non-affiliation line and the signing/upgrade line | Release notes drafted with conditions + disclaimers; pushing next |

| G0 | README structure, subpage split, publish scope and release notes | GO WITH CHANGES: lead with a since-the-fork progress table (before -> now -> evidence link), then v0.6 bullets; cut Build/Limitations; push all four -q3 tags but only the v0.6.0 release; confirm no keystore/credentials in history and back up the keystore; add a pre-push hygiene scan and the public-reader release-note items; link check + rendered README after push | Spec updated (FR-012/FR-013, SC-007); implementation starts with the hygiene scan |
