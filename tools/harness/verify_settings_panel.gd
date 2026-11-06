extends Node

# UI-2 gate: instantiate the settings panel and prove every `@onready` reference resolved.
#
# Run: godot --headless --path . res://tools/harness/verify_settings_panel.tscn
# Exit code 0 = no null references, 1 = at least one (the names are printed).
#
# This is a scene rather than a `-s` script because the panel's _ready() uses the Settings and
# UI_AudioEngine autoloads, which a bare SceneTree script does not load.

const PANEL := preload("res://game/settings_Panel.tscn")

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

	print("VERIFYPANEL nulls=%d" % bad)
	panel.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if bad == 0 else 1)
