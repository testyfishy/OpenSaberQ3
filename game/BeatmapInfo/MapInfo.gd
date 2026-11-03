extends RefCounted
class_name MapInfo

var version: String
var song_name: String
var song_sub_name: String
var song_author_name: String
var level_author_name: String
var beats_per_minute: float
#var shuffle: float
#var shuffle_period: float
var preview_start_time: float
var preview_duration: float
var song_filename: String
var cover_image_filename: String
var environment_name: String
var song_time_offset: float
var custom_data: Dictionary

var filepath: String
var difficulty_beatmaps: Array[DifficultyInfo]

@warning_ignore("shadowed_variable")
func _init(
	version: String, song_name: String, song_sub_name: String,
	song_author_name: String, level_author_name: String, beats_per_minute: float,
	preview_start_time: float, preview_duration: float, song_filename: String,
	cover_image_filename: String, environment_name: String,
	song_time_offset: float, custom_data: Dictionary, filepath: String,
	difficulty_beatmaps: Array[DifficultyInfo]
) -> void:
	self.version = version
	self.song_name = song_name
	self.song_sub_name = song_sub_name
	self.song_author_name = song_author_name
	self.level_author_name = level_author_name
	self.beats_per_minute = beats_per_minute
	# shuffle and shuffle period maybe in the future?
	self.preview_start_time = preview_start_time
	self.preview_duration = preview_duration
	self.song_filename = song_filename
	self.cover_image_filename = cover_image_filename
	self.environment_name = environment_name
	self.song_time_offset = song_time_offset
	self.custom_data = custom_data
	self.filepath = filepath
	self.difficulty_beatmaps = difficulty_beatmaps

func is_empty() -> bool:
	return (
		song_name.is_empty()
		and song_author_name.is_empty()
		and song_sub_name.is_empty()
		and level_author_name.is_empty()
	)

func get_key() -> String:
	return "[%s,%s,%s,%s]" % [
		song_author_name,
		song_name,
		song_sub_name,
		level_author_name
	]

static func new_v2(info_dict: Dictionary, load_path: String) -> MapInfo:
	# mix all the difficulty sets into a single one
	var diffs: Array[DifficultyInfo] = []
	var difficulty_beatmap_sets := Utils.get_array(info_dict, "_difficultyBeatmapSets", [])
	if (difficulty_beatmap_sets.is_empty()):
		vr.log_warning("No _difficultyBeatmapSets in info.dat")
	
	for difficulty_set: Variant in difficulty_beatmap_sets:
		if difficulty_set is Dictionary:
			var beatmaps := Utils.get_array(difficulty_set as Dictionary, "_difficultyBeatmaps", [])
			for i: Variant in beatmaps:
				if i is Dictionary:
					diffs.append(DifficultyInfo.load_v2(i as Dictionary))
	return MapInfo.new(
		Utils.get_str(info_dict, "_version", "2.0.0"),
		Utils.get_str(info_dict, "_songName", ""),
		Utils.get_str(info_dict, "_songSubName", ""),
		Utils.get_str(info_dict, "_songAuthorName", ""),
		Utils.get_str(info_dict, "_levelAuthorName", ""),
		Utils.get_float(info_dict, "_beatsPerMinute", 60.0),
		Utils.get_float(info_dict, "_previewStartTime", 0.0),
		Utils.get_float(info_dict, "_previewDuration", 0.0),
		Utils.get_str(info_dict, "_songFilename", ""),
		Utils.get_str(info_dict, "_coverImageFilename", ""),
		Utils.get_str(info_dict, "_environmentName", ""),
		Utils.get_float(info_dict, "_songTimeOffset", 0.0),
		Utils.get_dict(info_dict, "_customData", {}),
		load_path,
		diffs
	)


# v3 and v4 share one Info layout: a `song` block, an `audio` block, and a flat
# `difficultyBeatmaps` array. Two differences matter here: v4 has no top-level level-author
# (it is per beatmap, in `beatmapAuthors`), and v4 writes colour schemes as hex strings
# ("C81414FF") where v3 still uses {r,g,b} objects.
#
# Scheme colours are folded into `_colorLeft` / `_colorRight` so the existing custom-colour
# path in Map.set_colors_from_custom_data() picks them up unchanged. Only the first scheme is
# used: this loader merges every characteristic's difficulties into one list, so there is no
# single "current beatmap" whose scheme index could be honoured.
static func new_v3(info_dict: Dictionary, load_path: String) -> MapInfo:
	var version := Utils.get_str(info_dict, "version", "3.0.0")
	var song := Utils.get_dict(info_dict, "song", {})
	var audio := Utils.get_dict(info_dict, "audio", {})

	var diffs: Array[DifficultyInfo] = []
	for d: Variant in Utils.get_array(info_dict, "difficultyBeatmaps", []):
		if d is Dictionary:
			diffs.append(DifficultyInfo.load_v3(d as Dictionary))
	if diffs.is_empty():
		vr.log_warning("No difficultyBeatmaps in %s" % load_path)

	var environment := ""
	var env_names := Utils.get_array(info_dict, "environmentNames", [])
	if not env_names.is_empty() and env_names[0] is String:
		environment = env_names[0]

	# v4 credits mappers per beatmap; take the first credited one as the map's author.
	var level_author := ""
	for d: DifficultyInfo in diffs:
		if not d.level_author.is_empty():
			level_author = d.level_author
			break

	return MapInfo.new(
		version,
		Utils.get_str(song, "title", ""),
		Utils.get_str(song, "subTitle", ""),
		Utils.get_str(song, "author", ""),
		level_author,
		Utils.get_float(audio, "bpm", 60.0),
		Utils.get_float(audio, "previewStartTime", 0.0),
		Utils.get_float(audio, "previewDuration", 0.0),
		Utils.get_str(audio, "songFilename", ""),
		Utils.get_str(info_dict, "coverImageFilename", ""),
		environment,
		0.0,
		_color_scheme_custom_data(info_dict),
		load_path,
		diffs
	)


static func _color_scheme_custom_data(info_dict: Dictionary) -> Dictionary:
	var schemes := Utils.get_array(info_dict, "colorSchemes", [])
	if schemes.is_empty() or not (schemes[0] is Dictionary):
		return {}
	@warning_ignore("unsafe_cast")
	var scheme := schemes[0] as Dictionary
	# v2.1 nests the colours one level deeper; v3 and v4 have them directly on the entry.
	var colors := Utils.get_dict(scheme, "colorScheme", scheme)

	var left: Variant = _scheme_color(colors, "saberAColor")
	var right: Variant = _scheme_color(colors, "saberBColor")
	if left == null or right == null:
		return {}
	return {"_colorLeft": left, "_colorRight": right}


# Returns {r,g,b} for the existing colour reader, or null when the scheme omits the colour.
static func _scheme_color(scheme: Dictionary, key: String) -> Variant:
	var v: Variant = scheme.get(key, null)
	if v is Dictionary:
		@warning_ignore("unsafe_cast")
		var obj := v as Dictionary
		return {
			"r": Utils.get_float(obj, "r", 1.0),
			"g": Utils.get_float(obj, "g", 1.0),
			"b": Utils.get_float(obj, "b", 1.0),
		}
	if v is String:
		# v4: "RRGGBBAA".
		var hex := (v as String).strip_edges()
		if hex.length() < 6:
			return null
		return {
			"r": ("0x" + hex.substr(0, 2)).hex_to_int() / 255.0,
			"g": ("0x" + hex.substr(2, 2)).hex_to_int() / 255.0,
			"b": ("0x" + hex.substr(4, 2)).hex_to_int() / 255.0,
		}
	return null
