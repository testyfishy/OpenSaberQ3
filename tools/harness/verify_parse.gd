extends Node

# Parse gate. `godot --headless --path . --quit` only compiles what the main scene reaches, so a
# broken script that nothing loads (a stale test, a harness for a deleted scene) stays invisible
# until the export log. This loads every .gd in the project with the autoloads present.
#
# Run: godot --headless --path . res://tools/harness/verify_parse.tscn
# Prints `PARSECHECK files=<n> bad=<m>` and exits non-zero when any script fails to compile.

const SKIP_DIRS: Array[String] = ["res://.godot", "res://android", "res://.git"]


func _ready() -> void:
	var files: Array[String] = []
	_collect("res://", files)
	files.sort()
	var bad: Array[String] = []
	for path in files:
		var script := ResourceLoader.load(path) as Script
		if script == null or not script.can_instantiate():
			# An abstract or static-only script is valid but not instantiable; reload() tells
			# the two apart.
			if script != null and script.reload(true) == OK:
				continue
			bad.append(path)
	for path in bad:
		print("PARSECHECK bad ", path)
	print("PARSECHECK files=%d bad=%d" % [files.size(), bad.size()])
	get_tree().quit(0 if bad.is_empty() else 1)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.include_hidden = false
	for sub in dir.get_directories():
		var child := dir_path.path_join(sub)
		if child in SKIP_DIRS:
			continue
		_collect(child, out)
	for file in dir.get_files():
		if file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
