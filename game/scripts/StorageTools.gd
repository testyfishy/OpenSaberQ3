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

static func format_bytes(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	if bytes < 1024 * 1024:
		return "%.1f KB" % (float(bytes) / 1024.0)
	if bytes < 1024 * 1024 * 1024:
		return "%.1f MB" % (float(bytes) / (1024.0 * 1024.0))
	return "%.2f GB" % (float(bytes) / (1024.0 * 1024.0 * 1024.0))
