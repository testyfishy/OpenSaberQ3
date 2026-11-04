extends RefCounted
class_name ColorNoteInfo

var beat: float
var line_index: int
var line_layer: int
var color: int # 0=left, 1=right
var cut_direction: int
var angle_offset: int
# Per-note colour from the map (FR per-note colour). Transparent means "not specified", so the
# game falls back to the map's scheme colour and then to settings.
var custom_color: Color = Color(0.0, 0.0, 0.0, 0.0)
# Noodle Extensions can place a note anywhere instead of on the lane grid. When a map supplies
# coordinates we use them; otherwise the lane formula is untouched.
var has_custom_position := false
var custom_position := Vector2.ZERO

@warning_ignore("shadowed_variable")
func _init(beat: float, line_index: int, line_layer: int, color: int, cut_direction: int, angle_offset: int) -> void:
	self.beat = beat
	self.line_index = line_index
	self.line_layer = line_layer
	self.color = color
	self.cut_direction = cut_direction
	self.angle_offset = angle_offset

static func new_v2(note_dict: Dictionary) -> ColorNoteInfo:
	var note := ColorNoteInfo.new(
		Utils.get_float(note_dict, "_time", 0.0),
		int(Utils.get_float(note_dict, "_lineIndex", 0)),
		int(Utils.get_float(note_dict, "_lineLayer", 0)),
		int(Utils.get_float(note_dict, "_type", -1.0)),
		int(Utils.get_float(note_dict, "_cutDirection", 0)),
		0
	)
	note.custom_color = _read_custom_color(note_dict)
	_read_custom_position(note, note_dict)
	return note

static func new_v3(note_dict: Dictionary) -> ColorNoteInfo:
	var note := ColorNoteInfo.new(
		Utils.get_float(note_dict, "b", 0.0),
		int(Utils.get_float(note_dict, "x", 0)),
		int(Utils.get_float(note_dict, "y", 0)),
		int(Utils.get_float(note_dict, "c", -1)),
		int(Utils.get_float(note_dict, "d", 0)),
		int(Utils.get_float(note_dict, "a", 0))
	)
	note.custom_color = _read_custom_color(note_dict)
	_read_custom_position(note, note_dict)
	return note

static func _read_custom_position(note: ColorNoteInfo, note_dict: Dictionary) -> void:
	var cd = note_dict.get("_customData", note_dict.get("customData", null))
	if cd is not Dictionary:
		return
	var coords = cd.get("_coordinates", cd.get("coordinates", null))
	if coords is Dictionary:
		note.has_custom_position = true
		note.custom_position = Vector2(
			float(coords.get("x", 0.0)),
			float(coords.get("y", 0.0))
		)

# Maps express this differently per format: v2 uses `_customData._color` as {r,g,b},
# v3 embeds `customData.color`. Returns transparent when absent so callers can fall back.
static func _read_custom_color(note_dict: Dictionary) -> Color:
	var cd = note_dict.get("_customData", note_dict.get("customData", null))
	if cd is not Dictionary:
		return Color(0.0, 0.0, 0.0, 0.0)
	var c = cd.get("_color", cd.get("color", null))
	if c is Dictionary:
		return Color(
			float(c.get("r", 1.0)),
			float(c.get("g", 1.0)),
			float(c.get("b", 1.0)),
			1.0)
	return Color(0.0, 0.0, 0.0, 0.0)
