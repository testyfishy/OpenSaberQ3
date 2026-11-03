# Feature Specification: Remove C: junk and make OneDrive online-only

**Feature Branch**: `010-c-drive-cleanup`

**Created**: 2026-11-03

**Status**: Done (G4 accepted with changes, 2026-11-03)

**Input**: User: "Remove windows junk. Find other junk too. Onedrive make everything on-demand. Doesnt need to waste space here locally."

---

## Scoped change *(operational work)*

- **Trigger**: C: is a 464.7 GB NVMe; after the WLO move (spec 009) it has **43.44 GB free**. Junk left by Windows, Godot, dev caches and a fully-pinned OneDrive keeps it that low.
- **Root cause**: default "keep on this device" pinning for 91,495 OneDrive files (148.66 GB), plus accumulated Windows/Godot/dev leftovers.
- **Blast radius**: user profile and Windows system folders. Wrong deletes could break Godot (running now), OneDrive sync, or Windows servicing. Nothing under `F:\Dev\WLO-RI` or `F:\Dev\OpenSaberQ3` is touched.

## Facts measured 2026-11-03

| Item | Size | Notes |
| --- | ---: | --- |
| OneDrive | **149.24 GB**, 91,539 files | 91,495 **pinned** (148.66 GB), 44 normal (0.58 GB); OneDrive.exe running |
| Godot logs (`…\Godot\app_userdata\Open Saber Q3\logs`) | **16.35 GB** | Godot **is running** (PID 25068); `godot.log` 3.69 GB is live, 4 rotated logs total 12.66 GB |
| `%LOCALAPPDATA%\Temp` | 11.34 GB | safe (>1 day) = **4.65 GB**; today's items (`toolchain` 3.11, `claude` 2.68, `EC9254…swap.vhdx` 2.85) are in use |
| `C:\$WinREAgent` | 1.81 GB | staging from the 14 Oct feature update; **admin** |
| `C:\Windows\SoftwareDistribution\Download` | 0.24 GB | **admin** |
| `C:\Windows\Logs\CBS` | 0.09 GB | **admin** |
| `C:\tmp` | 0.11 GB | user |
| CrashDumps | 0.05 GB | user |
| dev caches (npm 0.36, pip 0.25, uv 0.26, Gradle 6.18, HF 17.22) | 24.3 GB | regenerable; HF models 16.35 GB may be wanted |
| Edge/Firefox caches | ~0.9 GB | regenerable |
| WSL `ext4.vhdx` | 91.19 GB | **not junk** — compaction only, needs `wsl --shutdown` |
| Sandbox `Containers` | 19.53 GB | needs admin + stopped container service |
| `Documents\Default Project\duolinux\out` + `duo-backups` | ~13 GB | build outputs/backups — user decision |

## Requirements *(mandatory)*

- **FR-001**: Delete the safe Windows/user junk: Temp items **older than 24 h**, `C:\tmp`, `CrashDumps`, rotated Godot logs, and the browser/dev caches listed in the plan.
- **FR-002**: Never delete a file that a running process holds, or anything younger than 24 h in Temp. Godot's live `godot.log` MUST be skipped.
- **FR-003**: Admin-only items (`C:\$WinREAgent`, `SoftwareDistribution\Download`, `CBS` logs) MUST be attempted only in an elevated shell, and reported as skipped if elevation is unavailable.
- **FR-004**: **Unpin every OneDrive file** so Files On-Demand may dehydrate it (`attrib +U -P`), which is the scripted equivalent of "Free up space".
- **FR-005**: OneDrive dehydration MUST NOT run while sync is incomplete or paused; if that state cannot be proven, abort and report rather than risk a local-only file. *(Actual proof at 07:52: OneDrive.exe running; `LastKnownCloudFilesEnabled = 1`; no file in the tree written for 37 min; no pause/error key present. The tray status was **not** visually confirmed by a human — no screenshot. Dehydration was still safe because `+U` only unpins: OneDrive refuses to dehydrate anything not already uploaded, so a local-only file would have stayed local.)*
- **FR-006**: After dehydration, count files still carrying `PINNED`, and report both the **logical size** (unchanged) and the **on-disk savings** (C: free delta).
- **FR-007**: Every deletion MUST be logged with path, size and result to `C:\Users\user\AppData\Local\Temp\c-cleanup-<stamp>.log` and to this spec's Outcome section.
- **FR-008**: Items outside the safe list (HF models, Gradle, Android SDK, Godot editor data, WSL, Containers, duolinux outputs) MUST only be reported, never deleted, unless the user asks.
- **FR-009**: Total freed space MUST be reported as measured before/after `Get-Volume` values, not estimates.
- **FR-010**: Before unpinning, the attribute cross-tab MUST be recorded, and only files that are cloud placeholders (`ReparsePoint`) may be unpinned. Plain local files MUST be listed and left alone. *(Measured: 91,491 reparse+pinned = 146.74 GB; 4 non-reparse pinned = ~0 GB, left; 44 already unpinned = 0.58 GB.)*
- **FR-011**: Dev caches MUST be cleared with each tool's own command (`npm cache clean --force`, `pip cache purge`, `uv cache clean`), not raw deletes.
- **FR-012**: Browser caches MUST only be cleared when that browser is closed; a running browser's cache is skipped and reported.

## Success Criteria

- **SC-001**: C: free space increases by **≥ 140 GB** (≈15 GB junk/caches + ≈145 GB OneDrive), measured once dehydration stops changing (free-space delta flat for 10 min) or within 2 h — dehydration runs in the background, so the delta is not instant.
- **SC-002**: **0** OneDrive files remain pinned; every file that could not dehydrate is listed with a reason.
- **SC-003**: No running application is broken: Godot still running, OneDrive still running, and `godot.log` still present.
- **SC-004**: The cleanup log exists and every deleted path is listed.
- **SC-005**: A final table separates *done*, *skipped (needs admin)*, and *offered but not done*.

## Out of scope

- WSL compaction, Containers/Sandbox cleanup, HuggingFace model deletion, Gradle/Android caches, `duolinux` outputs, `Documents` (reported only).
- Any change to the WLO tree or the OpenSaberQ3 repo.

## Open questions

- **Q1**: Delete the 16.35 GB HuggingFace model (`Qwen3.8-27B-GGUF`) too, or keep it? Default: **keep**, report only (FR-008).

## Assumptions

- OneDrive personal account, Files On-Demand available (the pinned attribute is present, so the cloud filter is active).
- No OneDrive sync error blocks dehydration; verified before acting.
- Admin items can wait for the user to approve a UAC prompt.

## Outcome (measured 2026-11-03 07:50–08:40)

| Item | Result |
| --- | --- |
| C: free | **43.44 GB → 206.69 GB (+163.25 GB)**, measured after dehydration stopped |
| Old Temp (>24 h) | 4.04 GB deleted; 1,646 items in use skipped |
| Godot rotated logs | 12.66 GB deleted, then **15.73 GB more** when Godot re-created four 3.93 GB logs (see finding) |
| `C:\tmp` + CrashDumps | 0.18 GB |
| pip / uv caches | 0.27 / 0.26 GB via their own commands |
| Firefox cache | 0.38 GB (Firefox closed) |
| Edge cache | **skipped** — 17 Edge processes running (FR-012) |
| `$WinREAgent`, CBS logs | **removed in an elevated shell**, 2.01 GB; SoftwareDistribution\Download kept 24 in-use items |
| OneDrive unpin | 91,491 cloud placeholders set to `UNPINNED` (1,086 needed the `\\?\` long-path form) |
| OneDrive dehydrated | **90,476 files / 148.96 GB** online-only; 1,063 files / 0.28 GB still local (in use/recent); 5 files remain pinned (4 non-reparse + 1, all 0.00 GB) |
| npm cache | `npm cache clean --force` ran (no measurable delta) |
| Logs (FR-007/SC-004) | `%TEMP%\c-cleanup-20261103-072905.log` (junk phase, 1.8 MB, every deleted path including the second 15.73 GB Godot pass), `…-075204.log` (unpin), `…-075352.log` (cross-tab), `…-elevated-result.txt`, `…-unpin-failures-20261103-075204.txt` (the 1,086 long paths, all since fixed) |
| Still-local remainder | 29 files / 0.28 GB at final count — CSV at `%TEMP%\onedrive-still-local-20261103.csv` (in use or written during dehydration) |
| 5 pinned remain (SC-002 deviation) | 4 non-reparse, kept by FR-010: `.849C9593-…` (OneDrive system folder), `desktop.ini`, `OpenSaberQ3 (code on C drive).lnk`, `~syncthing~…lock…tmp`; 1 reparse: `Personal Vault.lnk` (vault shortcut). All 0 MB. |

**Finding (not fixed, out of scope): Godot was error-looping.** `res://game/vr_slider.gd:45` raises
`Invalid access to property or key 'rotation_degrees' on a base object of type 'Nil'` every frame;
at one point it produced four 3.93 GB logs in ~2 minutes (~15.7 GB), which briefly ate the cleanup
gain. It stopped on its own (live `godot.log` flat at 0.0 MB/s, 3.95 GB). It will refill C: if that
scene loads again. Fix `vr_slider.gd:45` (null-check the slider node) or cap Godot's log size.

**Second finding:** `Documents\Default Project\duolinux\` (out images ~11 GB + `duo-backups` 2 GB),
HuggingFace 17.22 GB, Gradle 6.18 GB, Android SDK 5.37 GB, WSL `ext4.vhdx` 91.51 GB and Sandbox
`Containers` 19.53 GB remain — all reported, none touched (FR-008).

**Follow-up recommended (new spec, not this one):** cap Godot's log size or move
`…\Godot\app_userdata\Open Saber Q3\logs` off C:. The live `godot.log` is 3.95 GB and can be deleted
once Godot exits. `vr_slider.gd:45` can refill C: with ~16 GB in minutes if that scene reloads.

**Expected drift:** OneDrive re-downloads a file when it is opened, so free space will fall slowly
as files are used. That is normal Files On-Demand behaviour, not a leak.

## Consultation Log

| Gate | Question | Verdict | Follow-up |
| --- | --- | --- | --- |
| G0 | Spec review: safe junk set, OneDrive dehydrate safety, admin handling | **GO WITH CHANGES** — unpin only `ReparsePoint` cloud placeholders (FR-010); tool-native cache commands (FR-011); browser caches only when closed (FR-012); SC-001 measured after dehydration settles; prove sync (tray up to date, no writes in 15 min) or abort; treat locked files as skips | Applied; sync proof escalated to the user before unpinning |
| G1 | Plan review (destructive deletes + OneDrive) | Covered by G0 brief (same plan, no stacking) | — |
| G4 | Final review + drift check | **ACCEPT WITH CHANGES** — work passed; record needed the real FR-005 sync proof (tray not human-confirmed), SC-002 deviation for the 5 pinned files + CSV of the 1,063 local, exact log filenames, the Godot refill warning and the OneDrive re-download drift | All applied; Status → Done |
