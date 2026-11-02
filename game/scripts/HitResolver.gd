# Analytic swept-blade hit detection (specs/006-swing-hit-sweep).
#
# Why this exists: SwingableRayCast forces nine RayCast3D queries per saber per
# physics tick (one core ray + eight swept aux rays, whose nodes also cast on
# their own every step). This resolver replaces that with a closed-form
# segment-vs-box test over the cuttables that are actually hittable, so the cost
# scales with the live notes in the hit window instead of with an engine query
# per ray, and so a sweep is never discarded for being shorter than a threshold.
#
# Shape of the data: a flat, packed registry. One entry per *collider shape*, not
# per cuttable, because that is the granularity the physics has and the layer
# bits on each shape are what decide which saber may hit it (a cube's big box is
# on its own note layer, its small box on the other one; see BeepCube.gd:78-86).
# Keeping the layer bits is what makes per-saber eligibility bit-identical to the
# ray masks instead of a re-derivation that could drift.
#
# Cost rules, because this runs inside the physics tick:
#   - registration walks the cuttable's children ONCE, when it becomes hittable;
#   - a query never touches the scene tree: it iterates the flat arrays;
#   - the shape's global transform is read live (a note keeps moving after it
#     registered, and shape resources are mutated per spawn), so nothing cached
#     can go stale.
#
# Deliberately not a `class_name` global and not an autoload: preloaded by path,
# same as CostProbe.gd, so a clean clone never depends on the editor's global
# class cache, and there is no extra node in the tree or tick to run.
extends RefCounted

# FR-005: the detection source. "rays" keeps the pre-006 behaviour exactly.
const SETTING := &"gameplay/swing_hit/detection"
const MODE_RAYS := "rays"
const MODE_ANALYTIC := "analytic"

# Bounds of one tick's work, so a pathological frame cannot turn a query into a
# stall. 8 matches the number of colliders the ray fan could report per tick.
const MAX_HITS_PER_TICK := 8
# Target spacing between swept samples, in metres. The sweep between the previous
# and the current sample is tested at n = ceil(tip_travel / STEP_M) + 1 poses, so
# a longer tick gets more samples instead of a coarser one (FR-003).
const STEP_M := 0.04
const MAX_STEPS := 16
# A blade that moved more than this in one tick teleported (map load, controller
# reconnect, tracking loss). Sweeping that distance would cut everything in the
# lane, so the sample is dropped and treated as the new "previous".
const MAX_JUMP_M := 1.0

# --- registry (parallel arrays; index i is one collider shape) ---------------
static var _cuttable: Array = []          # the Cuttable that owns the shape
static var _shape_node: Array = []        # its CollisionShape3D
static var _layer := PackedInt32Array()   # that area's collision_layer bits
static var _count := 0

# -1 = not read yet, 0 = rays, 1 = analytic. Read once per process, not per note.
static var _analytic := -1


static func is_analytic() -> bool:
	if _analytic < 0:
		var raw := str(ProjectSettings.get_setting(SETTING, MODE_ANALYTIC)).strip_edges().to_lower()
		if raw != MODE_RAYS and raw != MODE_ANALYTIC:
			push_warning("gameplay/swing_hit/detection=%s is not \"rays\" or \"analytic\"; using analytic" % raw)
			raw = MODE_ANALYTIC
		_analytic = 0 if raw == MODE_RAYS else 1
	return _analytic == 1

# BenchmarkRunner applies its A/B override after the sabers exist, so the cached
# answer must be droppable (see BenchmarkRunner._apply_overrides).
static func reset_mode_cache() -> void:
	_analytic = -1


# --- registration ------------------------------------------------------------
# `shape_node` carries both the box (or sphere) and the frame it sits in, and its
# `global_transform` is read at query time, so only the nodes and the layer bits
# are captured here.
static func add(cuttable: Node3D, layer: int, shape_node: CollisionShape3D) -> void:
	_cuttable.append(cuttable)
	_shape_node.append(shape_node)
	_layer.append(layer)
	_count += 1


static func remove(cuttable: Node3D) -> void:
	var i := 0
	while i < _count:
		if _cuttable[i] == cuttable:
			_remove_at(i)
		else:
			i += 1


static func clear() -> void:
	_cuttable.clear()
	_shape_node.clear()
	_layer.clear()
	_count = 0


static func count() -> int:
	return _count


static func _remove_at(i: int) -> void:
	_count -= 1
	if i == _count:
		_cuttable.pop_back()
		_shape_node.pop_back()
		_layer.remove_at(_count)
		return
	_cuttable[i] = _cuttable[_count]
	_shape_node[i] = _shape_node[_count]
	_layer[i] = _layer[_count]
	_cuttable.pop_back()
	_shape_node.pop_back()
	_layer.remove_at(_count)


# --- query -------------------------------------------------------------------
# One saber's tick: the blade segment at the previous and the current sample. The
# swept volume between them is the ruled surface joining the two segments, so it
# is sampled at several poses and each pose is an exact segment-vs-box test.
# Returns the cuttable to cut, or null. Ordering (earliest sample, then nearest
# the hilt) keeps "which of two overlapping notes is cut first" deterministic.
static func find_hit(mask: int, base_prev: Vector3, tip_prev: Vector3,
		base_cur: Vector3, tip_cur: Vector3) -> Node3D:
	if _count == 0:
		return null
	var steps := clampi(ceili(tip_prev.distance_to(tip_cur) / STEP_M), 1, MAX_STEPS)
	var best: Node3D = null
	var best_step := 1 << 30
	var best_s := INF
	var i := 0
	while i < _count:
		var cuttable: Node3D = _cuttable[i]
		if not is_instance_valid(cuttable):
			# Freed while registered (a bomb): drop the entry, keep the array packed.
			_remove_at(i)
			continue
		if (_layer[i] & mask) == 0:
			i += 1
			continue
		var hit := _test_entry(i, base_prev, tip_prev, base_cur, tip_cur, steps)
		if hit.x >= 0.0 and (int(hit.x) < best_step or (int(hit.x) == best_step and hit.y < best_s)):
			best = cuttable
			best_step = int(hit.x)
			best_s = hit.y
		i += 1
	return best


# Returns Vector2(sample_index, position_along_blade); x < 0 means no hit.
static func _test_entry(i: int, base_prev: Vector3, tip_prev: Vector3,
		base_cur: Vector3, tip_cur: Vector3, steps: int) -> Vector2:
	var shape_node := _shape_node[i] as CollisionShape3D
	var shape := shape_node.shape
	if shape == null:
		return Vector2(-1.0, 0.0)
	var inv := shape_node.global_transform.affine_inverse()
	var half := Vector3.ZERO
	var radius := 0.0
	var is_sphere := false
	if shape is BoxShape3D:
		half = (shape as BoxShape3D).size * 0.5
	elif shape is SphereShape3D:
		is_sphere = true
		radius = (shape as SphereShape3D).radius
	else:
		return Vector2(-1.0, 0.0)
	
	# Oldest pose first so the reported sample is the earliest one that hit.
	for k in range(steps + 1):
		var u := float(k) / float(steps)
		var a := inv * base_prev.lerp(base_cur, u)
		var b := inv * tip_prev.lerp(tip_cur, u)
		var hits := false
		if is_sphere:
			hits = _segment_sphere(a, b, radius)
		else:
			hits = _segment_box(a, b, half)
		if hits:
			return Vector2(float(k), _along_blade(a, b))
	
	# The tip's own path. The ruled surface is not planar, so its tip edge can
	# cross a box that the sampled poses straddle; this closes that gap for free.
	var tip_a := inv * tip_prev
	var tip_b := inv * tip_cur
	var tip_hit := false
	if is_sphere:
		tip_hit = _segment_sphere(tip_a, tip_b, radius)
	else:
		tip_hit = _segment_box(tip_a, tip_b, half)
	if tip_hit:
		return Vector2(float(steps), 1.0)
	return Vector2(-1.0, 0.0)


# 0 at the hilt, 1 at the tip: the exact closest approach of the line to the box
# centre (the box is centred on its own frame's origin).
static func _along_blade(a: Vector3, b: Vector3) -> float:
	var d := b - a
	var dd := d.length_squared()
	if dd < 1e-12:
		return 0.0
	return clampf(-a.dot(d) / dd, 0.0, 1.0)


# Segment vs axis-aligned box centred on the origin, by the slab method.
static func _segment_box(a: Vector3, b: Vector3, half: Vector3) -> bool:
	var d := b - a
	var tmin := 0.0
	var tmax := 1.0
	
	if absf(d.x) < 1e-9:
		if a.x < -half.x or a.x > half.x:
			return false
	else:
		var inv_d := 1.0 / d.x
		var t1 := (-half.x - a.x) * inv_d
		var t2 := (half.x - a.x) * inv_d
		if t1 > t2:
			var swap_x := t1
			t1 = t2
			t2 = swap_x
		if t1 > tmin: tmin = t1
		if t2 < tmax: tmax = t2
		if tmin > tmax:
			return false
	
	if absf(d.y) < 1e-9:
		if a.y < -half.y or a.y > half.y:
			return false
	else:
		var inv_dy := 1.0 / d.y
		var ty1 := (-half.y - a.y) * inv_dy
		var ty2 := (half.y - a.y) * inv_dy
		if ty1 > ty2:
			var swap_y := ty1
			ty1 = ty2
			ty2 = swap_y
		if ty1 > tmin: tmin = ty1
		if ty2 < tmax: tmax = ty2
		if tmin > tmax:
			return false
	
	if absf(d.z) < 1e-9:
		if a.z < -half.z or a.z > half.z:
			return false
	else:
		var inv_dz := 1.0 / d.z
		var tz1 := (-half.z - a.z) * inv_dz
		var tz2 := (half.z - a.z) * inv_dz
		if tz1 > tz2:
			var swap_z := tz1
			tz1 = tz2
			tz2 = swap_z
		if tz1 > tmin: tmin = tz1
		if tz2 < tmax: tmax = tz2
		if tmin > tmax:
			return false
	return true


# Segment vs sphere centred on the origin (bombs are SphereShape3D).
static func _segment_sphere(a: Vector3, b: Vector3, radius: float) -> bool:
	var d := b - a
	var dd := d.length_squared()
	var closest := a
	if dd > 1e-12:
		closest = a + d * clampf(-a.dot(d) / dd, 0.0, 1.0)
	return closest.length_squared() <= radius * radius
