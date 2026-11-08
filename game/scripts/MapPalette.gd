extends RefCounted
class_name MapPalette

# The map's colour rules (specs/013 FR-007, second Map split).
#
# One place decides note, room and wall colours: the environment profile, the Classic override,
# the map/difficulty custom data, and the readability guards. Map.gd keeps the loader and calls
# `set_colors_from_custom_data()`; everything else reads these values directly.
#
# Static state, like Map: explicit reset() because it survives scene changes.

static var color_left: Color
static var color_right: Color
static var env_left: Color
static var env_right: Color
static var env_left_boost: Color
static var env_right_boost: Color
static var wall_color: Color
static var boost_active := false
static var environment_name := ""

static func reset() -> void:
	color_left = Color()
	color_right = Color()
	env_left = Color()
	env_right = Color()
	env_left_boost = Color()
	env_right_boost = Color()
	wall_color = Color()
	boost_active = false
	environment_name = ""

static func _read_colour(data: Dictionary, key: String, fallback: Color) -> Color:
	if data.has(key) and data[key] is Dictionary:
		@warning_ignore("unsafe_cast")
		var d := data[key] as Dictionary
		return Color(
			Utils.get_float(d, "r", fallback.r),
			Utils.get_float(d, "g", fallback.g),
			Utils.get_float(d, "b", fallback.b)
		)
	return fallback

# `info` and `difficulty` are passed in rather than read from Map, so this class has no dependency
# on the loader it was split out of.
static func set_colors_from_custom_data(info: MapInfo, difficulty: DifficultyInfo) -> void:
	reset()
	environment_name = info.environment_name if info != null else ""
	var profile := EnvironmentProfiles.get_profile(environment_name)
	var classic := Settings.environment_mode == 1
	color_left = Settings.color_left if classic else profile.note_left
	color_right = Settings.color_right if classic else profile.note_right
	env_left = Settings.color_left if classic else profile.env_left
	env_right = Settings.color_right if classic else profile.env_right
	env_left_boost = Settings.color_left if classic else profile.boost_left
	env_right_boost = Settings.color_right if classic else profile.boost_right
	# Walls stay the classic red unless the map authors an obstacle colour: the per-environment
	# tints (green, purple) read as black over a dark room and the owner asked for the red look.
	wall_color = EnvironmentProfiles.DEFAULT.wall
	if Settings.disable_map_color:
		return

	var info_data := info.custom_data if info != null else {}
	var diff_data := difficulty.custom_data if difficulty != null else {}
	color_left = _read_colour(diff_data, "_colorLeft", _read_colour(info_data, "_colorLeft", color_left))
	color_right = _read_colour(diff_data, "_colorRight", _read_colour(info_data, "_colorRight", color_right))
	env_left = _read_colour(diff_data, "_envColorLeft", _read_colour(info_data, "_envColorLeft", env_left))
	env_right = _read_colour(diff_data, "_envColorRight", _read_colour(info_data, "_envColorRight", env_right))
	env_left_boost = _read_colour(diff_data, "_envColorLeftBoost", _read_colour(info_data, "_envColorLeftBoost", env_left_boost))
	env_right_boost = _read_colour(diff_data, "_envColorRightBoost", _read_colour(info_data, "_envColorRightBoost", env_right_boost))
	# Respect the creator's authored obstacle colour; the menu toggle can force classic red.
	if Settings.wall_map_color:
		wall_color = _read_colour(diff_data, "_obstacleColor", _read_colour(info_data, "_obstacleColor", wall_color))

	# Readability guards (FR-028): the room stays below 0.6x the note brightness, and a palette
	# whose two hues are nearly the same (or nearly grey) falls back to the environment default.
	var guard := func(env: Color, note: Color, fallback: Color) -> Color:
		if absf(env.h - note.h) < 0.0834 or env.s < 0.25:
			return fallback
		return env.darkened(maxf(0.0, env.v - note.v * 0.6))
	env_left = guard.call(env_left, color_left, profile.env_left)
	env_right = guard.call(env_right, color_right, profile.env_right)
