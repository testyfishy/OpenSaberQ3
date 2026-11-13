extends RefCounted
class_name NoodlePoints

# One parsed point definition (Heck "PointDefinition"): a list of points, each
# `[values..., time, "optional easing", "optional splineCatmullRom"]`, evaluated at a time t.
#
# Semantics follow Heck/Animation/PointDefinition (MIT, Aeroluna):
#   - A bare point (`[x, y, z]` rather than `[[x, y, z, t]]`) is one point with time 0 appended.
#   - Numbers anywhere in the point are its values, the last one being the time; strings that
#     start with "ease" are its easing; "splineCatmullRom" makes the segment ending at this point
#     a Catmull-Rom curve (vectors only; rotations always slerp, as in Heck).
#   - At or after the last point's time the last value is returned, at or before the first
#     point's time the first; in between the segment [l, r] around t is found by binary search,
#     the local time (t - tl) / (tr - tl) is eased with the easing of the RIGHT point, then
#     interpolated. Points are assumed sorted by time, as Heck assumes.
#   - Point modifiers (nested lists with opAdd etc.) and base providers ("baseHeadPosition"...)
#     are not supported here: such a definition has no points and `unsupported` says why, so
#     MapSupport can report it instead of the map silently misbehaving.
#
# Values are converted from Beat Saber's left-handed frame (+z away from the player) to Godot's
# (-z away) once, at parse time: positions flip z, rotations become quaternions with x and y
# negated. Both conversions commute with the interpolation, so evaluating the converted points
# is the same as converting the evaluated value. Units are NOT converted here: a position is
# still in the property's own units (lanes for offsetPosition/definitePosition), and the caller
# scales it.
#
# Parsing allocates; evaluation does not (it reads packed arrays and returns value types), so a
# definition can be evaluated per object per tick.

enum { KIND_FLOAT, KIND_POSITION, KIND_SCALE, KIND_ROTATION }

var kind := KIND_FLOAT
var times := PackedFloat32Array()
# Stride 1 for floats, 3 for vectors, 4 (x, y, z, w) for rotations.
var values := PackedFloat32Array()
var easings := PackedInt32Array()
var smooth := PackedByteArray()

# Non-empty when the definition uses a feature this build does not evaluate (a base provider or
# a point modifier). Such a definition has no points and evaluates to the default value.
var unsupported := ""


func count() -> int:
	return times.size()


static func stride_of(k: int) -> int:
	match k:
		KIND_FLOAT: return 1
		KIND_ROTATION: return 4
	return 3


## Euler degrees (Beat Saber order: z, then x, then y) to a Godot-frame quaternion.
static func euler_to_quat(x_deg: float, y_deg: float, z_deg: float) -> Quaternion:
	# Unity's Quaternion.Euler and Godot's YXZ order build the same matrix (Ry * Rx * Rz) from
	# the same numbers. Mirroring z (left- to right-handed) conjugates the rotation, which for a
	# quaternion is (x, y, z, w) -> (-x, -y, z, w).
	var q := Quaternion.from_euler(Vector3(deg_to_rad(x_deg), deg_to_rad(y_deg), deg_to_rad(z_deg)))
	return Quaternion(-q.x, -q.y, q.z, q.w)


## Parses a raw point definition. Returns null when it is empty, malformed or uses something
## this build does not support. Pure: safe to call from the loader threads.
static func parse(raw: Variant, point_kind: int) -> NoodlePoints:
	if not (raw is Array) or (raw as Array).is_empty():
		return null
	var list := raw as Array
	var rows: Array = []
	if list[0] is Array:
		rows = list
	else:
		var single := list.duplicate()
		single.append(0.0)
		rows = [single]
	var dims := 1 if point_kind == KIND_FLOAT else 3
	var out := NoodlePoints.new()
	out.kind = point_kind
	var numbers := PackedFloat32Array()
	for row: Variant in rows:
		if not (row is Array):
			return null
		numbers.clear()
		var easing := NoodleEasing.LINEAR
		var is_smooth := 0
		for item: Variant in row as Array:
			if item is float or item is int:
				numbers.append(float(item))
			elif item is String:
				var s := item as String
				if s.begins_with("base"):
					return _reject("base provider '%s'" % s)
				if s.begins_with("ease"):
					easing = NoodleEasing.from_name(s)
				elif s == "splineCatmullRom":
					is_smooth = 1
				# Other flags (lerpHSV is colour-only) do not change these kinds.
			elif item is Array:
				return _reject("point modifier")
			else:
				return null
		if numbers.size() != dims + 1:
			return null
		out.times.append(numbers[dims])
		out.easings.append(easing)
		out.smooth.append(is_smooth)
		match point_kind:
			KIND_FLOAT:
				out.values.append(numbers[0])
			KIND_POSITION:
				out.values.append(numbers[0])
				out.values.append(numbers[1])
				out.values.append(-numbers[2])
			KIND_SCALE:
				out.values.append(numbers[0])
				out.values.append(numbers[1])
				out.values.append(numbers[2])
			KIND_ROTATION:
				var q := euler_to_quat(numbers[0], numbers[1], numbers[2])
				out.values.append(q.x)
				out.values.append(q.y)
				out.values.append(q.z)
				out.values.append(q.w)
	return out


static func _reject(reason: String) -> NoodlePoints:
	var out := NoodlePoints.new()
	out.unsupported = reason
	return out


## A property value as it appears in an event or an `animation` block: either the points
## themselves or the name of a point definition in `named` (see named_definitions).
static func from_value(value: Variant, point_kind: int, named: Dictionary) -> NoodlePoints:
	if value is String or value is StringName:
		return parse(named.get(String(value), null), point_kind)
	return parse(value, point_kind)


## The map's named point definitions, name -> raw points. v3 keeps them as an object in
## `customData.pointDefinitions`; v2 as a list of {_name, _points} in
## `_customData._pointDefinitions`. A map can carry both.
static func named_definitions(map_data: Dictionary) -> Dictionary:
	var named := {}
	var cd2: Variant = map_data.get("_customData", null)
	if cd2 is Dictionary:
		var list: Variant = (cd2 as Dictionary).get("_pointDefinitions", null)
		if list is Array:
			for entry: Variant in list as Array:
				if entry is Dictionary and (entry as Dictionary).get("_name", null) is String:
					named[(entry as Dictionary)["_name"]] = (entry as Dictionary).get("_points", null)
	var cd3: Variant = map_data.get("customData", null)
	if cd3 is Dictionary:
		var defs: Variant = (cd3 as Dictionary).get("pointDefinitions", null)
		if defs is Dictionary:
			for key: Variant in (defs as Dictionary):
				named[str(key)] = (defs as Dictionary)[key]
		elif defs is Array:
			# A v2-style list under the v3 key appears in converted maps.
			for entry: Variant in defs as Array:
				if entry is Dictionary:
					var d := entry as Dictionary
					var n: Variant = d.get("name", d.get("_name", null))
					if n is String:
						named[n] = d.get("points", d.get("_points", null))
	return named


# Finds the segment for time t. Returns -1 for "before or at the first point", -2 for "at or
# after the last point", otherwise the index r of the right point (l = r - 1).
func _segment(t: float) -> int:
	var n := times.size()
	if times[n - 1] <= t:
		return -2
	if times[0] >= t:
		return -1
	var l := 0
	var r := n
	while l < r - 1:
		var m := (l + r) >> 1
		if times[m] < t:
			l = m
		else:
			r = m
	return r


func _local(t: float, r: int) -> float:
	var t0 := times[r - 1]
	var d := times[r] - t0
	var u := (t - t0) / d if d != 0.0 else 0.0
	return NoodleEasing.ease(u, easings[r])


func eval_float(t: float) -> float:
	var n := times.size()
	if n == 0:
		return 0.0
	var r := _segment(t)
	if r == -2:
		return values[n - 1]
	if r == -1:
		return values[0]
	return lerpf(values[r - 1], values[r], _local(t, r))


func _vec(i: int) -> Vector3:
	return Vector3(values[i * 3], values[i * 3 + 1], values[i * 3 + 2])


func eval_vec3(t: float) -> Vector3:
	var n := times.size()
	if n == 0:
		return Vector3.ZERO
	var r := _segment(t)
	if r == -2:
		return _vec(n - 1)
	if r == -1:
		return _vec(0)
	var u := _local(t, r)
	var pa := _vec(r - 1)
	var pb := _vec(r)
	if smooth[r] == 0:
		return pa + (pb - pa) * u
	# Catmull-Rom through the neighbours, clamped at the ends (Heck SmoothVectorLerp).
	var p0 := _vec(r - 2) if r - 2 >= 0 else pa
	var p3 := _vec(r + 1) if r + 1 < n else pb
	var uu := u * u
	var uuu := uu * u
	var q0 := -uuu + 2.0 * uu - u
	var q1 := 3.0 * uuu - 5.0 * uu + 2.0
	var q2 := -3.0 * uuu + 4.0 * uu + u
	var q3 := uuu - uu
	return 0.5 * (p0 * q0 + pa * q1 + pb * q2 + p3 * q3)


func _quat(i: int) -> Quaternion:
	return Quaternion(values[i * 4], values[i * 4 + 1], values[i * 4 + 2], values[i * 4 + 3])


func eval_quat(t: float) -> Quaternion:
	var n := times.size()
	if n == 0:
		return Quaternion.IDENTITY
	var r := _segment(t)
	if r == -2:
		return _quat(n - 1)
	if r == -1:
		return _quat(0)
	return _quat(r - 1).slerp(_quat(r), _local(t, r))
