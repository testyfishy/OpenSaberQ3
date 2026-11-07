# itch.io push plan

**Status:** plan only. 0.6.3 is the arc/menu build; upload only the 0.6.3 APK. The clip and
stills are kept locally (not in the repository). Nothing has been uploaded or published. The page needs the owner's itch.io
account and an explicit go-ahead. Page copy is in [itch-page.md](itch-page.md).

## 1. Go / no-go

All of these must be true before the page goes live:

- [x] **0.6.3 APK** built from the tagged commit `v0.6.3-q3`: 78,146,219 bytes, SHA-256
      `F123F07D30EBD38E8324303F6E31409DFD58778EB9F4A422EB9659F58DAD2D43`, versionCode 13. 0.6.0
      must not be uploaded: its icon is the old mark and it still contains the demo.
- [x] **Bundled demo song removed in 0.6.1.** TheFatRat “Time Lapse” is no longer in the
      repository, the 0.6.3 APK or matching libraries. Upload 0.6.3 only; do not upload or
      promote 0.6.0, which still contains it.
- [x] **Real headset media.** The 24 s 1080p60 clip with game audio and four stills are kept
      locally in `itch-media/` (not committed). Add menu stills later if wanted.
- [ ] Page copy pasted from `docs/itch-page.md`, including **AI-generated content: Graphics** and
      the non-affiliation line.
- [ ] The **AI disclosure field** is set to Yes / Graphics.
- [ ] Every performance claim carries its test conditions (Quest 3, Performance preset, bot).
- [ ] The known-issues list matches the build.
- [ ] No "Beat Saber" in the title, tags, cover or screenshots; no Beat Saber assets anywhere.
- [ ] Upstream credit is visible in the description and the licence link works.
- [ ] The APK installs over 0.6.0 with maps, scores and settings kept.

## 2. Build and verify

1. Build 0.6.3 from the tagged commit with the new icon/menu logo and the arc/menu fixes.
2. The bundled demo is already absent (`game/data/maps/Songs` is empty) and the build
   template was cleaned; nothing to remove.
3. Verify the package:
   - `aapt dump badging` shows versionName 0.6.3, versionCode 13, and no `application-debuggable`.
   - `apksigner verify --print-certs` shows the same certificate as 0.6.0.
   - Install over 0.6.2 (done), launch, play one map, open the library source filter, both menu
   signs and a BeastSaber playlist. The over-0.6.0 path still needs one run.
4. Record the size and SHA-256 in the upload notes and in the release notes.
5. Upload the file as an **Android** build. itch treats it as a download; it does not install it.

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
| AI disclosure | Graphics: yes |

Do not use `beat-saber` as a tag. Do not put "Beat Saber" in the title or the cover.

## 4. Page

Paste the copy from `docs/itch-page.md`:

- tagline and short description;
- full description with the feature list, credits, AI disclosure, install, known issues,
  non-affiliation and the source link;
- screenshot captions under the real captures.

## 5. Upload and publish

1. Create the project, set the fields above, save as **draft**.
2. Upload the APK as an Android build; set the version string and the minimum requirement (Quest 3,
   Android 12+; sideloading required).
3. Add the cover, banner, screenshots and clip.
4. Tick the AI-generated content disclosure (Graphics) and check the preview on desktop and mobile.
5. Verify the download works while logged out (open the page in a private window).
6. Publish only after the owner signs off on the preview. Then:
   - link the itch page from the GitHub README and the release notes;
   - do not change the uploaded file afterwards without a version bump.

## 6. Risks

- **Demo song licence** — resolved for 0.6.3 by removal. Do not upload 0.6.0, and do not
  reintroduce the track without written permission.
- **Trademark** — no Beat Saber name, logo or art in the page, tags, screenshots or APK. Use
  "BeatSaver maps" and "rhythm game".
- **AI disclosure** — required. The cover, logo and icon are AI-generated vector art; the field and
  the copy must say so.
- **Screenshots** — simulator overlays and debug HUD text make the build look unfinished. Use real
  headset captures only.
- **Performance claims** — always with conditions. Do not quote 120 fps bare.
- **Sideloading** — state that itch does not install the APK and Developer Mode is required.
- **Support load** — pin the known issues and the GitHub issues link; do not promise store-style
  updates.

## 7. After launch

- Add the itch link to `README.md` and the next release notes.
- Watch the first comments for install failures and missing Android permissions.
- Keep `v0.5.1` as the rollback APK on GitHub.
- Plan 0.6.3 for the first round of itch feedback; do not hot-swap the uploaded file.
