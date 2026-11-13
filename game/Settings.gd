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
		value = clamp_to_schema(&"thickness", value)
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
		value = clamp_to_schema(&"ui_volume", value)
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
var wall_map_color: bool:
	set(value):
		wall_map_color = value
		set_and_emit(&"wall_map_color", value)
# Labs (settings panel): off by default since 0.7.22. Off keeps the controllers in charge even
# when the headset reports tracked hands.
var hand_tracking_enabled: bool:
	set(value):
		hand_tracking_enabled = value
		set_and_emit(&"hand_tracking_enabled", value)
# Beat Saber's hit rules: a cut against the arrow, or slower than 2 m/s, is a bad cut. Off keeps
# this fork's older behaviour, where any contact with the right saber counts as a hit.
var strict_cuts: bool:
	set(value):
		strict_cuts = value
		set_and_emit(&"strict_cuts", value)
# On: the energy bar is not enforced and a song always plays to the end. Off: energy reaching
# zero ends the song as a fail, and nothing is saved for it.
var no_fail: bool:
	set(value):
		no_fail = value
		set_and_emit(&"no_fail", value)
# How fast notes approach, as a percentage of the map's own note jump speed. 100 is what the
# mapper set. Lower values slow the approach without changing when a note has to be hit, so the
# song, the timing and the score are unaffected; notes simply appear closer and arrive slower.
var note_speed_percent: int:
	set(value):
		value = clamp_to_schema(&"note_speed_percent", value)
		note_speed_percent = value
		set_and_emit(&"note_speed_percent", value)
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
		value = clamp_to_schema(&"player_height_offset", value)
		player_height_offset = value
		set_and_emit(&"player_height_offset", value)
var audio_master: float:
	set(value):
		value = clamp_to_schema(&"audio_master", value)
		audio_master = value
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"Master"), linear_to_db(value))
		set_and_emit(&"audio_master", value)
var audio_music: float:
	set(value):
		value = clamp_to_schema(&"audio_music", value)
		audio_music = value
		set_and_emit(&"audio_music", value)
var audio_sfx: float:
	set(value):
		value = clamp_to_schema(&"audio_sfx", value)
		audio_sfx = value
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"SFX"), linear_to_db(value))
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"UI"), linear_to_db(value))
		set_and_emit(&"audio_sfx", value)
# Music is written by HitAudio's ducker, which owns the Music bus; this key only carries the
# player's level so the ducker has one base to add its envelope to.
var audio_ducking: bool:
	set(value):
		audio_ducking = value
		set_and_emit(&"audio_ducking", value)
var audio_analyser: bool:
	set(value):
		audio_analyser = value
		set_and_emit(&"audio_analyser", value)
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
		value = clamp_to_schema(&"render_scale", value)
		render_scale = value
		set_and_emit(&"render_scale", value)
var msaa_3d: int:
	set(value):
		value = clamp_to_schema(&"msaa_3d", value)
		msaa_3d = value
		set_and_emit(&"msaa_3d", value)
var foveation_level: int:
	set(value):
		value = clamp_to_schema(&"foveation_level", value)
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
		# msaa / foveation values on every load, because reload() sets every key in one pass.
		# (schema order). The panel applies it when the player picks one,
		# and restore_defaults() applies it once on a fresh install.
		value = clamp_to_schema(&"perf_preset", value)
		perf_preset = value
		set_and_emit(&"perf_preset", value)

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
		value = clamp_to_schema(&"sky_style", value)
		sky_style = value
		set_and_emit(&"sky_style", value)
var debris_cap: bool:
	set(value):
		debris_cap = value
		set_and_emit(&"debris_cap", value)
# Cut shards (spec FR-013): the shader-driven debris pool. On by default - it is one draw call
# and it is the only debris that exists on the headset, since the old per-cube GPU particles
# were freed on Android.
var debris_shards: bool:
	set(value):
		debris_shards = value
		set_and_emit(&"debris_shards", value)
# FR-027: 0 = the map's environment scheme (default), 1 = Classic (the pre-v0.3 look).
# Glow (measured free on device: ~1% GPU, ~0.15 ms app). 0 off, 1 subtle (one blur level),
# 2 full (Godot's default chain). Subtle is the default because it reads as glow without the
# multi-level chain.
# 0 = Classic (shipped v0.3 impacts), 1 = Thump (low-heavy re-derivation). Both sets ship.
var hit_sound: int:
	set(value):
		value = clamp_to_schema(&"hit_sound", value)
		hit_sound = value
		set_and_emit(&"hit_sound", value)
var glow_mode: int:
	set(value):
		value = clamp_to_schema(&"glow_mode", value)
		glow_mode = value
		set_and_emit(&"glow_mode", value)
var environment_mode: int:
	set(value):
		value = clamp_to_schema(&"environment_mode", value)
		environment_mode = value
		set_and_emit(&"environment_mode", value)

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
# Library source filter (specs/020 FR-002): the selected source, "all" for unfiltered.
var library_source_filter: String:
	set(value):
		library_source_filter = value
		set_and_emit(&"library_source_filter", value)
# Cards view sort/selection (specs/029 FR-006): the card key and sort survive launches.
var library_card: String:
	set(value):
		library_card = value
		set_and_emit(&"library_card", value)
var library_sort_field: String:
	set(value):
		library_sort_field = value
		set_and_emit(&"library_sort_field", value)
var library_sort_desc: bool:
	set(value):
		library_sort_desc = value
		set_and_emit(&"library_sort_desc", value)
# Both triggers held for 0.5 s takes a screenshot (specs/024 FR-005/FR-013). Off leaves the
# pause button/F12.
var screenshot_trigger: bool:
	set(value):
		screenshot_trigger = value
		set_and_emit(&"screenshot_trigger", value)
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

# --- Schema -------------------------------------------------------------------------------
# The single source of truth for every persisted setting: the key, its default and, where the
# value has a domain, the range the panel exposes and a hand-edited config.ini is clamped into.
# Insertion order is behaviour: reload() walks `default_values` (derived from this, same order)
# and emits `changed` per key, so the panel and the live systems react in that order.
# A key without min/max is free-form: a string, a colour, or a rate the runtime chooses.
const SCHEMA := {
	"thickness": {"default": 1.0, "min": 0.1, "max": 1.0, "step": 0.01},
	"cube_cuts_falloff": {"default": true},
	"color_left": {"default": Color("ff1a1a")},
	"color_right": {"default": Color("1a1aff")},
	"saber_tail": {"default": true},
	"show_debug_info": {"default": false},
	"bombs_enabled": {"default": true},
	"events": {"default": true},
	"saber_visual": {"default": 0},
	"ui_volume": {"default": 10.0, "min": 0.0, "max": 10.0, "step": 1.0},
	"left_saber_offset_pos": {"default": Vector3.ZERO},
	"left_saber_offset_rot": {"default": Vector3.ZERO},
	"right_saber_offset_pos": {"default": Vector3.ZERO},
	"right_saber_offset_rot": {"default": Vector3.ZERO},
	"disable_map_color": {"default": false},
	"upload_server": {"default": true},
	"player_height_offset": {"default": 0.0, "min": -0.25, "max": 0.25, "step": 0.05},
	"audio_master": {"default": 0.8, "min": 0.0, "max": 1.0, "step": 0.01},
	"audio_music": {"default": 0.8, "min": 0.0, "max": 1.0, "step": 0.01},
	"audio_sfx": {"default": 0.8, "min": 0.0, "max": 1.0, "step": 0.01},
	"audio_ducking": {"default": true},
	"audio_analyser": {"default": false},
	"spectator_view": {"default": false},
	"spectator_hud": {"default": true},
	"display_refresh_rate": {"default": 120.0},
	"render_scale": {"default": 1.2546, "min": 0.7, "max": 1.5, "step": 0.0001},
	"msaa_3d": {"default": 2, "min": 0, "max": 2, "step": 1},
	"foveation_level": {"default": 0, "min": 0, "max": 2, "step": 1},
	"floor_light": {"default": true},
	"saber_halo": {"default": true},
	"mirror_reflections": {"default": false},
	"note_edge_glow": {"default": true},
	"hit_flash": {"default": true},
	"note_map_colors": {"default": true},
	"event_tint": {"default": true},
	"floor_grid": {"default": true},
	"perf_preset": {"default": 2, "min": 0, "max": 2, "step": 1},
	"sky_style": {"default": 0, "min": 0, "max": 2, "step": 1},
	"debris_cap": {"default": false},
	"debris_shards": {"default": true},
	"environment_mode": {"default": 0, "min": 0, "max": 1, "step": 1},
	"glow_mode": {"default": 1, "min": 0, "max": 2, "step": 1},
	"hit_sound": {"default": 0, "min": 0, "max": 1, "step": 1},
	"beatsaver_order": {"default": "Latest"},
	"beatsaver_curated": {"default": false},
	"beatsaver_verified": {"default": false},
	"beatsaver_ranked": {"default": false},
	"beatsaver_playable_only": {"default": false},
	"beatsaver_duration": {"default": 0},
	"beatsaver_nps": {"default": 0},
	"beatsaver_difficulties": {"default": ""},
	"library_source_filter": {"default": "all"},
	"library_card": {"default": "all"},
	"library_sort_field": {"default": "name"},
	"library_sort_desc": {"default": false},
	"screenshot_trigger": {"default": true},
	"wall_map_color": {"default": true},
	"hand_tracking_enabled": {"default": false},
	"strict_cuts": {"default": true},
	"no_fail": {"default": true},
	"note_speed_percent": {"default": 100, "min": 50, "max": 100, "step": 5},
}

# Derived view for the loader, the panel and the tests. The platform patch in _ready() writes
# into this dictionary, never into SCHEMA, so it must be the dictionary the loader reads: a
# missing key on Web has to fall back to the Web default, not the shared one.
var default_values: Dictionary = _derive_defaults()

static func _derive_defaults() -> Dictionary:
	var out := {}
	for key: String in SCHEMA:
		out[key] = SCHEMA[key]["default"]
	return out

# Clamp into the schema's domain. Called on load, so a hand-edited ini cannot store a value
# the panel could never produce, and by every ranged setter, so the table and the setters
# cannot drift apart.
static func clamp_to_schema(key: StringName, value: Variant) -> Variant:
	var spec: Dictionary = SCHEMA.get(String(key), {})
	if spec.is_empty() or not (value is float or value is int):
		return value
	var lo: Variant = spec.get("min")
	var hi: Variant = spec.get("max")
	if lo != null and float(value) < float(lo):
		value = lo
	if hi != null and float(value) > float(hi):
		value = hi
	return value

# The default a missing key loads as. Reads default_values so the platform patch and the
# Web overrides still apply; SCHEMA only supplies the fallback for a key outside the table.
func _default(key: String) -> Variant:
	if key in default_values:
		return default_values[key]
	return SCHEMA[key]["default"] if key in SCHEMA else null

func cast_or_default(key: String, to_type: int = -1) -> Variant:
	var default: Variant = _default(key)
	var raw: Variant = convert(config.get_value(SECTION, key, default), typeof(default) if to_type < 0 else to_type)
	return clamp_to_schema(StringName(key), raw)

func set_and_emit(key: StringName, value: Variant) -> void:
	# Defaults are stored as null, not written, so a later build that changes a default is not
	# pinned by an old config file.
	var default: Variant = _default(String(key))
	config.set_value(SECTION, String(key), value if default != value else null)
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
	# 0.7.6: back to 120 Hz as the default after the owner's test; 90 remains in Settings. Move
	# the previous 90 default once, and keep a deliberate later choice because the marker is
	# written once.
	if not config.has_section_key(SECTION, "refresh_default_120"):
		display_refresh_rate = 120.0
		config.set_value(SECTION, "display_refresh_rate", 120.0)
		config.set_value(SECTION, "refresh_default_120", true)
		save()

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


