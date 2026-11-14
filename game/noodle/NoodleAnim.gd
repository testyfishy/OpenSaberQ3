extends RefCounted
class_name NoodleAnim

# Applies Noodle Extensions animation to one note, bomb or wall per tick (step 4 of
# docs/noodle-animation-brief.md). The combination rules are Heck's AnimationHelper:
#
#   - Path properties come from the object's own `animation` block when it has that property,
#     otherwise from its tracks' AssignPathAnimation paths, evaluated at the object's lifetime
#     (0 when it appears, 0.5 at its beat, 1 when its jump ends).
#   - Track properties come from its tracks' AnimateTrack values (song time).
#   - offsetPosition and definitePosition add up; offsetWorldRotation, localRotation, scale,
#     dissolve, dissolveArrow and interactable multiply. Across several tracks the same rule
#     combines the tracks first; then track (x) path.
#   - Position offsets are in lanes (0.6 m). definitePosition replaces the object's own travel
#     but keeps its x/y and is still offset by offsetPosition.
#   - The pose is: rotate the position about the player by offsetWorldRotation; the object's
#     rotation is offsetWorldRotation * its own static rotation * localRotation; scale multiplies
#     the static scale. A track parent (AssignTrackParent) applies on top.
#
# Results are written to static vars (no allocation, main thread only), read right after the
# call by the object that asked.

const LANE := 0.6
const MIN_SCALE := 0.0001

static var song_sec := 0.0
# Off only for verify_noodle's comparison of cached against fresh evaluations.
static var cache_enabled := true

static var out_offset := Vector3.ZERO
static var out_world := Quaternion.IDENTITY
static var out_local := Quaternion.IDENTITY
static var out_scale := Vector3.ONE
static var out_dissolve := 1.0
static var out_dissolve_arrow := 1.0
static var out_interactable := 1.0
static var out_has_definite := false
static var out_definite := Vector3.ZERO
static var out_has_parent := false
static var out_parent := Transform3D.IDENTITY


static func reset() -> void:
	song_sec = 0.0


## The song clock the animations run on. The audio playback position only moves in mix-sized
## steps, so it is followed rather than copied: advanced by the tick, pulled gently toward the
## audio, and snapped to it after a seek or a stall.
static func advance(playback_sec: float, delta: float) -> void:
	song_sec += delta
	var err := playback_sec - song_sec
	if absf(err) > 0.1:
		song_sec = playback_sec
	else:
		song_sec += err * 0.1


## Evaluates every animated property of `obj` at lifetime `life`.
static func evaluate(obj: NoodleObject, life: float) -> void:
	var P := NoodleTracks
	var tracks := NoodleTracks.tracks
	# Bit p set: some track of this object has a value (vm) or a path (pm) for property p.
	var vm := 0
	var pm := 0
	var parent := -1
	var latest := 0
	for ti in obj.tracks:
		var t := tracks[ti]
		NoodleEvents.sync(t)
		vm |= t.vmask
		pm |= t.pmask
		if t.parent >= 0:
			parent = t.parent
		if t.changed > latest:
			latest = t.changed
	# Nothing this object depends on changed since its last evaluation: the same outputs.
	if obj.c_ok and life >= obj.c_lo and life <= obj.c_hi and latest <= obj.c_at and cache_enabled:
		out_offset = obj.c_offset
		out_world = obj.c_world
		out_local = obj.c_local
		out_scale = obj.c_scale
		out_dissolve = obj.c_dissolve
		out_dissolve_arrow = obj.c_dissolve_arrow
		out_interactable = obj.c_interactable
		out_has_definite = obj.c_has_definite
		out_definite = obj.c_definite
		out_has_parent = obj.c_parent >= 0
		if out_has_parent:
			out_parent = NoodleEvents.track_xform(tracks[obj.c_parent])
		return
	var am := obj.anim_mask
	# Properties nothing animates keep their neutral value without a call (identity, 1).
	var used := am | pm | vm

	# offsetPosition: sum.
	var off := Vector3.ZERO
	var bit := 1 << P.P_OFFSET_POSITION
	if am & bit:
		off = obj.anim[P.P_OFFSET_POSITION].eval_vec3(life)
	elif pm & bit:
		for ti in obj.tracks:
			var t := tracks[ti]
			if t.pmask & bit:
				off += t.path_vec(P.P_OFFSET_POSITION, life)
	if vm & bit:
		for ti in obj.tracks:
			var t := tracks[ti]
			if t.vmask & bit:
				off += t.vec[P.P_OFFSET_POSITION]
	out_offset = off

	out_world = Quaternion.IDENTITY
	if used & (1 << P.P_OFFSET_WORLD_ROTATION):
		out_world = _quat(obj, P.P_OFFSET_WORLD_ROTATION, life, am, pm, vm)
	out_local = Quaternion.IDENTITY
	if used & (1 << P.P_LOCAL_ROTATION):
		out_local = _quat(obj, P.P_LOCAL_ROTATION, life, am, pm, vm)

	# scale: component product.
	var scl := Vector3.ONE
	bit = 1 << P.P_SCALE
	if am & bit:
		scl = obj.anim[P.P_SCALE].eval_vec3(life)
	elif pm & bit:
		for ti in obj.tracks:
			var t := tracks[ti]
			if t.pmask & bit:
				scl *= t.path_vec(P.P_SCALE, life)
	if vm & bit:
		for ti in obj.tracks:
			var t := tracks[ti]
			if t.vmask & bit:
				scl *= t.vec[P.P_SCALE]
	out_scale = scl

	out_dissolve = 1.0
	if used & (1 << P.P_DISSOLVE):
		out_dissolve = _float(obj, P.P_DISSOLVE, life, am, pm, vm)
	out_dissolve_arrow = 1.0
	if used & (1 << P.P_DISSOLVE_ARROW):
		out_dissolve_arrow = _float(obj, P.P_DISSOLVE_ARROW, life, am, pm, vm)
	out_interactable = 1.0
	if obj.uninteractable:
		out_interactable = 0.0
	elif used & (1 << P.P_INTERACTABLE):
		out_interactable = _float(obj, P.P_INTERACTABLE, life, am, pm, vm)

	# definitePosition: path only, sum.
	bit = 1 << P.P_DEFINITE_POSITION
	out_has_definite = false
	if am & bit:
		out_has_definite = true
		out_definite = obj.anim[P.P_DEFINITE_POSITION].eval_vec3(life)
	elif pm & bit:
		var d := Vector3.ZERO
		for ti in obj.tracks:
			var t := tracks[ti]
			if t.pmask & bit:
				d += t.path_vec(P.P_DEFINITE_POSITION, life)
		out_has_definite = true
		out_definite = d

	out_has_parent = parent >= 0
	if out_has_parent:
		out_parent = NoodleEvents.track_xform(tracks[parent])
	_store(obj, life, pm, parent)


# Keeps this evaluation on the object when its own animations are constant around `life` (before
# the first point or after the last of every list) and no track path is involved.
static func _store(obj: NoodleObject, life: float, pm: int, parent: int) -> void:
	if not cache_enabled:
		return
	obj.c_ok = false
	if pm != 0:
		return
	var lo := -INF
	var hi := INF
	if obj.anim_mask != 0:
		for pts in obj.anim:
			if pts == null:
				continue
			var times := pts.times
			var n := times.size()
			if n <= 1:
				continue
			if life >= times[n - 1]:
				lo = maxf(lo, times[n - 1])
			elif life <= times[0]:
				hi = minf(hi, times[0])
			else:
				return
	obj.c_ok = true
	obj.c_lo = lo
	obj.c_hi = hi
	obj.c_at = NoodleTrack.clock
	obj.c_offset = out_offset
	obj.c_world = out_world
	obj.c_local = out_local
	obj.c_scale = out_scale
	obj.c_dissolve = out_dissolve
	obj.c_dissolve_arrow = out_dissolve_arrow
	obj.c_interactable = out_interactable
	obj.c_has_definite = out_has_definite
	obj.c_definite = out_definite
	obj.c_parent = parent


static func _quat(obj: NoodleObject, p: int, life: float, am: int, pm: int, vm: int) -> Quaternion:
	var bit := 1 << p
	var tracks := NoodleTracks.tracks
	var q := Quaternion.IDENTITY
	if vm & bit:
		for ti in obj.tracks:
			var t := tracks[ti]
			if t.vmask & bit:
				q = q * t.quat[p]
	var path := Quaternion.IDENTITY
	if am & bit:
		path = obj.anim[p].eval_quat(life)
	elif pm & bit:
		for ti in obj.tracks:
			var t := tracks[ti]
			if t.pmask & bit:
				path = path * t.path_quat(p, life)
	return q * path


static func _float(obj: NoodleObject, p: int, life: float, am: int, pm: int, vm: int) -> float:
	var bit := 1 << p
	var tracks := NoodleTracks.tracks
	var f := 1.0
	if am & bit:
		f = obj.anim[p].eval_float(life)
	elif pm & bit:
		for ti in obj.tracks:
			var t := tracks[ti]
			if t.pmask & bit:
				f *= t.path_float(p, life)
	if vm & bit:
		for ti in obj.tracks:
			var t := tracks[ti]
			if t.vmask & bit:
				f *= t.flt[p]
	return f


## The object's transform in its lane, from its un-animated position (`base`: x/y on the grid,
## z from its travel), static rotation and static scale, and the last evaluate().
static func compose(base: Vector3, static_rot: Quaternion, static_scale: Vector3) -> Transform3D:
	var pos := base + out_offset * LANE
	if out_has_definite:
		pos = Vector3(base.x, base.y, 0.0) + (out_offset + out_definite) * LANE
	# Scale 0 is a common way to hide an object. Kept just off zero: a singular basis breaks
	# every affine_inverse() downstream (hit tests, the wall fade) and the cut-plane maths.
	var s := static_scale * out_scale
	if absf(s.x) < MIN_SCALE:
		s.x = MIN_SCALE
	if absf(s.y) < MIN_SCALE:
		s.y = MIN_SCALE
	if absf(s.z) < MIN_SCALE:
		s.z = MIN_SCALE
	var basis := Basis(out_world * static_rot * out_local) * Basis.from_scale(s)
	var xf := Transform3D(basis, out_world * pos)
	if out_has_parent:
		xf = out_parent * xf
	return xf
