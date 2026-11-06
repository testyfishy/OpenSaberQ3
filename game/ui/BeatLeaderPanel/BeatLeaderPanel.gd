extends Panel
class_name BeatLeaderPanel

## Read-only BeatLeader leaderboard for the selected map and difficulty
## (specs/020 FR-004, FR-005, FR-010).
##
## Two documented GETs (board, then scores), one at a time, 10 s timeout, only from the menu and
## only when the panel is opened. Results are cached per hash/difficulty/mode for the session;
## a transport failure is not cached, so the player can retry by reopening the panel.

const Api := preload("res://game/ui/BeatLeaderPanel/BeatLeaderApi.gd")
const ROW_COUNT := 10

## Emitted after Close hides this panel's canvas; the game restores the main menu.
signal closed

# Column widths, shared by the header and every row so the table reads as a table.
const COLUMNS: Array[int] = [80, 300, 150, 120, 110, 110]
const HEADERS: Array[String] = ["Rank", "Player", "Score", "Accuracy", "PP", "Mods"]

@onready var _title := $Margin/VBox/Title as Label
@onready var _song_info := $Margin/VBox/SongInfo as Label
@onready var _status := $Margin/VBox/Status as Label
@onready var _rows := $Margin/VBox/Rows as VBoxContainer
@onready var _exit_button := $Margin/VBox/Exit_Button as Button

var _http: HTTPRequest
var _cache: Dictionary = {}
var _token := 0
var _row_labels: Array[Array] = []
var _map: MapInfo
var _diff: DifficultyInfo
## Last failure reason, for the device probe and support. Empty after a successful render.
var last_error := ""

func _ready() -> void:
	UI_AudioEngine.attach_children(self)
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_exit_button.pressed.connect(_on_exit_pressed)
	_rows.add_child(_make_row(HEADERS, Color(0.65, 0.65, 0.65, 1.0), true))
	for _i in ROW_COUNT:
		var row := _make_row(["", "", "", "", "", ""], Color.WHITE, false)
		_rows.add_child(row)
		_row_labels.append(_row_label_array(row))

## Opens the board for `map_info` at `diff`. Safe to call repeatedly: the cache answers an
## already-resolved board without a request, and a new map cancels the one in flight.
func open(map_info: MapInfo, diff: DifficultyInfo) -> void:
	_map = map_info
	_diff = diff
	_token += 1
	if _http != null:
		_http.cancel_request()
	_clear_rows()
	_title.text = "BeatLeader"
	last_error = ""
	if map_info == null:
		_song_info.text = ""
		_set_status("No map selected.")
		return
	_song_info.text = "%s - %s" % [map_info.song_name, map_info.song_author_name]
	if diff == null:
		_set_status("No difficulty selected.")
		return
	if map_info.level_hash.is_empty():
		_set_status(
			"This map has no BeatSaver hash, so BeatLeader cannot identify it.\n" +
			"Download it again from BeatSaver to get leaderboards.")
		return
	var mode := Api.mode_for_characteristic(diff.characteristic)
	if mode.is_empty():
		_set_status("BeatLeader has no leaderboard for the %s characteristic." % diff.characteristic)
		return

	var key := _cache_key(map_info.level_hash, diff.difficulty, mode)
	if _cache.has(key):
		_apply(_cache[key])
		return
	_fetch(key, map_info.level_hash, diff.difficulty, mode)

func _fetch(key: String, hash: String, difficulty: String, mode: String) -> void:
	var token := _token
	_set_status("Loading top %d scores..." % Api.TOP_COUNT)

	var board_res := await _http_get(Api.board_url(hash, difficulty, mode))
	if token != _token:
		return
	if not bool(board_res["ok"]):
		last_error = "board_transport"
		_set_status("Could not reach BeatLeader. Check the connection and try again.")
		return
	if int(board_res["code"]) == 404:
		_finish(key, {"status": Api.STATUS_NOT_FOUND})
		return
	if int(board_res["code"]) != 200:
		last_error = "board_http_%d" % int(board_res["code"])
		_set_status("BeatLeader returned HTTP %d." % int(board_res["code"]))
		return
	# Parse here, in the panel's instance context: the API's static path was observed returning
	# null for this valid body in the Android export (cause unconfirmed).
	var board_body := (board_res["body"] as PackedByteArray).get_string_from_utf8()
	var board := Api.parse_board_value(JSON.parse_string(board_body))
	if not bool(board.get("ok", false)):
		last_error = "board_parse_%s" % str(board.get("error", ""))
		_set_status("Could not read BeatLeader's board response.")
		return

	var scores_res := await _http_get(Api.scores_url(str(board["id"])))
	if token != _token:
		return
	if not bool(scores_res["ok"]):
		last_error = "scores_transport"
		_set_status("Could not reach BeatLeader. Check the connection and try again.")
		return
	if int(scores_res["code"]) == 404:
		_finish(key, {"status": Api.STATUS_NOT_FOUND})
		return
	if int(scores_res["code"]) != 200:
		_set_status("BeatLeader returned HTTP %d." % int(scores_res["code"]))
		return
	var scores_body := (scores_res["body"] as PackedByteArray).get_string_from_utf8()
	var parsed := Api.parse_scores_value(JSON.parse_string(scores_body))
	if not bool(parsed.get("ok", false)):
		last_error = "scores_parse_%s" % str(parsed.get("error", ""))
		_set_status("Could not read BeatLeader's scores response.")
		return
	var rows: Array = parsed.get("scores", [])
	if rows.is_empty():
		_finish(key, {"status": Api.STATUS_NO_SCORES})
		return
	_finish(key, {
		"status": Api.STATUS_OK,
		"rows": rows,
		"song": str(board.get("song_name", "")),
		"author": str(board.get("song_author", "")),
		"difficulty": str(board.get("difficulty", difficulty)),
		"mode": str(board.get("mode", mode)),
	})

func _finish(key: String, result: Dictionary) -> void:
	_cache[key] = result
	_apply(result)

func _apply(result: Dictionary) -> void:
	var status := str(result.get("status", Api.STATUS_OFFLINE))
	vr.log_info("BEATLEADER result %s" % status)
	match status:
		Api.STATUS_NOT_FOUND:
			_set_status("BeatLeader has no leaderboard for this map and difficulty.")
		Api.STATUS_NO_SCORES:
			_set_status("No scores on BeatLeader for this difficulty yet.")
		Api.STATUS_OK:
			var rows: Array = result.get("rows", [])
			var song := str(result.get("song", ""))
			if not song.is_empty():
				_song_info.text = "%s - %s" % [song, str(result.get("author", ""))]
			_title.text = "BeatLeader - %s / %s" % [
				str(result.get("difficulty", "")), str(result.get("mode", ""))]
			_status.text = "Top %d of %d shown." % [mini(rows.size(), ROW_COUNT), rows.size()]
			_fill_rows(rows)
		_:
			_set_status("Could not reach BeatLeader. Check the connection and try again.")
	_refresh()

func _set_status(text: String) -> void:
	_clear_rows()
	_status.text = text
	_refresh()

func _fill_rows(rows: Array) -> void:
	for i in _row_labels.size():
		var labels := _row_labels[i]
		var visible := i < rows.size()
		(labels[0].get_parent() as Control).visible = visible
		if not visible:
			continue
		var r: Dictionary = rows[i]
		var rank := int(r.get("rank", 0))
		labels[0].text = str(rank) if rank > 0 else "-"
		labels[1].text = str(r.get("player", "Unknown"))
		labels[2].text = str(int(r.get("score", 0)))
		labels[3].text = Api.format_accuracy(float(r.get("accuracy", 0.0)))
		labels[4].text = Api.format_pp(float(r.get("pp", 0.0)))
		labels[5].text = str(r.get("modifiers", "-"))

func _clear_rows() -> void:
	for labels in _row_labels:
		(labels[0].get_parent() as Control).visible = false

func _on_exit_pressed() -> void:
	_token += 1
	if _http != null:
		_http.cancel_request()
	var node: Node = self
	while node != null:
		if node is OQ_UI2DCanvas:
			(node as OQ_UI2DCanvas)._hide()
			break
		node = node.get_parent()
	closed.emit()

func _cache_key(hash: String, difficulty: String, mode: String) -> String:
	return "%s|%s|%s" % [hash.strip_edges().to_lower(), difficulty, mode]

## One HTTP round trip. `ok` is false only for transport failures; HTTP status is left for the
## caller so 404 (no board) and 5xx (server/offline) stay distinct.
func _http_get(url: String) -> Dictionary:
	vr.log_info("BEATLEADER GET %s" % url)
	var err := _http.request(url, PackedStringArray(["User-Agent: " + Api.USER_AGENT]))
	if err != OK:
		return {"ok": false, "code": 0, "body": PackedByteArray()}
	var res: Array = await _http.request_completed
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "code": int(res[1]), "body": PackedByteArray()}
	return {"ok": true, "code": int(res[1]), "body": res[3] as PackedByteArray}

func _make_row(texts: Array, color: Color, header: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size = Vector2(0, 32 if header else 34)
	var labels: Array[Label] = []
	for i in texts.size():
		var label := Label.new()
		label.text = str(texts[i])
		label.custom_minimum_size = Vector2(float(COLUMNS[i]), 0)
		label.add_theme_font_size_override("font_size", 18 if header else 20)
		label.add_theme_color_override("font_color", color)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.clip_text = true
		# Numbers read against the right edge; names against the left.
		if i != 1:
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(label)
		labels.append(label)
	return row

func _row_label_array(row: HBoxContainer) -> Array:
	var out: Array = []
	for child in row.get_children():
		out.append(child as Label)
	return out

func _refresh() -> void:
	var refresh := CanvasRefresh.of(self)
	if refresh != null:
		refresh.request()
