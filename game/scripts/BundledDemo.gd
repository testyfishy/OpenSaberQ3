extends RefCounted
class_name BundledDemo

## One-shot removal of the TheFatRat demo that shipped with this project through 0.6.0
## (specs/024 FR-001/F2). The folder is deleted only when the song file is byte-identical to the
## bundled copy; a player's own download with a different hash is left alone. The marker is written
## even on a miss so the 4.7 MB file is not hashed on every launch.

const FOLDER := "TheFatRat_Timelapse"
const SONG := "song_q1.egg"
const SONG_SHA256 := "303F764B259F309F9DEB1AC077524B1A4995AFD7B691CD48C194FD8FB7606C16"
const MARKER := ".bundled_demo_removed"

static func cleanup(songs_dir: String) -> void:
	var marker := songs_dir.path_join(MARKER)
	if FileAccess.file_exists(marker):
		return
	var dir := songs_dir.path_join(FOLDER)
	if DirAccess.dir_exists_absolute(dir):
		var song := dir.path_join(SONG)
		if FileAccess.file_exists(song) and _sha256(song) == SONG_SHA256:
			_remove_tree(dir)
			print("BUNDLEDDEMO removed ", dir)
	var file := FileAccess.open(marker, FileAccess.WRITE)
	if file != null:
		file.store_string("removed\n")
		file.close()

static func _sha256(path: String) -> String:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return ""
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK:
		return ""
	ctx.update(bytes)
	return ctx.finish().hex_encode().to_upper()

static func _remove_tree(path: String) -> void:
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
