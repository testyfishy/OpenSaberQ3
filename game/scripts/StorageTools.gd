extends RefCounted
class_name StorageTools

## Size, source and safe-delete helpers for the Storage panel (specs/026).
##
## The safety rule is the important part: a map delete only ever removes a **direct child** of
## `user://OpenSaber/Songs/`. An empty, relative or `..` path is refused, so a bad MapInfo can
## never turn a recursive delete into a wipe of the library root.

const SOURCE_ALL := "all"

static func songs_root() -> String:
	return Constants.APPDATA_PATH + "Songs/"

## True only for a direct child folder of Songs/ (not Songs/ itself, no traversal).
static func is_safe_map_path(path: String) -> bool:
	if path.strip_edges().is_empty():
		return false
	var raw := path.replace("\\", "/")
	if raw.contains(".."):
		return false
	var root := songs_root().simplify_path().trim_suffix("/") + "/"
	var target := path.simplify_path().trim_suffix("/")
	if not target.begins_with("user://") and not target.begins_with("/"):
		return false
	if target == root.trim_suffix("/"):
		return false
	if not target.begins_with(root):
		return false
	var rest := target.substr(root.length())
	return not rest.is_empty() and not rest.contains("/")

## Recursive byte size of a map folder. Missing files count as zero.
static func folder_size(path: String) -> int:
	var total := 0
	var dir := DirAccess.open(path)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			var child := path.path_join(name)
			if dir.current_is_dir():
				total += folder_size(child)
			else:
				var file := FileAccess.open(child, FileAccess.READ)
				if file != null:
					total += file.get_length()
					file.close()
		name = dir.get_next()
	dir.list_dir_end()
	return total

## Re-reads the sidecar so the source action cannot delete a folder whose tag changed since load.
static func source_of(path: String) -> String:
	return str(MapSource.read(path).get("source", MapSource.SOURCE_UNKNOWN))

## Deletes one map folder and reports whether it is really gone.
static func remove_map(path: String) -> bool:
	if not is_safe_map_path(path):
		return false
	Utils.remove_tree(path)
	return not DirAccess.dir_exists_absolute(path)

## Folders under Songs/ that hold no Info.dat: an interrupted download, or what is left of one.
## They are not maps, so the library skips them and the Storage panel cannot list them.
static func incomplete_folders() -> PackedStringArray:
	var found := PackedStringArray()
	var root := songs_root()
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	for folder in dir.get_directories():
		var path := root + folder + "/"
		if not FileAccess.file_exists(path + "Info.dat") and not FileAccess.file_exists(path + "info.dat"):
			found.append(path)
	return found

## Deletes every folder incomplete_folders() reports, through the same guarded delete as a map,
## and returns the ones that are really gone.
static func remove_incomplete_folders() -> PackedStringArray:
	var removed := PackedStringArray()
	for path in incomplete_folders():
		if remove_map(path):
			removed.append(path)
	return removed

## One-shot cleanup requested from outside the headset: the file `cleanup_incomplete.flag`,
## pushed next to bench.flag (or placed in user://), removes the incomplete folders at the next
## library scan and is then renamed to `.consumed`. Nothing is deleted without that file.
const CLEANUP_FLAG := "cleanup_incomplete.flag"

static func run_requested_cleanup() -> void:
	var flag_dir := ""
	var runner: Script = load("res://game/scripts/BenchmarkRunner.gd")
	if runner != null:
		var external := str(runner.call("_android_external_files_dir"))
		if not external.is_empty() and FileAccess.file_exists(external.path_join(CLEANUP_FLAG)):
			flag_dir = external
	if flag_dir.is_empty() and FileAccess.file_exists("user://" + CLEANUP_FLAG):
		flag_dir = "user://"
	if flag_dir.is_empty():
		return
	var found := incomplete_folders()
	var removed := remove_incomplete_folders()
	for path in removed:
		vr.log_info("CLEANUP removed incomplete download: " + path)
	vr.log_info("CLEANUP done: %d of %d incomplete folders removed" % [removed.size(), found.size()])
	var dir := DirAccess.open(flag_dir)
	if dir != null:
		@warning_ignore("return_value_discarded")
		dir.rename(CLEANUP_FLAG, CLEANUP_FLAG + ".consumed")

static func format_bytes(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	if bytes < 1024 * 1024:
		return "%.1f KB" % (float(bytes) / 1024.0)
	if bytes < 1024 * 1024 * 1024:
		return "%.1f MB" % (float(bytes) / (1024.0 * 1024.0))
	return "%.2f GB" % (float(bytes) / (1024.0 * 1024.0 * 1024.0))
