# v0.3 A/B testing plan (one arm pair per new feature)

The rule the player set: **no feature is included (or made default) before its cost is measured
as an arm pair**, on the same map, bot and preset, in the same session. This file is the plan and
the record.

## Method

- **Harness:** `tools/perf/feature-ab.ps1 -Feature <name>` runs the off arm and the on arm back to
  back and prints both. Each arm uses `run-vrapi.ps1`, so the VrApi **GPU%** counter and the
  app frame time come from the runtime, not from our own timing.
- **Preset:** the shipped Performance preset is pinned in every arm
  (`render_scale=1.0 msaa=1 foveation=2`), so an arm pair is about the feature, not resolution.
- **Map/bot:** ODDS ExpertPlus, bot at 0% miss, 120 Hz, 60 s per arm unless stated.
- **Noise band:** from the 180 s repeats, run-to-run spread on on-time is ~1.2 pp (binomial) and
  p99 moves by up to 0.3 ms. A difference below that is *not* a cost. Any claim that a feature is
  free needs the difference to sit inside the band **and** the same sign in both arms of a repeat.
- **Battery protocol:** arms run only when the headset reports >= 40% and AC powered, spaced by
  idle gaps, and the app is force-stopped after each. No continuous overnight play.

## Arm pairs

| Feature | Off arm | On arm | Why it needs an arm | Status |
|---|---|---|---|---|
| **Debris shards** (FR-013) | `visual_off="debris"` | defaults (shards on) | 128-instance MultiMesh + 10 buffer writes per cut + one uniform/frame | queued (battery) |
| **Bloom / glow** | `glow="false"` | `glow="cheap"` and `glow="true"` (bench-only) | the removal was reasoned, never measured; three arms separate "off" from Godot's seven-pass glow and from a single-level glow that keeps the resolve but drops six blur passes | queued (battery) |
| **Environment palette** (FR-027/028) | `environment="classic"` | `environment="map"` | per-map colours write the same uniforms as before; the arm verifies "free" rather than assuming it | queued (battery) |
| **Chroma event colours** | not applicable | not applicable | per-event colour is parsed at load and written once when the event fires; there is no per-frame work to isolate. Recorded as by-construction-zero, and checked by loading a Chroma map (`Somewhere Out There`) and reading the frame stats against `ODDS` only as a sanity check | recorded |
| **BPM segments** (FR-025) | not applicable | not applicable | load-time parse plus two binary searches per spawn; no per-frame cost. Covered by the BPM unit test and a bot run on `FitBeat` (14 segments) | recorded |
| **Fake-note filter** (FR-026) | not applicable | not applicable | fewer notes exist after load, so the arm would be "less work", not more. Logged at load: `fakes_filtered` | recorded |
| **Per-wall colour + wall tint** | not applicable | not applicable | one uniform write per wall spawn, same count as the size write it sits beside | recorded |
| **Boost palette** (FR-029) | not applicable | not applicable | two colour assignments when a boost event fires | recorded |

## What a result has to look like

- `GPU%` median, on-time %, dropped %, p50/p95/p99/max and the three thirds of the run.
- Decision rule: if the on arm is worse than the off arm by more than the noise band, the feature
  is either optimised or its default changes. If it is inside the band, it stays on and the number
  is recorded in `PERF.md`.
- Bloom specifically: if the measured cost is small (< ~0.5 ms), restore it as a setting with a
  modest configuration; if it is 0.5–1.5 ms, build the separate quarter-res emissive glow layer
  (which avoids resolving the MSAA buffer) and measure that; above that, keep it off and record
  the number so the argument is settled.

## Results

### Blocked, 2026-11-03 night

The headset reported **10% while on AC via the PC's USB port** and the level was falling, not
charging. Running six 120 Hz arms would have risked shutting it down overnight, which the player
explicitly asked us not to do. No device arms were run. Everything needed to run them is in
place; the moment the headset is on a real charger at >= 40%:

```
pwsh -File tools/perf/feature-ab.ps1 -Feature debris
pwsh -File tools/perf/feature-ab.ps1 -Feature environment
pwsh -File tools/perf/bloom-ab.ps1
```

Each writes `perf/captures/<name>-*.{bench.csv,meta.txt}` and prints the table.

### Harness bug found and fixed before any run

A bare identifier in a bench flag (`visual_off=debris`, `environment=classic`) makes Godot's
ConfigFile fail to parse, so the run aborts as `bad_config` and looks like a crash. The harness
now quotes every string value, and `tools/tests/test_flag.tscn` reports the parse result without
starting a run.

### Device results (Quest 3, ODDS ExpertPlus, 120 Hz, Performance preset pinned, 60 s arms)

| arm | GPU% median | App median | on-time | dropped | p99 |
|---|---|---|---|---|---|
| bloom off | 0.77 | 4.96 ms | 46.83% | 0.22% | 9.84 ms |
| bloom cheap (1 level) | 0.78 | 5.08 ms | 48.90% | 0.18% | 10.08 ms |
| bloom full | 0.78 | 5.12 ms | 49.17% | 0.20% | 9.98 ms |
| **repeat** bloom off | 0.75 | 4.98 ms | - | - | - |
| **repeat** bloom full | 0.78 | 5.13 ms | - | - | - |
| debris off | 0.75 | 4.94 ms | 47.72% | 0.13% | 9.75 ms |
| debris on | 0.76 | 4.97 ms | 47.01% | 0.13% | 9.91 ms |
| environment classic | 0.76 | 5.06 ms | 46.39% | 0.18% | 10.01 ms |
| environment map | 0.75 | 4.93 ms | 45.54% | 0.17% | 9.95 ms |

Readings: **glow costs about 0.03 GPU (2-3% relative) and 0.15 ms of app time**, both repeats
agreeing, which is small but real - not free, and not the 1-2 ms the earlier reasoning predicted.
The MSAA resolve dominates: the single-level "cheap" arm costs almost the same as the full chain.
**Debris costs 0.01 GPU and 0.03 ms**, i.e. inside the noise band.

Decisions from these numbers:
- Glow becomes a setting (Off / Subtle / Full), **default Subtle**: the cheapest glowing option,
  with Full available for players who prefer the authored chain.
- Debris stays on by default; the arm shows it is free (+0.01 GPU, +0.03 ms, p99 +0.16).
- The per-map environment palette is free within noise (map is 0.01 GPU and 0.13 ms *better* than
  classic, which is ordering noise): default stays Map.

### Measured off-device (not a substitute for the arms)

- `environment="classic"` applies and logs `mode=1` with the old red/blue notes and red walls
  (Gloom, desktop capture).
- Glow renders on the desktop build (`glow=true` produces visible bloom on blades and HUD), so the
  arm is exercising a real effect, not a no-op.

