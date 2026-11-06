# Feature Specification: Delete the HuggingFace cache; move duolinux + duo-backups to F:\Dev

**Feature Branch**: `012-duolinux-hf-move`

**Created**: 2026-11-03

**Status**: Done (G4 accepted with changes, 2026-11-03)

**Input**: User: "Clean up hugging face cache. Move entire duolinux to the F-drive under dev as well as that is an old project as well." Confirmed: move **both** duolinux and duo-backups, and leave junctions at the old paths.

---

## Scoped change *(operational work)*

- **Trigger**: C: has 206.69 GB free after spec 010, but two more reclaimable blocks remain: a 17.22 GB HuggingFace model cache and a 14.97 GB old project sitting in `Documents`.
- **Root cause**: `Qwen3.8-27B-GGUF` was downloaded once (30 Oct) and is unused; `duolinux` is a finished project still on the system SSD.
- **Blast radius**: the git repo at `…\Documents\Default Project\duolinux`, its `out\` build artifacts, any shortcut/script naming the old path, and (for the cache) nothing but a re-download if the model is wanted again.

## Facts measured 2026-11-03

| Item | Value | Evidence |
| --- | --- | --- |
| `Documents` known folder | `C:\Users\<user>\Documents` — **local, not OneDrive-redirected** | `User Shell Folders\Personal` |
| `…\Default Project\duolinux` | **12.80 GB**, 3,238 regular files, **62 LX symlinks** (all under `out\`, build artifacts) | recursive enumeration |
| Git | repo with `origin https://github.com/testyfishy/duolinux.git`, worktree **clean** | `git status` exit 0 |
| Processes using it | none | `Get-Process \| Path` |
| `Documents\duo-backups` | **2.17 GB**, one dated set `20261031-1935` | enumeration |
| HF cache `~\.cache\huggingface` | **17.22 GB**, 14 files: `hub\models--unsloth--Qwen3.8-27B-GGUF` (17.22 GB) + `xet` (1.4 MB) | enumeration; no process reading it |
| `F:\Dev\duolinux`, `F:\Dev\duo-backups` | absent | `Test-Path` |

## Requirements *(mandatory)*

- **FR-001**: Delete the HuggingFace model cache (`hub\models--unsloth--Qwen3.8-27B-GGUF`) and the `xet` transfer cache; leave the two root metadata JSON files. It is regenerable; no process holds it.
- **FR-002**: Move `…\Documents\Default Project\duolinux` → `F:\Dev\duolinux` and `…\Documents\duo-backups` → `F:\Dev\duo-backups`.
- **FR-003**: Leave a **junction** at each old path so existing references keep resolving.
- **FR-004**: The copy MUST NOT follow reparse points. The 62 LX symlinks under `out\` cannot be recreated as LX links on NTFS; they may be missing or copied as placeholders and MUST be reported, not treated as failure.
- **FR-005**: No source deletion before verification: every **source** regular file must exist at the destination with equal size and equal sha256; directory count must match.
- **FR-006**: Refuse to start if a process holds files under either source.
- **FR-007**: After the switch, verify through the old paths: junction type/target, root listing, a sample file hash, `git status` and `git remote -v` for duolinux.
- **FR-008**: Rollback order: rename source → create junction → test. On failure remove the junction and rename back.
- **FR-009**: Log everything (copy log, verification counts, deletions, timings) under `%TEMP%\duolinux-move-<stamp>.log` and cite the filenames in the Outcome.
- **FR-011**: Before copying, write a manifest of the 62 LX symlinks (relative path + target) to `F:\Dev\duolinux\out\LX-SYMLINKS.txt`, and record how robocopy treated them. They cannot be recreated as LX links on NTFS; the manifest is the record.
- **FR-012**: Before any deletion, record `git log --branches --not --remotes`, `git stash list` and `git status --ignored` for duolinux. Robocopy exit ≥8 is a hard stop. Hash with long-path support. A post-switch `safe.directory` complaint is fixed, not rolled back.
- **FR-010**: Report measured C: before/after.

## Success Criteria

- **SC-001**: C: free increases by **≥ 30 GB** (≈17.2 GB cache + ≈15 GB project).
- **SC-002**: 0 source files missing at the destination; 0 sha256 mismatches; the 62 LX symlinks accounted for in the report.
- **SC-003**: `C:\Users\<user>\Documents\Default Project\duolinux` and `…\Documents\duo-backups` are junctions resolving to F:.
- **SC-004**: `git -C <old duolinux path> status` exits 0 and `git remote -v` still shows the origin.
- **SC-005**: The HF model directory and the `xet` cache no longer exist; the two root metadata files remain.

## Out of scope

- Any other `Documents` content, the `Default Project` wrapper (`.specify`, `specs`, loose probe scripts) — reported only.
- Re-downloading the model, WSL, Containers, Gradle, Android SDK.

## Open questions

- None blocking. *(Q1 both folders — answered; Q2 junction — answered.)*

## Assumptions

- duolinux is dormant (no process, worktree clean, last edit 2 Nov).
- The 62 LX symlinks are disposable build output; `out\` can be regenerated.
- F: stays attached; a junction dangles if it is not.

## Outcome (measured 2026-11-03 13:22–13:28)

| Check | Result |
| --- | --- |
| C: free | **189.46 GB → 221.73 GB (+32.27 GB)** |
| duolinux copy | 3,238 regular files, 12.80 GB, robocopy exit 1, 1 min 47 s |
| duolinux verify | 3,238/3,238 compared, **0 missing, 0 mismatches, 0 extras**, 2 min 08 s |
| duo-backups copy + verify | 4 files, 2.17 GB, **0/0/0**, 14 s |
| 62 LX symlinks | skipped by `/XJ` (dest=0); manifest written to `F:\Dev\duolinux\out\LX-SYMLINKS.txt` (62 entries + header) |
| Git state pre-move | `git log --branches --not --remotes` empty, `git stash list` empty, `status --ignored` clean apart from "Function not implemented" warnings on the LX-symlink dirs |
| Switch tests | duolinux: 5/5 (junction, listing, sample hash, `git status`, `git remote`); duo-backups: 3/3 after a fix |
| Rollback event | first duo-backups switch was rolled back because the sample-hash test assumed a file at the folder root; it only holds one subfolder. Test fixed to use the largest file recursively; second switch passed. Rollback was clean (`duo-backups` still a plain folder, no `.moved-` left) |
| Old copies | both deleted; no `.moved-*` remains under `Documents` |
| Junctions | `…\Default Project\duolinux` → `F:\Dev\duolinux`; `…\Documents\duo-backups` → `F:\Dev\duo-backups` |
| Git after switch | `git status` exit 0, `remote -v` still `https://github.com/testyfishy/duolinux.git` |
| HF cache | model dir (17.22 GB) and `xet` deleted; `.agent_harnesses.json` and `unsloth_xet_health.HTPCAran.json` kept |

SC-001 (+32.27 ≥ 30) met. SC-002 met. SC-003–SC-005 met.
Move script: `specs/012-duolinux-hf-move/Move-TreeToF.ps1`; logs in `%TEMP%\duolinux-move\`.

## Notes for future agents

- **`out\` on F: is missing 62 LX symlinks.** `F:\Dev\duolinux\out\LX-SYMLINKS.txt` has **66 lines: a 4-line header plus 62 entries** (path TAB target). Rebuild `out\` from that manifest — or rebuild it under WSL ext4 — before relying on it. A build that consumes `out\` on NTFS may fail.
- **`git status --ignored` prints `Function not implemented` warnings** for the directories that used to hold those LX symlinks. That is expected and harmless; `git status` itself exits 0.
- **The junctions break if F: is not attached.** `C:\Users\<user>\Documents\Default Project\duolinux` and `…\Documents\duo-backups` dangle until F: is back. `F:\Dev\OpenSaberQ3` also lives on F:.
- **Moving back** means deleting the junction first (`cmd /c rmdir <path>`), then copying the tree back. Never delete into the junction — that would delete the F: data.
- The HuggingFace model `Qwen3.8-27B-GGUF` is gone; re-download it if the Unsloth workflow needs it again. The two JSON files in `~\.cache\huggingface` are kept.

## Consultation Log

| Gate | Question | Verdict | Follow-up |
| --- | --- | --- | --- |
| G0 | Spec review: HF delete, move mechanics, LX symlink handling, junction pattern | **PROCEED WITH CHANGES** — manifest the LX links, hard-stop on robocopy ≥8, record unpushed/stash, delete model+xet only | Verdict was given before the work but recorded retroactively; all changes applied (FR-011/FR-012, FR-001 corrected) |
| G4 | Final review + drift check | **ACCEPT WITH CHANGES** — FR/SC met; only paperwork: Status, G0 row, manifest line count, future-agent notes | Applied below |
