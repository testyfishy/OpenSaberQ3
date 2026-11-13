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
# True when the loaded map's notes have their own jumps and arcs/chains were linked to their
# head notes at load (link_heads). False for every other map.
static var heads_linked := false


static func reset() -> void:
	tracks.clear()
	_index.clear()
	named = {}
	is_v2 = false
	active = false
	heads_linked = false


## Called by Map.load_beatmap before the loader threads start.
static func begin_load(map_data: Dictionary) -> void:
	reset()
	NoodleEvents.reset()
	NoodleAnim.reset()
	is_v2 = map_data.has("_version")
	named = NoodlePoints.named_definitions(map_data)


## Called by Map.load_beatmap after the loader threads joined.
static func finish_load(map_data: Dictionary) -> void:
	resolve_objects()
	apply_jumps()
	NoodleEvents.load_events(map_data)


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


## Per-object jumps (Noodle `noteJumpMovementSpeed` / `noteJumpStartBeatOffset`): works out each
## such object's half jump and how much earlier or later than the map's it must spawn, and
## re-sorts a stack by spawn beat when any lead is not zero. Main thread, after the joins and
## after NoteMotion.configure().
static func apply_jumps() -> void:
	if not NoteMotion.configured:
		return
	heads_linked = false
	var notes_lead := _jump_stack(MapData.note_stack)
	_jump_stack(MapData.bomb_stack)
	_jump_stack(MapData.obstacle_stack)
	if notes_lead:
		link_heads()


## Links each arc and chain to its head note (and each arc to its tail note) by beat, colour and
## grid position. Only needed when notes have their own jumps: a note spawned earlier or later
## than the map's half jump is no longer in the same spawn frame as its arc or chain, which is
## where Playing looks for it otherwise. Main thread, at load.
static func link_heads() -> void:
	heads_linked = true
	var by_key := {}
	for info: Variant in MapData.note_stack:
		if info == null or info.fake:
			continue
		by_key[_note_key(info.beat, info.color, info.line_index, info.line_layer)] = info
	for arc: ArcInfo in MapData.arc_stack:
		if arc == null:
			continue
		arc.head_info = by_key.get(_note_key(arc.head_beat, arc.color, arc.head_line_index, arc.head_line_layer))
		var tail: ColorNoteInfo = by_key.get(_note_key(arc.tail_beat, arc.color, arc.tail_line_index, arc.tail_line_layer))
		arc.tail_linked = tail != null
		if tail != null:
			tail.arc_tail_link = true
	for chain: ChainInfo in MapData.chain_stack:
		if chain == null:
			continue
		chain.head_info = by_key.get(_note_key(chain.head_beat, chain.color, chain.head_line_index, chain.head_line_layer))


static func _note_key(beat: float, color: int, x: float, y: float) -> String:
	return "%d|%d|%.3f|%.3f" % [roundi(beat * 1000.0), color, x, y]


## Returns whether any object of `stack` spawns earlier or later than the map's half jump.
static func _jump_stack(stack: Array) -> bool:
	var map_beats := NoteMotion.spawn_beats()
	var map_sec := NoteMotion.half_jump_seconds()
	var any := false
	for info: Variant in stack:
		if info == null or info.noodle == null:
			continue
		var obj: NoodleObject = info.noodle
		if obj.njs <= 0.0 and not obj.has_jump_offset:
			continue
		var beats := NoteMotion.object_half_jump_beats(obj.njs, obj.has_jump_offset, obj.jump_offset)
		obj.half_sec = map_sec * beats / map_beats
		info.spawn_lead = beats - map_beats
		if info.spawn_lead != 0.0:
			any = true
	if not any:
		return false
	# Spawn order is beat - lead. The stack is reversed (next to spawn at the back); the original
	# position breaks ties so objects on one beat keep their order (sort_custom is not stable).
	var keyed: Array = []
	for i in stack.size():
		var info: Variant = stack[i]
		var at: float = INF if info == null else float(info.beat) - float(info.spawn_lead)
		keyed.append([at, i, info])
	keyed.sort_custom(func(x: Array, y: Array) -> bool:
		return x[0] > y[0] or (x[0] == y[0] and x[1] < y[1]))
	for i in keyed.size():
		stack[i] = keyed[i][2]
	return true


static func _resolve(obj: NoodleObject) -> void:
	active = true
	obj.tracks.clear()
	for track_name in obj.track_names:
		obj.tracks.append(index_of(track_name))
