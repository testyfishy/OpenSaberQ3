# Feature Specification: v0.4 - eloquent code

**Feature Branch**: `013-code-quality`

**Created**: 2026-11-04

**Status**: Draft (G1 consulted; implementation deferred until v0.3 ships)

**Input**: The player's observation that the codebase is probably "a hodgepodge" after months of
features, with a request for an optimised, clean, eloquent rewrite that produces the same outcome
and runs smoother. The G1 consult's verdict was: **ship v0.3 first, then refactor as v0.4, and
build the proof harness before any extraction.**

## Why v0.4 exists

Inventory at the time of writing: 124 GDScript files, 16,409 lines; 77 `static var` declarations
(36 in `Map.gd` alone); 11 autoloads; 46 deep `$a/b/c` node paths; colour rules duplicated in four
places; pooled nodes reimplementing the same lifecycle; 1,224 lines of benchmark tooling shipping
in the release build. None of this is visibly broken - the point is that every new feature is
getting more expensive to add, and the risk of silent behaviour drift rises with each one.

The G1 consult was explicit that this is **maintainability, not frame time**: the GPU is the
limiter, and only the bench-gating and pooled-node items could plausibly move a frame.

## Requirements

### Harness first (nothing is refactored before this exists)

- **FR-001**: A deterministic bot replay MUST exist: fixed seed, per-frame log of spawns (beat,
  time, position hash), cut results, score and combo, diffable byte for byte.
- **FR-002**: A colour dump MUST resolve every note, wall and event colour for the 43 audit maps
  (`docs/map-data-audit.md`), so palette refactors are checked against data, not screenshots.
- **FR-003**: A settings round-trip test MUST prove a config written by the old code reads
  identically through any new schema.

### Extractions, in this order

- **FR-004**: BenchmarkRunner and BotDriver MUST be excluded from release builds (export filter or
  a build-time feature tag), not merely left inert. Verified by the APK's file list and by a
  device run that still works.
- **FR-005**: A single `PaletteResolver` MUST replace the four copies of the colour rules (map
  environment colours, note colours, environment profile, player settings, Chroma per-entry).
  Checked against FR-002.
- **FR-006**: A single `NoteMotion.speed_at(beat)` MUST replace the repeated
  `BEAT_DISTANCE * bpm_at(beat) / 60` formula in every spawned object. Checked against FR-001.
- **FR-007**: `Map.gd` MUST be split behind a thin facade - `MapData` (stacks and loaders),
  `MapTimer` (BPM segments), `MapPalette` (colours), `MapSupport` (unsupported features) - one
  sub-object per commit, with the replay identical after each. Every split class needs an explicit
  `reset()` because static state survives scene changes.
- **FR-008**: `PooledNode3D` MUST own the acquire/release/hide/clear lifecycle with virtual hooks,
  and the five pooled types MUST stop reimplementing it. Checked with FR-001 plus the device bench.
- **FR-009**: Deep node paths MUST become scene-unique names (`%Name`, only where the node is in
  the same owner scene) or exported NodePaths. Checked with golden screenshots.
- **FR-010**: The settings file MAY become a declarative schema (key, type, default, emit) last,
  because it is the riskiest change for signal order; the autoload initialisation order MUST be
  preserved.

## Success criteria

- **SC-001**: Replay log byte-identical to the v0.3 baseline after every slice.
- **SC-002**: Colour dump identical after the palette extraction.
- **SC-003**: Settings round-trip identical after the schema change.
- **SC-004**: Golden screenshots (settings top/mid/bottom, gameplay, end card) unchanged within
  the noise of the capture path.
- **SC-005**: Existing tests green: `tools/tests/test_bpm.tscn`, `test_flag.tscn`, the hit-resolver
  and BeatSaver browser tests.
- **SC-006**: On-device bench, three runs, p99, max and the count of frames over 1.5x the period
  inside the v0.3 baseline's run-to-run noise band.
- **SC-007**: Release APK no longer contains the bench tooling, and a normal launch still works.

## Out of scope

- Rewriting the BeatSaver browser UI or the art.
- Changing gameplay, scoring or map format support.
- Any optimisation not justified by a measurement (the A/B plan in `docs/v03-ab-plan.md` is the
  model for how a claim gets made).

## Open questions

- Does the export filter break `preload` references to bench scripts? (BenchmarkRunner is
  preloaded by `BeepSaber_Game.gd`, so the reference has to move behind the flag too.)
- How much of `BeepSaber_Game.gd` (870 lines) is scene wiring that could move to exported
  NodePaths without changing signal order?

## Consultation Log

| Gate | Question | Verdict | Follow-up |
|---|---|---|---|
| G1 | Is a code-quality refactor appropriate now, and in what order? | **GO WITH CHANGES: ship v0.3 first.** Freeze the release candidate so the play-test and A/B data are not confounded. Build the replay/golden harness before extracting anything. Then: bench gating, PaletteResolver, NoteMotion, Map split behind a facade, PooledNode3D, `%Name`, settings schema last. Only bench gating and pooled nodes can plausibly move frame time; the rest is maintainability | Recorded as the order above; this sheet stays Draft until v0.3 ships |
