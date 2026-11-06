extends RefCounted
class_name DifficultyInfo

var difficulty: String
var difficulty_rank: int
var beatmap_filename: String
# The characteristic the beatmap belongs to ("Standard", "OneSaber", "Lawless", ...). The loader
# merges every set into one list, so this is what tells BeatLeader which leaderboard to ask for.
var characteristic := "Standard"
var note_jump_movement_speed: float
var note_jump_start_beat_offset: float
var custom_data: Dictionary
# not officially part of the spec, but used by mods a lot
var custom_name: String
# v4 only: the lightshow lives in its own file, named here. Empty for v2/v3.
var lightshow_filename: String
# v4 only: the mapper credits for this beatmap.
var level_author: String

func _init(
	difficulty: String, difficulty_rank: int, beatmap_filename: String,
	note_jump_movement_speed: float, note_jump_start_beat_offset: float,
	custom_data: Dictionary, custom_name: String
) -> void:
	self.difficulty = difficulty
	self.difficulty_rank = difficulty_rank
	self.beatmap_filename = beatmap_filename
	self.note_jump_movement_speed = note_jump_movement_speed
	self.note_jump_start_beat_offset = note_jump_start_beat_offset
	self.custom_data = custom_data
	# not officially part of the spec, but used by mods a lot
	self.custom_name = custom_name

static func load_v2(diff_dict: Dictionary) -> DifficultyInfo:
	var diff := Utils.get_str(diff_dict, "_difficulty", "")
	var data := Utils.get_dict(diff_dict, "_customData", {})
	
	var name := ""
	# not officially part of the spec, but used by mods a lot
	if not data.is_empty():
		name = Utils.get_str(data, "_difficultyLabel", "")
	if name.is_empty():
		name = diff
	
	return DifficultyInfo.new(
		diff,
		int(Utils.get_float(diff_dict, "_difficultyRank", 0)),
		Utils.get_str(diff_dict, "_beatmapFilename", ""),
		Utils.get_float(diff_dict, "_noteJumpMovementSpeed", 1.0),
		Utils.get_float(diff_dict, "_noteJumpStartBeatOffset", 0.0),
		data,
		name
	)

# v3/v4 ranks are not written to the file: the schema fixes them by difficulty name.
const RANKS := {
	"Easy": 1,
	"Normal": 3,
	"Hard": 5,
	"Expert": 7,
	"ExpertPlus": 9,
}

static func load_v3(diff_dict: Dictionary) -> DifficultyInfo:
	var diff := Utils.get_str(diff_dict, "difficulty", "")
	var data := Utils.get_dict(diff_dict, "customData", {})

	var name := Utils.get_str(data, "customName", "")
	if name.is_empty():
		name = diff

	var authors := Utils.get_dict(diff_dict, "beatmapAuthors", {})
	var mappers := Utils.get_array(authors, "mappers", [])
	var author := ""
	for m: Variant in mappers:
		if m is String and not (m as String).is_empty():
			author = m
			break

	var info := DifficultyInfo.new(
		diff,
		int(RANKS.get(diff, 0)),
		Utils.get_str(diff_dict, "beatmapDataFilename", ""),
		Utils.get_float(diff_dict, "noteJumpMovementSpeed", 1.0),
		Utils.get_float(diff_dict, "noteJumpStartBeatOffset", 0.0),
		data,
		name
	)
	# Only v4 splits the lightshow out; the field is simply absent in v3.
	info.lightshow_filename = Utils.get_str(diff_dict, "lightshowDataFilename", "")
	info.level_author = author
	info.characteristic = Utils.get_str(diff_dict, "characteristic", "Standard")
	return info
