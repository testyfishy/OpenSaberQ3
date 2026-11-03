# Feature Specification: v0.3 — feedback, layout and frame stability

**Feature Branch**: `009-v03-polish`

**Created**: 2026-11-02

**Status**: In progress

**Input**: Player feedback after playing v0.2 on a Quest 3, plus an instruction to work the
whole list overnight as the v0.3 release, one item at a time, measuring before and after each.

## Why v0.3 exists

v0.2 shipped the format, browser and settings work. Playing it produced six complaints, in the
player's words:

1. "The reflection of the blades on the floor is very bright" and "a singular light object
   gives such a diffuse large blob" — the floor light is not believable.
2. UI text overlaps: bottom-right HUD words sit on each other; the end-of-map score card does
   not sit right.
3. BeatSaver list scrolling is not smooth ("a couple of ticks, then it stops").
4. A random red dot appears mid-play and distracts.
5. Audio: "tinny", "minimal in intensity", "barely hear it beyond the background music", and
   left/right/above/below are indistinguishable. "The vibration of the sticks is better
   feedback than the audio, which is bad design."
6. "It feels like there is very minimal physicality" when cutting a block.
7. The skybox "looks poorly designed"; a black void would be preferred; options wanted.
8. "I'm definitely feeling more stutter with the new changes."

## Requirements

### Frame stability (do this first — everything else is judged against it)

- **FR-001**: A stutter metric MUST be reported separately from the average: p99 and max
  frame interval, count of frames over 1.5x period, and the number/length of consecutive-frame
  clusters. Averages hide exactly the frames the player feels.
- **FR-002**: The shipped default configuration MUST be no worse than v0.2 on that metric.
  Where a visual setting causes measurable stutter, it MUST be fixed or its default changed.
- **FR-003**: A capture MUST be possible during *human* play, not only bot play: a mode that
  records the same CSV while the player plays, started before a map and written out when the
  song ends, so the measurement describes real play.

### Feedback (physicality)

- **FR-004**: Hit feedback MUST be layered: audio, haptics and visuals each contribute, and
  each MUST be measurable on its own (an audio probe, a haptic log, a visual toggle).
- **FR-005**: Audio MUST be audible over the music at default volumes: verified by an offline
  measurement of the hit samples (band energy and loudness) plus music ducking, not by ear
  alone.
- **FR-006**: Directional feedback MUST be honest about what the hardware can do: left/right
  from stereo panning, and the player MUST be told plainly that up/down cannot be reproduced
  without HRTF.
- **FR-007**: An in-game debug analyser MUST exist to show per-hit level, spectrum and pan,
  off by default, so audio quality can be inspected while playing.

### Presentation

- **FR-008**: The floor light MUST read as light from a blade, not a painted disc: falloff
  driven by distance and angle to the blade, peak brightness capped below the blade's own
  emission, and a setting to tune it.
- **FR-009**: The sky MUST be selectable between void (default), gradient and panorama, and
  switching to void MUST NOT dull the scene: ambient and reflected light sources must be set
  explicitly rather than inherited from the removed sky.
- **FR-010**: No two HUD text elements may overlap at maximum score/length, and the end-of-map
  card MUST lay out without overlap on a 4:3 panel.
- **FR-011**: The BeatSaver list MUST scroll smoothly: measured as a per-frame scroll delta
  sequence with no multi-frame stalls, verified by an automated probe.

### Defects

- **FR-012**: The intermittent red dot during play MUST be identified and either removed or
  explained. It MUST NOT remain an unexplained artefact.

## Success criteria

- **SC-001**: v0.3 default configuration stutter metrics are at or better than v0.2's
  (`v03-def` capture, 60 s, ODDS ExpertPlus, 120 Hz).
- **SC-002**: Turning every visual setting off changes p99 by less than the run-to-run noise
  band established in v0.2 (sigma ~1.1 pp on the on-time metric).
- **SC-003**: Human-play capture produces a CSV with the same columns as a bot capture and is
  retrievable with `adb pull`.
- **SC-004**: Scroll probe reports >= 95% of sampled frames moving by a non-zero delta with
  no zero-run longer than 2 frames.
- **SC-005**: Audio: hit samples carry measurable energy in the 200 Hz - 5 kHz band and are
  ducked into the music by a sidechain; before/after numbers recorded.
- **SC-006**: Sky void is the default, and the scene's ambient brightness is unchanged within
  10% (measured, not judged by eye).
- **SC-007**: Every item in this sheet carries a before/after measurement or an explicit
  statement of why it could not be measured.

## GPU lever curve (Quest 3, ODDS ExpertPlus, 120 Hz, 40 s arms, VrApi GPU% median)

The runtime counter is the reliable signal: GPU% is the share of the 8.33 ms budget the GPU
uses. Baseline is 0.86 at 2107x2208 with 4x MSAA and no foveation.

| configuration | GPU% | on time | dropped | p99 |
|---|---|---|---|---|
| baseline: 2107x2208, MSAA 4x, FFR 0 | 0.86 | 78.3% | 0.21% | 10.37 ms |
| MSAA 2x, same resolution | 0.77 | 82.4% | 0.02% | 9.57 ms |
| FFR 2, same resolution and MSAA | 0.80 | 85.1% | 0.07% | 9.59 ms |
| render scale 1.0 (1680x1760), MSAA 4x | 0.69 | 88.6% | 0.00% | 9.52 ms |

Each is one lever. The player has to pick where on this curve to sit, because every one of them
trades sharpness: resolution softens everything, MSAA softens edges on glow and thin geometry,
foveation softens the periphery. Combined arms are being measured to complete the curve.

Nothing on the CPU side reaches this: the CPU is at 22% and halving the physics rate moved the
on-time figure by 0.6 points.

## Out of scope

- Ray tracing, real-time GI, shadow maps for the floor light.
- HRTF audio (Godot has none; Quest has no system HRTF for us).
- Re-authoring the whole menu system; only the overlap defects and the end card are in scope.
- Physics debris on Quest (the slice particles are freed on Android; see v0.2 notes).

## Open questions

- Which node draws the red dot? Not reproducible from code inspection alone; needs a capture
  from a human-play session (FR-003) or a frame-by-frame recording.
- How much of the perceived stutter is thermal throttling rather than the build? The stress
  protocol in PERF.md has never been run.

## Landing order

1. Stutter baseline and regression hunt (FR-001, FR-002) — because every later item is
   measured against it.
2. Human-play capture (FR-003) — because it is the instrument the player asked for.
3. Sky void + ambient fix (FR-009) — cheap, highly visible, buys GPU headroom.
4. Floor light (FR-008) — tuned against the new sky.
5. HUD and end card overlap (FR-010).
6. Scroll smoothness (FR-011) — implemented; needs the probe to pass SC-004.
7. Red dot (FR-012).
8. Audio measurement, ducking, redesign (FR-005, FR-006, FR-007).
9. Feedback research application (FR-004).
10. Final optimisation pass and release.

## Consultation Log

| Gate | Question | Verdict | Follow-up |
|---|---|---|---|
| G1 | Light / UI / sky / audio approach and order | GO WITH CHANGES: light A, sky A with ambient fix, HUD A + end card SubViewport, audio measure first then redesign | Recorded in the v0.3 order above |
| measure | Is the v0.2 measurement method precise enough to attribute a 1-4 pp visual cost? | **NO.** Three 60 s runs of the same scenario (ODDS ExpertPlus, 120 Hz) gave 74.48 / 78.38 / 78.25% on time. The spread is ~4 pp, the same size as the effect being measured | FR-001 amended: comparisons need >=180 s runs or >=3 repeats; no per-feature claim below ~5 pp without both |
| measure | Is the drop from the earlier 80.07% a regression? | Not established. 80.07 sits inside the same 4 pp band as today's 74.5-78.4. Thermal status 0 (no throttling), 47.9 C | Do not chase a regression until a 180 s baseline exists |
| measure | **180 s run, defaults vs all visuals off** | Visuals cost **nothing measurable**: 63.01% vs 64.28% on time, identical dropped (0.72%), p95 (10.40 vs 10.38), p99 (11.93 vs 11.98), sd (0.96 vs 0.97), hitches (140 vs 141) | The visual layer is exonerated. Stop attributing stutter to it |
| measure | What does 180 s reveal that 60 s hid? | **The frame time drifts upward within the run**: 8.36 ms in the first 20 s, 9.04 ms in the last, on-time 80.7% -> 47.7%, and it does this identically with all visuals off. Correlates with notes live (1.1 -> 8.0) and the start of arc spawning | Two hypotheses queued: audio voice churn (`no_audio`) and CSG arcs (`arcs=false`) |
| change | Per-note cost on the drift path | `Cuttable._physics_process` read `global_transform` twice per tick per live note though it already writes the local transform; notes are children of an origin-placed track, so local z is the same number | Replaced with one local read. Scales with live notes, which is the shape of the drift |
