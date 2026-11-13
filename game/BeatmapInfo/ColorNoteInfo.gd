extends RefCounted
class_name ColorNoteInfo

var beat: float
var line_index: float
var line_layer: float
var color: int # 0=left, 1=right
var cut_direction: int
var angle_offset: int
# Mapping Extensions any-direction note: show the arrow but ignore the cut angle when scoring.
var ignore_cut_angle := false
# Per-note colour from the map (FR per-note colour). Transparent means "not specified", so the
# game falls back to the map's scheme colour and then to settings.
var custom_color: Color = Color(0.0, 0.0, 0.0, 0.0)
# Noodle Extensions can place a note anywhere instead of on the lane grid. When a map supplies
# coordinates we use them; otherwise the lane formula is untouched.
# Noodle Extensions per-note jump speed (`noteJumpMovementSpeed`); 0 means the map's own.
var custom_njs := 0.0
var has_custom_position := false
var custom_position := Vector2.ZERO
# Noodle static transforms (specs/027 FR-007): rotations and a scale multiplier. The rotations
# are Godot-frame quaternions (converted from Beat Saber's left-handed frame like the animated
# ones); the note's rotation is world * local * cut direction, as Heck composes it.
# `custom_euler` keeps the map's raw degrees for the probes only.
var has_custom_rotation := false
var custom_euler := Vector3.ZERO
var custom_world := Quaternion.IDENTITY
var custom_local := Quaternion.IDENTITY
var has_custom_scale := false
var custom_scale := Vector3.ONE
# Noodle Extensions tracks and animation (game/noodle); null for an object without any.
var noodle: NoodleObject = null
# Beats earlier (positive) or later than the map's half jump this object spawns: its own Noodle
# jump (step 5). 0 for every object of an ordinary map.
var spawn_lead := 0.0
# Noodle/Chroma decorative note (`fake` / `_fake`, or v3 `fakeColorNotes`): drawn and animated,
# never hittable, missable or scored.
var fake := false
# Set only on maps where notes have their own jump (NoodleTracks.link_heads): such a note may
# spawn in a different frame from the arc or chain it starts, so the link is made at load.
# `spawned` is the cube drawing this note once it is spawned (runtime only).
var spawned: Node3D = null
var arc_tail_link := false

@warning_ignore("shadowed_variable")
func _init(beat: float, line_index: float, line_layer: float, color: int, cut_direction: int, angle_offset: int) -> void:
	self.beat = beat
	self.line_index = line_index
	self.line_layer = line_layer
	self.color = color
	self.cut_direction = cut_direction
	self.angle_offset = angle_offset

static func new_v2(note_dict: Dictionary) -> ColorNoteInfo:
	var raw_dir := int(Utils.get_float(note_dict, "_cutDirection", 0))
	var precise := BeatmapPrecision.cut_angle(raw_dir)
	var direction := raw_dir
	var offset := 0
	var any_direction := false
	if not precise.is_empty():
		# 0 = down, 90 = left, 180 = up; base direction 1 is the down arrow (rotation 0).
		direction = 1
		offset = -int(precise["angle"])
		any_direction = bool(precise["any"])
	var note := ColorNoteInfo.new(
		Utils.get_float(note_dict, "_time", 0.0),
		BeatmapPrecision.decode_position(Utils.get_float(note_dict, "_lineIndex", 0.0)),
		BeatmapPrecision.decode_position(Utils.get_float(note_dict, "_lineLayer", 0.0)),
		int(Utils.get_float(note_dict, "_type", -1.0)),
		direction,
		offset
	)
	note.ignore_cut_angle = any_direction
	note.custom_color = _read_custom_color(note_dict)
	_read_custom_position(note, note_dict)
	note.noodle = NoodleObject.from_entry(note_dict)
	return note

static func new_v3(note_dict: Dictionary) -> ColorNoteInfo:
	var raw_dir := int(Utils.get_float(note_dict, "d", 0))
	var precise := BeatmapPrecision.cut_angle(raw_dir)
	var direction := raw_dir
	var offset := int(Utils.get_float(note_dict, "a", 0))
	var any_direction := false
	if not precise.is_empty():
		direction = 1
		offset = -int(precise["angle"])
		any_direction = bool(precise["any"])
	var note := ColorNoteInfo.new(
		Utils.get_float(note_dict, "b", 0.0),
		BeatmapPrecision.decode_position(Utils.get_float(note_dict, "x", 0.0)),
		BeatmapPrecision.decode_position(Utils.get_float(note_dict, "y", 0.0)),
		int(Utils.get_float(note_dict, "c", -1)),
		direction,
		offset
	)
	note.ignore_cut_angle = any_direction
	note.custom_color = _read_custom_color(note_dict)
	_read_custom_position(note, note_dict)
	note.noodle = NoodleObject.from_entry(note_dict)
	return note

static func _read_custom_position(note: ColorNoteInfo, note_dict: Dictionary) -> void:
	var cd = note_dict.get("_customData", note_dict.get("customData", null))
	if cd is not Dictionary:
		return
	var is_fake = cd.get("fake", cd.get("_fake", false))
	note.fake = is_fake is bool and is_fake
	var own_njs = cd.get("noteJumpMovementSpeed", cd.get("_noteJumpMovementSpeed", null))
	if own_njs is float or own_njs is int:
		note.custom_njs = maxf(float(own_njs), 0.0)
	var coords = cd.get("_coordinates", cd.get("coordinates", null))
	if coords is Dictionary:
		note.has_custom_position = true
		note.custom_position = Vector2(
			float(coords.get("x", 0.0)),
			float(coords.get("y", 0.0))
		)
	var pos = cd.get("coordinates", cd.get("_position", cd.get("position", null)))
	if pos is Array and pos.size() >= 2:
		note.has_custom_position = true
		note.custom_position = Vector2(float(pos[0]), float(pos[1]))
	elif pos is Dictionary:
		note.has_custom_position = true
		note.custom_position = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
	var world_raw = cd.get("worldRotation", cd.get("_rotation", cd.get("rotation", null)))
	var local_raw = cd.get("localRotation", cd.get("_localRotation", null))
	var world = NoodlePoints.static_rotation(world_raw, true)
	var local = NoodlePoints.static_rotation(local_raw, false)
	if world != null or local != null:
		note.has_custom_rotation = true
		var raw = local_raw if local != null else world_raw
		note.custom_euler = Vector3(float(raw[0]), float(raw[1]), float(raw[2])) if raw is Array else Vector3(0.0, float(raw), 0.0)
		if world != null:
			note.custom_world = world
		if local != null:
			note.custom_local = local
	var scl = cd.get("size", cd.get("_scale", cd.get("scale", null)))
	if scl is Array and scl.size() >= 3:
		note.has_custom_scale = true
		note.custom_scale = Vector3(float(scl[0]), float(scl[1]), float(scl[2]))
	elif scl is float or scl is int:
		note.has_custom_scale = true
		note.custom_scale = Vector3.ONE * float(scl)

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


