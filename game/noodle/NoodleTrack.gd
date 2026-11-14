extends RefCounted
class_name NoodleTrack

# One Heck track: a named group of objects that custom events animate together.
#
# A track holds the current value of every animated property (set by AnimateTrack) and the path
# currently assigned to each path property (set by AssignPathAnimation). A property that was
# never animated is "unset" (`has[p] == 0`), which matters: Heck combines only the properties
# that have a value, so an unset scale is not a scale of zero.
#
# Values are stored per property index (NoodleTracks.P_*) in packed arrays, so reading them in
# the per-tick path does not allocate. Vector properties are already in Godot's frame (z
# flipped) and in the map's own units; rotations are quaternions.

var name := ""
var has := PackedByteArray()
var vec := PackedVector3Array()
var quat: Array[Quaternion] = []
var flt := PackedFloat32Array()

# Path animation (AssignPathAnimation): the current points per property, the previous points
# while a transition with a duration is running, and how far that transition is (0..1).
var path_cur: Array[NoodlePoints] = []
var path_prev: Array[NoodlePoints] = []
var path_blend := PackedFloat32Array()
var has_path := false
# Bit p set when property p has a value (vmask) or a path (pmask), so an object can skip every
# property none of its tracks animate.
var vmask := 0
var pmask := 0

# AssignTrackParent: the track this track's objects are parented to (-1 for none), and whether
# this track drives a transform (it is a parent or the player's track).
var parent := -1
var is_transform := false
# The transform this track applies to its children: `local` from its own properties, `xform`
# with its parents' chained on. Both computed when read (NoodleEvents.track_xform).
var local := Transform3D.IDENTITY
var xform := Transform3D.IDENTITY

# Lazy evaluation (NoodleEvents.sync): the running AnimateTrack (`tw`) and AssignPathAnimation
# (`ptw`) tween of each property, null when none (a new one replaces the old, as Heck stops it),
# sized on this track's first tween. They are stepped only when something reads the track, at
# most once per tick: `synced`, `local_tick` and `xform_tick` are the NoodleEvents tick the
# values, `local` and `xform` were last brought up to date in.
var tw: Array = []
var ptw: Array = []
var tw_count := 0
var synced := -1
var local_tick := -1
var xform_tick := -1
# This track's AnimateTrack / AssignPathAnimation events in beat order, and the first one not yet
# applied (NoodleEvents applies the due ones when the track is read).
var events: Array = []
var next_ev := 0
# How many of NoodleEvents' backward time jumps this track has been brought through.
var jumps_done := 0


func _init(track_name: String = "") -> void:
	name = track_name
	var n := NoodleTracks.P_COUNT
	has.resize(n)
	vec.resize(n)
	flt.resize(n)
	path_blend.resize(n)
	quat.resize(n)
	path_cur.resize(n)
	path_prev.resize(n)
	for i in n:
		quat[i] = Quaternion.IDENTITY
		path_blend[i] = 1.0


func clear_value(p: int) -> void:
	has[p] = 0
	vmask &= ~(1 << p)


func set_vec(p: int, v: Vector3) -> void:
	vec[p] = v
	has[p] = 1
	vmask |= 1 << p


func set_quat(p: int, q: Quaternion) -> void:
	quat[p] = q
	has[p] = 1
	vmask |= 1 << p


func set_float(p: int, f: float) -> void:
	flt[p] = f
	has[p] = 1
	vmask |= 1 << p


## Assigns (or with null, erases) the path of property `p`.
func set_path(p: int, points: NoodlePoints) -> void:
	path_cur[p] = points
	if points != null:
		pmask |= 1 << p
	else:
		pmask &= ~(1 << p)


## Writes the value of `points` at time `t` into property `p`, by the property's kind.
func set_from_points(p: int, points: NoodlePoints, t: float) -> void:
	match points.kind:
		NoodlePoints.KIND_FLOAT:
			set_float(p, points.eval_float(t))
		NoodlePoints.KIND_ROTATION:
			set_quat(p, points.eval_quat(t))
		_:
			set_vec(p, points.eval_vec3(t))


## True when property `p` has a path at all (a transition from nothing still counts as the new
## path, as in Heck).
func has_path_for(p: int) -> bool:
	return path_cur[p] != null


func path_vec(p: int, t: float) -> Vector3:
	var cur := path_cur[p]
	var prev := path_prev[p]
	if prev == null:
		return cur.eval_vec3(t)
	var a := prev.eval_vec3(t)
	return a + (cur.eval_vec3(t) - a) * path_blend[p]


func path_quat(p: int, t: float) -> Quaternion:
	var cur := path_cur[p]
	var prev := path_prev[p]
	if prev == null:
		return cur.eval_quat(t)
	return prev.eval_quat(t).slerp(cur.eval_quat(t), path_blend[p])


func path_float(p: int, t: float) -> float:
	var cur := path_cur[p]
	var prev := path_prev[p]
	if prev == null:
		return cur.eval_float(t)
	return lerpf(prev.eval_float(t), cur.eval_float(t), path_blend[p])
