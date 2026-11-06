extends Node

# UI-3 gate: every settings key must be a real property, and writing it must emit `changed`
# with that key. That is the contract the future data-driven schema has to preserve, and it is
# the failure mode a mechanical schema rewrite is most likely to introduce (a key that loads
# but never notifies, so the panel and the live systems silently disagree).
#
# Run: godot --headless --path . res://tools/harness/verify_settings_schema.tscn
# Exit 0 = all keys conform.

func _ready() -> void:
	var bad := 0
	var seen := {}
	var emitted: Array[StringName] = []
	Settings.changed.connect(func(key: StringName) -> void: emitted.append(key))

	for key: String in Settings.default_values:
		if not (key in Settings):
			push_error("SCHEMA missing property: %s" % key)
			bad += 1
			continue
		# Write the current value back: a no-op write still has to emit, because callers update
		# the stored value before emitting in some paths.
		var before: Variant = Settings.get(key)
		emitted.clear()
		Settings.set(key, before)
		if not emitted.has(StringName(key)):
			push_error("SCHEMA no `changed` emitted for %s" % key)
			bad += 1
		seen[key] = true

	print("VERIFYSCHEMA keys=%d bad=%d" % [seen.size(), bad])
	get_tree().quit(0 if bad == 0 else 1)
