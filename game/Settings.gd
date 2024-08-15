extends Node

var config := ConfigFile.new()

const SECTION := "OpenSaber"
const CONFIG_PATH := "user://config.ini"
const OLD_CONFIG_PATH := "user://config.dat"
var SABER_VISUALS: Array[PackedStringArray] = [
	PackedStringArray(["Default saber","res://game/sabers/default/default_saber.tscn"]),
	PackedStringArray(["Particle sword","res://game/sabers/particles/particles_saber.tscn"])
]

var thickness: float:
	set(value):
		thickness = value
		config.set_value(SECTION, "thickness", value)
var color_left: Color:
	set(value):
		color_left = value
		config.set_value(SECTION, "color_left", value)
var color_right: Color:
	set(value):
		color_right = value
		config.set_value(SECTION, "color_right", value)
var saber_visual: int:
	set(value):
		saber_visual = value
		config.set_value(SECTION, "saber_visual", value)
var ui_volume: float:
	set(value):
		ui_volume = value
		config.set_value(SECTION, "ui_volume", value)
var left_saber_offset_pos: Vector3:
	set(value):
		left_saber_offset_pos = value
		config.set_value(SECTION, "left_saber_offset_pos", value)
var left_saber_offset_rot: Vector3:
	set(value):
		left_saber_offset_rot = value
		config.set_value(SECTION, "left_saber_offset_rot", value)
var right_saber_offset_pos: Vector3:
	set(value):
		right_saber_offset_pos = value
		config.set_value(SECTION, "right_saber_offset_pos", value)
var right_saber_offset_rot: Vector3:
	set(value):
		right_saber_offset_rot = value
		config.set_value(SECTION, "right_saber_offset_rot", value)
var cube_cuts_falloff: bool:
	set(value):
		cube_cuts_falloff = value
		config.set_value(SECTION, "cube_cuts_falloff", value)
var saber_tail: bool:
	set(value):
		saber_tail = value
		config.set_value(SECTION, "saber_tail", value)
var glare: bool:
	set(value):
		glare = value
		config.set_value(SECTION, "glare", value)
var show_fps: bool:
	set(value):
		show_fps = value
		config.set_value(SECTION, "show_fps", value)
var bombs_enabled: bool:
	set(value):
		bombs_enabled = value
		config.set_value(SECTION, "bombs_enabled", value)
var events: bool:
	set(value):
		events = value
		config.set_value(SECTION, "events", value)
var disable_map_color: bool:
	set(value):
		disable_map_color = value
		config.set_value(SECTION, "disable_map_color", value)
var player_height_offset: float:
	set(value):
		player_height_offset = value
		config.set_value(SECTION, "player_height_offset", value)

func _ready() -> void:
	if FileAccess.file_exists(OLD_CONFIG_PATH):
		reload()
	else:
		restore_defaults()
		save()

# load() is the name of a built-in function,
# so i went with the next best thing.
func reload() -> void:
	#var file := FileAccess.open(OLD_CONFIG_PATH, FileAccess.READ)
	var config_error := config.load(CONFIG_PATH)
	if config_error != OK:
		if config_error == ERR_FILE_NOT_FOUND:
			load_old_config()
		else:
			vr.log_file_error(config_error, CONFIG_PATH, "reload() in Settings.gd")
		return
	
	var type_checking_holder: Variant = config.get_value(SECTION, "thickness")
	thickness = (type_checking_holder as float) if (type_checking_holder is float) else 100.0
	type_checking_holder = config.get_value(SECTION, "color_left")
	color_left = (type_checking_holder as Color) if (type_checking_holder is Color) else Color("ff1a1a")
	type_checking_holder = config.get_value(SECTION, "color_right")
	color_right = (type_checking_holder as Color) if (type_checking_holder is Color) else Color("1a1aff")
	type_checking_holder = config.get_value(SECTION, "saber_visual")
	saber_visual = (type_checking_holder as int) if (type_checking_holder is int) else 0
	type_checking_holder = config.get_value(SECTION, "ui_volume")
	ui_volume = (type_checking_holder as float) if (type_checking_holder is float) else 10.0
	type_checking_holder = config.get_value(SECTION, "left_saber_offset_pos")
	left_saber_offset_pos = (type_checking_holder as Vector3) if (type_checking_holder is Vector3) else Vector3.ZERO
	type_checking_holder = config.get_value(SECTION, "left_saber_offset_rot")
	left_saber_offset_rot = (type_checking_holder as Vector3) if (type_checking_holder is Vector3) else Vector3.ZERO
	type_checking_holder = config.get_value(SECTION, "right_saber_offset_pos")
	right_saber_offset_pos = (type_checking_holder as Vector3) if (type_checking_holder is Vector3) else Vector3.ZERO
	type_checking_holder = config.get_value(SECTION, "right_saber_offset_rot")
	right_saber_offset_rot = (type_checking_holder as Vector3) if (type_checking_holder is Vector3) else Vector3.ZERO
	type_checking_holder = config.get_value(SECTION, "player_height_offset")
	player_height_offset = (type_checking_holder as float) if (type_checking_holder is float) else 0.0
	type_checking_holder = config.get_value(SECTION, "cube_cuts_falloff")
	cube_cuts_falloff = (type_checking_holder as bool) if (type_checking_holder is bool) else true
	type_checking_holder = config.get_value(SECTION, "saber_tail")
	saber_tail = (type_checking_holder as bool) if (type_checking_holder is bool) else true
	type_checking_holder = config.get_value(SECTION, "glare")
	glare = (type_checking_holder as bool) if (type_checking_holder is bool) else true
	type_checking_holder = config.get_value(SECTION, "show_fps")
	show_fps = (type_checking_holder as bool) if (type_checking_holder is bool) else false
	type_checking_holder = config.get_value(SECTION, "bombs_enabled")
	bombs_enabled = (type_checking_holder as bool) if (type_checking_holder is bool) else true
	type_checking_holder = config.get_value(SECTION, "events")
	events = (type_checking_holder as bool) if (type_checking_holder is bool) else true
	type_checking_holder = config.get_value(SECTION, "disable_map_color")
	disable_map_color = (type_checking_holder as bool) if (type_checking_holder is bool) else false

func load_old_config() -> void:
	var file := FileAccess.open(OLD_CONFIG_PATH, FileAccess.READ)
	if FileAccess.get_open_error() != OK:
		vr.log_file_error(FileAccess.get_open_error(), OLD_CONFIG_PATH, "load_old_config() in Settings.gd")
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
	player_height_offset = Utils.get_float(settings_dict, "player_height_offset", 0.0)

func save() -> void:
	var error := config.save(CONFIG_PATH)
	if error != OK:
		vr.log_file_error(error, CONFIG_PATH, "save() in Settings.gd")
		return
	# remove old config
	if FileAccess.file_exists(OLD_CONFIG_PATH):
		error = DirAccess.open("user://").remove(OLD_CONFIG_PATH)
		if error != OK:
			vr.log_file_error(error, OLD_CONFIG_PATH, "save() in Settings.gd")

func restore_defaults() -> void:
	thickness = 100.0
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
	player_height_offset = 0.0
