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

# Self-time of the saber hit path, both sabers. Under the ray fan that is
# SwingableRayCast._physics_process; under the analytic resolver (specs/006) it is
# LightSaber._resolve_analytic_hits. Compare the two arms of a run with this
# column AND TIME_PHYSICS_PROCESS: the aux rays' automatic casts run inside the
# physics server, i.e. outside this timer.
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

# ── Spike attribution counters (FR-033) ──────────────────────────────────────
# The process-step p99 is 3x the physics p99, so the spike is in something the
# process step owns. These counters make each candidate falsifiable per frame:
# what a spike frame did, rather than what the run averaged.
#
#   cuts           Scoreboard.add_points calls = notes/links that actually scored
#                  (Scoreboard.gd). Distinguishes "spike when many notes die".
#   labels_spawned point-label node instantiations. Expected to be 0 for a whole
#                  run because Points_label_driver pre-pools 4 of them; the
#                  column exists so that claim is measured, not asserted.
#   text_mesh_writes TextMesh.text assignments. A TextMesh rebuild re-triangulates
#                  glyphs and re-uploads the mesh, so this is the cost of the HUD.
#   objs_spawned   wall/bomb/arc scene instantiations (Playing._process_map).
#   objs_freed     queue_free() on a spawned wall/bomb/arc. Deferred frees run on
#                  the main thread, so they can be the spike rather than the spawn.
#   arcs_spawned   subset of objs_spawned: sliders, which are CSGPolygon3D nodes
#                  whose ribbon is rebuilt on the main thread when the curve
#                  changes. The leading suspect for a process-step spike.
static var cuts := 0
static var labels_spawned := 0
static var text_mesh_writes := 0
static var objs_spawned := 0
static var objs_freed := 0
static var arcs_spawned := 0

static func reset() -> void:
	swing_usec = 0
	cuttable_usec = 0
	floor_ray_usec = 0
	spawn_usec = 0
	shape_reenable = 0
	physics_ticks = 0
	cuts = 0
	labels_spawned = 0
	text_mesh_writes = 0
	objs_spawned = 0
	objs_freed = 0
	arcs_spawned = 0
