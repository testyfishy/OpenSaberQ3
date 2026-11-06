# 0.6.0 device evidence (Quest 3, `2G0YC1ZF9J0G2V`)

Captured 2026-11-06 from the 0.6.0 debug build, then the 0.6.0 release for the upgrade test.
Raw captures live in `perf/captures/` on this machine (gitignored); these are the lines that
matter.

## Backfill on the real library

`source_backfill.log` (debug build, first run after the JSON workaround):

```text
queued 13
hash user://OpenSaber/Songs/hiroki. - Birthdays (feat. Hatsune Miku & Kasane Teto)/ = e493620492860c23b184becb6a8c25e41fedca31
lookup e493620492860c23b184becb6a8c25e41fedca31 -> 200
hash user://OpenSaber/Songs/TheFatRat_Timelapse/ = 4d35efe2e086ac6c7b90a00b9bb3fd03f8f416a1
lookup 4d35efe2e086ac6c7b90a00b9bb3fd03f8f416a1 -> 404
hash user://OpenSaber/Songs/Fall Out Boy - The Phoenix/ = bf2c367d29b133b66dc27f6f8e20467d0ec3301f
lookup bf2c367d29b133b66dc27f6f8e20467d0ec3301f -> 200
...
hash failed user://OpenSaber/Songs/UploadedSong-2494795461/ (missing:,)
hash failed user://OpenSaber/Songs/UploadedSong-527932676/ (missing:,)
finished updated=10
```

Result: 11 sidecars written (10 BeatSaver, 1 Unknown+hash), 2 maps left Unknown because their
`Info.dat` references a difficulty file that is not in the folder.

## BeatLeader on the headset

`[bench] leaderboard_probe=true` (bench-only path; the release ignores flags):

```text
probe_hash_result=bf2c367d29b133b66dc27f6f8e20467d0ec3301f
probe_leaderboard_song=The Phoenix
probe_leaderboard_hash=bf2c367d29b133b66dc27f6f8e20467d0ec3301f
probe_leaderboard_difficulty=ExpertPlus
probe_leaderboard_mode=Standard
probe_leaderboard_status=Top 10 of 10 shown.
probe_leaderboard_error=
probe_leaderboard_rows=10
exit_reason=leaderboard_probe
```

## No background work once Playing starts

With all sidecars except Phoenix removed, a 30 s dense-map bench (`v060-stop2`) logged:

```text
ready
queued 11
hash user://OpenSaber/Songs/hiroki. - Birthdays (feat. Hatsune Miku & Kasane Teto)/ = e493...
stopped at 0/11
```

`fps median 120  App median 5.08 ms  GPU% median 0.87  samples=3550  cubes_peak=7`. No lookup
after `stopped`, and the panel was never opened, so no BeatLeader request ran during play.

## Upgrade 0.5.1 -> 0.6.0 (data kept)

`adb install -r -d OpenSaber-v051.apk` then `adb install -r OpenSaber-v060.apk`; after a launch
and a debug reinstall to read app-private files:

```text
d4cfb1a6bdd4cc1334c177bb6d70f2523e292e2a431f7642aa8dc2b3d285f141  files/config.ini
fed011f759a855a91634c984de68737cc8b2fec65555f07c03227fca7b07955f  files/profiles.json
1131ab710f3f34ac0dc71b1cbede461f7c33a72ce75d60070200d9104c6ae884  files/highscores.json
```

Identical to the hashes before the downgrade/upgrade.

Release build ignores the bench: with a valid `bench.flag` pushed, a fresh launch wrote no
`bench_meta.txt`, `bench.csv` or `bench.flag.consumed`.

## Android export quirk

`JSON.parse_string` inside a static function of a `class_name` script returned `null` for a valid
body in the exported APK (the BeatLeader board body, and every map `Info.dat`), while
`vr.load_json_file` (autoload instance method) parsed the same file. The fix:

- `MapSource.compute_level_hash` reads `Info.dat` through `vr.load_json_file`.
- `BeatLeaderPanel` parses the HTTP body in its (instance) context and calls
  `BeatLeaderApi.parse_board_value` / `parse_scores_value`.

Both carry a comment; do not collapse them back into a static `JSON.parse_string`.
