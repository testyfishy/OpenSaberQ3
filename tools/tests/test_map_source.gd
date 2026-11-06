extends Node3D

# Source tag test (specs/020 FR-001, FR-002, FR-007, FR-009, SC-001, SC-006).
#
#  1. every source round-trips through `OpenSaber.meta` (atomic write, schema version);
#  2. a missing, corrupt or future-schema sidecar reads as unknown and never crashes;
#  3. the library filter returns exactly the matching maps;
#  4. the level hash of a known BeatSaver map equals its published hash (Phoenix, bf2c...).
#
# Run: godot --headless --path . res://tools/tests/test_map_source.tscn

const PHOENIX := "bf2c367d29b133b66dc27f6f8e20467d0ec3301f"
const PHOENIX_DIR := "F:/Dev/BeepSaberBin/map-corpus/Songs/Fall Out Boy - The Phoenix"

var _bad := 0

func _ready() -> void:
	var root := ProjectSettings.globalize_path("user://test_map_source")
	_remove_tree(root)
	DirAccess.make_dir_recursive_absolute(root)

	_test_round_trip(root)
	_test_bad_sidecars(root)
	_test_filter(root)
	_test_hash()

	_remove_tree(root)
	print("MAPSOURCETEST ", "PASS" if _bad == 0 else "FAIL")
	get_tree().quit(0 if _bad == 0 else 1)

func _test_round_trip(root: String) -> void:
	for source: String in MapSource.SOURCES:
		var dir := root.path_join(source)
		DirAccess.make_dir_recursive_absolute(dir)
		var ok := MapSource.write(dir, source, "12345", "ABCDEF0123456789")
		_check(ok, "write %s" % source)
		_check(MapSource.has_sidecar(dir), "sidecar exists for %s" % source)
		var meta := MapSource.read(dir)
		_check(str(meta.source) == source, "%s source reads back (%s)" % [source, str(meta.source)])
		_check(str(meta.map_id) == "12345", "%s map_id reads back" % source)
		_check(str(meta.hash) == "abcdef0123456789", "%s hash is lower-case" % source)
		_check(not FileAccess.file_exists(MapSource.sidecar_path(dir) + ".tmp"), "%s leaves no temp file" % source)

func _test_bad_sidecars(root: String) -> void:
	var missing := root.path_join("missing")
	DirAccess.make_dir_recursive_absolute(missing)
	_check(str(MapSource.read(missing).source) == MapSource.SOURCE_UNKNOWN, "missing sidecar is unknown")

	var corrupt := root.path_join("corrupt")
	DirAccess.make_dir_recursive_absolute(corrupt)
	var f := FileAccess.open(MapSource.sidecar_path(corrupt), FileAccess.WRITE)
	f.store_string("this is not an ini file\n[[[")
	f.close()
	_check(str(MapSource.read(corrupt).source) == MapSource.SOURCE_UNKNOWN, "corrupt sidecar is unknown")

	var future := root.path_join("future")
	DirAccess.make_dir_recursive_absolute(future)
	var cfg := ConfigFile.new()
	cfg.set_value("map", "schema", MapSource.SCHEMA_VERSION + 1)
	cfg.set_value("map", "source", MapSource.SOURCE_BEATSAVER)
	cfg.set_value("map", "map_id", "999")
	cfg.save(MapSource.sidecar_path(future))
	_check(str(MapSource.read(future).source) == MapSource.SOURCE_UNKNOWN, "future schema is unknown")

	var weird := root.path_join("weird")
	DirAccess.make_dir_recursive_absolute(weird)
	var cfg2 := ConfigFile.new()
	cfg2.set_value("map", "schema", MapSource.SCHEMA_VERSION)
	cfg2.set_value("map", "source", "not-a-source")
	cfg2.save(MapSource.sidecar_path(weird))
	_check(str(MapSource.read(weird).source) == MapSource.SOURCE_UNKNOWN, "unknown source string is unknown")

func _test_filter(root: String) -> void:
	var songs: Array[MapInfo] = []
	for source: String in MapSource.SOURCES:
		var m := MapInfo.new(
			"2.0.0", "Song " + source, "", "Author " + source, "Mapper", 120.0,
			0.0, 0.0, "song.ogg", "", "", 0.0, {}, root.path_join(source).path_join(""), [])
		m.source = source
		songs.append(m)
	var all := MapSource.filter_by_source(songs, MapSource.ALL)
	_check(all.size() == songs.size(), "all returns every map (%d)" % all.size())
	for source: String in MapSource.SOURCES:
		var filtered := MapSource.filter_by_source(songs, source)
		_check(filtered.size() == 1, "%s filter returns 1 map (%d)" % [source, filtered.size()])
		if filtered.size() == 1:
			_check(filtered[0].source == source, "%s filter returns the right map" % source)
	var none := MapSource.filter_by_source(songs, MapSource.SOURCE_BEASTSABER)
	_check(none.size() == 1, "single-source filter is stable")

	# A filtered view is sorted by author then title, independent of discovery order.
	var shuffled: Array[MapInfo] = [songs[2], songs[0], songs[1]]
	var sorted := MapSource.filter_by_source(shuffled, MapSource.ALL)
	_check(sorted[0].song_author_name == "Author uploaded", "all keeps its order")
	var picked: Array[MapInfo] = []
	for source: String in MapSource.SOURCES:
		var m := MapInfo.new(
			"2.0.0", "Song", "", "Author " + source, "Mapper", 120.0,
			0.0, 0.0, "song.ogg", "", "", 0.0, {}, root.path_join(source).path_join(""), [])
		m.source = MapSource.SOURCE_BEATSAVER
		picked.append(m)
	var out_of_order: Array[MapInfo] = [picked[2], picked[0], picked[1]]
	var ordered := MapSource.filter_by_source(out_of_order, MapSource.SOURCE_BEATSAVER)
	_check(ordered[0].song_author_name == "Author beastsaber", "filter sorts by author (%s)" % ordered[0].song_author_name)

func _test_hash() -> void:
	if not DirAccess.dir_exists_absolute(PHOENIX_DIR):
		print("MAPSOURCETEST hash SKIP (corpus map not present)")
		return
	var hash := MapSource.compute_level_hash(PHOENIX_DIR + "/")
	_check(hash == PHOENIX, "Phoenix level hash (%s)" % hash)

func _check(condition: bool, what: String) -> void:
	if not condition:
		printerr("MAPSOURCETEST FAIL: " + what)
		_bad += 1

func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var child := path.path_join(name)
		if dir.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
