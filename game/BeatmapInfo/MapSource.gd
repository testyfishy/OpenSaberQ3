extends RefCounted
class_name MapSource

## Where a library map came from (specs/020 FR-001..FR-003, FR-007, FR-009).
##
## The tag lives in a per-map-folder sidecar, `OpenSaber.meta` (INI), not in the map's own
## `Info.dat`: the map files are the author's, and editing them would change the level hash.
## A missing, unreadable or future-schema sidecar reads as `unknown`; nothing here may fail a
## map load.
##
## BeatSaver's version hash is the standard Beat Saber level hash: SHA-1 over the bytes of
## `Info.dat` followed by every difficulty file, in the order `Info.dat` lists them. That is
## what `compute_level_hash` reproduces, which is why old maps can be re-identified.

const FILENAME := "OpenSaber.meta"
## v2 (specs/029): adds `added_unix` and the cached `bytes`; v1 sidecars read as 0. Playlist
## membership is not here: one map can be in several BeastSaber playlists, so it lives in
## `Songs/.playlists.json` (PlaylistManifest).
const SCHEMA_VERSION := 2

const SOURCE_BEATSAVER := "beatsaver"
const SOURCE_BEASTSABER := "beastsaber"
const SOURCE_UPLOADED := "uploaded"
const SOURCE_LOCAL := "local"
const SOURCE_UNKNOWN := "unknown"

## Display order for the library filter; `all` is the unfiltered view.
const SOURCES: Array[String] = [
	SOURCE_BEATSAVER, SOURCE_BEASTSABER, SOURCE_UPLOADED, SOURCE_LOCAL, SOURCE_UNKNOWN
]
const ALL := "all"
const LABELS := {
	SOURCE_BEATSAVER: "BeatSaver",
	SOURCE_BEASTSABER: "BeastSaber",
	SOURCE_UPLOADED: "Uploaded",
	SOURCE_LOCAL: "Local",
	SOURCE_UNKNOWN: "Unknown",
}


## Normalises anything a config/panel hands us into one of SOURCES (or `all`).
static func normalize_source(value: String) -> String:
	var s := value.strip_edges().to_lower()
	if s == ALL or SOURCES.has(s):
		return s
	return SOURCE_UNKNOWN


static func label(source: String) -> String:
	var s := normalize_source(source)
	if s == ALL:
		return "All Sources"
	return String(LABELS.get(s, "Unknown"))


static func sidecar_path(dir_path: String) -> String:
	if dir_path.is_empty():
		return ""
	return dir_path.path_join(FILENAME)


## Reads the sidecar. Always returns a valid dictionary:
## {source, map_id, hash, added_unix, bytes}.
static func read(dir_path: String) -> Dictionary:
	var out := {"source": SOURCE_UNKNOWN, "map_id": "", "hash": "", "added_unix": 0, "bytes": 0}
	var path := sidecar_path(dir_path)
	if path.is_empty() or not FileAccess.file_exists(path):
		return out
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return out
	# A sidecar from a newer build is not guessed at: the safe read is Unknown.
	if int(cfg.get_value("map", "schema", 0)) > SCHEMA_VERSION:
		return out
	out.source = normalize_source(str(cfg.get_value("map", "source", SOURCE_UNKNOWN)))
	if String(out.source) == ALL:
		out.source = SOURCE_UNKNOWN
	out.map_id = str(cfg.get_value("map", "map_id", "")).strip_edges()
	out.hash = str(cfg.get_value("map", "hash", "")).strip_edges().to_lower()
	out.added_unix = int(cfg.get_value("map", "added_unix", 0))
	out.bytes = int(cfg.get_value("map", "bytes", 0))
	return out


## Writes the sidecar atomically: temp file first, then a rename over the real one. A failed
## write leaves the old sidecar (or none) in place; the caller keeps the map either way.
static func write(dir_path: String, source: String, map_id: String = "", hash: String = "",
		added_unix: int = 0, bytes: int = 0) -> bool:
	if dir_path.is_empty():
		return false
	var cfg := ConfigFile.new()
	cfg.set_value("map", "schema", SCHEMA_VERSION)
	cfg.set_value("map", "source", normalize_source(source))
	cfg.set_value("map", "map_id", map_id.strip_edges())
	cfg.set_value("map", "hash", hash.strip_edges().to_lower())
	cfg.set_value("map", "added_unix", added_unix)
	cfg.set_value("map", "bytes", bytes)
	var path := sidecar_path(dir_path)
	var tmp := path + ".tmp"
	if cfg.save(tmp) != OK:
		return false
	if DirAccess.rename_absolute(tmp, path) == OK:
		return true
	# Windows will not rename over an existing file; replace then retry.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(tmp, path) == OK:
		return true
	DirAccess.remove_absolute(tmp)
	return false


## Updates the cached size/added date without touching source/id/hash (specs/029 FR-013).
static func set_stats(dir_path: String, added_unix: int, bytes: int) -> bool:
	var cur := read(dir_path)
	return write(dir_path, str(cur.source), str(cur.map_id), str(cur.hash), added_unix, bytes)


## SHA-1 of `Info.dat` plus each difficulty file in declared order, lower-case hex. Returns ""
## when the folder is not a readable map (missing files, bad JSON), which the backfill treats as
## "leave it Unknown" rather than "invent a hash".
static func compute_level_hash(dir_path: String) -> String:
	var info_path := _info_path(dir_path)
	if info_path.is_empty():
		return ""
	var info_bytes := FileAccess.get_file_as_bytes(info_path)
	if info_bytes.is_empty():
		return ""
	# Prefer the exact loader the game uses for map selection (the autoload's
	# FileAccess.get_as_text + JSON.parse_string path). Observed in the Android export: our own
	# copy of that path returned non-Dictionary for a valid, ASCII Info.dat, silently disabling
	# every hash. The cause is unconfirmed (other static JSON callers still work); reusing the
	# game's loader fixes it on device.
	var info: Variant = vr.load_json_file(info_path)
	if not (info is Dictionary) or (info as Dictionary).is_empty():
		info = _read_json_file(info_path)
	if not (info is Dictionary):
		return ""
	var files := _difficulty_files(info as Dictionary)
	if files.is_empty():
		return ""

	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA1) != OK:
		return ""
	ctx.update(info_bytes)
	for file_name: String in files:
		if file_name.is_empty():
			return ""
		var file_path := dir_path.path_join(file_name)
		if not FileAccess.file_exists(file_path):
			return ""
		ctx.update(FileAccess.get_file_as_bytes(file_path))
	return ctx.finish().hex_encode()


## The library filter (FR-002): a pure list operation, no filesystem or network work.
## `all` returns the input unchanged; a specific source returns only its maps, in a stable
## author/title order so the filtered view reads deliberately.
static func filter_by_source(songs: Array[MapInfo], source: String) -> Array[MapInfo]:
	var wanted := normalize_source(source)
	if wanted == ALL:
		return songs
	var out: Array[MapInfo] = []
	for song: MapInfo in songs:
		if song != null and song.source == wanted:
			out.append(song)
	out.sort_custom(func(a: MapInfo, b: MapInfo) -> bool:
		if a.song_author_name != b.song_author_name:
			return a.song_author_name.naturalnocasecmp_to(b.song_author_name) < 0
		return a.song_name.naturalnocasecmp_to(b.song_name) < 0
	)
	return out


static func has_sidecar(dir_path: String) -> bool:
	return FileAccess.file_exists(sidecar_path(dir_path))


static func _info_path(dir_path: String) -> String:
	for name: String in ["Info.dat", "info.dat"]:
		var path := dir_path.path_join(name)
		if FileAccess.file_exists(path):
			return path
	return ""


## Flattens every difficulty set: the hash is over the files in the order Info.dat lists them,
## across characteristics (Standard, OneSaber, Lawless, ...), not one characteristic at a time.
static func _difficulty_files(info_dict: Dictionary) -> Array[String]:
	var files: Array[String] = []
	# Local dictionary access only: this runs from a static function, and the autoload helper
	# path failed to read the sets in the Android export (every hash came back empty).
	var sets := _array_of(info_dict, "_difficultyBeatmapSets")
	if not sets.is_empty():
		for set_entry: Variant in sets:
			if not (set_entry is Dictionary):
				continue
			for diff: Variant in _array_of(set_entry as Dictionary, "_difficultyBeatmaps"):
				if diff is Dictionary:
					files.append(_string_of(diff as Dictionary, "_beatmapFilename", ""))
		return files
	# v3/v4: one flat array.
	for diff: Variant in _array_of(info_dict, "difficultyBeatmaps"):
		if diff is Dictionary:
			files.append(_string_of(diff as Dictionary, "beatmapFilename", ""))
	return files


static func _array_of(d: Dictionary, key: String) -> Array:
	var v: Variant = d.get(key)
	@warning_ignore("unsafe_cast")
	return v as Array if v is Array else []


static func _string_of(d: Dictionary, key: String, default: String) -> String:
	var v: Variant = d.get(key)
	return v as String if v is String else default


## One-line reason a map hashes or fails, for the backfill's debug log on the headset.
static func diagnose(dir_path: String) -> String:
	var info_path := _info_path(dir_path)
	if info_path.is_empty():
		return "no_info_path"
	var info_bytes := FileAccess.get_file_as_bytes(info_path)
	if info_bytes.is_empty():
		return "empty_info_bytes"
	var file := FileAccess.open(info_path, FileAccess.READ)
	if file == null:
		return "open_failed"
	var text := file.get_as_text()
	file.close()
	if text.is_empty():
		return "text_empty"
	var direct: Variant = JSON.parse_string(text)
	if not (direct is Dictionary):
		return "parse_text_failed(len=%d,head=%s)" % [text.length(), text.substr(0, 8)]
	var lit: Variant = JSON.parse_string("{\"a\":1}")
	if not (lit is Dictionary):
		return "json_literal_failed"
	var via_vr: Variant = vr.load_json_file(info_path)
	var info: Variant = via_vr if (via_vr is Dictionary and not (via_vr as Dictionary).is_empty()) else direct
	if not (info is Dictionary):
		return "parse_failed"
	var files := _difficulty_files(info as Dictionary)
	if files.is_empty():
		return "no_difficulty_files"
	var missing: Array[String] = []
	for file_name: String in files:
		if file_name.is_empty() or not FileAccess.file_exists(dir_path.path_join(file_name)):
			missing.append(file_name)
	if not missing.is_empty():
		return "missing:" + ",".join(missing)
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA1) != OK:
		return "hash_start_failed"
	ctx.update(info_bytes)
	for file_name: String in files:
		ctx.update(FileAccess.get_file_as_bytes(dir_path.path_join(file_name)))
	return "ok:" + ctx.finish().hex_encode()


static func _read_json_file(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	# A UTF-8 BOM is legal in the wild and the JSON parser rejects it.
	if text.begins_with("\ufeff"):
		text = text.substr(1)
	return JSON.parse_string(text)
