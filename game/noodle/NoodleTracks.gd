extends RefCounted
class_name NoodleTracks

# The track registry for the loaded map (Heck "tracks"): name -> NoodleTrack, plus the map's
# named point definitions. Static, like Map and MapData, and reset on every map load.
#
# Threading: the object parsers run on MapData's loader threads. They only READ `named` (set
# before the threads start) and store raw track names on their NoodleObject; tracks are created
# and names resolved to indices on the main thread in finish_load(), after the threads joined.

# Property indices. One table for track values and for paths; not every property is valid in
# both (definitePosition is path-only, time / position / localPosition / rotation are track-only).
const P_OFFSET_POSITION := 0
const P_OFFSET_WORLD_ROTATION := 1
const P_LOCAL_ROTATION := 2
const P_SCALE := 3
const P_DISSOLVE := 4
const P_DISSOLVE_ARROW := 5
const P_INTERACTABLE := 6
const P_DEFINITE_POSITION := 7
const P_POSITION := 8
const P_LOCAL_POSITION := 9
const P_ROTATION := 10
const P_TIME := 11
const P_COUNT := 12

const KINDS: Array[int] = [
	NoodlePoints.KIND_POSITION,  # offsetPosition
	NoodlePoints.KIND_ROTATION,  # offsetWorldRotation
	NoodlePoints.KIND_ROTATION,  # localRotation
	NoodlePoints.KIND_SCALE,     # scale
	NoodlePoints.KIND_FLOAT,     # dissolve
	NoodlePoints.KIND_FLOAT,     # dissolveArrow
	NoodlePoints.KIND_FLOAT,     # interactable
	NoodlePoints.KIND_POSITION,  # definitePosition
	NoodlePoints.KIND_POSITION,  # position (transform tracks, v3)
	NoodlePoints.KIND_POSITION,  # localPosition (transform tracks, v3)
	NoodlePoints.KIND_ROTATION,  # rotation (transform tracks, v3)
	NoodlePoints.KIND_FLOAT,     # time
]

# Property names as they appear in events and `animation` blocks. v2 renames: `_position` is
# offsetPosition and `_rotation` is offsetWorldRotation (Heck wiki, V2ToV3).
const V3_NAMES := {
	"offsetPosition": P_OFFSET_POSITION, "offsetWorldRotation": P_OFFSET_WORLD_ROTATION,
	"localRotation": P_LOCAL_ROTATION, "scale": P_SCALE, "dissolve": P_DISSOLVE,
	"dissolveArrow": P_DISSOLVE_ARROW, "interactable": P_INTERACTABLE,
	"definitePosition": P_DEFINITE_POSITION, "position": P_POSITION,
	"localPosition": P_LOCAL_POSITION, "rotation": P_ROTATION, "time": P_TIME,
}
const V2_NAMES := {
	"_position": P_OFFSET_POSITION, "_rotation": P_OFFSET_WORLD_ROTATION,
	"_localRotation": P_LOCAL_ROTATION, "_scale": P_SCALE, "_dissolve": P_DISSOLVE,
	"_dissolveArrow": P_DISSOLVE_ARROW, "_interactable": P_INTERACTABLE,
	"_definitePosition": P_DEFINITE_POSITION, "_localPosition": P_LOCAL_POSITION,
	"_time": P_TIME,
}

static var tracks: Array[NoodleTrack] = []
static var _index := {}
# Named point definitions, name -> raw points (see NoodlePoints.named_definitions).
static var named := {}
# True when the loaded map is a v2 map (some units differ, see NoodleAnim).
static var is_v2 := false
# True once any object or event of the loaded map uses tracks or animation. Everything per tick
# is skipped while this is false, so a map without Noodle data runs the code it always ran.
static var active := false


static func reset() -> void:
	tracks.clear()
	_index.clear()
	named = {}
	is_v2 = false
	active = false


## Called by Map.load_beatmap before the loader threads start.
static func begin_load(map_data: Dictionary) -> void:
	reset()
	is_v2 = map_data.has("_version")
	named = NoodlePoints.named_definitions(map_data)


## Called by Map.load_beatmap after the loader threads joined.
static func finish_load(_map_data: Dictionary) -> void:
	resolve_objects()


## The index of track `track_name`, creating it if needed. Main thread only.
static func index_of(track_name: String) -> int:
	var found: Variant = _index.get(track_name, null)
	if found != null:
		return int(found)
	var i := tracks.size()
	tracks.append(NoodleTrack.new(track_name))
	_index[track_name] = i
	return i


## The index of an existing track, or -1.
static func find(track_name: String) -> int:
	return int(_index.get(track_name, -1))


static func get_track(i: int) -> NoodleTrack:
	return tracks[i]


## Raw `track` / `_track` value (a string or a list of strings) to names. Pure.
static func names_from(value: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if value is String or value is StringName:
		if String(value) != "":
			out.append(String(value))
	elif value is Array:
		for v: Variant in value as Array:
			if (v is String or v is StringName) and String(v) != "":
				out.append(String(v))
	return out


## Resolves the track names of every loaded object to indices. Main thread, after the joins.
static func resolve_objects() -> void:
	for info in MapData.note_stack:
		if info != null and info.noodle != null:
			_resolve(info.noodle)
	for info in MapData.bomb_stack:
		if info != null and info.noodle != null:
			_resolve(info.noodle)
	for info in MapData.obstacle_stack:
		if info != null and info.noodle != null:
			_resolve(info.noodle)


static func _resolve(obj: NoodleObject) -> void:
	active = true
	obj.tracks.clear()
	for track_name in obj.track_names:
		obj.tracks.append(index_of(track_name))
