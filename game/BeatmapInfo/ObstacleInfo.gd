extends RefCounted
class_name ObstacleInfo

var beat: float
var duration: float
var line_index: float
var line_layer: float
var width: float
var height: float
# Chroma can colour one wall; transparent means "use the map's wall colour".
var custom_color := Color(0.0, 0.0, 0.0, 0.0)
var fake := false

@warning_ignore("shadowed_variable")
func _init(beat: float, duration: float, line_index: float, line_layer: float, width: float, height: float) -> void:
	self.beat = beat
	self.duration = duration
	self.line_index = line_index
	self.line_layer = line_layer
	self.width = width
	self.height = height

static func new_v2(obstacle_dict: Dictionary) -> ObstacleInfo:
	var raw_type := int(Utils.get_float(obstacle_dict, "_type", 0))
	var y: float = 0.0
	var h: float = 0.0
	var me := BeatmapPrecision.wall_height(raw_type)
	if not me.is_empty():
		y = float(me["layer"])
		h = float(me["height"])
	else:
		match raw_type:
			0: # full height
				y = 0
				h = 5
			1: # crouch
				y = 2
				h = 3
			2: # free
				y = BeatmapPrecision.decode_position(Utils.get_float(obstacle_dict, "_lineLayer", 0.0))
				h = Utils.get_float(obstacle_dict, "_height", 0.0)
	var obstacle := ObstacleInfo.new(
		Utils.get_float(obstacle_dict, "_time", 0.0),
		Utils.get_float(obstacle_dict, "_duration", 0.0),
		BeatmapPrecision.decode_position(Utils.get_float(obstacle_dict, "_lineIndex", 0.0)),
		y,
		BeatmapPrecision.decode_size(Utils.get_float(obstacle_dict, "_width", 0.0)),
		h
	)
	var cd := Utils.get_dict(obstacle_dict, "_customData", {})
	obstacle.custom_color = PaletteResolver.chroma_color(cd.get("_color", cd.get("color", null)))
	obstacle.fake = Utils.get_bool(cd, "_fake", false)
	return obstacle

static func new_v3(obstacle_dict: Dictionary) -> ObstacleInfo:
	var obstacle := ObstacleInfo.new(
		Utils.get_float(obstacle_dict, "b", 0.0),
		Utils.get_float(obstacle_dict, "d", 0.0),
		BeatmapPrecision.decode_position(Utils.get_float(obstacle_dict, "x", 0.0)),
		BeatmapPrecision.decode_position(Utils.get_float(obstacle_dict, "y", 0.0)),
		BeatmapPrecision.decode_size(Utils.get_float(obstacle_dict, "w", 0.0)),
		Utils.get_float(obstacle_dict, "h", 0.0)
	)
	var cd := Utils.get_dict(obstacle_dict, "customData", {})
	obstacle.custom_color = PaletteResolver.chroma_color(cd.get("color", cd.get("_color", null)))
	obstacle.fake = Utils.get_bool(cd, "fake", false)
	return obstacle

