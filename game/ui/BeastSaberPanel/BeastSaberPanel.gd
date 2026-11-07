extends Panel
class_name BeastSaberPanel

## BeastSaber (curated) browser (specs/025 FR-008..FR-011).
##
## BeastSaber's curation now lives on BeatSaver, so this panel reads the public JSON API:
##   list   GET https://api.beatsaver.com/playlists/search/{page}?curated=true
##   songs  GET <downloadURL>  (.bplist with one hash per song)
##   map    GET https://api.beatsaver.com/maps/hash/{hash}
##   zip    GET versions[0].downloadURL
## No HTML or devalue payloads are parsed.

const LIST_URL := "https://api.beatsaver.com/playlists/search/%d?curated=true"
const MAP_URL := "https://api.beatsaver.com/maps/hash/%s"
const USER_AGENT := "OpenSaberQ3/0.6 (in-VR BeastSaber playlist browser)"
const PAGE_SIZE := 20
const MAX_PLAYLIST_SONGS := 120

enum Busy { NONE, LIST, PLAYLIST, MAP, ZIP }

@export var main_menu_ref: MainMenu

@onready var prev_button := $Margin/VBox/Header/PrevButton as Button
@onready var next_button := $Margin/VBox/Header/NextButton as Button
@onready var back_button := $Margin/VBox/Header/BackButton as Button
@onready var page_label := $Margin/VBox/Header/PageLabel as Label
@onready var status_label := $Margin/VBox/StatusLabel as Label
@onready var list_box := $Margin/VBox/Body/ListScroll/PlaylistList as VBoxContainer
@onready var detail_title := $Margin/VBox/Body/Detail/DetailTitle as Label
@onready var detail_meta := $Margin/VBox/Body/Detail/DetailMeta as Label
@onready var detail_desc := $Margin/VBox/Body/Detail/DetailDesc as RichTextLabel
@onready var progress_label := $Margin/VBox/Body/Detail/ProgressLabel as Label
@onready var download_button := $Margin/VBox/Body/Detail/DownloadButton as Button

var _list_request: HTTPRequest
var _playlist_request: HTTPRequest
var _map_request: HTTPRequest
var _zip_request: HTTPRequest

var _busy := Busy.NONE
var _page := 0
var _loaded := false
var _playlists: Array = []
var _selected := -1

var _queue: Array = []
var _current_url := ""
var _current_name := ""
var _current_hash := ""
var _current_id := ""
var _downloaded := 0
var _skipped := 0
var _failed := 0

func _ready() -> void:
	UI_AudioEngine.attach_children(self)
	_list_request = _make_request(_on_list_completed)
	_playlist_request = _make_request(_on_playlist_completed)
	_map_request = _make_request(_on_map_completed)
	_zip_request = _make_request(_on_zip_completed)
	# A map zip can be several MB on a slow link; the download must not time out mid-file.
	_zip_request.timeout = 0.0
	prev_button.pressed.connect(_on_prev_pressed)
	next_button.pressed.connect(_on_next_pressed)
	back_button.pressed.connect(_on_back_pressed)
	download_button.pressed.connect(_on_download_pressed)
	_set_controls()

func _make_request(handler: Callable) -> HTTPRequest:
	var req := HTTPRequest.new()
	req.timeout = 20.0
	req.use_threads = true
	add_child(req)
	req.request_completed.connect(handler)
	return req

func _show() -> void:
	var canvas := _find_canvas()
	if canvas != null:
		canvas._show()
	else:
		visible = true
	if not _loaded:
		_load_page(0)

func _hide() -> void:
	var canvas := _find_canvas()
	if canvas != null:
		canvas._hide()
	else:
		visible = false

func _find_canvas() -> OQ_UI2DCanvas:
	var node: Node = self
	while node != null:
		if node is OQ_UI2DCanvas:
			return node as OQ_UI2DCanvas
		node = node.get_parent()
	return null

func _canvas_input_update() -> void:
	var canvas := _find_canvas()
	if canvas != null:
		canvas._input_update()

# --- list -------------------------------------------------------------------------------

func _load_page(page: int) -> void:
	if _busy != Busy.NONE:
		return
	_page = maxi(page, 0)
	_busy = Busy.LIST
	status_label.text = "Loading curated playlists..."
	_set_controls()
	_list_request.request(LIST_URL % _page, PackedStringArray(["User-Agent: " + USER_AGENT]))

func _on_list_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = Busy.NONE
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status_label.text = "Could not load playlists (%s). Check the connection and press Retry." % _code_text(result, code)
		_loaded = false
		_set_controls()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		status_label.text = "Playlist list was not understood. Press Retry."
		_loaded = false
		_set_controls()
		return
	var docs: Variant = (parsed as Dictionary).get("docs", [])
	_playlists = docs if docs is Array else []
	_loaded = true
	_selected = -1
	_rebuild_list()
	status_label.text = "%d curated playlists on page %d - pick one to see its maps." % [_playlists.size(), _page + 1]
	_set_controls()

func _rebuild_list() -> void:
	for child in list_box.get_children():
		child.queue_free()
	for i in range(_playlists.size()):
		var doc: Dictionary = _playlists[i]
		var owner: Dictionary = doc.get("owner", {})
		var stats: Dictionary = doc.get("stats", {})
		var maps := int(stats.get("totalMaps", 0))
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 78)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 24)
		button.text = "%s\n%s - %d maps" % [str(doc.get("name", "?")), str(owner.get("name", "?")), maps]
		button.pressed.connect(_on_playlist_pressed.bind(i))
		list_box.add_child(button)

func _on_playlist_pressed(index: int) -> void:
	if index < 0 or index >= _playlists.size():
		return
	_selected = index
	var doc: Dictionary = _playlists[index]
	var owner: Dictionary = doc.get("owner", {})
	var stats: Dictionary = doc.get("stats", {})
	detail_title.text = str(doc.get("name", "?"))
	detail_meta.text = "%s - %d maps - %s" % [
		str(owner.get("name", "?")),
		int(stats.get("totalMaps", 0)),
		_duration_text(int(stats.get("totalDuration", 0))),
	]
	detail_desc.text = str(doc.get("description", "")).strip_edges()
	progress_label.text = ""
	_set_controls()

func _on_prev_pressed() -> void:
	if _page > 0:
		_load_page(_page - 1)

func _on_next_pressed() -> void:
	if _playlists.size() >= PAGE_SIZE:
		_load_page(_page + 1)

func _on_back_pressed() -> void:
	if _busy != Busy.NONE:
		_cancel_download()
		return
	_hide()

func _cancel_download() -> void:
	for req in [_list_request, _playlist_request, _map_request, _zip_request]:
		if req != null:
			req.cancel_request()
	_queue.clear()
	_busy = Busy.NONE
	progress_label.text = "Cancelled"
	status_label.text = "Cancelled"
	_set_controls()

# --- download ---------------------------------------------------------------------------

func _on_download_pressed() -> void:
	if _busy != Busy.NONE or _selected < 0 or _selected >= _playlists.size():
		return
	var doc: Dictionary = _playlists[_selected]
	var url := str(doc.get("downloadURL", ""))
	if url.is_empty():
		status_label.text = "This playlist has no download URL."
		return
	OS.request_permissions()
	_queue.clear()
	_downloaded = 0
	_skipped = 0
	_failed = 0
	_busy = Busy.PLAYLIST
	progress_label.text = "Reading playlist..."
	status_label.text = "Reading playlist..."
	_set_controls()
	_playlist_request.request(url, PackedStringArray(["User-Agent: " + USER_AGENT]))

func _on_playlist_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = Busy.NONE
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("Could not read the playlist (%s)." % _code_text(result, code))
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("The playlist file was not understood.")
		return
	var songs: Variant = (parsed as Dictionary).get("songs", [])
	if songs is not Array or (songs as Array).is_empty():
		_fail("This playlist lists no songs.")
		return
	for entry in songs:
		if _queue.size() >= MAX_PLAYLIST_SONGS:
			break
		if entry is Dictionary:
			var hash := str((entry as Dictionary).get("hash", "")).strip_edges().to_lower()
			if hash.length() == 40:
				_queue.append({
					"hash": hash,
					"name": str((entry as Dictionary).get("songName", hash)),
				})
	if _queue.is_empty():
		_fail("This playlist lists no usable map hashes.")
		return
	progress_label.text = "0 of %d maps" % _queue.size()
	_download_next()

func _download_next() -> void:
	if _queue.is_empty():
		_finish_download()
		return
	var item: Dictionary = _queue[0]
	_busy = Busy.MAP
	progress_label.text = "%d of %d - looking up %s" % [_downloaded + 1, _downloaded + _queue.size(), str(item.name)]
	status_label.text = progress_label.text
	_map_request.request(MAP_URL % str(item.hash), PackedStringArray(["User-Agent: " + USER_AGENT]))

func _on_map_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = Busy.NONE
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_failed += 1
		_queue.remove_at(0)
		_download_next()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		_failed += 1
		_queue.remove_at(0)
		_download_next()
		return
	var doc: Dictionary = parsed
	var versions: Variant = doc.get("versions", [])
	var version: Dictionary = {}
	if versions is Array and not (versions as Array).is_empty() and (versions as Array)[0] is Dictionary:
		version = (versions as Array)[0]
	_current_url = str(version.get("downloadURL", ""))
	_current_hash = str(version.get("hash", _queue[0].hash))
	_current_id = str(doc.get("id", ""))
	_current_name = _safe_name(str(doc.get("name", _queue[0].name)))
	if _current_url.is_empty():
		_failed += 1
		_queue.remove_at(0)
		_download_next()
		return
	_busy = Busy.ZIP
	progress_label.text = "%d of %d - downloading %s" % [_downloaded + 1, _downloaded + _queue.size(), _current_name]
	status_label.text = progress_label.text
	_zip_request.request(_current_url, PackedStringArray(["User-Agent: " + USER_AGENT]))

enum Install { INSTALLED, SKIPPED, FAILED }

func _on_zip_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = Busy.NONE
	var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200 and not _looks_like_html(body)
	var outcome := Install.FAILED
	if ok:
		outcome = _install_zip(body)
	match outcome:
		Install.INSTALLED:
			_downloaded += 1
		Install.SKIPPED:
			_skipped += 1
		_:
			_failed += 1
	_queue.remove_at(0)
	_download_next()

## Writes the map zip, checks it really is a map, and only then creates the library folder and
## writes the `beastsaber` tag. A corrupt zip or a failed unpack leaves nothing behind (FR-011).
func _install_zip(body: PackedByteArray) -> Install:
	var tempdir := Constants.APPDATA_PATH + "temp"
	if DirAccess.make_dir_recursive_absolute(tempdir) != OK:
		return Install.FAILED
	var zippath := tempdir + "/%s.zip" % _current_name
	var file := FileAccess.open(zippath, FileAccess.WRITE)
	if file == null:
		return Install.FAILED
	file.store_buffer(body)
	file.close()
	if not _zip_has_info(zippath):
		DirAccess.remove_absolute(zippath)
		return Install.FAILED

	var folder_name := _current_name
	var song_out_dir := Constants.APPDATA_PATH + ("Songs/%s/" % folder_name)
	if _has_info(song_out_dir):
		var existing := MapSource.read(song_out_dir)
		if str(existing.get("hash", "")) == _current_hash:
			DirAccess.remove_absolute(zippath)
			return Install.SKIPPED
		# Same map name, different map: keep both rather than overwrite the installed one.
		folder_name = _safe_name("%s (%s)" % [_current_id, _current_name])
		song_out_dir = Constants.APPDATA_PATH + ("Songs/%s/" % folder_name)
		if _has_info(song_out_dir):
			DirAccess.remove_absolute(zippath)
			return Install.SKIPPED

	if DirAccess.make_dir_recursive_absolute(song_out_dir) != OK:
		DirAccess.remove_absolute(zippath)
		return Install.FAILED
	Utils.unzip(zippath, song_out_dir)
	DirAccess.remove_absolute(zippath)
	if not _has_info(song_out_dir):
		_remove_tree(song_out_dir)
		return Install.FAILED
	MapSource.write(song_out_dir, MapSource.SOURCE_BEASTSABER, _current_id, _current_hash)
	return Install.INSTALLED

func _has_info(dir_path: String) -> bool:
	return FileAccess.file_exists(dir_path + "Info.dat") or FileAccess.file_exists(dir_path + "info.dat")

func _zip_has_info(zip_path: String) -> bool:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return false
	var found := false
	for entry in reader.get_files():
		if entry.get_file().to_lower() == "info.dat":
			found = true
			break
	reader.close()
	return found

func _remove_tree(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var path := dir_path + entry
			if dir.current_is_dir():
				_remove_tree(path + "/")
			else:
				DirAccess.remove_absolute(path)
		entry = dir.get_next()
	dir.list_dir_end()

func _finish_download() -> void:
	_busy = Busy.NONE
	var text := "Downloaded %d maps" % _downloaded
	if _skipped > 0:
		text += ", %d already present" % _skipped
	if _failed > 0:
		text += ", %d failed" % _failed
	progress_label.text = text
	status_label.text = text
	if _downloaded > 0 and main_menu_ref != null:
		main_menu_ref._on_LoadPlaylists_Button_pressed()
	_set_controls()

func _fail(message: String) -> void:
	_busy = Busy.NONE
	_queue.clear()
	message += " Press Download to retry."
	progress_label.text = message
	status_label.text = message
	_set_controls()

# --- helpers ----------------------------------------------------------------------------

func _set_controls() -> void:
	var idle := _busy == Busy.NONE
	prev_button.disabled = not idle or _page <= 0
	next_button.disabled = not idle or _playlists.size() < PAGE_SIZE
	back_button.disabled = false
	download_button.disabled = not idle or _selected < 0

func _code_text(result: int, code: int) -> String:
	if result != HTTPRequest.RESULT_SUCCESS:
		return "request %d" % result
	return "HTTP %d" % code

func _duration_text(seconds: int) -> String:
	if seconds <= 0:
		return "duration unknown"
	return "%d min" % int(round(seconds / 60.0))

func _looks_like_html(body: PackedByteArray) -> bool:
	var head := body.slice(0, mini(16, body.size())).get_string_from_utf8().strip_edges().to_lower()
	return head.begins_with("<!doctype") or head.begins_with("<html")

func _safe_name(name: String) -> String:
	var out := name.strip_edges()
	for bad in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		out = out.replace(bad, "")
	if out.is_empty():
		out = "beastsaber-map"
	return out

