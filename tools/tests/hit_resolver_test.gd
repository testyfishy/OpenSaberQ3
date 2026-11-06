extends SceneTree

## Parity check for specs/006-swing-hit-sweep: the analytic swept-blade test
## (HitResolver) against the *ideal* swept ray fan it replaces.
##
##   godot --headless --path . --script res://tools/tests/hit_resolver_test.gd
##
## The fan here is the best case the old path can do: nine swept rays per tick,
## every ray swept over the whole tick, no 35 mm threshold. The analytic test is
## supposed to be a superset of that (same boxes, same layers, plus the interior
## of the swept band), so every note the fan cuts must also be cut analytically,
## and the tick the cut lands on must be within one tick.
##
## Autoloads are unavailable in a --script run, so the hitboxes are built by hand
## from the .tscn dimensions instead of instancing BeepCube/ChainLink, and the
## cuttables are plain Node3D nodes registered straight into HitResolver.

const HitResolver := preload("res://game/scripts/HitResolver.gd")
const CollisionLayerConstants := preload("res://game/scripts/CollisionLayerConstants.gd")

const BLADE := 1.26          # "tip" marker of default_saber.tscn
const TICKS := 28            # 0.2356 s at 120 Hz, the bot's swing window
const FAN := 8               # aux rays per saber
const SHOULDER := Vector3(0.25, 1.35, 0.0)

# Constants.gd is an autoload, which this run cannot use.
const UNIT_VECTORS := [
	Vector2(0, 1), Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0),
	Vector2(-0.70710678, 0.70710678), Vector2(0.70710678, 0.70710678),
	Vector2(-0.70710678, -0.70710678), Vector2(0.70710678, -0.70710678), Vector2(0, 1),
]

const LEFT_MASK := (1 << CollisionLayerConstants.LeftNote_bit) | (1 << CollisionLayerConstants.Bombs_bit)
const RIGHT_MASK := (1 << CollisionLayerConstants.RightNote_bit) | (1 << CollisionLayerConstants.Bombs_bit)

var _space: PhysicsDirectSpaceState3D
var _checks := 0
var _failures := 0
var _notes: Array[Node3D] = []


func _initialize() -> void:
	await physics_frame
	await physics_frame
	_space = root.world_3d.direct_space_state
	print("hit resolver parity: space=%s" % _space)
	
	_test_cube_all_directions()
	_test_wrong_saber_uses_the_small_box()
	_test_chain_link_is_left_only()
	_test_dropped_frame()
	_test_note_out_of_reach_is_never_hit()
	
	if _failures == 0:
		print("hit resolver parity: OK (%d checks)" % _checks)
	else:
		print("hit resolver parity: %d of %d checks FAILED" % [_failures, _checks])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


# --- hitboxes ----------------------------------------------------------------
# Mirrors BeepCube.tscn: a big box on one note layer (centre z +0.25) and a
# 0.375 cube on the other one, both under the note node.
func _make_cube(pos: Vector3, owner_layer: int, other_layer: int, dot: bool) -> Node3D:
	var note := _make_note(pos)
	_add_box(note, owner_layer, Vector3(0.8, 0.8 if dot else 0.5, 1.0), Vector3(0, 0, 0.25))
	_add_box(note, other_layer, Vector3(0.375, 0.375, 0.375), Vector3.ZERO)
	return note


func _make_link(pos: Vector3) -> Node3D:
	var note := _make_note(pos)
	# ChainLink.tscn: layer 768 = bit 8 + LeftNote. No saber mask ever had bit 8,
	# so in practice a link is left-saber-only.
	_add_box(note, 768, Vector3(0.8, 0.1, 1.0), Vector3(0, 0, 0.25))
	return note


func _make_note(pos: Vector3) -> Node3D:
	var note := Node3D.new()
	note.position = pos
	note.rotation.z = PI            # a "normal" note, as BeepCube.spawn sets it
	root.add_child(note)
	_notes.append(note)
	return note


func _add_box(note: Node3D, layer: int, size: Vector3, centre: Vector3) -> void:
	var area := Area3D.new()
	area.collision_layer = layer
	area.collision_mask = 0
	area.monitoring = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = centre
	area.add_child(cs)
	note.add_child(area)
	# What Cuttable._register_hit() does once the note becomes hittable.
	HitResolver.add(note, layer, cs)


# --- the two detectors --------------------------------------------------------
func _ray_hits(from: Vector3, to: Vector3, mask: int) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	return not _space.intersect_ray(q).is_empty()


# The ideal fan: eight aux rays swept over the tick at even blade parameters,
# plus the core ray at the current pose (what SwingableRayCast does when it is
# not skipping the sweep for being shorter than MIN_SWEPT_LENGTH_THRESHOLD).
func _fan_hits(prev: Array, cur: Array, mask: int) -> bool:
	for i in FAN:
		var t := float(i) / float(FAN - 1)
		if _ray_hits(cur[0].lerp(cur[1], t), prev[0].lerp(prev[1], t), mask):
			return true
	return _ray_hits(cur[0], cur[1], mask)


func _analytic_hits(prev: Array, cur: Array, mask: int) -> bool:
	return HitResolver.find_hit(mask, prev[0], prev[1], cur[0], cur[1]) != null


# --- the swing ---------------------------------------------------------------
# BotDriver._swing_pose, condensed: the note's centre sits ON the blade at
# mid-swing and the tip ends up 0.35-0.9 m past it, which is why the "tip
# crosses the note plane" rule cannot be used for this game's geometry.
func _pose(p: Vector3, d: Vector3, u: float) -> Array:
	var to_note := p - SHOULDER
	var r := to_note - d * to_note.dot(d)
	if r.length() < 0.15:
		r = Vector3(0.0, 0.0, -1.0)
		r -= d * r.dot(d)
	r = r.normalized()
	var reach := clampf(to_note.length(), 0.35, BLADE * 0.9)
	var hilt := p - r * reach
	var axis := r.cross(d).normalized()
	var theta := 0.6 / BLADE
	var phi := -0.5 * theta * cos(PI * u)
	var blade_dir := (r * cos(phi) + d * sin(phi)).normalized()
	return [hilt, hilt + blade_dir * BLADE]


# Returns [first_analytic_tick, first_fan_tick] (-1 = never), sweeping `u` from
# 0 to 1 in `ticks` steps. `stride` > 1 simulates dropped physics ticks.
func _run_swing(p: Vector3, d: Vector3, mask: int, ticks: int, stride: int = 1) -> Array:
	var first_a := -1
	var first_r := -1
	var prev := _pose(p, d, 0.0)
	var step := 1.0 / float(ticks)
	var k := 1
	while k <= ticks:
		var cur := _pose(p, d, minf(1.0, float(k) * step))
		if first_a < 0 and _analytic_hits(prev, cur, mask):
			first_a = k
		if first_r < 0 and _fan_hits(prev, cur, mask):
			first_r = k
		prev = cur
		k += stride
	return [first_a, first_r]


func _test_cube_all_directions() -> void:
	var cut_a := 0
	var cut_r := 0
	for dir_index in 9:
		var unit: Vector2 = UNIT_VECTORS[dir_index]
		var d := Vector3(unit.x, unit.y, 0.0).normalized()
		var p := Vector3(0.6, 0.8, 0.0)
		var note := _make_cube(p, 1 << CollisionLayerConstants.LeftNote_bit,
			1 << CollisionLayerConstants.RightNote_bit, dir_index == 8)
		var res := _run_swing(p, d, LEFT_MASK, TICKS)
		print("  dir %d: analytic=%s fan=%s" % [dir_index, res[0], res[1]])
		_check(int(res[1]) < 0 or int(res[0]) >= 0, "dir %d: fan cut but analytic missed" % dir_index)
		_check(int(res[0]) < 0 or int(res[1]) < 0 or absi(int(res[0]) - int(res[1])) <= 1,
			"dir %d: cut tick differs by more than one (a=%s r=%s)" % [dir_index, res[0], res[1]])
		if int(res[0]) >= 0: cut_a += 1
		if int(res[1]) >= 0: cut_r += 1
		HitResolver.remove(note)
		note.queue_free()
	print("  cubes: analytic %d/9, fan %d/9" % [cut_a, cut_r])
	_check(cut_a == 9, "analytic missed a cube the fan cuts (%d/9)" % cut_a)
	# Superset, not equality: where the blade is already inside the box at the
	# first sample the ray fan cannot see it at all (RayCast3D.hit_from_inside is
	# false, so a ray whose origin is inside a shape reports nothing). The
	# analytic test reports it. Never the other way round.
	_check(cut_a >= cut_r, "analytic cut fewer notes than the fan: %d vs %d" % [cut_a, cut_r])


func _test_note_out_of_reach_is_never_hit() -> void:
	# A note two metres away must not register on either path: guards against a
	# transform bug that would map every note into the blade's frame.
	var d := Vector3(0.0, -1.0, 0.0)
	var p := Vector3(0.6, 0.8, 0.0)
	var note := _make_cube(p + Vector3(0.0, 0.0, -2.0), 1 << CollisionLayerConstants.LeftNote_bit,
		1 << CollisionLayerConstants.RightNote_bit, false)
	var res := _run_swing(p, d, LEFT_MASK, TICKS)
	print("  out of reach: analytic=%s fan=%s" % [res[0], res[1]])
	_check(int(res[0]) < 0, "analytic registered a note two metres away")
	# The ray fan DOES register the far note (a 2 m swept ray still passes through it). That is a
	# known false positive of the legacy path, which is why `analytic` is the default. Recorded
	# rather than asserted, so the suite fails only on defects in the shipping path.
	if int(res[1]) >= 0:
		print("  NOTE: legacy fan false-positive on an unreachable note (analytic path correct)")
	_drop(note)


func _test_wrong_saber_uses_the_small_box() -> void:
	# Right saber over a left note: only the 0.375 cube is on a layer it can see.
	var d := Vector3(0.0, -1.0, 0.0)
	var p := Vector3(0.6, 0.8, 0.0)
	var note := _make_cube(p, 1 << CollisionLayerConstants.LeftNote_bit,
		1 << CollisionLayerConstants.RightNote_bit, false)
	var res := _run_swing(p, d, RIGHT_MASK, TICKS)
	print("  wrong saber: analytic=%s fan=%s" % [res[0], res[1]])
	_check(int(res[0]) >= 0, "wrong saber never registers analytically")
	_check(int(res[1]) < 0 or int(res[0]) >= 0, "wrong saber: fan cut but analytic missed")
	_drop(note)


func _test_chain_link_is_left_only() -> void:
	var d := Vector3(0.0, -1.0, 0.0)
	var p := Vector3(0.6, 0.8, 0.0)
	var note := _make_link(p)
	var left := _run_swing(p, d, LEFT_MASK, TICKS)
	var right := _run_swing(p, d, RIGHT_MASK, TICKS)
	print("  chain link: left=%s right=%s" % [left[0], right[0]])
	_check(int(left[0]) >= 0, "chain link not cut by the left saber")
	_check(int(right[0]) < 0, "chain link cut by the right saber (layer 768 says it must not be)")
	_drop(note)


func _test_dropped_frame() -> void:
	# A hitched tick covering four normal ticks must still register: the sweep
	# spans the whole gap instead of being discarded for being "too long".
	var d := Vector3(0.0, -1.0, 0.0)
	var p := Vector3(0.6, 0.8, 0.0)
	var note := _make_cube(p, 1 << CollisionLayerConstants.LeftNote_bit,
		1 << CollisionLayerConstants.RightNote_bit, false)
	var res := _run_swing(p, d, LEFT_MASK, TICKS, 4)
	print("  dropped frame (4x stride): analytic=%s fan=%s" % [res[0], res[1]])
	_check(int(res[0]) >= 0, "analytic missed the note across a 4-tick gap")
	_drop(note)

func _drop(note: Node3D) -> void:
	HitResolver.remove(note)
	note.queue_free()

