# Feature Specification: Move the C:\WLO-Revival tree to F:\Dev\WLO-RI and leave a pointer

**Feature Branch**: `009-wlo-archive-to-f`

**Created**: 2026-11-02

**Status**: Done (G4 accepted with changes, 2026-11-02)

**Input**: User request: "The WLO copies are from a major project I undertook a while ago. Can you move all of that into F:/dev/WLO-RI or something?" — plus the earlier question "Is there more space we can clear out of C drive?"

---

## Scoped change *(operational work — replaces user stories)*

- **Trigger**: C: is a 464.7 GB volume with only **18.5 GB free** (measured 2026-11-02). The WLO project archive occupies **25.37 GB / 162,247 regular files** on the system SSD, while F: (8 TB NTFS) has **5,795 GB free**.
- **Root cause**: the archive accumulated on C: during a past project and was never relocated; only two cold subfolders were parked on F: by the existing `fmove.py` tool.
- **Blast radius**:
  - every launcher/script that names `C:\WLO-Revival\...` (`Start 1 - server.cmd`, `Go live…`, `telemetry-venv\Scripts\python.exe`, `fmove.py`, `free_temp.ps1`, …);
  - the git worktree `wlo-lane2`, whose `.git` file hardcodes `gitdir: C:/WLO-Revival/wlo-revival/.git/worktrees/wlo-lane2`;
  - `telemetry-venv` (absolute interpreter paths, `pyvenv.cfg`);
  - ~hundreds of **junctions inside the tree** (QA client dir sets, sandbox `consol` cases) with **absolute `C:\WLO-Revival\…` targets**;
  - `C:\Users\user\WLO` → **junction** to `C:\WLO-Revival` (must keep resolving);
  - Windows Firewall rules that match `aLogin.exe` / `Main.exe` by their old C: path (per `docs/f-drive-plan.md` §2).

## Facts measured before planning

| Fact | Value | Evidence |
| --- | --- | --- |
| C: free / size | 18.6 / 464.7 GB | `Get-Volume` |
| F: free / size, FS | 5,794.9 / 7,452 GB, NTFS, `Fixed` | `Get-Volume` |
| `C:\WLO-Revival` | **25.37 GB unique**, 162,247 regular files | `Move-WloToF.ps1 -Phase Inventory` (2026-11-02 21:50) |
| `C:\WLO-Revival` (first estimate) | ~~51.19 GB~~ | **wrong**: `robocopy /L /BYTES` followed the 1,452 junctions and counted shared data up to six times. Corrected by enumerating only non-reparse files. |
| `C:\Users\user\WLO` | **Junction → `C:\WLO-Revival`**, *not* a second copy | `Get-Item -Force` |
| Reparse points in tree | many junctions (6 at root + QA client dir sets + `fan-server\work\consol-sandbox-cases\*`); 3 unix sockets `run\*.sock` | `Get-ChildItem -Attributes ReparsePoint` |
| Processes running from tree | none at 2026-11-02T22:0x | `Get-Process \| Where Path` |
| Existing tool | `wlo-revival\tools\Lab\fmove.py` — copy → sha256 both sides → rename → junction; **table-driven and refuses folders with links inside** → cannot move the root | `fmove.py plan` output |
| Already on F: | `F:\WLO-Revival\moved\reference`, `…\archive-fixes`, plus `video\ring`, `models\image` | `fmove.py plan`, `docs/f-drive-plan.md` §3 |
| Prior guidance | `docs/f-drive-plan.md` says `wlo-revival`, `WLO-work`, `WLO-qa`, `run`, `fan-server`, `telemetry-venv` **stay on C:** (F: sleeps ~20 s, slower), and `WLO-original` has a C:-path firewall rule | `docs/f-drive-plan.md` §2 |

**Known conflict**: the user's request ("move all of that") contradicts the project's own rule that live pieces stay on C:. The user describes WLO as a past project; that resolves the conflict only if it is in fact dormant. See Open questions Q1.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The tree at `C:\WLO-Revival` (25.37 GB / 162,247 files) MUST be relocated to `F:\Dev\WLO-RI`.
- **FR-002**: `C:\WLO-Revival` MUST remain a directory **junction** → `F:\Dev\WLO-RI`, so existing absolute C: paths keep resolving.
- **FR-003**: The copy MUST preserve every reparse point **as a reparse point** with its original absolute target, and MUST NOT follow reparse points (no duplication, no recursion).
- **FR-003a**: Reparse points MUST be inventoried by kind (directory junction, directory/file symlink) before copying, and recreated with the same kind and target, including the ones already pointing at `F:\WLO-Revival\moved\*`. Copy excludes them (`/XJ`), then recreates them explicitly.
- **FR-004**: The copy MUST preserve file timestamps and attributes; UNIX sockets (`run\measure.sock`, `run\smoke.sock`, `run\wlo.sock`) MUST NOT abort the copy.
- **FR-004a**: The copy MUST use `/R:0 /W:0 /LOG`; a robocopy exit code ≥ 8 is a failure. Paths over 260 characters MUST copy.
- **FR-005**: No source data may be deleted until verification passes: **file count equal**, **total bytes equal**, and **sha256 equal for every regular file** on both sides.
- **FR-005a**: After hashing, a second `robocopy /L` against the source MUST report zero differences (nothing changed during the copy), and the junction count and target list MUST match on both sides.
- **FR-006**: Verification results MUST be written to a log under `C:\WLO-Revival\evidence\` (or the new location if the pointer exists) before deletion. *(Written to `F:\WLO-Revival\moved\_wlo-move\` during the run — before the pointer existed — then copied to `F:\Dev\WLO-RI\evidence\wlo-move-2026-11-02\`, readable as `C:\WLO-Revival\evidence\wlo-move-2026-11-02\`, before the old copy was deleted.)*
- **FR-007**: After the switch, reads through `C:\WLO-Revival\…` MUST be tested: root listing, biggest files, a sample byte-for-byte read, `git -C C:\WLO-Revival\wlo-revival status`, and `C:\WLO-Revival\telemetry-venv\Scripts\python.exe -V`.
- **FR-008**: `C:\Users\user\WLO` MUST be left untouched and MUST still resolve (it points at `C:\WLO-Revival`, which becomes the new junction).
- **FR-009**: The operation MUST refuse to start or MUST stop if a process holds files open inside the tree.
- **FR-010**: If any verification step fails, the operation MUST leave `C:\WLO-Revival` intact and report, rather than delete.
- **FR-010a**: Rollback order is rename → `mklink /J` → tests. If the rename fails on an open handle, abort with C: untouched. If a test fails, remove the junction and rename the source back.
- **FR-011**: Deletion of the old C: copy MUST free ≥ 24 GB on C: (the revised, measured figure — the point of the exercise) and MUST be confirmed by the user at that step. *(Confirmed 2026-11-02; actual +25.6 GB.)*
- **FR-012**: A machine-readable `README`/move record MUST be written for future agents, at the new tree root **and** in `wlo-revival\docs\`, stating: old path, new path, the junction, date and verification result, what no longer matches (firewall rules, `backup.py`, tray, `f-drive-plan.md`), how to re-verify, and how to undo the move.

### Key Entities

- **Source tree**: `C:\WLO-Revival` — archive + repo + venvs + client copies + internal junctions.
- **Destination**: `F:\Dev\WLO-RI` — same tree, same layout, junctions preserved.
- **Pointer**: `C:\WLO-Revival` junction → `F:\Dev\WLO-RI`.
- **Verification log**: file counts, byte totals, hash mismatches, timings.

## Success Criteria *(mandatory)*

- **SC-001**: C: free space increases by **≥ 24 GB** (from 18.5 GB to ~43 GB) — revised down from 50 GB when the junction-inflated 51.19 GB figure was disproved.
- **SC-002**: **0** missing files and **0** sha256 mismatches between source and destination.
- **SC-003**: `C:\WLO-Revival`, `C:\Users\user\WLO`, and every internal junction resolve after the switch; a sample file reads identically through the C: path.
- **SC-004**: `git -C C:\WLO-Revival\wlo-revival status` succeeds and `git worktree list` still shows `wlo-lane2`.
- **SC-005**: `C:\WLO-Revival\telemetry-venv\Scripts\python.exe -V` prints a version through the pointer.
- **SC-006**: The whole operation is reported with measured timings and a verification summary.
- **SC-007**: The report lists every known path-bound side effect that the move invalidates (46 outbound firewall block rules, `backup.py`/tray paths, any Defender exclusion), without silently "fixing" them.
- **SC-008**: A move record exists at the new tree root and in `wlo-revival\docs\`, and a fresh agent can use it to re-verify or undo the move.

## Out of scope

- Deleting temp folders, compacting the 94 GB WSL `ext4.vhdx`, OneDrive on-demand, Godot, HF cache, or anything else on C: — those are reported separately, not acted on here.
- Re-pointing Windows Firewall rules, `backup.py`, or the tray to the new path (call out only).
- Moving `F:\WLO-Revival\moved\*` (already on F:) into the new tree.
- Any change to the WLO source code.

## Resolved questions

- **Q1 — answered 2026-11-02: WLO is dormant.** Evidence: no scheduled task, startup item, service or Run key names the tree; no process runs from it. The whole root may move; the `docs/f-drive-plan.md` "stay on C:" rule is superseded.
- **Q2 — answered: `F:\Dev\WLO-RI`** (the user's path), not the old `F:\WLO-Revival\moved\<name>` convention.
- **Q3 — answered: delete the old C: copy** after verification passes, to actually reclaim the space (FR-011). The `.moved-<date>` rename is still used as the rollback-safe intermediate step (FR-010a).

## Assumptions

- F: stays attached and is allowed to spin up/down; the archive is cold.
- No process uses the tree during the move (verified; re-checked before switch).
- Data will live **only on F:** after deletion; a second copy on D:/E: is the user's call.
- Junctions with absolute `C:\WLO-Revival\…` targets remain correct after the pointer is created (they resolve through it).
- 162k mostly-small files to a USB HDD will take tens of minutes, not seconds; the copy runs as a background job.
- **Accepted risk**: if F: is disconnected or asleep, `C:\WLO-Revival` dangles. That is the price of the pointer, and it is recorded in the move record for future agents.
- **Accepted risk**: after the move the data exists only on F:; `UrBackup`'s job may not hold a second copy.

## Outcome (measured 2026-11-02 22:42–22:45)

| Check | Result |
| --- | --- |
| Copy | 162,247 files, 25.37 GB, 14,288 dirs, 6 min 37 s (robocopy `/E /XJ /MT:16`) |
| Junctions | 1,452 recreated (1,449 via `New-Item`, 3 dangling via `mklink /J`) — inventory identical |
| Hash verify | 162,247 / 162,247 compared, **0 missing, 0 mismatches**; 42 min |
| Second dry-run diff | 0 dirs / 0 files / 0 bytes outstanding |
| Switch | rename + junction + 8 tests: **all PASS** (junction, listing, `~/WLO`, sample hash, `git status`, `git worktree list`, venv `python -V`, 1,452 reparse points) |
| Old copy deleted | yes; C: **17.8 → 43.44 GB free (+25.6 GB)** |
| Loose end | 1 empty, ACL-denied directory survives without elevation: `C:\WLO-Revival.moved-20261102-224234\evidence\quest-tool\qt-selftest-6wpbhvwy` (0 bytes). **The `…moved-20261102-224234` parent is NOT a rollback copy** — only this empty folder is left; the elevated 3-line fix is in the move record. |
| Path-bound side effects (SC-007) | 46 outbound firewall **block** rules still name the old exe paths and no longer match the resolved `F:\Dev\WLO-RI\…` image — listed, not fixed. Defender exclusions could **not** be read without elevation (`Get-MpPreference` refused); no claim either way. |
| Move record | `F:\Dev\WLO-RI\MOVE-RECORD-2026-11-02.md` + `…\wlo-revival\docs\f-drive-move-2026-11-02.md` |

SC-001 met (≥24 GB). SC-002 met (0/0). SC-003…SC-005 met by the switch tests.
SC-006/SC-008 met by this sheet and the move record.

## Consultation Log

| Gate | Question | Verdict | Follow-up |
| --- | --- | --- | --- |
| G0 | Spec review: whole-root relocation vs. fmove tier plan; mechanics holes | **PROCEED WITH CHANGES** — confirm dormancy before copy; add FR-003a/004a/005a/010a; keep `.moved-<date>` as rollback step; report path-bound side effects; accept dangling-pointer risk | Dormancy confirmed by user (Q1); required FRs added |
| G1 | Plan review of copy/junction/verify/delete mechanics | Covered by G0 brief (same mechanics, not re-reviewed — no stacking) | Mechanics frozen as FR-003a…FR-010a |
| G2 | Dormancy + delete policy + destination | **PROCEED** — dormant (no autostart/service/process); delete after verification; destination `F:\Dev\WLO-RI` | Recorded in Resolved questions |
| G3 | Progress at copy / verify / switch boundaries | Copy exit 9 caused by 3 pre-existing dangling junctions; parity proved (14,288 dirs / 162,247 files), 3 links recreated with `mklink /J`. Verify then passed 0/0 | Junctions phase added to the script |
| G4 | Final review + drift check | **ACCEPT WITH CHANGES** — evidence meets FR/SC; FR-011 still said ≥50 GB (drift, fixed to ≥24 GB); FR-006 log path now recorded; Status → Done; name the full surviving path and say the `.moved-` parent is not a rollback copy; add the firewall re-point command; record the Defender result | Applied: FR-011, FR-006, Outcome rows, move record §3.1/§3.8 |
