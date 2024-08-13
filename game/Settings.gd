extends Node

const CONFIG_PATH := "user://config.dat"
const NEW_CONFIG_SIZE := 94

var thickness: float
var color_left: Color
var color_right: Color
var saber_visual: int
var ui_volume: float
var left_saber_offset_pos: Vector3
var left_saber_offset_rot: Vector3
var right_saber_offset_pos: Vector3
var right_saber_offset_rot: Vector3
var cube_cuts_falloff: bool
var saber_tail: bool
var glare: bool
var show_fps: bool
var bombs_enabled: bool
var events: bool
var disable_map_color: bool
var player_height_offset: float

var SABER_VISUALS: Array[PackedStringArray] = [
	PackedStringArray(["Default saber","res://game/sabers/default/default_saber.tscn"]),
	PackedStringArray(["Particle sword","res://game/sabers/particles/particles_saber.tscn"])
]

func _ready() -> void:
	if FileAccess.file_exists(CONFIG_PATH):
		reload()
	else:
		restore_defaults()
		save()

# load() is the name of a built-in function,
# so i went with the next best thing.
func reload() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		vr.log_file_error(FileAccess.get_open_error(), CONFIG_PATH, "load() in Settings.gd")
		return
	if file.get_length() != NEW_CONFIG_SIZE:
		load_old_config(file)
		return
	thickness = file.get_float()
	color_left = Color(file.get_float(), file.get_float(), file.get_float(), file.get_float())
	color_right = Color(file.get_float(), file.get_float(), file.get_float(), file.get_float())
	saber_visual = file.get_8()
	ui_volume = file.get_float()
	left_saber_offset_pos.x = file.get_float()
	left_saber_offset_pos.y = file.get_float()
	left_saber_offset_pos.z = file.get_float()
	left_saber_offset_rot.x = file.get_float()
	left_saber_offset_rot.y = file.get_float()
	left_saber_offset_rot.z = file.get_float()
	right_saber_offset_pos.x = file.get_float()
	right_saber_offset_pos.y = file.get_float()
	right_saber_offset_pos.z = file.get_float()
	right_saber_offset_rot.x = file.get_float()
	right_saber_offset_rot.y = file.get_float()
	right_saber_offset_rot.z = file.get_float()
	player_height_offset = file.get_float()
	var bools_as_byte := file.get_8()
	file.close()
	cube_cuts_falloff = bools_as_byte & 64
	saber_tail = bools_as_byte & 32
	glare = bools_as_byte & 16
	show_fps = bools_as_byte & 8
	bombs_enabled = bools_as_byte & 4
	events = bools_as_byte & 2
	disable_map_color = bools_as_byte & 1

func load_old_config(file: FileAccess) -> void:
	var settings_var: Variant = file.get_var(true)
	file.close()
	if not settings_var is Dictionary:
		restore_defaults()
		return
	var settings_dict := settings_var as Dictionary
	thickness = Utils.get_float(settings_dict, "thickness", 100)
	if settings_dict.has("COLOR_LEFT") and settings_dict["COLOR_LEFT"] is Color:
		@warning_ignore("unsafe_cast")
		color_left = settings_dict["COLOR_LEFT"] as Color
	else:
		color_left = Color("ff1a1a")
	if settings_dict.has("COLOR_RIGHT") and settings_dict["COLOR_RIGHT"] is Color:
		@warning_ignore("unsafe_cast")
		color_right = settings_dict["COLOR_RIGHT"] as Color
	else:
		color_right = Color("1a1aff")
	saber_visual = int(Utils.get_float(settings_dict, "saber", 0))
	ui_volume = Utils.get_float(settings_dict, "ui_volume", 10.0)
	left_saber_offset_pos = Vector3.ZERO
	left_saber_offset_rot = Vector3.ZERO
	if settings_dict.has("left_saber_offset") and settings_dict["left_saber_offset"] is Array:
		@warning_ignore("unsafe_cast")
		var left_array: Array = settings_dict["left_saber_offset"] as Array
		if left_array.size() == 2:
			if left_array[0] is Vector3:
				@warning_ignore("unsafe_cast")
				left_saber_offset_pos = left_array[0] as Vector3
			if left_array[1] is Vector3:
				@warning_ignore("unsafe_cast")
				left_saber_offset_rot = left_array[1] as Vector3
	right_saber_offset_pos = Vector3.ZERO
	right_saber_offset_rot = Vector3.ZERO
	if settings_dict.has("right_saber_offset") and settings_dict["right_saber_offset"] is Array:
		@warning_ignore("unsafe_cast")
		var right_array: Array = settings_dict["right_saber_offset"] as Array
		if right_array.size() == 2:
			if right_array[0] is Vector3:
				@warning_ignore("unsafe_cast")
				right_saber_offset_pos = right_array[0] as Vector3
			if right_array[1] is Vector3:
				@warning_ignore("unsafe_cast")
				right_saber_offset_rot = right_array[1] as Vector3
	cube_cuts_falloff = Utils.get_bool(settings_dict, "cube_cuts_falloff", true)
	saber_tail = Utils.get_bool(settings_dict, "saber_tail", true)
	glare = Utils.get_bool(settings_dict, "glare", true)
	show_fps = Utils.get_bool(settings_dict, "show_fps", false)
	bombs_enabled = Utils.get_bool(settings_dict, "bombs_enabled", true)
	events = Utils.get_bool(settings_dict, "events", true)
	disable_map_color = Utils.get_bool(settings_dict, "disable_map_color", false)
	player_height_offset = Utils.get_float(settings_dict, "player_height_offset", 0)

func save() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if not file:
		vr.log_file_error(FileAccess.get_open_error(), CONFIG_PATH, "save() in Settings.gd")
		return
	file.store_float(thickness)
	file.store_float(color_left.r)
	file.store_float(color_left.g)
	file.store_float(color_left.b)
	file.store_float(color_left.a)
	file.store_float(color_right.r)
	file.store_float(color_right.g)
	file.store_float(color_right.b)
	file.store_float(color_right.a)
	file.store_8(saber_visual)
	file.store_float(ui_volume)
	file.store_float(left_saber_offset_pos.x)
	file.store_float(left_saber_offset_pos.y)
	file.store_float(left_saber_offset_pos.z)
	file.store_float(left_saber_offset_rot.x)
	file.store_float(left_saber_offset_rot.y)
	file.store_float(left_saber_offset_rot.z)
	file.store_float(right_saber_offset_pos.x)
	file.store_float(right_saber_offset_pos.y)
	file.store_float(right_saber_offset_pos.z)
	file.store_float(right_saber_offset_rot.x)
	file.store_float(right_saber_offset_rot.y)
	file.store_float(right_saber_offset_rot.z)
	file.store_float(player_height_offset)
	var bools_to_byte := (
		int(cube_cuts_falloff) * 64
		+ int(saber_tail) * 32
		+ int(glare) * 16
		+ int(show_fps) * 8
		+ int(bombs_enabled) * 4
		+ int(events) * 2
		+ int(disable_map_color)
	)
	file.store_8(bools_to_byte)
	file.close()

func restore_defaults() -> void:
	thickness = 100
	cube_cuts_falloff = true
	color_left = Color("ff1a1a")
	color_right = Color("1a1aff")
	saber_tail = true
	glare = true
	show_fps = false
	bombs_enabled = true
	events = true
	saber_visual = 0
	ui_volume = 10.0
	left_saber_offset_pos = Vector3.ZERO
	left_saber_offset_rot = Vector3.ZERO
	right_saber_offset_pos = Vector3.ZERO
	right_saber_offset_rot = Vector3.ZERO
	disable_map_color = false
