extends Node

# Regression harness for four bugs found in the 0.7.9 audit (docs/audit-fable-5.2.md).
# Headless, no network beyond loopback, and it only touches its own probe folders.
#
# Run: godot --headless --path . res://tools/harness/verify_io_fixes.tscn
# Prints one IOFIX line per check and `IOFIX PASS` / `IOFIX FAIL`.

const STORAGE_PANEL := preload("res://game/ui/StoragePanel/StoragePanel.tscn")
const PoolScript := preload("res://game/scripts/HTTPRequestPool.gd")
const UploaderScript := preload("res://game/scripts/SongUploader/song_uploader.gd")
const PROBE_PORT := 45877

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
	print("IOFIX %s %s%s" % ["ok  " if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_unzip()
	await _test_storage_delete()
	_test_incomplete_cleanup()
	await _test_pool()
	await _test_uploader()
	_test_v2_loader()
	print("IOFIX ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


# --- Utils.unzip: subfolders extract, traversal entries do not ---------------------------------
func _test_unzip() -> void:
	var base := "user://iofix_probe/"
	var dest := base + "dest"
	Utils.remove_tree(base)
	DirAccess.make_dir_recursive_absolute(dest)
	var zip_path := base + "probe.zip"
	var packer := ZIPPacker.new()
	packer.open(zip_path)
	for entry: String in ["../escaped.dat", "Info.dat", "sub/inner.dat", "after.dat"]:
		packer.start_file(entry)
		packer.write_file("x".to_utf8_buffer())
		packer.close_file()
	packer.close()

	Utils.unzip(zip_path, dest)
	_check("unzip: top-level file extracted", FileAccess.file_exists(dest + "/Info.dat"))
	_check("unzip: file in a subfolder extracted", FileAccess.file_exists(dest + "/sub/inner.dat"))
	_check("unzip: entry after the subfolder still extracted", FileAccess.file_exists(dest + "/after.dat"))
	_check("unzip: ../ entry did not escape the destination", not FileAccess.file_exists(base + "escaped.dat"))
	Utils.remove_tree(base)


# --- StoragePanel: the confirmed delete actually deletes ----------------------------------------
func _test_storage_delete() -> void:
	var folder := StorageTools.songs_root() + "IoFixProbeMap/"
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder + "Info.dat", FileAccess.WRITE)
	file.store_string("{}")
	file.close()

	var panel := STORAGE_PANEL.instantiate() as StoragePanel
	add_child(panel)
	await get_tree().process_frame
	var no_difficulties: Array[DifficultyInfo] = []
	var map := MapInfo.new("2.0.0", "IoFixProbe", "", "probe", "probe", 120.0, 0.0, 0.0, "", "", "",
		0.0, {}, folder, no_difficulties, MapSource.SOURCE_UNKNOWN, "", "iofix-probe-hash")
	var batch: Array = [{"map": map, "size": 2}]
	# First press arms the confirmation, second press confirms: the path a player takes.
	panel._arm(batch, panel.delete_button, "Delete 1 maps")
	panel._on_delete_pressed()
	await get_tree().process_frame
	_check("storage: confirmed delete removes the map folder", not DirAccess.dir_exists_absolute(folder),
		panel.status_label.text)
	if DirAccess.dir_exists_absolute(folder):
		StorageTools.remove_map(folder)
	panel.queue_free()
	await get_tree().process_frame


# --- StorageTools: only folders without an Info.dat are treated as incomplete downloads --------
func _test_incomplete_cleanup() -> void:
	var root := StorageTools.songs_root()
	var empty := root + "IoFixProbeIncomplete/"
	var partial := root + "IoFixProbePartial/"
	var real := root + "IoFixProbeReal/"
	for path: String in [empty, partial, real]:
		DirAccess.make_dir_recursive_absolute(path)
	for file_path: String in [partial + "song.egg", real + "Info.dat"]:
		var file := FileAccess.open(file_path, FileAccess.WRITE)
		file.store_string("{}")
		file.close()
	var found := StorageTools.incomplete_folders()
	_check("cleanup: a folder with no files and one with files but no Info.dat are incomplete",
		found.has(empty) and found.has(partial))
	_check("cleanup: a folder with an Info.dat is not", not found.has(real))
	# Without the flag file nothing is touched.
	StorageTools.run_requested_cleanup()
	_check("cleanup: nothing is deleted without the request file", DirAccess.dir_exists_absolute(empty))
	# Only the probe folders are removed here, so a developer's own leftovers are not touched.
	_check("cleanup: an incomplete folder can be removed", StorageTools.remove_map(empty) and StorageTools.remove_map(partial))
	_check("cleanup: the real map is still there", FileAccess.file_exists(real + "Info.dat"))
	StorageTools.remove_map(real)


# --- HTTPRequestPool: finished requests are freed, queued requests keep their token -------------
func _test_pool() -> void:
	var pool := PoolScript.new()
	pool.max_simultaneous_request = 1
	pool.request_timeout = 2.0
	add_child(pool)
	var seen: Array[int] = []
	pool.request_complete.connect(
		func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray, token: int, _u: Dictionary) -> void:
			seen.append(token))
	# Nothing listens on this loopback port, so both requests fail fast without leaving the machine.
	var first: int = pool.request("http://127.0.0.1:9/a")
	var second: int = pool.request("http://127.0.0.1:9/b")
	var deadline := Time.get_ticks_msec() + 8000
	while seen.size() < 2 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_check("pool: both requests completed", seen.size() == 2, "completed=%d" % seen.size())
	_check("pool: the queued request completes under its own token", seen.has(first) and seen.has(second),
		"issued %d,%d completed %s" % [first, second, str(seen)])
	var leaked := 0
	for child in pool.get_children():
		if child is HTTPRequest:
			leaked += 1
	_check("pool: no HTTPRequest left as a child", leaked == 0)
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	pool.queue_free()
	await get_tree().process_frame
	_check("pool: no orphaned HTTPRequest nodes", _orphan_http_requests() == 0,
		"orphan nodes total=%d" % orphans)


func _orphan_http_requests() -> int:
	var count := 0
	for id in Node.get_orphan_node_ids():
		var obj := instance_from_id(id)
		if obj is HTTPRequest:
			count += 1
	return count


# --- MapData: a non-object entry in a v2 `_notes` array does not hang the loader -----------------
func _test_v2_loader() -> void:
	# Before the fix this call never returned.
	MapData.load_note_stack_v2([1, {"_time": 2.0, "_lineIndex": 1.0, "_lineLayer": 0.0, "_type": 0.0, "_cutDirection": 1.0}, "x"])
	_check("v2 loader: skips non-object note entries", MapData.note_stack.size() == 1,
		"notes=%d" % MapData.note_stack.size())
	MapData.note_stack.clear()
	MapData.bomb_stack.clear()


# --- SongUploader: a client that connects and says nothing cannot hang the game -----------------
func _test_uploader() -> void:
	var listener := TCPServer.new()
	if listener.listen(PROBE_PORT, "127.0.0.1") != OK:
		_check("uploader: probe listener started", false)
		return
	var client := StreamPeerTCP.new()
	client.connect_to_host("127.0.0.1", PROBE_PORT)
	var deadline := Time.get_ticks_msec() + 3000
	while not listener.is_connection_available() and Time.get_ticks_msec() < deadline:
		client.poll()
		await get_tree().process_frame
	if not listener.is_connection_available():
		_check("uploader: probe client connected", false)
		return
	var connection := listener.take_connection()
	# Not added to the tree: _enter_tree would open the real upload port.
	var uploader := UploaderScript.new() as SongUploader
	var started := Time.get_ticks_msec()
	# Before the fix this call never returned (the harness run had to be killed).
	uploader.handle_connection(connection)
	var took := Time.get_ticks_msec() - started
	_check("uploader: a silent client is dropped instead of freezing the game", took < 5000, "returned after %d ms" % took)
	uploader.free()
	client.disconnect_from_host()
	listener.stop()
