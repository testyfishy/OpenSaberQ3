extends RefCounted
class_name PlaylistManifest

## Playlist membership for the local library (specs/029 FR-012).
##
## Playlists are many-to-many: one map can be in several BeastSaber playlists, and a re-download
## must not move it between cards. The per-map sidecar therefore keeps only the source, hash,
## added date and cached size; membership lives here, in `Songs/.playlists.json`:
##
##   {"schema": 1, "playlists": [
##     {"id": "1245683", "title": "DITR8", "cover": "", "added_unix": 0, "hashes": ["..."]}
##   ]}
##
## Writes are atomic (temp + rename), like the sidecar. Missing/corrupt files read as empty; the
## library still lists every map under its source.

const FILENAME := ".playlists.json"
const SCHEMA := 1

static func path_for(songs_dir: String) -> String:
	if songs_dir.is_empty():
		return ""
	return songs_dir.path_join(FILENAME)

static func read(songs_dir: String) -> Dictionary:
	var out := {"schema": SCHEMA, "playlists": []}
	var path := path_for(songs_dir)
	if path.is_empty() or not FileAccess.file_exists(path):
		return out
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return out
	var lists: Variant = (parsed as Dictionary).get("playlists", [])
	if not (lists is Array):
		return out
	out["playlists"] = lists
	return out

static func save(songs_dir: String, data: Dictionary) -> bool:
	var path := path_for(songs_dir)
	if path.is_empty():
		return false
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	if DirAccess.rename_absolute(path + ".tmp", path) == OK:
		return true
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(path + ".tmp", path) == OK:
		return true
	DirAccess.remove_absolute(path + ".tmp")
	return false

## Adds the installed map hashes to a playlist, creating it if needed. Returns true on save.
static func add_maps(songs_dir: String, id: String, title: String, hashes: Array,
		cover: String = "") -> bool:
	var clean_id := id.strip_edges()
	if clean_id.is_empty() or hashes.is_empty():
		return false
	var data := read(songs_dir)
	var lists: Array = data.get("playlists", [])
	var entry: Dictionary = {}
	for existing in lists:
		if existing is Dictionary and str((existing as Dictionary).get("id", "")) == clean_id:
			entry = existing
			break
	if entry.is_empty():
		entry = {
			"id": clean_id,
			"title": title.strip_edges(),
			"cover": cover,
			"added_unix": int(Time.get_unix_time_from_system()),
			"hashes": [],
		}
		lists.append(entry)
	elif str(entry.get("title", "")).is_empty() and not title.strip_edges().is_empty():
		entry["title"] = title.strip_edges()
	if cover != "" and str(entry.get("cover", "")).is_empty():
		entry["cover"] = cover
	var current: Array = entry.get("hashes", [])
	for hash in hashes:
		var h := str(hash).strip_edges().to_lower()
		if not h.is_empty() and not current.has(h):
			current.append(h)
	entry["hashes"] = current
	data["playlists"] = lists
	return save(songs_dir, data)

## Removes a deleted map from every playlist; a playlist left empty is dropped.
static func remove_map(songs_dir: String, hash: String) -> bool:
	var h := hash.strip_edges().to_lower()
	if h.is_empty():
		return false
	var data := read(songs_dir)
	var lists: Array = data.get("playlists", [])
	var changed := false
	var kept: Array = []
	for entry in lists:
		if not (entry is Dictionary):
			continue
		var hashes: Array = (entry as Dictionary).get("hashes", [])
		if hashes.has(h):
			hashes.erase(h)
			(entry as Dictionary)["hashes"] = hashes
			changed = true
		if not hashes.is_empty():
			kept.append(entry)
	if not changed:
		return true
	data["playlists"] = kept
	return save(songs_dir, data)

## Playlist entries that contain `hash`.
static func playlists_for(data: Dictionary, hash: String) -> Array:
	var out: Array = []
	var h := hash.strip_edges().to_lower()
	if h.is_empty():
		return out
	for entry in data.get("playlists", []):
		if entry is Dictionary and (entry as Dictionary).get("hashes", []).has(h):
			out.append(entry)
	return out

