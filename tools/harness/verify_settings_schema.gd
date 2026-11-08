extends Node

# UI-3 gate: the settings schema is the single source of truth.
#
#  1. every SCHEMA key is a typed property, and its type matches the default;
#  2. `default_values` mirrors SCHEMA exactly, in the same order (order is behaviour: reload()
#     emits `changed` per key and the panel and live systems react in that order);
#  3. every settings property is in SCHEMA - the table cannot silently miss a key;
#  4. every declared range is sane, contains its default, and `clamp_to_schema` actually clamps;
#  5. writing a key emits `changed` with that key and does not change the stored value.
#
# Run: godot --headless --path . res://tools/harness/verify_settings_schema.tscn
# Exit 0 = the table and the class agree.

# The historical insertion order. Frozen here so a reorder of SCHEMA - which changes the order
# `changed` fires in - fails loudly instead of being a silent behavioural change.
const EXPECTED_ORDER: Array[String] = [
	"thickness", "cube_cuts_falloff", "color_left", "color_right", "saber_tail",
	"show_debug_info", "bombs_enabled", "events", "saber_visual", "ui_volume",
	"left_saber_offset_pos", "left_saber_offset_rot", "right_saber_offset_pos",
	"right_saber_offset_rot", "disable_map_color", "upload_server", "player_height_offset",
	"audio_master", "audio_music", "audio_sfx", "audio_ducking", "audio_analyser", "spectator_view", "spectator_hud",
	"display_refresh_rate", "render_scale", "msaa_3d", "foveation_level", "floor_light",
	"saber_halo", "mirror_reflections", "note_edge_glow", "hit_flash", "note_map_colors",
	"event_tint", "floor_grid", "perf_preset", "sky_style", "debris_cap", "debris_shards",
	"environment_mode", "glow_mode", "hit_sound", "beatsaver_order", "beatsaver_curated",
	"beatsaver_verified", "beatsaver_ranked", "beatsaver_playable_only", "beatsaver_duration",
	"beatsaver_nps", "beatsaver_difficulties", "library_source_filter", "library_card",
	"library_sort_field", "library_sort_desc", "screenshot_trigger", "wall_map_color",
	"hand_tracking_enabled",
]

# Script variables that are not settings.
const NOT_SETTINGS := ["config", "default_values", "SABER_VISUALS"]

var _bad := 0
var _emitted: Array[StringName] = []

func _ready() -> void:
	Settings.changed.connect(_on_changed)

	var schema_keys: Array[String] = []
	for key: String in Settings.SCHEMA:
		schema_keys.append(key)

	if schema_keys != EXPECTED_ORDER:
		_fail("SCHEMA order changed:\n  got %s\n  expected %s" % [str(schema_keys), str(EXPECTED_ORDER)])

	var derived_keys: Array[String] = []
	for key: String in Settings.default_values:
		derived_keys.append(key)
	if derived_keys != schema_keys:
		_fail("default_values does not mirror SCHEMA (%d vs %d keys)" % [derived_keys.size(), schema_keys.size()])

	for key: String in schema_keys:
		_check_key(key)

	# Coverage the other way: a typed property that is not in SCHEMA would load but never be
	# validated, clamped or shown by a schema-driven panel.
	for prop in Settings.get_property_list():
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if prop.name in NOT_SETTINGS:
			continue
		if not Settings.SCHEMA.has(prop.name):
			_fail("property %s is not in SCHEMA" % prop.name)

	# The contract the panel and the live systems actually see on launch: reload() emits once per
	# key, in schema order.
	_emitted.clear()
	Settings.reload()
	var fired: Array[String] = []
	for key: StringName in _emitted:
		fired.append(String(key))
	var expected_n := EXPECTED_ORDER.size()
	if fired.size() < expected_n or fired.slice(0, expected_n) != EXPECTED_ORDER:
		_fail("reload() did not emit the settings pass in schema order:\n  got %s" % str(fired))
	# A config written before perf_preset existed gets the preset applied once *after* the pass
	# (reload() applies it when the key is absent), so those three follow and are not part of it.
	var preset_keys := ["render_scale", "msaa_3d", "foveation_level"]
	for i in range(expected_n, fired.size()):
		if not fired[i] in preset_keys:
			_fail("reload() emitted unexpected %s after the settings pass" % fired[i])

	_check_platform_patch()

	print("VERIFYSCHEMA keys=%d bad=%d" % [schema_keys.size(), _bad])
	get_tree().quit(0 if _bad == 0 else 1)

func _check_key(key: String) -> void:
	var spec: Dictionary = Settings.SCHEMA[key]
	if not spec.has("default"):
		_fail("%s has no default" % key)
		return
	var default: Variant = spec["default"]

	if not (key in Settings):
		_fail("%s is not a property" % key)
		return
	var actual: Variant = Settings.get(key)
	if typeof(actual) != typeof(default):
		_fail("%s is %s but its default is %s" % [key, type_string(typeof(actual)), type_string(typeof(default))])
	if Settings.default_values[key] != default:
		_fail("%s: default_values holds %s, SCHEMA says %s" % [key, str(Settings.default_values[key]), str(default)])

	if spec.has("min") or spec.has("max"):
		_check_range(key, spec, default)

	# The setter contract: a write emits with that key and leaves the value untouched.
	_emitted.clear()
	Settings.set(key, actual)
	if not _emitted.has(StringName(key)):
		_fail("%s did not emit `changed`" % key)
	if Settings.get(key) != actual:
		_fail("%s changed value on a no-op write: %s -> %s" % [key, str(actual), str(Settings.get(key))])

func _check_range(key: String, spec: Dictionary, default: Variant) -> void:
	if not (spec.has("min") and spec.has("max")):
		_fail("%s has only one of min/max" % key)
		return
	var lo: float = spec["min"]
	var hi: float = spec["max"]
	if lo >= hi:
		_fail("%s: min %.4f >= max %.4f" % [key, lo, hi])
	if float(default) < lo or float(default) > hi:
		_fail("%s: default %s outside [%.4f, %.4f]" % [key, str(default), lo, hi])
	if spec.has("step") and float(spec["step"]) <= 0.0:
		_fail("%s: step must be positive" % key)
	if typeof(default) == TYPE_INT and (lo != floor(lo) or hi != floor(hi)):
		_fail("%s is an int but its bounds are fractional" % key)

	var below: Variant = Settings.clamp_to_schema(StringName(key), lo - 1000.0)
	var above: Variant = Settings.clamp_to_schema(StringName(key), hi + 1000.0)
	if float(below) != lo or float(above) != hi:
		_fail("%s: clamp gives %s/%s, expected %.4f/%.4f" % [key, str(below), str(above), lo, hi])
	if typeof(default) == TYPE_INT and (typeof(below) != TYPE_INT or typeof(above) != TYPE_INT):
		_fail("%s: clamping an int key returned a non-int" % key)

func _check_platform_patch() -> void:
	# The Web patch writes into default_values, not SCHEMA. `saber_tail` is false on Web and true
	# everywhere else, so it is the one key that proves which table the loader reads.
	var key := "saber_tail"
	var saved: Variant = Settings.default_values[key]
	Settings.default_values[key] = false
	Settings.config.erase_section_key(Settings.SECTION, key)
	var loaded: Variant = Settings.cast_or_default(key)
	if loaded != false:
		_fail("platform default ignored: a missing %s loaded %s" % [key, str(loaded)])

	# A value equal to its default is stored as null, and ConfigFile drops a null key entirely, so
	# "absent after the write" is the observable proof that the platform default was the one used.
	Settings.set(key, false)
	if Settings.config.has_section_key(Settings.SECTION, key):
		_fail("set_and_emit compared against the shared default, not the platform one")

	Settings.default_values[key] = saved

func _on_changed(key: StringName) -> void:
	_emitted.append(key)

func _fail(message: String) -> void:
	push_error("SCHEMA " + message)
	_bad += 1
