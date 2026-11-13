extends RefCounted
class_name BombInfo

var beat: float
var line_index: float
var line_layer: float
# Noodle Extensions tracks and animation (game/noodle); null for an object without any.
var noodle: NoodleObject = null
# Beats earlier (positive) or later than the map's half jump this object spawns: its own Noodle
# jump (step 5). 0 for every object of an ordinary map.
var spawn_lead := 0.0
# Decorative bomb (`fake` / `_fake`, or v3 `fakeBombNotes`): drawn, never hittable.
var fake := false

@warning_ignore("shadowed_variable")
func _init(beat: float, line_index: float, line_layer: float) -> void:
	self.beat = beat
	self.line_index = line_index
	self.line_layer = line_layer

static func new_v2(bomb_dict: Dictionary) -> BombInfo:
	var bomb := BombInfo.new(
		Utils.get_float(bomb_dict, "_time", 0.0),
		BeatmapPrecision.decode_position(Utils.get_float(bomb_dict, "_lineIndex", 0.0)),
		BeatmapPrecision.decode_position(Utils.get_float(bomb_dict, "_lineLayer", 0.0))
	)
	bomb.noodle = NoodleObject.from_entry(bomb_dict)
	bomb.fake = _read_fake(bomb_dict)
	return bomb

static func _read_fake(bomb_dict: Dictionary) -> bool:
	var cd: Variant = bomb_dict.get("_customData", bomb_dict.get("customData", null))
	if not (cd is Dictionary):
		return false
	var f: Variant = (cd as Dictionary).get("fake", (cd as Dictionary).get("_fake", false))
	return f is bool and f

static func new_v3(bomb_dict: Dictionary) -> BombInfo:
	var bomb := BombInfo.new(
		Utils.get_float(bomb_dict, "b", 0.0),
		BeatmapPrecision.decode_position(Utils.get_float(bomb_dict, "x", 0.0)),
		BeatmapPrecision.decode_position(Utils.get_float(bomb_dict, "y", 0.0))
	)
	bomb.noodle = NoodleObject.from_entry(bomb_dict)
	bomb.fake = _read_fake(bomb_dict)
	return bomb
