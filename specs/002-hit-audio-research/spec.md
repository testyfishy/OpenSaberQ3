# Feature Specification: Hit-feedback audio design research (Godot 4.6 VR rhythm game, Quest 3)

**Feature Branch**: `002-hit-audio-research`

**Created**: 2026-11-01

**Status**: Done (G4)

**Input**: User description: "Research hit-feedback audio design for Godot 4.6 VR rhythm game on Quest 3 — verify how VR rhythm games do hit audio, what Godot 4.6 spatialisation offers, how to map cut-score data to audio parameters, whether GPU audio is real on Snapdragon XR2 Gen 2, cheap-CPU best practice for many short sounds, and CC0 sample licensing."

## Intent

Produce a sourced design brief that tells the implementer exactly what to change in
`game/sabers/default/default_saber.gd` (and the saber `.tscn`) to replace the single
fixed non-varying hit tone with a velocity/score-varied, non-fatiguing, spatially
plausible hit-feedback system, and to settle the GPU-audio question with evidence.

## Scoped change (research, no gameplay code in this session)

**Symptom**: every hit plays the same stream at the same pitch/volume from one
`AudioStreamPlayer3D` per saber (`game/sabers/default/default_saber.tscn:323`,
`game/sabers/default/default_saber.gd:60`). Rapid hits on one saber cut each other
off because there is exactly one voice per saber. The only variation anywhere is a
0.9–1.1 pitch jitter in `game/sabers/particles/particles_saber.gd:21`, applied
*after* `super.hit()` already called `play()`.

**Root cause of the flatness**: `hit(time_offset)` receives only a time offset.
The score components that already exist per hit — `cut_angle_accuracy`,
`cut_distance_accuracy`, `travel_distance_factor`, `beat_accuracy`
(`game/BeepCube/BeepCube.gd:132-139`) and `controller_speed`
(`game/LightSaber.gd:140`) — are computed *after* `saber_visual.hit(time_offset)`
is called (`game/LightSaber.gd:136` vs `:143`), so audio cannot see them.

**Blast radius of the eventual change**: saber scripts + saber scene + one new
autoload/manager + bus layout. No scoring or note logic changes. This session
writes no gameplay code.

## Requirements *(mandatory)*

- **FR-001**: The brief MUST document how at least three shipping VR rhythm titles
  handle hit audio, marking each claim VERIFIED (primary source or direct
  measurement) or PLAUSIBLE (inference from secondary sources).
- **FR-002**: The brief MUST document Godot 4.6's native spatial-audio surface:
  `AudioStreamPlayer3D` attenuation models and units, `panning_strength`,
  HRTF availability, Doppler, and reverb/Area3D, citing Godot docs or source.
- **FR-003**: The brief MUST state whether a Meta first-party spatial-audio SDK is
  usable from Godot on Quest 3, with a source for the claim.
- **FR-004**: The brief MUST give concrete, defensible parameter ranges mapping
  the project's existing cut data (angle, centrality, travel/velocity, beat
  accuracy, saber colour, note position) to pitch, gain, layer and filter values.
- **FR-005**: The brief MUST give an explicit verdict on GPU audio synthesis for
  this target, distinguishing (a) what PS5 Tempest actually is, (b) whether GPU
  audio ships on mobile/VR, (c) whether Godot's `AudioStreamPlayback` could
  generate on GPU and what readback costs. Each sub-claim sourced.
- **FR-006**: The brief MUST specify the cheapest correct Godot pattern for
  ~8 hits/second, including voice pooling, polyphony, bus layout, and whether
  per-hit node churn is measurable.
- **FR-007**: The brief MUST name specific sample sources with licences and state
  the attribution obligations each imposes.
- **FR-008**: The brief MUST end with an implementation order in dependency order,
  each step naming the file it touches.
- **FR-009**: Claims that could not be sourced MUST be labelled PLAUSIBLE or
  UNVERIFIED rather than presented as fact.
- **FR-010**: The brief MUST pick a polyphony mechanism for overlapping hits on
  one saber (two hits within ~50 ms must not cut each other off), naming either
  `AudioStreamPlayer3D.max_polyphony` or a small voice pool, with the reason and
  a voice-steal rule.
- **FR-011**: For every mapped input in FR-004 the brief MUST state whether the
  value is known at contact time or only after the swing completes, and state how
  it reaches `hit()` (reorder `LightSaber.gd:136/143` or pass a hit-info object).
- **FR-012**: The brief MUST give measurable anti-fatigue limits: pitch spread
  ≤ ±2 semitones, gain range ≤ ~9 dB, ≥ 3 round-robin variants per layer, no
  exact repeat of the same sample+pitch twice in a row.

## Success Criteria *(mandatory)*

- **SC-001**: Every one of the six questions in the request is answered with at
  least one named source; zero answers are left as "it depends" without a default.
- **SC-002**: The GPU verdict is unambiguous (real win / false economy) and cites
  at least two independent sources.
- **SC-003**: An implementer can build the system from the brief alone, without
  further research: every parameter has a numeric starting value and a range.
- **SC-004**: No claim labelled VERIFIED is contradicted by a primary source cited
  in the same document.
- **SC-005**: Every number in FR-004's parameter tables is tagged either
  "sourced" (with the source) or "tuning start" (a deliberate estimate to be
  measured on device). Untagged invented numbers fail this criterion.

## Out of scope

- Writing or modifying gameplay/scene code this session (research only).
- Music/beatmap audio pipeline, latency calibration, haptics tuning.
- Non-Quest platforms, PCVR, Web export.
- Buying or commissioning commercial sample libraries.

## Open questions

- `[NEEDS CLARIFICATION: none blocking — the parent session owns any product decision about whether hit audio should be pitch-locked to musical key; the brief will present both and recommend one.]`

## Assumptions

- Target is Quest 3 standalone, Snapdragon XR2 Gen 2, Godot 4.6, Vulkan/mobile renderer.
- Hits per second peak around 8 (both sabers, dense streams); typical 4–6.
- Saber tip speed is in metres/second (1 Godot unit = 1 m in this project).
- The two sabers are the only emitters of hit sound; bombs/chain links are separate.

## Consultation Log

| Gate | Asked | Verdict | Action taken |
|------|-------|---------|--------------|
| G0 | Is the FR/SC set sufficient to stop the brief becoming opinion? Where should the cut-data→audio mapping anchor? How hard to push the GPU question? | **GO WITH CHANGES** | Added FR-010 (polyphony + voice-steal), FR-011 (data availability at contact + delivery to `hit()`), FR-012 (measurable anti-fatigue limits), SC-005 (every number tagged sourced/tuning-start). Plan changes adopted: anchor gain/cutoff/layer to physical speed + centrality, pitch as small jitter with optional key-lock; GPU section capped at ~10% of effort; `LightSaber.gd` ordering change placed first in the implementation order; Meta SDK limited to one search pass with a dated "no maintained binding" fallback. |
| G4 + G5 | Can an implementer build from `specs/002-hit-audio-research/research.md`? Does the doc still answer FR-001..FR-012 / SC-001..SC-005? | **SHIP WITH FIXES** | Drift found: FR-012/SC-003 failed (the three gain terms summed to −15 dB, so a `[-9,+1.5]` clamp still spanned 10.5 dB) and FR-004 had no filter row. Fixed: gain split into −6/−1.5/−0.5 terms plus ±0.5 jitter with the total clamped to `[-8.5,+0.5]` (exactly 9 dB); randomizer `random_volume_offset_db = 0`; filter requirement resolved as *baked into the soft layer* because `AudioStreamPolyphonic` has no per-voice DSP and `attenuation_filter_cutoff_hz` is node-wide; added the `AudioStreamPolyphonic` lifecycle rules (single `play()` in `_ready`, cache the playback; any later `play()`/`stop()` invalidates all voice ids, so step 5 now deletes every `hitsound.play()` call); added the explicit `&"SFX"` bus argument as a `[P]` device check; named the three on-device tests with pass conditions. |
