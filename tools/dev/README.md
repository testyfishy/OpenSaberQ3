# Local scripts

These run on your PC and cost nothing to use. Run them from a normal terminal in the repo root.

| Script | What it does |
|---|---|
| `pwsh tools/dev/check.ps1` | Every headless check plus a boot test; ends with `CHECKS PASS` or `CHECKS FAIL`. About three minutes. |
| `pwsh tools/dev/build.ps1` | Exports the release APK to `F:\Dev\BeepSaberBin` and validates its version and hand-tracking entries. Add `-Bump` to raise the version first, `-Install` to put it on the Quest, `-Launch` to start it. |
| `pwsh tools/dev/botrun.ps1 -Map "ODDS" -DifficultyIndex 5` | Plays a song on the headset with the bot (no hands needed) and prints hits, misses, score and any script errors. Ends with `BOTRUN PASS` or `BOTRUN FAIL`. |
| `python tools/dev/census.py [folder]` | Counts which map features a folder of maps uses. Defaults to `%TEMP%\toolchain\allsongs`. |

The usual loop after a code change: `check.ps1`, then `build.ps1 -Bump -Install`, then `botrun.ps1`.

The Android export has to run from your own terminal: Gradle's JDK 17 cannot open its internal
pipe from a sandboxed tool shell.
