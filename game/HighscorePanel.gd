extends Panel
class_name HighscorePanel

## Local scores plus the read-only BeatLeader board in one panel (specs/028 FR-004..006).
##
## The left world-space panel is the one the player already sees beside the menu; the separate
## BeatLeader sign that used to sit on top of it is gone. The BeatLeader tab loads lazily: opening
## the tab or pressing the menu's Leaderboard button fetches, changing the selection only marks the
## board stale, and a token drops any response for a map that is no longer selected.

signal close()

const Api := preload("res://game/ui/BeatLeaderPanel/BeatLeaderApi.gd")
const BL_COLUMNS: Array[int] = [70, 280, 150, 110, 90]
const BL_HEADERS: Array[String] = ["Rank", "Player", "Score", "Acc", "PP"]
const BL_ROWS := 10

@export var show_close_button := true
@export var show_song_info := true

# keep a copy of the base row for regeneration later
@onready var _base_row = $Margin/VBox/LeftRight/ScrollContainer/Margin/HighscoresList/BaseRecordRow.duplicate()
@onready var _highscore_list = $Margin/VBox/LeftRight/ScrollContainer/Margin/HighscoresList
@onready var _title = $Margin/VBox/Title
@onready var _song_info = $Margin/VBox/LeftRight/VBox/SongInfo_Label
@onready var _exit_button = $Margin/VBox/Exit_Button
@onready var _song_info_panel = $Margin/VBox/LeftRight/VBox
@onready var _local_page = $Margin/VBox/LeftRight

var _map: MapInfo
var _diff: DifficultyInfo
var _diff_rank := 0
var _tab := 0

var _tabs: HBoxContainer
var _local_button: Button
var _bl_button: Button
var _bl_page: VBoxContainer
var _bl_title: Label
var _bl_status: Label
var _bl_rows: VBoxContainer
var _bl_row_labels: Array[Array] = []

var _http: HTTPRequest
var _cache: Dictionary = {}
var _token := 0

func _ready() -> void:
	_clear_list()
	_exit_button.visible = show_close_button
	_song_info_panel.visible = show_song_info
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_build_tabs()
	_select_tab(0)

func _build_tabs() -> void:
	var vbox := $Margin/VBox as VBoxContainer
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	_local_button = _make_tab_button("Local")
	_bl_button = _make_tab_button("BeatLeader")
	_tabs.add_child(_local_button)
	_tabs.add_child(_bl_button)
	vbox.add_child(_tabs)
	vbox.move_child(_tabs, 1)

	_bl_page = VBoxContainer.new()
	_bl_page.visible = false
	_bl_page.size_flags_vertical = 3
	_bl_page.add_theme_constant_override("separation", 6)
	_bl_title = Label.new()
	_bl_title.text = "BeatLeader"
	_bl_title.add_theme_font_size_override("font_size", 24)
	_bl_page.add_child(_bl_title)
	_bl_status = Label.new()
	_bl_status.add_theme_font_size_override("font_size", 18)
	_bl_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bl_page.add_child(_bl_status)
	_bl_rows = VBoxContainer.new()
	_bl_rows.size_flags_vertical = 3
	_bl_page.add_child(_bl_rows)
	_bl_rows.add_child(_make_bl_row(BL_HEADERS, Color(0.65, 0.65, 0.65, 1.0), true))
	for _i in BL_ROWS:
		var row := _make_bl_row(["", "", "", "", ""], Color.WHITE, false)
		_bl_rows.add_child(row)
		var labels: Array = []
		for child in row.get_children():
			labels.append(child as Label)
		_bl_row_labels.append(labels)
	vbox.add_child(_bl_page)

func _make_tab_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(160, 34)
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(_select_tab.bind(0 if text == "Local" else 1))
	return button

func _select_tab(index: int) -> void:
	_tab = clampi(index, 0, 1)
	if _local_button != null:
		_local_button.button_pressed = _tab == 0
	if _bl_button != null:
		_bl_button.button_pressed = _tab == 1
	_local_page.visible = _tab == 0
	if _bl_page != null:
		_bl_page.visible = _tab == 1
	if _tab == 1:
		_load_beatleader()
	_refresh()

func load_highscores(map_info: MapInfo, diff_rank: int):
	var same_selection := (map_info == _map and _diff != null and _diff.difficulty_rank == diff_rank)
	_map = map_info
	_diff_rank = diff_rank
	if not same_selection:
		_diff = null
		if map_info != null:
			for beat_map in map_info.difficulty_beatmaps:
				if beat_map.difficulty_rank == diff_rank:
					_diff = beat_map
					break

	# clear the high score list
	_clear_list()

	# populate title text
	set_title("Highscores (%s)" % _get_difficulty_name(map_info,diff_rank))

	# populate song info
	_song_info.text = """Artist: %s
		Song: %s
		Map Author: %s""" % [map_info.song_author_name, map_info.song_name, map_info.level_author_name]

	var records := Highscores.get_records(map_info,diff_rank)
	var idx = 1
	for record in records:
		# build a new row and populate fields from record
		var new_row = _base_row.duplicate()
		new_row.get_child(0).text = "%d." % idx
		new_row.get_child(1).text = record.player_name
		new_row.get_child(2).text = str(record.score)

		_highscore_list.add_child(new_row)
		idx += 1

	if _tab == 1:
		if same_selection:
			# Same map/difficulty: the cached board is still valid, so show it.
			_load_beatleader()
		else:
			# A selection change is not a request: drop any board in flight and ask for a
			# deliberate press so browsing the library does not hammer BeatLeader.
			_token += 1
			if _http != null:
				_http.cancel_request()
			_clear_bl_rows()
			_bl_title.text = "BeatLeader"
			_bl_status.text = "Map changed - press Leaderboard to load this board."
	_refresh()

func show_local() -> void:
	_select_tab(0)

## The menu's Leaderboard button: show the tab and fetch the current selection.
func show_beatleader(map_info: MapInfo, diff: DifficultyInfo) -> void:
	_map = map_info
	_diff = diff
	if map_info != null and diff != null:
		_diff_rank = diff.difficulty_rank
	_select_tab(1)

func set_title(title_text):
	_title.text = title_text

# clears all rows from the highscore table
func _clear_list():
	for c in _highscore_list.get_children():
		c.queue_free()

func _get_difficulty_name(map_info: MapInfo, diff_rank: int) -> String:
	for beat_map in map_info.difficulty_beatmaps:
		if beat_map.difficulty_rank == diff_rank:
			return beat_map.difficulty
	return 'Rank %s' % diff_rank

func _on_Exit_Button_pressed() -> void:
	close.emit()

# --- BeatLeader tab -----------------------------------------------------------------------

func _load_beatleader() -> void:
	_token += 1
	if _http != null:
		_http.cancel_request()
	_clear_bl_rows()
	_bl_title.text = "BeatLeader"
	if _map == null:
		_bl_status.text = "No map selected."
		_refresh()
		return
	if _diff == null:
		_bl_status.text = "No difficulty selected."
		_refresh()
		return
	if _map.level_hash.is_empty():
		_bl_status.text = "This map has no BeatSaver hash, so BeatLeader cannot identify it."
		_refresh()
		return
	var mode := Api.mode_for_characteristic(_diff.characteristic)
	if mode.is_empty():
		_bl_status.text = "BeatLeader has no board for the %s characteristic." % _diff.characteristic
		_refresh()
		return
	var key := _cache_key(_map.level_hash, _diff.difficulty, mode)
	if _cache.has(key):
		_apply_bl(_cache[key])
		return
	_fetch_bl(key, _map.level_hash, _diff.difficulty, mode)

func _fetch_bl(key: String, hash: String, difficulty: String, mode: String) -> void:
	var token := _token
	_bl_status.text = "Loading top %d scores..." % Api.TOP_COUNT
	_refresh()

	var board_res := await _http_get(Api.board_url(hash, difficulty, mode))
	if token != _token:
		return
	if not bool(board_res["ok"]):
		_bl_status.text = "Could not reach BeatLeader. Check the connection."
		_refresh()
		return
	if int(board_res["code"]) == 404:
		_finish_bl(key, {"status": Api.STATUS_NOT_FOUND})
		return
	if int(board_res["code"]) != 200:
		_bl_status.text = "BeatLeader returned HTTP %d." % int(board_res["code"])
		_refresh()
		return
	var board_body := (board_res["body"] as PackedByteArray).get_string_from_utf8()
	var board := Api.parse_board_value(JSON.parse_string(board_body))
	if not bool(board.get("ok", false)):
		_bl_status.text = "Could not read BeatLeader's board response."
		_refresh()
		return

	var scores_res := await _http_get(Api.scores_url(str(board["id"])))
	if token != _token:
		return
	if not bool(scores_res["ok"]):
		_bl_status.text = "Could not reach BeatLeader. Check the connection."
		_refresh()
		return
	if int(scores_res["code"]) == 404:
		_finish_bl(key, {"status": Api.STATUS_NOT_FOUND})
		return
	if int(scores_res["code"]) != 200:
		_bl_status.text = "BeatLeader returned HTTP %d." % int(scores_res["code"])
		_refresh()
		return
	var scores_body := (scores_res["body"] as PackedByteArray).get_string_from_utf8()
	var parsed := Api.parse_scores_value(JSON.parse_string(scores_body))
	if not bool(parsed.get("ok", false)):
		_bl_status.text = "Could not read BeatLeader's scores response."
		_refresh()
		return
	var rows: Array = parsed.get("scores", [])
	if rows.is_empty():
		_finish_bl(key, {"status": Api.STATUS_NO_SCORES})
		return
	_finish_bl(key, {
		"status": Api.STATUS_OK,
		"rows": rows,
		"song": str(board.get("song_name", "")),
		"author": str(board.get("song_author", "")),
		"difficulty": str(board.get("difficulty", difficulty)),
		"mode": str(board.get("mode", mode)),
	})

func _finish_bl(key: String, result: Dictionary) -> void:
	_cache[key] = result
	_apply_bl(result)
	if _tab != 1:
		_refresh()

func _apply_bl(result: Dictionary) -> void:
	var status := str(result.get("status", Api.STATUS_OFFLINE))
	match status:
		Api.STATUS_NOT_FOUND:
			_bl_title.text = "BeatLeader"
			_bl_status.text = "BeatLeader has no leaderboard for this map and difficulty."
			_clear_bl_rows()
		Api.STATUS_NO_SCORES:
			_bl_title.text = "BeatLeader"
			_bl_status.text = "No scores on BeatLeader for this difficulty yet."
			_clear_bl_rows()
		Api.STATUS_OK:
			_bl_title.text = "BeatLeader - %s / %s" % [
				str(result.get("difficulty", "")), str(result.get("mode", ""))]
			_bl_status.text = "Top %d of %d shown." % [mini((result.get("rows", []) as Array).size(), BL_ROWS),
				(result.get("rows", []) as Array).size()]
			_fill_bl_rows(result.get("rows", []))
			var song := str(result.get("song", ""))
			if not song.is_empty():
				_bl_title.tooltip_text = "%s - %s" % [song, str(result.get("author", ""))]
		_:
			_bl_title.text = "BeatLeader"
			_bl_status.text = "Could not reach BeatLeader. Check the connection."
			_clear_bl_rows()
	_refresh()

func _fill_bl_rows(rows: Array) -> void:
	_clear_bl_rows()
	for i in _bl_row_labels.size():
		if i >= rows.size():
			break
		var labels := _bl_row_labels[i]
		var r: Dictionary = rows[i]
		(labels[0].get_parent() as Control).visible = true
		var rank := int(r.get("rank", 0))
		labels[0].text = str(rank) if rank > 0 else "-"
		labels[1].text = str(r.get("player", "Unknown"))
		labels[2].text = str(int(r.get("score", 0)))
		labels[3].text = Api.format_accuracy(float(r.get("accuracy", 0.0)))
		labels[4].text = Api.format_pp(float(r.get("pp", 0.0)))

func _clear_bl_rows() -> void:
	for labels in _bl_row_labels:
		(labels[0].get_parent() as Control).visible = false

func _make_bl_row(texts: Array, color: Color, header: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size = Vector2(0, 26 if header else 28)
	var labels: Array[Label] = []
	for i in texts.size():
		var label := Label.new()
		label.text = str(texts[i])
		label.custom_minimum_size = Vector2(float(BL_COLUMNS[i]), 0)
		label.add_theme_font_size_override("font_size", 16 if header else 18)
		label.add_theme_color_override("font_color", color)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.clip_text = true
		if i != 1:
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(label)
		labels.append(label)
	return row

func _cache_key(hash: String, difficulty: String, mode: String) -> String:
	return "%s|%s|%s" % [hash.strip_edges().to_lower(), difficulty, mode]

func _http_get(url: String) -> Dictionary:
	var err := _http.request(url, PackedStringArray(["User-Agent: " + Api.USER_AGENT]))
	if err != OK:
		return {"ok": false, "code": 0, "body": PackedByteArray()}
	var res: Array = await _http.request_completed
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "code": int(res[1]), "body": PackedByteArray()}
	return {"ok": true, "code": int(res[1]), "body": res[3] as PackedByteArray}

func _refresh() -> void:
	var refresh := CanvasRefresh.of(self)
	if refresh != null:
		refresh.request()
