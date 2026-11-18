# itch.io push plan

**Status:** plan only. Nothing has been uploaded or published. The page needs the owner's itch.io
account and an explicit go-ahead. Page copy: [itch-page.md](itch-page.md). SideQuest copy:
[sidequest-page.md](sidequest-page.md).

**Target build:** 0.77.1 (versionCode 58). It is 0.77.0 with a signing-password change only; the
gameplay is the same. Upload `OpenSaber-v0.77.1.apk` from `F:\Dev\BeepSaberBin`: 82,473,900
bytes, SHA-256 `453001DDFBFEFE7F348421599E4462B156AED4D3245D3C540E84BA8444B1DD6D` (read from the
file on 2026-11-17).

## 1. Go / no-go

All of these must be true before the page goes live:

- [x] **0.77.1 APK exists** at the path above, with the size and hash above.
- [ ] `aapt dump badging` shows versionName 0.77.1, versionCode 58 and no
      `application-debuggable`.
- [ ] `apksigner verify --print-certs` shows the certificate the owner means to keep for store
      builds.
- [ ] The APK installs over 0.77.0 with maps, scores and settings kept.
- [x] **No bundled demo song.** It was removed in 0.6.1 and `game/data/maps/Songs` is empty.
- [ ] **Media.** The clip and stills in `store-media/` (excluded from git) come from an older build
      (0.7.3x). They are provisional: replace them with 0.77 footage when available.
- [ ] Page copy pasted from `docs/itch-page.md`, including the vibe-coded statement near the top
      and the non-affiliation line.
- [ ] The **AI disclosure field** is set to Yes, with Graphics and Code ticked.
- [ ] Every performance claim carries its conditions (Quest 3, 120 Hz, Performance preset, bot).
- [ ] The known-issues list matches the README's Known limitations.
- [ ] No "Beat Saber" in the title, tagline, tags, cover or screenshots; no Beat Saber assets.
- [ ] Upstream credit is visible, the licence link works, and the GitHub Issues link works.

## 2. Verify the package

1. Run the `aapt` and `apksigner` checks above.
2. Install over 0.77.0, launch, play one map, open the BeatSaver browser and the song panel.
3. Upload the file as an **Android** build. itch treats it as a download; it does not install it.

## 3. Project setup

| field | value |
|---|---|
| Title | OpenSaberQ3 |
| URL | `open-saber-q3` |
| Classification | Game |
| Kind | Downloadable |
| Pricing | No payments (free) |
| Release status | In development |
| Platforms | Android |
| Genre | Rhythm |
| Tags | `vr`, `meta-quest`, `rhythm`, `open-source`, `sidequest`, `beatsaver` |
| Cover | `docs/images/itch-cover.png` (630×500) |
| Banner | `docs/images/banner.png` (1280×640) |
| AI disclosure | Yes — Graphics, Code |

Do not use `beat-saber` as a tag. Do not put "Beat Saber" in the title or the cover.

## 4. Page

Paste the copy from `docs/itch-page.md`:

- tagline and short description;
- full description: vibe-coded statement, features, performance with conditions, install, known
  issues, feedback link, credits and licence, non-affiliation, source link;
- screenshot captions under the stills.

## 5. Upload and publish

1. Create the project, set the fields above, save as **draft**.
2. Upload the APK as an Android build. Set the version string to 0.77.1 and the requirement
   (Quest 3, sideloading required).
3. Add the cover, banner, stills and clip.
4. Tick the AI-generated content disclosure and check the preview on desktop and mobile.
5. Check the download works while logged out (open the page in a private window).
6. Publish only after the owner signs off on the preview. Then link the itch page from the GitHub
   README and the release notes. Do not change the uploaded file afterwards without a version
   bump.

## 6. Risks

- **Trademark.** No Beat Saber name, logo or art in the page, tags, screenshots or APK. Use
  "BeatSaver maps" and "rhythm game".
- **AI disclosure.** The artwork is AI-generated and the code was written with AI coding agents.
  The field and the copy must say so.
- **Old footage.** The clip and stills show 0.7.3x. Replace them when 0.77 footage exists.
- **Performance claims.** Always with conditions. Do not quote 120 fps bare.
- **Sideloading.** State that itch does not install the APK and Developer Mode is required.
- **Support load.** Point feedback to GitHub Issues; do not promise store-style updates.

## 7. After launch

- Add the itch link to `README.md` and the next release notes.
- Watch GitHub Issues and the itch comments for install failures.
- Keep 0.77.0 on GitHub as the rollback APK.
- Do not hot-swap the uploaded file; ship fixes as a new version.
