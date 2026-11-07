extends Node

# StorageTools probe (specs/026 SC-005/SC-006): recursive size, source grouping, and the
# refusal cases that keep a recursive delete inside a single map folder.

func _ready() -> void:
	var root := StorageTools.songs_root()
	var a := root + "ProbeA/"
	var b := root + "ProbeB/"
	_make_dir(a + "nested/")
	_make_dir(b)
	_write(a + "info.dat", 100)
	_write(a + "nested/extra.bin", 2500)
	_write(b + "x.dat", 10)
	MapSource.write(a, MapSource.SOURCE_BEATSAVER, "probe-a", "hash-a")
	MapSource.write(b, MapSource.SOURCE_BEASTSABER, "probe-b", "hash-b")
	print("STORAGEPROBE sizes a=%d b=%d" % [StorageTools.folder_size(a), StorageTools.folder_size(b)])
	print("STORAGEPROBE sources a=%s b=%s" % [StorageTools.source_of(a), StorageTools.source_of(b)])
	print("STORAGEPROBE format 2600=%s 1048576=%s" % [
		StorageTools.format_bytes(2600), StorageTools.format_bytes(1048576)])

	var safe_a := StorageTools.is_safe_map_path(a)
	var safe_root := StorageTools.is_safe_map_path(root)
	var safe_traversal := StorageTools.is_safe_map_path(a + "../ProbeB/")
	var safe_empty := StorageTools.is_safe_map_path("")
	var safe_outside := StorageTools.is_safe_map_path("C:/temp/evil/")
	print("STORAGEPROBE safe a=%s root=%s traversal=%s empty=%s outside=%s" % [
		safe_a, safe_root, safe_traversal, safe_empty, safe_outside])

	var refused_root := not StorageTools.remove_map(root)
	var refused_traversal := not StorageTools.remove_map(a + "../ProbeB/")
	var root_alive := DirAccess.dir_exists_absolute(root)
	var b_alive := DirAccess.dir_exists_absolute(b)
	var removed_a := StorageTools.remove_map(a)
	var a_gone := not DirAccess.dir_exists_absolute(a)
	print("STORAGEPROBE delete root_refused=%s traversal_refused=%s root_alive=%s b_alive=%s a_removed=%s a_gone=%s" % [
		refused_root, refused_traversal, root_alive, b_alive, removed_a, a_gone])
	# clean the second probe map so a headset run does not leave test folders behind
	print("STORAGEPROBE cleanup=%s" % StorageTools.remove_map(b))
	get_tree().quit()

func _make_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)

func _write(path: String, size: int) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		var buffer := PackedByteArray()
		buffer.resize(size)
		file.store_buffer(buffer)
		file.close()
