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

static func load_beatmap(info: MapInfo, difficulty: DifficultyInfo, map_data: Dictionary, lightshow_data: Dictionary = {}, audio_data: Dictionary = {}) -> bool:
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

