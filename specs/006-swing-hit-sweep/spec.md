# Feature Specification: Analytic swept-blade hit test behind a reversible setting

**Feature Branch**: `006-swing-hit-sweep`

**Created**: 2026-11-02

**Status**: Draft

**Input**: User description: "Replace the raycast fan with an analytic swept-blade hit test, behind a reversible project setting."

## Intent

Saber hit detection is the largest remaining CPU cost in the physics tick
(`TIME_PHYSICS_PROCESS` p95 3.66-4.18 ms against an 8.33 ms 120 Hz budget). Today
each saber forces nine `RayCast3D` queries per physics tick (one core ray plus
eight swept aux rays, and the eight aux nodes also cast on their own every step
because only the parent's `enabled` flag is ever toggled). Replace that fan with a
closed-form swept-segment/box test over a registry of the notes that are actually
hittable, so the cost scales with the number of live notes in the hit window
rather than with an engine physics query per ray, and so hit registration no
longer depends on a 35 mm per-tick distance threshold.

Scoring, timing, audio, cut planes and `HitInfo` stay exactly as they are: the new
path only decides *whether* a cuttable was hit, then calls the same
`note.cut(...)` funnel the rays call today. The whole thing sits behind
`gameplay/swing_hit/detection`, so the ray path remains selectable for an A/B.

## Scoped change *(bug/perf work)*

- **Symptom**: physics-tick time is roughly half of a 120 Hz frame budget, and hit
  registration silently drops sub-35 mm per-tick blade motion (`MIN_SWEPT_LENGTH_THRESHOLD`
  in `SwingableRayCast.gd`), i.e. it is not frame-rate independent.
- **Root cause (cost)**: 8 aux `RayCast3D` nodes + 1 core ray per saber, each
  forced per physics tick, plus an unimpeded automatic cast per aux node.
- **Root cause (correctness)**: the swept segment is only cast when its length
  exceeds 35 mm; below that, motion is still accumulated (fixed), but the cast
  count still varies with tick rate.
- **Blast radius**: `LightSaber` hit path, `Cuttable` collision enable/disable,
  `SwingableRayCast` enable plumbing, one new script, one project setting.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A note/link/bomb MUST register its hit geometry with a resolver when
  it becomes hittable and unregister when cut, missed, hidden, released or freed.
  Registration MUST capture, per collider area, the collision-layer bits and the
  shape, so that per-saber eligibility matches today's ray masks bit for bit.
- **FR-002**: The resolver MUST be queried per physics tick per saber with the
  blade's previous and current base/tip; it MUST NOT walk the scene tree per tick.
- **FR-003**: The test MUST be an analytic segment-vs-box (slab) test performed in
  cuttable-local space, over the swept blade between the previous and current
  sample, with no minimum-length threshold, so a longer tick produces a longer
  sweep rather than a discarded one.
- **FR-004**: A hit MUST be reported through the existing
  `LightSaber._handle_cuttable` path with the same `saber_end`, `saber_end_past`,
  `last_dt`, controller and cut plane the ray path uses, so scoring, angle checks,
  rumble, debris and `HitInfo` are unchanged.
- **FR-005**: The detection source MUST be selectable at
  `gameplay/swing_hit/detection` = `"rays" | "analytic"`, default `"analytic"`.
  With `"rays"` the build MUST behave exactly as before this change.
- **FR-006**: With `"rays"` the resolver MUST do no per-note work beyond one cached
  bool test; with `"analytic"` the ray fan MUST NOT cast at all.
- **FR-007**: Aux ray nodes MUST follow the parent `enabled` state instead of
  casting while nothing reads them.
- **FR-008**: With `"analytic"`, cuttable collision shapes MUST stay disabled: the
  physics has no remaining consumer of them, so the per-approach
  `CollisionShape3D.disabled` writes are unnecessary.
- **FR-009**: Bombs MUST go through the same resolver (any hit is a hit) while
  remaining subject to the layer mask that decides whether the rays could hit them.

### Out of scope

- Changing scoring maths, timing windows, cut planes, audio mapping.
- Changing note/link/bomb hitshape *sizes* or the beam-saber geometry.
- Re-enabling bombs by editing their collision layer (see FR-009 / open question).

### Success criteria

- **SC-001**: Headless parse check passes with no SCRIPT ERROR / Parse Error.
- **SC-002**: With the bot workload, the analytic path's cut count is within noise
  of the ray path (baseline ~380 cuts / 120 s), and wrong-saber counts do not rise.
- **SC-003**: `Cost.swing_usec` (both sabers, per frame) is materially lower on the
  analytic path than on the ray path in a like-for-like benchmark run.
- **SC-004**: Setting `gameplay/swing_hit/detection="rays"` restores the previous
  behaviour without any other edit.

## Open questions

- `[NEEDS CLARIFICATION: Bomb.tscn puts its Area3D on layer 16 (Saber_bit), which no
  saber ray mask includes (LeftNote|Bombs / RightNote|Bombs), so bombs are currently
  unhittable by the saber. The resolver reproduces that exactly (FR-009). Re-enabling
  bombs is a gameplay change and is deliberately NOT part of this task.]`

## Consultation Log

| Gate | Asked | Verdict | Action taken |
|------|-------|---------|--------------|
| G0 | Spec review (placeholder) | pending | - |
