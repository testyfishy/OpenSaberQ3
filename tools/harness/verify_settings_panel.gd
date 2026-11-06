extends Node

# UI-2 / UI-3 gate: instantiate the settings panel and prove
#  1. every `@onready` reference resolved (no null name lookups), and
#  2. every ranged slider exposes exactly the range Settings.SCHEMA declares, so the panel and the
#     setter cannot disagree about what a value may be.
#
# Run: godot --headless --path . res://tools/harness/verify_settings_panel.tscn
# Exit code 0 = no failures, 1 = at least one (the names are printed).
#
# This is a scene rather than a `-s` script because the panel's _ready() uses the Settings and
# UI_AudioEngine autoloads, which a bare SceneTree script does not load.

const PANEL := preload("res://game/settings_Panel.tscn")

# Slider node -> settings key. `thickness` is the one setting whose slider has another name.
const SLIDERS := {
	"saber_thickness": "thickness",
	"ui_volume_slider": "ui_volume",
	"render_scale": "render_scale",
	"master_slider": "audio_master",
	"sfx_slider": "audio_sfx",
	"music_slider": "audio_music",
}

func _ready() -> void:
	var panel := PANEL.instantiate()
	add_child(panel)
	for i in 4:
		await get_tree().process_frame

	# Variables that are allowed to be null at this point (set later by gameplay code).
	var allow := {
		"beepsaber_game": true,
	}

	var bad := 0
	for prop in panel.get_property_list():
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if prop.type != TYPE_OBJECT:
			continue
		if allow.has(prop.name):
			continue
		if panel.get(prop.name) == null:
			push_error("VERIFY null reference: %s" % prop.name)
			bad += 1

	var range_bad := 0
	var ranges := 0
	for node_name: String in SLIDERS:
		var slider := panel.get_node_or_null("%" + node_name) as Range
		if slider == null:
			push_error("VERIFY slider missing: %s" % node_name)
			range_bad += 1
			continue
		var spec: Dictionary = Settings.SCHEMA.get(SLIDERS[node_name], {})
		if not spec.has("min"):
			continue
		if not is_equal_approx(slider.min_value, float(spec["min"])) \
				or not is_equal_approx(slider.max_value, float(spec["max"])):
			push_error("VERIFY range %s: panel %.4f..%.4f, schema %.4f..%.4f" % [
				node_name, slider.min_value, slider.max_value, spec["min"], spec["max"]])
			range_bad += 1
		elif spec.has("step") and not is_equal_approx(slider.step, float(spec["step"])):
			push_error("VERIFY step %s: panel %.4f, schema %.4f" % [node_name, slider.step, spec["step"]])
			range_bad += 1
		else:
			ranges += 1

	var failures := bad + range_bad
	print("VERIFYPANEL nulls=%d range_bad=%d ranges=%d" % [bad, range_bad, ranges])
	panel.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)
