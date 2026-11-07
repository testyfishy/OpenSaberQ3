extends RefCounted
class_name Map

const MapTimer := preload("res://game/scripts/MapTimer.gd")

# this would have basically been impossible to figure out without constantly
# referencing the beat saber modding group wiki.
# https://bsmg.wiki/mapping/map-format.html

static var current_info: MapInfo
# Bench-only: when true, _process_map spawns nothing, so a run measures the floor.
static var spawn_disabled := false
static var current_difficulty: DifficultyInfo

# --- BPM segments (FR-025) ---------------------------------------------------------------
# The segments live in MapTimer (specs/013 FR-007). These wrappers keep the call sites on the
# Map facade; the tempo state is deliberately not duplicated here.
static func bpm_at_beat(beat: float) -> float:
	return MapTimer.bpm_at_beat(beat)

static func beat_to_seconds(beat: float) -> float:
	return MapTimer.beat_to_seconds(beat)

static func seconds_to_beat(seconds: float) -> float:
	return MapTimer.seconds_to_beat(seconds)


# --- 360/90 track rotation (specs/027 FR-006) ---------------------------------------------
# Rotation events turn the lane ring around the player. Every object spawned after an event is
# placed at its rotated position and yaw, so the map reads as designed. v2 types 14 (early) and
# 15 (late) use the 0..7 value table; v3/v4 use {b, e, r} (r in degrees).
const ROT_VALUES: Array[float] = [-60.0, -45.0, -30.0, -15.0, 15.0, 30.0, 45.0, 60.0]
static var track_rotations: Array = []

static func _build_track_rotations(map_data: Dictionary) -> void:
	track_rotations.clear()
	var events: Array = []
	for entry in Utils.get_array(map_data, "rotationEvents", []):
		if entry is Dictionary:
			events.append({
				"beat": float((entry as Dictionary).get("b", 0.0)),
				"early": int(float((entry as Dictionary).get("e", 0))) == 0,
				"angle": float((entry as Dictionary).get("r", 0.0)),
			})
	for entry in Utils.get_array(map_data, "_events", []):
		if entry is Dictionary:
			var kind := int(float((entry as Dictionary).get("_type", -1)))
			if kind == 14 or kind == 15:
				var value := int(float((entry as Dictionary).get("_value", 0)))
				var angle := 0.0
				if value >= 0 and value < ROT_VALUES.size():
					angle = ROT_VALUES[value]
				events.append({
					"beat": float((entry as Dictionary).get("_time", 0.0)),
					"early": kind == 14,
					"angle": angle,
				})
	for entry in Utils.get_array(map_data, "basicBeatmapEvents", []):
		if entry is Dictionary:
			var kind := int(float((entry as Dictionary).get("et", -1)))
			if kind == 14 or kind == 15:
				var value := int(float((entry as Dictionary).get("i", 0)))
				var angle := 0.0
				if value >= 0 and value < ROT_VALUES.size():
					angle = ROT_VALUES[value]
				events.append({
					"beat": float((entry as Dictionary).get("b", 0.0)),
					"early": kind == 14,
					"angle": angle,
				})
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["beat"]), float(b["beat"])):
			return float(a["beat"]) < float(b["beat"])
		return bool(a["early"]) and not bool(b["early"]))
	track_rotations = events

## Cumulative rotation in degrees at `beat`; early events apply to objects on their beat, late
## events only after it.
static func track_rotation_at(beat: float) -> float:
	if track_rotations.is_empty():
		return 0.0
	var total := 0.0
	for entry: Dictionary in track_rotations:
		var event_beat := float(entry["beat"])
		if event_beat < beat - 0.0005:
			total += float(entry["angle"])
		elif is_equal_approx(event_beat, beat) and bool(entry["early"]):
			total += float(entry["angle"])
	return total

## Rotates a spawned object around the player. Godot's positive Y rotation is counter-clockwise
## from above; the map's positive r is clockwise, so the sign is negated.
static func apply_track_rotation(node: Node3D, beat: float) -> void:
	var angle := track_rotation_at(beat)
	if absf(angle) < 0.001:
		return
	var rad := deg_to_rad(-angle)
	node.transform.origin = node.transform.origin.rotated(Vector3.UP, rad)
	node.rotation.y += rad

# --- Map colours (FR-027/FR-028) ---------------------------------------------------------
# Notes, the room's lights and the walls each take a colour from the track, in order:
# map environment colours -> map note colours -> the environment's default scheme -> the
# player's settings. "Classic" skips the environment scheme and reproduces the old look.
static var bpm_segments := 1
# Bench instrumentation (specs/018 FR-001): the parse time and the first spawned note's delay.
static var last_load_ms := 0.0
static var load_finished_usec := 0
static var first_note_ms := -1.0
static var first_note_beat := -1.0

# --- Palette (FR-025/FR-028) --------------------------------------------------------------
# The colour rules live in MapPalette (specs/013 FR-007); this wrapper keeps the loader and
# the game on the Map facade.
static func set_colors_from_custom_data() -> void:
	MapPalette.set_colors_from_custom_data(current_info, current_difficulty)


static func _finish_load(start_usec: int) -> void:
	load_finished_usec = Time.get_ticks_usec()
	last_load_ms = (load_finished_usec - start_usec) / 1000.0
	vr.log_info("MAP load: %.1f ms" % last_load_ms)

static func load_map_info(load_path: String) -> MapInfo:
	var info_dict := {}
	if FileAccess.file_exists(load_path + "Info.dat"):
		info_dict = vr.load_json_file(load_path + "Info.dat")
	elif FileAccess.file_exists(load_path + "info.dat"):
		info_dict = vr.load_json_file(load_path + "info.dat")
	if (info_dict.is_empty()):
		vr.log_error("Invalid info.dat found in " + load_path)
		return null
	
	if info_dict.has("_version"):
		var v2 := MapInfo.new_v2(info_dict, load_path)
		v2.apply_source(MapSource.read(load_path))
		return v2
	elif info_dict.has("version"):
		var version := Utils.get_str(info_dict, "version", "")
		if version.begins_with("3.") or version.begins_with("4."):
			var v3 := MapInfo.new_v3(info_dict, load_path)
			v3.apply_source(MapSource.read(load_path))
			return v3
		vr.log_warning("%s is an unsupported beatmap version: %s" % [load_path, version])
		return null
	else:
		vr.log_warning("%s is an unknown beatmap version" % load_path)
		return null

static func load_beatmap(info: MapInfo, difficulty: DifficultyInfo, map_data: Dictionary, lightshow_data: Dictionary = {}, audio_data: Dictionary = {}) -> bool:
	var load_start := Time.get_ticks_usec()
	first_note_ms = -1.0
	first_note_beat = -1.0
	# v4 splits the beatmap and the lightshow into two files and references shared geometry
	# through index arrays. Expand it into the flat v3 shape once, up front, so every object
	# type keeps a single parser (the v3 loaders below) instead of gaining a second one.
	MapSupport.reset()
	if Utils.get_str(map_data, "version", "").begins_with("4."):
		MapData.v4_to_v3(map_data, lightshow_data)
		map_data["version"] = "3.0.0"
	# Ensures the map_data dict has a version (some maps include the version only on info but not in the data)
	if !map_data.has("_version") and !map_data.has("version"):
		if info.version.begins_with("2.") or info.version.begins_with("1."):
			map_data["_version"] = info.version
		else:
			map_data["version"] = info.version
	MapTimer.load_bpm_events(map_data, info.beats_per_minute, audio_data)
	bpm_segments = MapTimer.segment_count()
	_build_track_rotations(map_data)
	MapSupport.detect_unsupported(map_data, info)
	vr.log_info("MAP data: bpm_segments=%d fakes_filtered=%d unsupported=%s" % [bpm_segments, MapSupport.fakes_filtered, str(MapSupport.unsupported_features)])
	
	MapData.reset()
	if map_data.has("_version"):
		MapData.load_v2(map_data)
		current_info = info
		current_difficulty = difficulty
		Map.set_colors_from_custom_data()
		_finish_load(load_start)
		return true
	elif map_data.has("version"):
		var version := Utils.get_str(map_data, "version", "")
		if version.begins_with("3."):
			MapData.load_v3(map_data)
			current_info = info
			current_difficulty = difficulty
			Map.set_colors_from_custom_data()
			_finish_load(load_start)
			return true
	vr.log_warning("selected map is an unsupported version")
	return false

