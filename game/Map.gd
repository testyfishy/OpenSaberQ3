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


# --- Map colours (FR-027/FR-028) ---------------------------------------------------------
# Notes, the room's lights and the walls each take a colour from the track, in order:
# map environment colours -> map note colours -> the environment's default scheme -> the
# player's settings. "Classic" skips the environment scheme and reproduces the old look.
static var bpm_segments := 1

# --- Palette (FR-025/FR-028) --------------------------------------------------------------
# The colour rules live in MapPalette (specs/013 FR-007); this wrapper keeps the loader and
# the game on the Map facade.
static func set_colors_from_custom_data() -> void:
	MapPalette.set_colors_from_custom_data(current_info, current_difficulty)


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
		return MapInfo.new_v2(info_dict, load_path)
	elif info_dict.has("version"):
		var version := Utils.get_str(info_dict, "version", "")
		if version.begins_with("3.") or version.begins_with("4."):
			return MapInfo.new_v3(info_dict, load_path)
		vr.log_warning("%s is an unsupported beatmap version: %s" % [load_path, version])
		return null
	else:
		vr.log_warning("%s is an unknown beatmap version" % load_path)
		return null

# --- v4 -> v3 expansion --------------------------------------------------------------------
# v4 stores each object's geometry once in a `...Data` collection and references it by index,
# so several objects can share one definition. The game needs a concrete object per note, so
# the index is resolved here and the result written in the v3 field names.
static func _v4_to_v3(map_data: Dictionary, lightshow_data: Dictionary) -> void:
	var note_data := Utils.get_array(map_data, "colorNotesData", [])
	var bomb_data := Utils.get_array(map_data, "bombNotesData", [])
	var obstacle_data := Utils.get_array(map_data, "obstaclesData", [])
	var arc_data := Utils.get_array(map_data, "arcsData", [])
	var chain_data := Utils.get_array(map_data, "chainsData", [])
	var event_data := Utils.get_array(lightshow_data, "basicEventsData", [])

	map_data["colorNotes"] = _v4_expand_notes(Utils.get_array(map_data, "colorNotes", []), note_data)
	map_data["bombNotes"] = _v4_expand_bombs(Utils.get_array(map_data, "bombNotes", []), bomb_data)
	map_data["obstacles"] = _v4_expand_obstacles(Utils.get_array(map_data, "obstacles", []), obstacle_data)
	map_data["sliders"] = _v4_expand_arcs(
		Utils.get_array(map_data, "arcs", []), note_data, arc_data)
	map_data["burstSliders"] = _v4_expand_chains(
		Utils.get_array(map_data, "chains", []), note_data, chain_data)
	map_data["basicBeatmapEvents"] = _v4_expand_events(
		Utils.get_array(lightshow_data, "basicEvents", []), event_data)


static func _v4_at(entry: Dictionary, data: Array, key: String, default: int = -1) -> Dictionary:
	var idx := int(Utils.get_float(entry, key, float(default)))
	if idx < 0 or idx >= data.size() or not (data[idx] is Dictionary):
		return {}
	@warning_ignore("unsafe_cast")
	return data[idx] as Dictionary


static func _v4_expand_notes(list: Array, data: Array) -> Array:
	var out: Array = []
	for e: Variant in list:
		if not (e is Dictionary):
			continue
		@warning_ignore("unsafe_cast")
		var entry := e as Dictionary
		var d := _v4_at(entry, data, "i")
		if d.is_empty():
			continue
		out.append({
			"b": Utils.get_float(entry, "b", 0.0),
			"x": Utils.get_float(d, "x", 0.0),
			"y": Utils.get_float(d, "y", 0.0),
			"c": Utils.get_float(d, "c", -1.0),
			"d": Utils.get_float(d, "d", 0.0),
			"a": Utils.get_float(d, "a", 0.0),
			"customData": entry.get("customData", d.get("customData", {})),
		})
	return out


static func _v4_expand_bombs(list: Array, data: Array) -> Array:
	var out: Array = []
	for e: Variant in list:
		if not (e is Dictionary):
			continue
		@warning_ignore("unsafe_cast")
		var entry := e as Dictionary
		var d := _v4_at(entry, data, "i")
		if d.is_empty():
			continue
		out.append({
			"b": Utils.get_float(entry, "b", 0.0),
			"x": Utils.get_float(d, "x", 0.0),
			"y": Utils.get_float(d, "y", 0.0),
		})
	return out


static func _v4_expand_obstacles(list: Array, data: Array) -> Array:
	var out: Array = []
	for e: Variant in list:
		if not (e is Dictionary):
			continue
		@warning_ignore("unsafe_cast")
		var entry := e as Dictionary
		var d := _v4_at(entry, data, "i")
		if d.is_empty():
			continue
		out.append({
			"b": Utils.get_float(entry, "b", 0.0),
			"d": Utils.get_float(d, "d", 0.0),
			"x": Utils.get_float(d, "x", 0.0),
			"y": Utils.get_float(d, "y", 0.0),
			"w": Utils.get_float(d, "w", 0.0),
			"h": Utils.get_float(d, "h", 0.0),
		})
	return out


static func _v4_expand_arcs(list: Array, note_data: Array, arc_data: Array) -> Array:
	var out: Array = []
	for e: Variant in list:
		if not (e is Dictionary):
			continue
		@warning_ignore("unsafe_cast")
		var entry := e as Dictionary
		var head := _v4_at(entry, note_data, "hi")
		var tail := _v4_at(entry, note_data, "ti")
		var meta := _v4_at(entry, arc_data, "ai")
		if head.is_empty() or tail.is_empty():
			continue
		out.append({
			"c": Utils.get_float(head, "c", 0.0),
			"b": Utils.get_float(entry, "hb", 0.0),
			"x": Utils.get_float(head, "x", 0.0),
			"y": Utils.get_float(head, "y", 0.0),
			"d": Utils.get_float(head, "d", 0.0),
			"mu": Utils.get_float(meta, "m", 1.0),
			"tb": Utils.get_float(entry, "tb", 0.0),
			"tx": Utils.get_float(tail, "x", 0.0),
			"ty": Utils.get_float(tail, "y", 0.0),
			"tc": Utils.get_float(tail, "d", 0.0),
			"tmu": Utils.get_float(meta, "tm", 1.0),
			"m": Utils.get_float(meta, "a", 0.0),
		})
	return out


static func _v4_expand_chains(list: Array, note_data: Array, chain_data: Array) -> Array:
	var out: Array = []
	for e: Variant in list:
		if not (e is Dictionary):
			continue
		@warning_ignore("unsafe_cast")
		var entry := e as Dictionary
		var head := _v4_at(entry, note_data, "i")
		var meta := _v4_at(entry, chain_data, "ci")
		if head.is_empty() or meta.is_empty():
			continue
		out.append({
			"c": Utils.get_float(head, "c", 0.0),
			"b": Utils.get_float(entry, "hb", 0.0),
			"x": Utils.get_float(head, "x", 0.0),
			"y": Utils.get_float(head, "y", 0.0),
			"d": Utils.get_float(head, "d", 0.0),
			"tb": Utils.get_float(entry, "tb", 0.0),
			"tx": Utils.get_float(meta, "tx", 0.0),
			"ty": Utils.get_float(meta, "ty", 0.0),
			"sc": Utils.get_float(meta, "c", 0.0),
			"s": Utils.get_float(meta, "s", 1.0),
		})
	return out


static func _v4_expand_events(list: Array, data: Array) -> Array:
	var out: Array = []
	for e: Variant in list:
		if not (e is Dictionary):
			continue
		@warning_ignore("unsafe_cast")
		var entry := e as Dictionary
		var d := _v4_at(entry, data, "i")
		out.append({
			"b": Utils.get_float(entry, "b", 0.0),
			"et": Utils.get_float(d, "t", 0.0),
			"i": Utils.get_float(d, "i", 0.0),
			"f": Utils.get_float(d, "f", -1.0),
		})
	return out


static func load_beatmap(info: MapInfo, difficulty: DifficultyInfo, map_data: Dictionary, lightshow_data: Dictionary = {}, audio_data: Dictionary = {}) -> bool:
	# v4 splits the beatmap and the lightshow into two files and references shared geometry
	# through index arrays. Expand it into the flat v3 shape once, up front, so every object
	# type keeps a single parser (the v3 loaders below) instead of gaining a second one.
	MapSupport.reset()
	if Utils.get_str(map_data, "version", "").begins_with("4."):
		_v4_to_v3(map_data, lightshow_data)
		map_data["version"] = "3.0.0"
	# Ensures the map_data dict has a version (some maps include the version only on info but not in the data)
	if !map_data.has("_version") and !map_data.has("version"):
		if info.version.begins_with("2.") or info.version.begins_with("1."):
			map_data["_version"] = info.version
		else:
			map_data["version"] = info.version
	MapTimer.load_bpm_events(map_data, info.beats_per_minute, audio_data)
	bpm_segments = MapTimer.segment_count()
	MapSupport.detect_unsupported(map_data, info)
	vr.log_info("MAP data: bpm_segments=%d fakes_filtered=%d unsupported=%s" % [bpm_segments, MapSupport.fakes_filtered, str(MapSupport.unsupported_features)])
	
	MapData.reset()
	if map_data.has("_version"):
		MapData.load_v2(map_data)
		current_info = info
		current_difficulty = difficulty
		Map.set_colors_from_custom_data()
		return true
	elif map_data.has("version"):
		var version := Utils.get_str(map_data, "version", "")
		if version.begins_with("3."):
			MapData.load_v3(map_data)
			current_info = info
			current_difficulty = difficulty
			Map.set_colors_from_custom_data()
			return true
	vr.log_warning("selected map is an unsupported version")
	return false

