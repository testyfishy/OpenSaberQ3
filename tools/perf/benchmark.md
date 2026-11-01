# Benchmark mode (deterministic gameplay run)

Unattended frame-time capture: the app starts a map, records one row per rendered frame, writes
the results and quits. No VR menu, no human, no debugger. Serves spec FR-006 / FR-007 / FR-014 /
FR-023 and unblocks the reference scenario in `PERF.md`.

Implementation: `game/scripts/BenchmarkRunner.gd`, created from `BeepSaber_Game._ready()` **only**
when a bench flag file exists. A launch without the flag is byte-for-byte the old behaviour.

## Trigger: the flag file

Standard Godot `ConfigFile` (INI). Strings **must be double-quoted**; numbers are bare; `;`/`#`
start a comment line. The `[bench]` section is required.

```ini
[bench]
map = "Timelapse"          ; required - case-insensitive substring of song_name or filepath
difficulty_index = 0       ; optional - 0-based index into the map's difficulty_beatmaps
difficulty = "Easy"        ; optional - case-insensitive match on difficulty or custom_name
difficulty_rank = 1        ; optional - exact DifficultyInfo.difficulty_rank
duration = 60              ; optional - seconds of gameplay to record; 0/absent = until the song ends
max_duration = 180         ; optional - hard cap in seconds (default 180)
```

Precedence: `difficulty_index` > `difficulty` > `difficulty_rank` > default of the lowest ranked
difficulty the map lists. `start_map()` takes a `DifficultyInfo` object, not a rank, so an index is
the primary selector.

Lookup order, with output written next to the flag that was found:

1. `user://bench.flag` — internal app storage. Only writable over `adb` on a **debuggable** APK
   (`run-as`), i.e. the `Oculus Quest (DEBUG)` preset.
2. `/sdcard/Android/data/<package>/files/bench.flag` — works on any APK, no storage permission.
   The runner derives this path from its own internal data dir.

The flag is renamed to `bench.flag.consumed` **before** the run starts, so a crash mid-run cannot
trap the next launch in benchmark mode.

## Output

`bench.csv` — one header row, then one row per rendered frame:

| Column | Meaning |
|---|---|
| `frame` | 0-based sample index |
| `ticks_usec` | `Time.get_ticks_usec()` (monotonic wall clock) |
| `delta_usec` | wall-clock interval since the previous sample — the honest frame interval |
| `process_delta_usec` | engine `_process(delta)` in µs, for comparison with wall clock |
| `song_pos_usec` | `song_player.get_playback_position()` in µs — aligns a spike with the map |
| `frames_drawn` | `Engine.get_frames_drawn()` — cannot see frames the XR compositor drops |
| `focused` | 1 while the app has focus; 0 after the headset is taken off mid-run |

`bench_meta.txt` — `key=value` block: map, filepath, difficulty name/rank/index and which rule
picked it, sample count, elapsed, exit reason, engine/OS/device, renderer method.
Both files are also summarised on stdout as `BENCH: ...` lines (visible in logcat).

Stop reasons, logged as `BENCH: exit=<reason>`: `duration`, `max_duration`, `song_end`, or the
aborts `bad_config`, `no_maps`, `map_not_found`, `no_difficulties`, `start_failed`, `no_scene_refs`.
Aborts exit with code 1 and write only `bench_meta.txt`.

## Device recipe (not verified by the author of this file on hardware)

```bash
PKG=io.github.testyfishy.opensaberq3   # DEBUG preset; RELEASE preset still uses org.godotengine.open_saber

# 1. keep the headset awake: pretend the proximity sensor sees a worn headset
adb shell am broadcast -a com.oculus.vrpowermanager.prox_close

# 2a. debug APK
adb push bench.flag /data/local/tmp/bench.flag
adb shell run-as $PKG cp /data/local/tmp/bench.flag files/bench.flag
# 2b. any APK
adb shell mkdir -p /sdcard/Android/data/$PKG/files
adb push bench.flag /sdcard/Android/data/$PKG/files/bench.flag

# 3. launch (activity name differs between templates; resolve it rather than guess)
adb shell cmd package resolve-activity --brief $PKG | tail -n 1
adb shell am start -n <resolved activity>

# 4. pull
adb exec-out run-as $PKG cat files/bench.csv > bench.csv        # debug flag location
adb pull /sdcard/Android/data/$PKG/files/bench.csv .             # external flag location

# 5. restore the proximity simulation
adb shell am broadcast -a com.oculus.vrpowermanager.automation_disable
```

The `focused` column should be 1 for every row; a 0 means the run was disturbed and must be
discarded, not averaged.

## Local sanity run (no headset)

```powershell
$d = "$env:APPDATA\Godot\app_userdata\Open Saber"
"[bench]`nmap = `"Timelapse`"`nduration = 3" | Set-Content "$d\bench.flag"
& "$env:LOCALAPPDATA\Godot\4.6.3\Godot_v4.6.3-stable_win64_console.exe" --headless --path .
```

Headless uses the dummy audio and renderer, so `frames_drawn`, absolute timings and `song_end`
detection are meaningless there — it only proves the plumbing (map selection, difficulty
selection, CSV shape, flag consumption, clean quit).

## Known side effects

If a run is not stopped by `duration`, it reaches the engine's normal song-end path, which
increments the map's play count and can record a zero-score highscore. That is existing game
behaviour and is deliberately not modified by benchmark mode.

## Bot (deterministic autoplay workload)

The advisor's rule: a workload that never cuts is a flattering microbenchmark, because debris,
slice particles, scoring and rumble all stay idle. So the bot **plays** the map. It drives the
real `SwingableRayCast` sweep; it never calls `note.cut()` directly.

`SwingableRayCast` samples the saber node's own transform (blade along local +Y), and
`LightSaber._physics_process` overwrites its own position/rotation every tick from
`offset_pos + extra_offset_pos` / `offset_rot + extra_offset_rot`. The bot therefore writes
`extra_offset_pos` / `extra_offset_rot`, converting its world-space target through the
controller's inverse transform, with `process_priority = -50` so it runs before the saber
consumes the offsets.

Note hit time is derived from the song's audio clock, not wall time, so a dropped frame produces
a real swept gap rather than being smoothed over.

```ini
[bench]
map="<substring of song name>"
duration=180
max_duration=240

[bot]
enabled=true        ; default false
miss_percent=0      ; deterministic stride of notes deliberately not swung (0..100)
sway=true           ; head sway on XROrigin3D (default true)
```

Head sway animates `XROrigin3D`, **not** `XRCamera3D`, because OpenXR tracking overwrites the
camera pose. Sway is yaw ±15° @0.2 Hz, pitch ±5° @0.13 Hz, lateral ±10 cm. On Quest, timewarp
runs every frame regardless of head motion, so sway changes culling/overdraw rather than adding
compositor cost — do not claim more for it than that.

### Extra CSV columns (bot workload)

`cubes_in_use`, `links_in_use`, `debris_live`, `slice_bursts`, plus `bot_score_*` keys in the
meta file. `slice_bursts` counts slice-particle bursts started since the previous sample; it
replaces a live particle count, which is not available on Android.

The calibration test depends on these: the synthetic run is only accepted if its CPU&GPU mean
and p95 are each >= the median of the worn calibration runs, and its peak debris/particle load
is >= the worn peak.

### Fidelity gaps (documented, not hidden)

- Chain links are not modelled individually; the bot cuts the head note only, so chain-link load
  is understated.
- The pose check validates origin error, not blade orientation.
- The bundled demo map starts its music late, so a short run reaches few notes; use a dense map
  and a long window (3 min) for a real workload.

