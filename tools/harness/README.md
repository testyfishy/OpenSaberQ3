# v0.4 proof harness

The v0.4 work happens on `harness-base` (v0.3 code + harness only) and `v4/cleanup` (branches from
it) in the worktree `../OpenSaberQ3-v4`. `godot-4-port` stays exactly what is installed on the
headset.

Nothing here changes gameplay. The harness exists so a refactor can be proven equivalent before
it is merged: replay identical, map dump identical, settings identical, goldens pass, draw calls
and node counts no higher.

## Map dump (FR-002 / SC-002)

`map_dump.tscn` parses a map - or every map under a directory - with the real loaders and writes a
canonical text dump: notes (beat, lane, layer, colour, direction, per-note colour and Noodle
position), walls, arcs, chains, light events (type, value, float, Chroma colour), BPM segment
count and the resolved palette.

```
godot --headless --path . res://tools/harness/map_dump.tscn -- <map-or-root> <outfile>
pwsh -File tools/harness/map_dump_all.ps1 -Root <songs-dir> -Out <outfile>   # one process per map
```

One process per map (the driver script) because a native crash in one map must not lose the whole
baseline. The 43-map audit set is extracted under `%TEMP%\toolchain\allsongs`.

Baseline: generated on `harness-base` from the v0.3 commit, stored with the source commit hash.
After each refactor slice the dump must be byte-identical.

## Settings round-trip (FR-003 / SC-003)

`settings_roundtrip.tscn` checks three things and prints `SETTINGSTEST PASS`:

1. defaults survive save -> reload unchanged (48 keys);
2. a v0.3-era file with unknown keys still loads the known ones;
3. a missing key falls back to its declared default.

## Baseline recorded on harness-base

- 45 maps (the 43-map audit set plus the bundled song and one duplicate export): `map_dump_all.ps1`
  reports `maps dumped: 45 failed: 0`; dump SHA256 `6FEFDF86DEB803A833DB4096671BD9BFE186775D1C4126F951905E491027C619`, lines 687292. The dump is
  regenerated rather than committed (it is several MB of text and deterministic).
- Replay: `[bench] replay=true, replay_frames=1440, refresh_hz=72` with
  `--fixed-fps 72 --disable-vsync` produced **two byte-identical logs** (same SHA256, 1,441
  frames, 22 events). Wall-clock duration is not usable as the stop condition because
  `--fixed-fps` runs the loop unthrottled; the frame cap is what makes the run reproducible.

## Still to build (in this order)

1. **Replay log (FR-001).** Fixed `--fixed-fps`, seeded RNG (bot, debris, pitch jitter, sway), and
   a clock seam so song time is `frame_index / fps` in replay mode instead of the audio clock.
   Log events, not frames: spawns (index, beat, quantised position), cuts (good/bad, score parts,
   combo), misses, final totals, plus a sparse position snapshot every 30 frames. Quantise
   positions to 1 mm and angles to 0.1 degrees.
2. **Threaded vs single-threaded map dump equality** - the safety net for the `Map.gd` split.
3. Then the slices: bench gating, PaletteResolver, NoteMotion, Map split behind a facade,
   PooledNode3D, scene-unique names, settings schema last.

## Acceptance per slice (host-only until v0.3 is approved)

- replay identical; map dump identical; tests green; settings round-trip green;
- draw calls, primitives and node counts no higher than baseline;
- host CPU script time (median of 3) not more than 5% worse;
- goldens pass a perceptual diff.

Device verification (install, bench within noise) stays a post-approval gate, because the headset
must keep the v0.3 build.
