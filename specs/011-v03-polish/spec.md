# Feature Specification: v0.3 — feedback, layout and frame stability

**Feature Branch**: `011-v03-polish`

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
- **FR-013**: A cut cube MUST shed debris shards that fly the way the slice implies: the burst
  direction comes from the cut-plane normal and the blade's own velocity, shards tumble, fall
  under gravity and fade, and none of it is per-shard CPU physics. It MUST run as a fixed-size
  GPU-animated pool (one draw call, no allocation on a hit) and MUST have its own setting. The
  debris MUST be directional enough to tell a horizontal slice from a diagonal one.
  - Pool: 128 instances on one shared BoxMesh, 10 shards per cut, 0.5 s life, 3-4 cm cubes.
  - Opaque, unshaded, note-coloured; they fade by shrinking to zero, not by alpha blending,
    so they add no overdraw or sort work.
  - Motion is entirely in the vertex shader from per-instance custom data
    `(birth_time, vx, vy, vz)`: `p += v*t + 0.5*g*t*t`, plus a hashed tumble. Slots are a ring;
    the oldest is overwritten when full. Dead slots collapse to zero size in the shader, so
    there is no per-frame CPU work beyond one `now` uniform.
  - `custom_aabb` covers the play volume, or the moving shards get culled with the mesh bounds.
  - `now` comes from game time, not shader `TIME` (which wraps and runs through pause).
  - Velocity: shards on each side of the cut move along +/-n at 2-2.5 m/s, plus 0.2x the blade
    velocity, plus a ~20 degree cone of spread.

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

### Sound (spec FR-014..FR-020, from the G1 sound-design consult)

Direction from the G1 consult. These are requirements to verify against the headset and against
Beat Saber reference footage; the notes from memory are marked "verify".

- **FR-014**: Each hit MUST layer a transient (attack under 5 ms, most energy 2-6 kHz), a body
  (150-800 Hz) and a short tail (300 ms or less), with separate sounds for a good cut, a bad cut
  and a miss; a bad cut MUST be audibly duller. [verify against the video]
- **FR-015**: Each hit MUST get random pitch of +/-3-5% and rotate through at least 3 sample
  variants, so dense streams do not sound like a machine gun.
- **FR-016**: When several cuts land within 30 ms, each voice MUST be attenuated by 1/sqrt(n).
  Total SFX peaks MUST stay at or below -1 dBFS. Voice stealing is oldest-first and logged.
- **FR-017**: The music MUST be ducked by a compressor on the Music bus sidechained from SFX
  (`AudioEffectCompressor`), attack 1-5 ms, release 100-150 ms, 2-4 dB of gain reduction, capped
  at 4 dB, and MUST have its own setting.
- **FR-018**: A continuous swing whoosh MUST scale with saber speed, and blades touching MUST
  play a separate clash sound.
- **FR-019**: A hit sound MUST start within 20 ms of the cut event, with the measured offset
  distribution recorded. An optional "snap to beat" setting MAY align the sound to the note's
  scheduled time. [verify: believed to be Beat Saber's behaviour]
- **FR-020**: Each hit sound MUST be positioned at the cube, not at the saber.

### Environment (FR-021..FR-024, from the G1 ambience consult)

The user asked for per-map ambience, colour-coded to the track's own colours, with an
old-school audio-reactive layer. The map already carries a hand-authored light show, which wins
over any generated one.

- **FR-021**: The environment palette MUST come from the track, in this order: the map's
  environment colours (v3 `_envColorLeft/Right`, boost variants), then its note colours
  (`_colorLeft/_colorRight`), then the preset default. A player override of the note colours
  wins over the map. Readability guards: environment colours stay at or below 0.6x note
  brightness; if the two hues are within 30 degrees, or saturation is below 0.25, fall back to
  the preset palette. Lane and note colours are never changed by this.
- **FR-022**: `environment_name` MUST select an ambience preset from a short table of the stock
  Beat Saber environment names. A map that names an environment, or supplies environment
  colours, MUST NOT be randomised: the map is the designer and its choice wins. Only when a map
  supplies neither does a preset get chosen from a stable hash of the map id, so the same map
  always looks the same and unmapped songs still differ. Setting: "Environment: Auto / Classic",
  where Classic is today's look.
  - Follow-up, not v0.3: v3 `colorBoostBeatmapEvents` (the brighter light state on a boost) and
    v4 `lightColorEventBoxGroups` are not parsed yet; `basicBeatmapEvents` already drive
    `event_driver` today.
- **FR-023**: An audio-reactive layer MAY modulate the environment, but MUST be subordinate to
  the map's own light events: it scales intensity of the sphere, rings and lasers and MUST NOT
  invent colour changes or beats. If a map averages fewer than one light event per 4 s, it may
  drive the scene directly. Modulation is a 40-150 Hz bass envelope, attack ~20 ms, release
  ~250 ms, gain +/-15% (Subtle) or +/-35% (Strong), written as one shared shader uniform, not
  per material. Setting: "Audio-reactive: Off / Subtle / Strong", default Subtle.
- **FR-024**: Photosensitivity: at most 3 large-area luminance transitions per second greater
  than 10% (WCAG 2.3.1), counting map events and the analyser together; no saturated-red
  full-field flashes. A "Reduce flashing" toggle MUST cap the analyser at Subtle and turn
  flashes into fades.

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
- **SC-008**: Debris: a cut emits one burst whose **principal velocity axis** (not the mean
  vector, which cancels when shards fly both ways along the normal) is within 30 degrees of the
  cut-plane normal, and horizontal and diagonal slices produce measurably different principal
  axes; the mean drift is within 30 degrees of the blade direction. The whole system costs one
  draw call with no allocation on a hit. Cost measured on device as GPU% and on-time with the
  setting on and off; if the delta is outside the run-to-run noise band the default changes,
  not the requirement.
- **SC-009**: The same map loads with the same ambience preset twice in a row; two maps with
  different environment names produce different presets.
- **SC-010**: A flash-rate counter logged over 60 s on ODDS reports no one-second window with
  more than 3 large-area luminance transitions.
- **SC-011**: Audio-reactive on/off changes GPU% and on-time by less than the run-to-run noise
  band, measured on device.

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
- Physics debris on Quest (the slice particles are freed on Android; see v0.2 notes). The new
  shard pool is shader-animated, not physics bodies; shards do not collide with anything.

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
10. Debris shards (FR-013) - approved at G1; implement behind `debris_shards`.
11. Per-map ambience, environment colours, audio-reactive layer (FR-021..FR-024) - approved
    at G1 as Auto/Classic plus an Off/Subtle/Strong analyser; only after SC-001 is green.
12. Final optimisation pass and release.

## Consultation Log

| Gate | Question | Verdict | Follow-up |
|---|---|---|---|
| G1 | Cut debris design and the sound-design spec | GO WITH CHANGES: MultiMesh shader pool (128, 10 per cut, opaque, shrink-out, custom_aabb, own `now`); reject RigidBody and GPUParticles; measure principal velocity axis, not the mean; FR-014..FR-020 added for hit layering, variation, 1/sqrt(n), sidechain duck, whoosh/clash, latency and cube-positioned audio | FR-013 written with the parameters; SC-008 corrected |
| G1 | Per-map ambience, track colours, audio-reactive visuals | GO WITH CHANGES: use env colours then note colours then preset; player override wins; palette guards (<=0.6x brightness, 30-degree hue separation, 0.25 saturation); map light events outrank the analyser; bass-envelope intensity only; Auto/Classic and Off/Subtle/Strong settings; WCAG flash limit | FR-021..FR-024 and SC-009..SC-011 added; land after SC-001 |
| G1 | Light / UI / sky / audio approach and order | GO WITH CHANGES: light A, sky A with ambient fix, HUD A + end card SubViewport, audio measure first then redesign | Recorded in the v0.3 order above |
| measure | Is the v0.2 measurement method precise enough to attribute a 1-4 pp visual cost? | **NO.** Three 60 s runs of the same scenario (ODDS ExpertPlus, 120 Hz) gave 74.48 / 78.38 / 78.25% on time. The spread is ~4 pp, the same size as the effect being measured | FR-001 amended: comparisons need >=180 s runs or >=3 repeats; no per-feature claim below ~5 pp without both |
| measure | Is the drop from the earlier 80.07% a regression? | Not established. 80.07 sits inside the same 4 pp band as today's 74.5-78.4. Thermal status 0 (no throttling), 47.9 C | Do not chase a regression until a 180 s baseline exists |
| measure | **180 s run, defaults vs all visuals off** | Visuals cost **nothing measurable**: 63.01% vs 64.28% on time, identical dropped (0.72%), p95 (10.40 vs 10.38), p99 (11.93 vs 11.98), sd (0.96 vs 0.97), hitches (140 vs 141) | The visual layer is exonerated. Stop attributing stutter to it |
| measure | What does 180 s reveal that 60 s hid? | **The frame time drifts upward within the run**: 8.36 ms in the first 20 s, 9.04 ms in the last, on-time 80.7% -> 47.7%, and it does this identically with all visuals off. Correlates with notes live (1.1 -> 8.0) and the start of arc spawning | Two hypotheses queued: audio voice churn (`no_audio`) and CSG arcs (`arcs=false`) |
| change | Per-note cost on the drift path | `Cuttable._physics_process` read `global_transform` twice per tick per live note though it already writes the local transform; notes are children of an origin-placed track, so local z is the same number | Replaced with one local read. Scales with live notes, which is the shape of the drift |
