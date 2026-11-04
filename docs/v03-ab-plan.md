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
| **Debris shards** (FR-013) | `visual_off="debris"` | defaults (shards on) | 128-instance MultiMesh + 10 buffer writes per cut + one uniform/frame | queued |
| **Bloom / glow** | `glow=false` | `glow=true` (bench-only) | the removal was reasoned, never measured; the answer decides whether a cheaper glow is worth building | queued |
| **Environment palette** (FR-027/028) | `environment="classic"` | `environment="map"` | per-map colours write the same uniforms as before; the arm verifies "free" rather than assuming it | queued |
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

(appended as arms complete; raw captures in `perf/captures/`)
