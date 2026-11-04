extends RefCounted
class_name ObstacleInfo

var beat: float
var duration: float
var line_index: int
var line_layer: int
var width: int
var height: int
# Chroma can colour one wall; transparent means "use the map's wall colour".
var custom_color := Color(0.0, 0.0, 0.0, 0.0)
var fake := false

@warning_ignore("shadowed_variable")
func _init(beat: float, duration: float, line_index: int, line_layer: int, width: int, height: int) -> void:
	self.beat = beat
	self.duration = duration
	self.line_index = line_index
	self.line_layer = line_layer
	self.width = width
	self.height = height

static func new_v2(obstacle_dict: Dictionary) -> ObstacleInfo:
	var y: int = 0
	var h: int = 0
	match int(Utils.get_float(obstacle_dict, "_type", 0)):
		0: # full height
			y = 0
			h = 5
		1: # crouch
			y = 2
			h = 3
		2: # free
			y = int(Utils.get_float(obstacle_dict, "_lineLayer", 0))
			h = int(Utils.get_float(obstacle_dict, "_height", 0))
	var obstacle := ObstacleInfo.new(
		Utils.get_float(obstacle_dict, "_time", 0.0),
		Utils.get_float(obstacle_dict, "_duration", 0.0),
		int(Utils.get_float(obstacle_dict, "_lineIndex", 0)),
		y,
		int(Utils.get_float(obstacle_dict, "_width", 0)),
		h
	)
	var cd := Utils.get_dict(obstacle_dict, "_customData", {})
	obstacle.custom_color = _chroma_color(cd.get("_color", cd.get("color", null)))
	obstacle.fake = Utils.get_bool(cd, "_fake", false)
	return obstacle

static func new_v3(obstacle_dict: Dictionary) -> ObstacleInfo:
	var obstacle := ObstacleInfo.new(
		Utils.get_float(obstacle_dict, "b", 0.0),
		Utils.get_float(obstacle_dict, "d", 0.0),
		int(Utils.get_float(obstacle_dict, "x", 0)),
		int(Utils.get_float(obstacle_dict, "y", 0)),
		int(Utils.get_float(obstacle_dict, "w", 0)),
		int(Utils.get_float(obstacle_dict, "h", 0))
	)
	var cd := Utils.get_dict(obstacle_dict, "customData", {})
	obstacle.custom_color = _chroma_color(cd.get("color", cd.get("_color", null)))
	obstacle.fake = Utils.get_bool(cd, "fake", false)
	return obstacle

static func _chroma_color(value: Variant) -> Color:
	if value is Dictionary:
		@warning_ignore("unsafe_cast")
		var d := value as Dictionary
		return Color(Utils.get_float(d, "r", 1.0), Utils.get_float(d, "g", 1.0), Utils.get_float(d, "b", 1.0), 1.0)
	if value is String:
		var hex := (value as String).strip_edges().trim_prefix("#")
		if hex.length() == 6:
			return Color(
				("0x" + hex.substr(0, 2)).hex_to_int() / 255.0,
				("0x" + hex.substr(2, 2)).hex_to_int() / 255.0,
				("0x" + hex.substr(4, 2)).hex_to_int() / 255.0,
				1.0
			)
	return Color(0.0, 0.0, 0.0, 0.0)
