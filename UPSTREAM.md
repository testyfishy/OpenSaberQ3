# Upstream provenance

This repository is a fork. Everything below is the pinned truth about where it came from,
so that any measurement can be attributed to a specific commit and any upstream change can
still be merged.

## Fork

| Field | Value |
|---|---|
| Upstream repository | https://github.com/leandrodreamer/BeepSaber |
| Upstream branch | `godot-4-port` |
| Pinned commit | `64200ad3572b634ae57159e234e87b5e3e5d96eb` |
| Commit date | 2025-03-05 |
| Commit subject | Merge pull request #23 from shocktail39/web-upload-style |
| License | MIT (inherited; see `LICENSE`) |
| Fork | https://github.com/testyfishy/OpenSaberQ3 (public, true fork) |

`upstream` remote is configured and must stay configured:

```powershell
git remote -v
# origin    https://github.com/testyfishy/OpenSaberQ3.git
# upstream  https://github.com/leandrodreamer/BeepSaber.git
```

## Lineage

`NeoSpark314/BeepSaber` (Godot 3, archived) → `leandrodreamer/BeepSaber@godot-4-port`
(Godot 4 + OpenXR) → **this fork**.

`NeoSpark314/BeepSaber` itself derives from the Godot Oculus Quest Toolkit demo. The MIT
notice covers the whole chain; see `ATTRIBUTION.md`.

## Installed build on the user's headset (the reference, not the baseline)

Established by `adb` on 2026-11-01, device `2G0YC1ZF9J0G2V` (`eureka`, Quest 3, Android 14 / SDK 34).

| Field | Value |
|---|---|
| Package | `org.godotengine.open_saber` |
| Version name | `0.5.0` |
| Version code | `5` |
| minSdk / targetSdk | 24 / 34 |
| Installed | 2026-10-29 |
| Origin | leandrodreamer/BeepSaber `godot-4-port` (package `open_saber`; the arpruss fork uses `open_saber_plus`) |

This confirms OQ-1: the user is playing the leandrodreamer lineage, not OpenSaberPlus.

**This installed APK is a reference point only.** Per FR-022 the "before" build is the pinned
commit above, built with the toolchain below, because a different engine build or export
setting would contaminate every comparison.

## Pinned toolchain

| Component | Version | Location |
|---|---|---|
| Godot | **4.6.3-stable** (win64) | `%LOCALAPPDATA%\Godot\4.6.3\Godot_v4.6.3-stable_win64.exe` |
| Export templates | **4.6.3.stable** | `%APPDATA%\Godot\export_templates\4.6.3.stable` |
| JDK | Temurin 17.0.20.1 | `%LOCALAPPDATA%\JDK\jdk-17` |
| Android SDK platform | 34 | `%LOCALAPPDATA%\Android\platforms\android-34` |
| Build-tools | 34.0.0 | `%LOCALAPPDATA%\Android\build-tools\34.0.0` |
| NDK | 23.2.8568313 | `%LOCALAPPDATA%\Android\ndk\23.2.8568313` |
| platform-tools | 37.0.1 | `%LOCALAPPDATA%\Android\platform-tools` |
| Debug keystore | `CN=Android Debug` | `%USERPROFILE%\debug.keystore` |

## Engine migration (deviation from upstream)

Upstream declares `config/features=PackedStringArray("4.3")`, but **4.3 cannot build this
repository on a clean clone**. On a fresh `git clone` the 4.3 importers crash inside
`ImporterMesh::generate_lods` on meshes with degenerate faces, and every mesh destination is
left as a **1-byte** file. Reproduced with both the 4.3 editor CLI (`--import`) and the 4.3 GUI.

This fork therefore builds on **Godot 4.6.3-stable**, recorded as plan decision D-2 (amended),
in commit `3f68a02`, as its own reviewable change. Rationale beyond "4.3 is broken":

- 4.6.3 imports the identical asset set cleanly (exit 0; meshes 6854 / 9837 / 1360 / 8828 bytes).
- 4.6 is the engine line `arpruss/OpenSaberPlus` ships, so this asset lineage is known-good there.
- 4.5+ is where Meta's fragment-density / foveation path exists, which matters for FR-012.

Because of this, the "before" build (FR-022) is **upstream `64200ad` built on 4.6.3**, not the
APK installed on the headset (that one was built by the author on 4.3). 4.7.2 is deliberately
deferred: it is tested only as an optional later change if 4.6.3 leaves a measurable gap.

As of Godot 4.4+, `.uid` sidecar files for scripts and shaders are generated and **are
committed**; they are not build artefacts.

The `arpruss/OpenSaberPlus` fork declares 4.6 and is still not a drop-in base, because a
wholesale base swap would invalidate every before/after pair (plan D-1).


## Known reproducibility gaps

| # | Gap | Consequence |
|---|---|---|
| G-1 | `.gitignore` excludes `/addons/godotopenxrvendors`, so the OpenXR vendor plugin is not in the repo and its version is unpinned | **Cause confirmed 2026-11-01.** A build made with the *prebuilt* Android template contains only `libc++_shared.so` and `libgodot_android.so` — no `libopenxr_loader.so` — and the app then logs `Can't open dynamic library: libopenxr_loader.so` → `OpenXR was requested but failed to start` → `Godot will start in normal mode`. i.e. flat mode, no VR. The loader is supplied by the Gradle build path (`config.gradle: openxrLoaderVersion 1.1.53`, `openxrVendorsVersion 4.3.0-stable`) and/or the vendors addon. A VR-capable build therefore **requires** the Gradle path, which requires `android/.build_version` to match the engine (see G-4) |
| G-4 | `android/.build_version` is committed by upstream as `4.3.stable` | Godot compares this file against the engine's template identifier and refuses to export when they differ (`Android build version mismatch`). Updated to `4.6.3.stable` as part of the engine migration |
| G-2 | `export_presets.cfg` uses `gradle_build/use_gradle_build=true` with empty gradle build directory | Upstream ships no gradle wrapper and the custom-build path additionally needs SDK 36 / build-tools 36.1.0 / NDK 29 plus a build template Godot cannot version-check when hand-extracted. **Resolved for this fork by building with the prebuilt template** (plan D-9): the DEBUG preset now sets `use_gradle_build=false` and produces a signed APK. The RELEASE preset is untouched |
| G-3 | No CI build exists upstream | Reproducibility (SC-001) is currently a claim, not a test |

## Dead configuration inherited from upstream

These keys exist in `project.godot` but are **Godot 3 setting names** and are ignored by
Godot 4. They are corrected in Phase 3/4 with measurement, not silently.

| Key present | Godot 4 key | Actual current behaviour |
|---|---|---|
| `[physics] common/physics_fps=72` | `physics/common/physics_ticks_per_second` | physics runs at the 60 Hz default |
| `quality/filters/msaa=6` | `rendering/anti_aliasing/quality/msaa_3d` | MSAA off |
| `3d/physics_engine="Bullet"` | `physics/3d/physics_engine` | default engine |
