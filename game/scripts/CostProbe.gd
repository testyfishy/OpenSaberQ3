# Per-path self-time accumulators for benchmark attribution (spec FR-033).
#
# FR-033 says a spike source must be attributed before an average is optimised,
# and the earlier advisor consult on this project recommended measuring the
# saber path with `Time.get_ticks_usec()` before rewriting it. `Performance
# .TIME_PHYSICS_PROCESS` only gives a total for the whole tick, so this file
# splits that total into the paths that are actually candidates.
#
# Design rules, because these run inside the physics tick:
#   - `enabled` is false on a normal launch, so every call site costs one branch
#     and nothing else. BenchmarkRunner turns it on only while recording.
#   - No allocation and no string formatting on the write path: two clock reads
#     and one integer add, per suspended region.
#   - Writers accumulate; the reader (BenchmarkRunner._process) copies the frame
#     totals out and calls reset(). Nothing is zeroed on the writer's hot path,
#     so a frame with several physics ticks sums them all - which is what makes
#     the numbers comparable with TIME_PHYSICS_PROCESS.
#
# Deliberately not a `class_name` global: the rest of the project preloads by
# path so a clean clone never depends on the editor's global class cache.
extends RefCounted

static var enabled := false

# Self-time of SwingableRayCast._physics_process, both sabers (the ray fan).
static var swing_usec := 0
# Self-time of Cuttable._physics_process, summed over every live note/link.
static var cuttable_usec := 0
# Self-time of LightSaber's floor-burn RayCast3D block, both sabers.
static var floor_ray_usec := 0
# Self-time of Playing's spawn/despawn pass (map beatmap -> scene nodes).
static var spawn_usec := 0

# Counts, not times: cheaper than timing, and a count is enough to prove or
# disprove "this write happens every tick for every note".
static var shape_reenable := 0   # set_collision_disabled(false) writes
static var physics_ticks := 0    # physics ticks started in the current frame

static func reset() -> void:
	swing_usec = 0
	cuttable_usec = 0
	floor_ray_usec = 0
	spawn_usec = 0
	shape_reenable = 0
	physics_ticks = 0
