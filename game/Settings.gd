extends Node

var config := ConfigFile.new()

const SECTION := "OpenSaber"
const CONFIG_PATH := "user://config.ini"
const OLD_CONFIG_PATH := "user://config.dat"
var SABER_VISUALS: Array[PackedStringArray] = [
	PackedStringArray(["Default saber","res://game/sabers/default/default_saber.tscn"]),
	PackedStringArray(["Particle sword","res://game/sabers/particles/particles_saber.tscn"])
]

signal changed(name: StringName)

var thickness: float:
	set(value):
		thickness = value
		set_and_emit(&"thickness", value)
var color_left: Color:
	set(value):
		color_left = value
		set_and_emit(&"color_left", value)
var color_right: Color:
	set(value):
		color_right = value
		set_and_emit(&"color_right", value)
var saber_visual: int:
	set(value):
		saber_visual = value
		set_and_emit(&"saber_visual", value)
var ui_volume: float:
	set(value):
		ui_volume = value
		set_and_emit(&"ui_volume", value)
var left_saber_offset_pos: Vector3:
	set(value):
		left_saber_offset_pos = value
		set_and_emit(&"left_saber_offset_pos", value)
var left_saber_offset_rot: Vector3:
	set(value):
		left_saber_offset_rot = value
		set_and_emit(&"left_saber_offset_rot", value)
var right_saber_offset_pos: Vector3:
	set(value):
		right_saber_offset_pos = value
		set_and_emit(&"right_saber_offset_pos", value)
var right_saber_offset_rot: Vector3:
	set(value):
		right_saber_offset_rot = value
		set_and_emit(&"right_saber_offset_rot", value)
var cube_cuts_falloff: bool:
	set(value):
		cube_cuts_falloff = value
		set_and_emit(&"cube_cuts_falloff", value)
var saber_tail: bool:
	set(value):
		saber_tail = value
		set_and_emit(&"saber_tail", value)
var show_debug_info: bool:
	set(value):
		show_debug_info = value
		set_and_emit(&"show_debug_info", value)
var bombs_enabled: bool:
	set(value):
		bombs_enabled = value
		set_and_emit(&"bombs_enabled", value)
var events: bool:
	set(value):
		events = value
		set_and_emit(&"events", value)
var disable_map_color: bool:
	set(value):
		disable_map_color = value
		set_and_emit(&"disable_map_color", value)
# The local upload page: a small HTTP server on the LAN that accepts a map zip from a PC
# browser. Off means the port is not opened at all, which is what a player on a shared or
# untrusted network wants. Default on because it is the only way to sideload a map without
# using the in-game browser.
var upload_server: bool:
	set(value):
		upload_server = value
		set_and_emit(&"upload_server", value)
var player_height_offset: float:
	set(value):
		player_height_offset = value
		set_and_emit(&"player_height_offset", value)
var audio_master: float:
	set(value):
		audio_master = value
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"Master"), linear_to_db(value))
		set_and_emit(&"audio_master", value)
var audio_music: float:
	set(value):
		audio_music = value
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"Music"), linear_to_db(value))
		set_and_emit(&"audio_music", value)
var audio_sfx: float:
	set(value):
		audio_sfx = value
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"SFX"), linear_to_db(value))
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"UI"), linear_to_db(value))
		set_and_emit(&"audio_sfx", value)
var spectator_view: bool:
	set(value):
		spectator_view = value
		set_and_emit(&"spectator_view", value)
var spectator_hud: bool:
	set(value):
		spectator_hud = value
		set_and_emit(&"spectator_hud", value)

# --- Performance settings (FR-040). These are applied by BeepSaber_Game, not here: the XR
# session does not exist yet while Settings loads. Defaults match the tuned project values so an
# untouched install behaves exactly as before.
var display_refresh_rate: float:
	set(value):
		display_refresh_rate = value
		set_and_emit(&"display_refresh_rate", value)
var render_scale: float:
	set(value):
		render_scale = value
		set_and_emit(&"render_scale", value)
var msaa_3d: int:
	set(value):
		msaa_3d = value
		set_and_emit(&"msaa_3d", value)
var foveation_level: int:
	set(value):
		foveation_level = value
		set_and_emit(&"foveation_level", value)

# --- Visual additions (FR-045..FR-048). Each is switchable because FR-049 gates every one
# of them on measurement rather than on intent: the defaults are the state the user asked to
# judge first, and the panel is the A/B switch.
var floor_light: bool:
	set(value):
		floor_light = value
		set_and_emit(&"floor_light", value)
var saber_halo: bool:
	set(value):
		saber_halo = value
		set_and_emit(&"saber_halo", value)
var mirror_reflections: bool:
	set(value):
		mirror_reflections = value
		set_and_emit(&"mirror_reflections", value)

# --- Round 2 visual work (specs/007-visual-options FR-001..FR-010). Same rule as above:
# every addition is a switch. The first five cost extra maths inside a pass that already
# runs, so they ship on; the last three add draws or overdraw, so they ship off and wait
# for a measurement (FR-049).
#
# `note_halo` is gone on purpose: the note glow is EMISSION inside BeepCube.gdshader now
# (FR-001), so the shell mesh, its material and this key had nothing left to switch. An
# old config.ini that still contains note_halo is simply ignored - reload() only ever
# reads keys that are in `default_values`.
var note_edge_glow: bool:
	set(value):
		note_edge_glow = value
		set_and_emit(&"note_edge_glow", value)
var hit_flash: bool:
	set(value):
		hit_flash = value
		set_and_emit(&"hit_flash", value)
var note_map_colors: bool:
	set(value):
		note_map_colors = value
		set_and_emit(&"note_map_colors", value)
var event_tint: bool:
	set(value):
		event_tint = value
		set_and_emit(&"event_tint", value)
var floor_grid: bool:
	set(value):
		floor_grid = value
		set_and_emit(&"floor_grid", value)
# Performance preset: one switch that sets the three GPU levers together, because they are
# measured as a group and their individual names mean nothing to a player.
#   0 Quality     - native supersampled render target, 4x MSAA, no foveation  (GPU ~86%)
#   1 Balanced    - 1.1x render target, 4x MSAA, foveation 1                   (GPU ~75%)
#   2 Performance - runtime-recommended render target, 2x MSAA, foveation 2    (GPU ~64%)
# Default is Performance: the player's stated priority is a rock-solid 120 Hz with headroom,
# and this is the only configuration measured with zero dropped frames and ~3 ms of GPU slack.
var perf_preset: int:
	set(value):
		# Stores the choice only. Applying it here would clobber the individual render_scale /
		# msaa / foveation values on every load, because reload() sets every key in
		# default_values in arbitrary order. The panel applies it when the player picks one,
		# and restore_defaults() applies it once on a fresh install.
		perf_preset = clampi(value, 0, 2)
		set_and_emit(&"perf_preset", perf_preset)

func _apply_perf_preset(preset: int) -> void:
	match preset:
		0:
			render_scale = 1.2546
			msaa_3d = 2
			foveation_level = 0
		1:
			render_scale = 1.1
			msaa_3d = 2
			foveation_level = 1
		_:
			render_scale = 1.0
			msaa_3d = 1
			foveation_level = 2
# 0 = black void, 1 = gradient sky, 2 = the original panorama. Void is the shipped default:
# the panorama was the most visible piece of unfinished art, and a black background is also
# cheaper to draw than a full-screen textured sky.
var sky_style: int:
	set(value):
		sky_style = clampi(value, 0, 2)
		set_and_emit(&"sky_style", sky_style)
var debris_cap: bool:
	set(value):
		debris_cap = value
		set_and_emit(&"debris_cap", value)

# --- BeatSaver browser state (specs/005-beatsaver-browser, FR-011). Only the sort and the filter
# set are remembered; the search text and the current page are deliberately not.
var beatsaver_order: String:
	set(value):
		beatsaver_order = value
		set_and_emit(&"beatsaver_order", value)
var beatsaver_curated: bool:
	set(value):
		beatsaver_curated = value
		set_and_emit(&"beatsaver_curated", value)
var beatsaver_verified: bool:
	set(value):
		beatsaver_verified = value
		set_and_emit(&"beatsaver_verified", value)
var beatsaver_ranked: bool:
	set(value):
		beatsaver_ranked = value
		set_and_emit(&"beatsaver_ranked", value)
var beatsaver_playable_only: bool:
	set(value):
		beatsaver_playable_only = value
		set_and_emit(&"beatsaver_playable_only", value)
var beatsaver_duration: int:
	set(value):
		beatsaver_duration = value
		set_and_emit(&"beatsaver_duration", value)
var beatsaver_nps: int:
	set(value):
		beatsaver_nps = value
		set_and_emit(&"beatsaver_nps", value)
var beatsaver_difficulties: String:
	set(value):
		beatsaver_difficulties = value
		set_and_emit(&"beatsaver_difficulties", value)



func _ready() -> void:
	if OS.get_name() in platform_default_values.keys():
		for key in platform_default_values[OS.get_name()].keys():
			default_values[key] = platform_default_values[OS.get_name()][key]
	
	if FileAccess.file_exists(CONFIG_PATH):
		reload()
	elif FileAccess.file_exists(OLD_CONFIG_PATH):
		load_old_config()
	else:
		restore_defaults()
		save()

const platform_default_values = {
	Web = {
		saber_tail = false,
		cube_cuts_falloff = false,
		events = false,
	},
}

var default_values = {
	thickness = 1.0,
	cube_cuts_falloff = true,
	color_left = Color("ff1a1a"),
	color_right = Color("1a1aff"),
	saber_tail = true,
	show_debug_info = false,
	bombs_enabled = true,
	events = true,
	saber_visual = 0,
	ui_volume = 10.0,
	left_saber_offset_pos = Vector3.ZERO,
	left_saber_offset_rot = Vector3.ZERO,
	right_saber_offset_pos = Vector3.ZERO,
	right_saber_offset_rot = Vector3.ZERO,
	disable_map_color = false,
	upload_server = true,
	player_height_offset = 0.0,
	audio_master = 0.8,
	audio_music = 0.8,
	audio_sfx = 0.8,
	spectator_view = false,
	spectator_hud = true,
	# Performance (FR-040). render_scale 1.2546 is the Quest 3 tuning (per-eye >= native);
	# other headsets can lower it from the settings panel.
	display_refresh_rate = 120.0,
	render_scale = 1.2546,
	msaa_3d = 2,
	foveation_level = 0,
	# Visual (FR-045..FR-047). 1 and 2 on, 3 and 4 off: the user judges those two visually.
	floor_light = true,
	saber_halo = true,
	mirror_reflections = false,
	# Round 2 (specs/007-visual-options), revised in v0.3 (specs/009): the background is an
	# explicit choice now - Black void (0, default), Gradient (1), Panorama (2). The plain
	# gradient shipped off in 007 because it replaced the art; the player has since asked for
	# a black void instead of the art, so void became the default and the art became option 2.
	note_edge_glow = true,
	hit_flash = true,
	note_map_colors = true,
	event_tint = true,
	floor_grid = true,
	perf_preset = 2,
	sky_style = 0,
	debris_cap = false,
	beatsaver_order = "Latest",
	beatsaver_curated = false,
	beatsaver_verified = false,
	beatsaver_ranked = false,
	beatsaver_playable_only = false,
	beatsaver_duration = 0,
	beatsaver_nps = 0,
	beatsaver_difficulties = ""
}

func cast_or_default(key: String, to_type: int = -1) -> Variant:
	var default = default_values[key] if key in default_values else null
	return convert(config.get_value(SECTION, key, default), typeof(default) if to_type < 0 else to_type)

func set_and_emit(key: StringName, value: Variant) -> void:
	config.set_value(SECTION, String(key), value if default_values[key] != value else null)
	changed.emit(key)

# load() is the name of a built-in function,
# so i went with the next best thing.
func reload() -> void:
	var config_error := config.load(CONFIG_PATH)
	if config_error != OK:
		vr.log_file_error(config_error, CONFIG_PATH, "reload() in Settings.gd")
		return
	
	# A config written before the preset existed has no key for it. Apply the preset once, then
	# always persist the key so a later launch cannot clobber individually tweaked settings.
	var had_preset := config.has_section_key(SECTION, "perf_preset")
	for key in default_values:
		set(key, cast_or_default(key))
	config.set_value(SECTION, "perf_preset", perf_preset)
	if not had_preset:
		_apply_perf_preset(perf_preset)

func load_old_config() -> void:
	var file := FileAccess.open(OLD_CONFIG_PATH, FileAccess.READ)
	if FileAccess.get_open_error() != OK:
		vr.log_file_error(FileAccess.get_open_error(), OLD_CONFIG_PATH, "load_old_config() in Settings.gd")
		return
	var settings_var: Variant = file.get_var(true)
	file.close()
	if not settings_var is Dictionary:
		restore_defaults()
		return
	var settings_dict := settings_var as Dictionary
	thickness = Utils.get_float(settings_dict, "thickness", 1)
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
	cube_cuts_falloff = Utils.get_bool(settings_dict, "cube_cuts_falloff", true, {"Web": false})
	saber_tail = Utils.get_bool(settings_dict, "saber_tail", true, {"Web": false})
	show_debug_info = Utils.get_bool(settings_dict, "show_debug_info", false)
	bombs_enabled = Utils.get_bool(settings_dict, "bombs_enabled", true)
	events = Utils.get_bool(settings_dict, "events", true, {"Web": false})
	disable_map_color = Utils.get_bool(settings_dict, "disable_map_color", false)
	upload_server = Utils.get_bool(settings_dict, "upload_server", true)
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
	config.clear()
	save()
	reload()


