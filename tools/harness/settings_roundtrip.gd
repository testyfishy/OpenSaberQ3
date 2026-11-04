extends Node

# Settings round-trip harness (v0.4 gate FR-003/SC-003).
#
# Proves that a config written by the current build reads back identically, that a v0.3-era file
# with unknown keys still loads without losing the known ones, and that a missing key falls back
# to its declared default. Run: godot --headless --path . res://tools/harness/settings_roundtrip.tscn

func _ready() -> void:
	var ok := true

	# 1. Defaults -> save -> reload -> same values.
	Settings.restore_defaults()
	var first := _dump()
	Settings.reload()
	var second := _dump()
	if first != second:
		ok = false
		print("ROUNDTRIP FAIL: reload changed values")
		for key: String in first:
			if first[key] != second.get(key):
				print("  %s: %s -> %s" % [key, str(first[key]), str(second.get(key))])
	else:
		print("ROUNDTRIP defaults ok (%d keys)" % first.size())

	# 2. An old file: known key, unknown key, missing key.
	var old := ConfigFile.new()
	old.set_value("OpenSaber", "audio_music", 0.42)
	old.set_value("OpenSaber", "some_removed_key", "legacy")
	var err := old.save(Settings.CONFIG_PATH)
	if err != OK:
		ok = false
		print("ROUNDTRIP FAIL: could not write the legacy config")
	else:
		Settings.reload()
		if absf(Settings.audio_music - 0.42) > 0.001:
			ok = false
			print("ROUNDTRIP FAIL: known key not read (%s)" % str(Settings.audio_music))
		if Settings.audio_master != Settings.default_values["audio_master"]:
			ok = false
			print("ROUNDTRIP FAIL: missing key did not fall back to its default")
		if not ok:
			print("ROUNDTRIP legacy-config check failed")
		else:
			print("ROUNDTRIP legacy config ok")

	# Leave the machine on clean defaults, not on the synthetic legacy file.
	Settings.restore_defaults()
	print("SETTINGSTEST ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)


func _dump() -> Dictionary:
	var out := {}
	for key: String in Settings.default_values:
		out[key] = str(Settings.get(key))
	return out
