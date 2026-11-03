extends Panel
class_name BeatSaverPanel

## The in-VR BeatSaver browser, rebuilt on `https://api.beatsaver.com/search/text/{page}`.
##
## Contract: `specs/005-beatsaver-browser/spec.md`; API: `specs/003-beatsaver-api-research/`.
## Kept from the old panel: the OQ_UI2D canvas hiding, the details pane with preview audio, the
## download/unzip path and the entry points `MapDownloadPanel` and `BeepSaberMainMenu` use.

const BeatSaverApi := preload("res://game/ui/BeatSaverPanel/BeatSaverApi.gd")
const BeatSaverCoversScript := preload("res://game/ui/BeatSaverPanel/BeatSaverCovers.gd")
const MapCardScript := preload("res://game/ui/BeatSaverPanel/BeatSaverMapCard.gd")
const HTTP_REQUEST_POOL := preload("res://game/scripts/HTTPRequestPool.tscn")
const VR_SLIDER := preload("res://game/vr_slider.tscn")
const PLACEHOLDER_COVER := preload("res://game/data/beepsaber_logo.png")

## Must match BeatSaverApi.PAGE_SIZE (kept as a literal so it is a compile-time constant here).
const PAGE_SIZE := 20
## Client-side filters can thin a server page out; keep fetching until the display page is full
## (reference 3.3), but never spend more than this many server pages on one display page.
const MAX_SERVER_PAGES_PER_PAGE := 4
const SEARCH_DEBOUNCE_SECONDS := 0.4
const SETTINGS_SAVE_DELAY := 1.0
const MAX_HISTORY := 10

const DURATION_LABELS: Array[String] = ["Any length", "<2 min", "2-4 min", "4+ min"]
const DURATION_MIN: Array[int] = [-1, -1, 120, 241]
const DURATION_MAX: Array[int] = [-1, 119, 240, -1]
const NPS_LABELS: Array[String] = ["Any NPS", "Slow <4", "4-7 NPS", "7-10 NPS", "10+ NPS"]
const NPS_MIN: Array[float] = [-1.0, -1.0, 4.0, 7.0, 10.0]
const NPS_MAX: Array[float] = [-1.0, 4.0, 7.0, 10.0, -1.0]
const SORT_WITH_QUERY: Array[String] = ["Latest", "Rating", "Curated", "Relevance"]
const SORT_WITHOUT_QUERY: Array[String] = ["Latest", "Rating", "Curated"]

const CHAR_TAG_NAMES := {
	"OneSaber": "1S",
	"90Degree": "90",
	"360Degree": "360",
	"NoArrows": "NA",
	"Lightshow": "LS",
}

# Settings keys (FR-011). Declared as literals so Settings.gd and this file cannot drift apart
# silently - `tools/tests/beatsaver_browser_test.gd` asserts they exist in Settings.default_values.
const SETTING_ORDER := "beatsaver_order"
const SETTING_CURATED := "beatsaver_curated"
const SETTING_VERIFIED := "beatsaver_verified"
const SETTING_RANKED := "beatsaver_ranked"
const SETTING_PLAYABLE := "beatsaver_playable_only"
const SETTING_DURATION := "beatsaver_duration"
const SETTING_NPS := "beatsaver_nps"
const SETTING_DIFFICULTIES := "beatsaver_difficulties"

# reference to the main main node (used for playing downloadable song previews)
@export var main_menu_ref: MainMenu
@export var keyboard: OQ_UI2DKeyboard

# --- query and paging state ---
var _query := {}
var _seq := 0
var _loading := false
var _error_message := ""
# Rows currently on screen, and the rows being assembled for the next page. Kept apart so a
# failed page leaves the previous page on screen (spec edge case).
var _rows: Array = []
var _rejected := 0
var _pending_rows: Array = []
var _pending_rejected := 0
var _pending_docs_seen := 0
var _page_index := 0
var _page_starts: Array = []
var _cursor_page := 0
var _cursor_doc := 0
var _served_pages := 0
var _exhausted := true
var _has_more := false
var _total := 0
var _cached_server_page := -1
var _cached_docs: Array = []
var _prefetch_url := ""
var _selected_index := -1
var _history: Array = []
var _download_queue := []

# --- runtime nodes ---
var _covers: Node
var _search_pool: Node
var _prefetch_pool: Node
var _preview_request: HTTPRequest
var _download_request: HTTPRequest
var _debounce: Timer
var _save_timer: Timer

# --- ui ---
var _search_button: Button
var _query_label: Label
var _sort_button: Button
var _back_button: Button
var _prev_button: Button
var _next_button: Button
var _page_label: Label
var _curated_toggle: Button
var _verified_toggle: Button
var _ranked_toggle: Button
var _playable_toggle: Button
var _duration_button: Button
var _nps_button: Button
var _difficulty_toggles: Array[Button] = []
var _scroll: ScrollContainer
var _card_list: VBoxContainer
var _cards: Array = []
var _status_label: Label
var _retry_button: Button
var _details_cover: TextureRect
var _song_data: RichTextLabel
var _download_button: Button
var _maps_by_button: Button
var _status_bar: Label

var _is_first_show := true


func _ready() -> void:
	_build_ui()
	_build_runtime_nodes()
	_load_query_from_settings()
	_update_controls()
	UI_AudioEngine.attach_children(self)

	var canvas := _find_canvas()
	if canvas != null:
		canvas.visibility_changed.connect(_on_visibility_changed)

	if keyboard != null:
		# The keyboard's TextEdit (and its `text_changed`) only exists once that node is ready.
		await keyboard.ready
		keyboard.text_input_enter.connect(_on_text_enter)
		keyboard.text_input_cancel.connect(_on_text_cancel)
		keyboard._text_edit.text_changed.connect(_on_text_changed)


# --- OQ_UI2D plumbing (unchanged behaviour) ----------------------------------------------------

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


# override hide() method to handle case where UI is inside a OQ_UI2DCanvas
func _hide() -> void:
	var canvas := _find_canvas()
	if canvas != null:
		canvas.hide()
	else:
		visible = false
	if keyboard != null:
		keyboard._hide()


# override show() method to handle case where UI is inside a OQ_UI2DCanvas
func _show() -> void:
	var canvas := _find_canvas()
	if canvas != null:
		canvas.show()
	else:
		visible = true
	if _is_first_show:
		_is_first_show = false
		_new_search()


func _on_visibility_changed() -> void:
	if _is_first_show and is_visible_in_tree():
		_is_first_show = false
		_new_search()


# --- UI construction ---------------------------------------------------------------------------

func _build_ui() -> void:
	# Row 1: search, sort, history, pager.
	_search_button = _make_button(Rect2(16, 14, 220, 54), "Search maps…")
	_search_button.pressed.connect(_on_search_button_pressed)

	_query_label = _make_label(Rect2(248, 14, 280, 54), "", 18, Color(1, 1, 1, 1))
	_query_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_query_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	_sort_button = _make_button(Rect2(540, 14, 200, 54), "Sort: Latest")
	_sort_button.pressed.connect(_on_sort_pressed)

	_back_button = _make_button(Rect2(752, 14, 100, 54), "Back")
	_back_button.pressed.connect(_on_back_pressed)

	_prev_button = _make_button(Rect2(864, 14, 80, 54), "<")
	_prev_button.pressed.connect(_on_prev_pressed)

	_page_label = _make_label(Rect2(952, 14, 224, 54), "Page 1", 18, Color(1, 1, 1, 1))
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_next_button = _make_button(Rect2(1184, 14, 80, 54), ">")
	_next_button.pressed.connect(_on_next_pressed)

	var source_label := _make_label(Rect2(1280, 14, 240, 54), "From beatsaver.com", 16, Color(0.75, 0.75, 0.75, 1))
	source_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	source_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Row 2: server-side filters.
	_curated_toggle = _make_toggle(Rect2(16, 76, 180, 54), "Curated")
	_curated_toggle.toggled.connect(_on_filter_toggled)
	_verified_toggle = _make_toggle(Rect2(204, 76, 180, 54), "Verified")
	_verified_toggle.toggled.connect(_on_filter_toggled)
	_ranked_toggle = _make_toggle(Rect2(392, 76, 180, 54), "Ranked")
	_ranked_toggle.toggled.connect(_on_filter_toggled)
	_playable_toggle = _make_toggle(Rect2(580, 76, 220, 54), "Playable only")
	_playable_toggle.toggled.connect(_on_filter_toggled)

	_duration_button = _make_button(Rect2(812, 76, 232, 54), "Length: Any")
	_duration_button.pressed.connect(_on_duration_pressed)
	_nps_button = _make_button(Rect2(1052, 76, 232, 54), "NPS: Any")
	_nps_button.pressed.connect(_on_nps_pressed)

	# Row 3: client-side difficulty chips + status.
	var diff_label := _make_label(Rect2(16, 138, 124, 54), "Difficulty", 18, Color(0.85, 0.85, 0.85, 1))
	diff_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	for i in BeatSaverApi.DIFFICULTIES.size():
		var chip := _make_toggle(Rect2(144 + i * 88, 138, 80, 54), BeatSaverApi.DIFFICULTY_SHORT[i])
		chip.toggled.connect(_on_difficulty_toggled)
		_difficulty_toggles.append(chip)

	_status_label = _make_label(Rect2(600, 138, 776, 54), "", 16, Color(0.8, 0.8, 0.8, 1))
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	_retry_button = _make_button(Rect2(1392, 138, 120, 54), "Retry")
	_retry_button.pressed.connect(_on_retry_pressed)
	_retry_button.visible = false

	# Cards.
	_scroll = ScrollContainer.new()
	_scroll.name = "CardsScroll"
	_scroll.position = Vector2(16, 204)
	_scroll.size = Vector2(864, 636)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_scroll)

	_card_list = VBoxContainer.new()
	_card_list.name = "CardList"
	_card_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_list.add_theme_constant_override("separation", 8)
	_scroll.add_child(_card_list)

	for i in PAGE_SIZE:
		var card = MapCardScript.new()
		card.name = "MapCard%d" % i
		card.visible = false
		_card_list.add_child(card)
		card.pressed.connect(_on_card_pressed.bind(i))
		_cards.append(card)

	# Details pane.
	_details_cover = TextureRect.new()
	_details_cover.position = Vector2(904, 204)
	_details_cover.size = Vector2(616, 264)
	_details_cover.texture = PLACEHOLDER_COVER
	_details_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_details_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_details_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_details_cover)

	_song_data = RichTextLabel.new()
	_song_data.name = "SongData"
	_song_data.position = Vector2(904, 478)
	_song_data.size = Vector2(616, 308)
	_song_data.bbcode_enabled = true
	_song_data.scroll_active = false
	_song_data.text = "Select a map to see the details.\n\nPress Download to add it to your library."
	add_child(_song_data)

	_download_button = _make_button(Rect2(904, 796, 296, 56), "Download")
	_download_button.pressed.connect(_on_download_pressed)

	_maps_by_button = _make_button(Rect2(1216, 796, 304, 56), "Maps by…")
	_maps_by_button.pressed.connect(_on_maps_by_pressed)
	_maps_by_button.disabled = true

	_status_bar = _make_label(Rect2(16, 868, 1264, 60), "", 16, Color(0.9, 0.9, 0.9, 1))
	_status_bar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var close_button := _make_button(Rect2(1312, 868, 208, 60), "Close")
	close_button.pressed.connect(_hide)

	# The existing thumbstick / drag scroller, pointed at the new list. Guarded: the panel
	# rebuilds its UI on some setting changes, and a second slider would double the stick speed.
	if not has_node("list_slider"):
		var slider := VR_SLIDER.instantiate()
		slider.name = "list_slider"
		slider.scroll_node_path = NodePath("../CardsScroll")
		add_child(slider)


func _make_button(rect: Rect2, text: String) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.text = text
	button.clip_text = true
	add_child(button)
	return button


func _make_toggle(rect: Rect2, text: String) -> Button:
	var button := _make_button(rect, text)
	button.toggle_mode = true
	var on := StyleBoxFlat.new()
	on.bg_color = Color(1, 1, 1, 1)
	on.border_color = Color(1, 1, 1, 1)
	on.set_border_width_all(5)
	button.add_theme_stylebox_override("pressed", on)
	button.add_theme_stylebox_override("hover_pressed", on)
	button.add_theme_color_override("font_pressed_color", Color(0.04, 0.04, 0.04, 1))
	button.add_theme_color_override("font_hover_pressed_color", Color(0.04, 0.04, 0.04, 1))
	return button


func _make_label(rect: Rect2, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _build_runtime_nodes() -> void:
	_search_pool = _make_pool("SearchRequestPool", 1, _on_search_complete)
	_prefetch_pool = _make_pool("PrefetchRequestPool", 1, _on_prefetch_complete)

	_preview_request = HTTPRequest.new()
	_preview_request.name = "PreviewRequest"
	_preview_request.timeout = 8.0
	add_child(_preview_request)
	_preview_request.request_completed.connect(_on_preview_completed)

	_download_request = HTTPRequest.new()
	_download_request.name = "DownloadRequest"
	_download_request.timeout = 0.0
	add_child(_download_request)
	_download_request.request_completed.connect(_on_download_completed)

	_covers = BeatSaverCoversScript.new()
	_covers.name = "CoverLoader"
	add_child(_covers)

	_debounce = Timer.new()
	_debounce.name = "SearchDebounce"
	_debounce.one_shot = true
	_debounce.wait_time = SEARCH_DEBOUNCE_SECONDS
	add_child(_debounce)
	_debounce.timeout.connect(_on_debounce_timeout)

	_save_timer = Timer.new()
	_save_timer.name = "SettingsSaveTimer"
	_save_timer.one_shot = true
	_save_timer.wait_time = SETTINGS_SAVE_DELAY
	add_child(_save_timer)
	_save_timer.timeout.connect(_on_settings_save_timeout)


func _make_pool(node_name: String, concurrency: int, handler: Callable) -> Node:
	var pool := HTTP_REQUEST_POOL.instantiate()
	pool.name = node_name
	pool.max_simultaneous_request = concurrency
	pool.request_timeout = 8.0
	pool.default_headers = PackedStringArray(["User-Agent: " + BeatSaverApi.USER_AGENT])
	add_child(pool)
	pool.request_complete.connect(handler)
	return pool


# --- settings ----------------------------------------------------------------------------------

func _load_query_from_settings() -> void:
	var order := String(Settings.beatsaver_order)
	if not BeatSaverApi.ORDERS.has(order) or order == "Relevance":
		# Relevance needs a query; never start in it (FR-003).
		order = BeatSaverApi.DEFAULT_ORDER
	_query = {
		"q": "",
		"order": order,
		"curated": bool(Settings.beatsaver_curated),
		"verified": bool(Settings.beatsaver_verified),
		"ranked": bool(Settings.beatsaver_ranked),
		"playable_only": bool(Settings.beatsaver_playable_only),
		"duration_index": clampi(int(Settings.beatsaver_duration), 0, DURATION_LABELS.size() - 1),
		"nps_index": clampi(int(Settings.beatsaver_nps), 0, NPS_LABELS.size() - 1),
		"difficulties": _parse_difficulties(String(Settings.beatsaver_difficulties)),
		"min_duration": -1,
		"max_duration": -1,
		"min_nps": -1.0,
		"max_nps": -1.0,
	}
	_apply_preset_bounds()


func _apply_preset_bounds() -> void:
	var duration_index: int = clampi(int(_query.get("duration_index", 0)), 0, DURATION_LABELS.size() - 1)
	var nps_index: int = clampi(int(_query.get("nps_index", 0)), 0, NPS_LABELS.size() - 1)
	_query["min_duration"] = DURATION_MIN[duration_index]
	_query["max_duration"] = DURATION_MAX[duration_index]
	_query["min_nps"] = NPS_MIN[nps_index]
	_query["max_nps"] = NPS_MAX[nps_index]


func _parse_difficulties(text: String) -> Array:
	var out: Array = []
	if text.strip_edges().is_empty():
		return out
	for part in text.split(",", false):
		var index := int(part)
		if index >= 0 and index < BeatSaverApi.DIFFICULTIES.size():
			out.append(BeatSaverApi.DIFFICULTIES[index])
	return out


func _difficulties_to_setting() -> String:
	var picked: Array = _query.get("difficulties", [])
	var parts: PackedStringArray = PackedStringArray()
	for i in BeatSaverApi.DIFFICULTIES.size():
		if picked.has(BeatSaverApi.DIFFICULTIES[i]):
			parts.append(str(i))
	return ",".join(parts)


## Writes the sort + filter state into Settings and coalesces the file write, so a burst of
## button presses costs at most one config save.
func _save_settings() -> void:
	Settings.beatsaver_order = String(_query.get("order", BeatSaverApi.DEFAULT_ORDER))
	Settings.beatsaver_curated = bool(_query.get("curated", false))
	Settings.beatsaver_verified = bool(_query.get("verified", false))
	Settings.beatsaver_ranked = bool(_query.get("ranked", false))
	Settings.beatsaver_playable_only = bool(_query.get("playable_only", false))
	Settings.beatsaver_duration = int(_query.get("duration_index", 0))
	Settings.beatsaver_nps = int(_query.get("nps_index", 0))
	Settings.beatsaver_difficulties = _difficulties_to_setting()
	_save_timer.start()


func _on_settings_save_timeout() -> void:
	Settings.save()


func _update_controls() -> void:
	_sort_button.text = "Sort: %s" % String(_query.get("order", BeatSaverApi.DEFAULT_ORDER))
	var text := String(_query.get("q", ""))
	_query_label.text = text if not text.is_empty() else "All maps"
	_curated_toggle.set_pressed_no_signal(bool(_query.get("curated", false)))
	_verified_toggle.set_pressed_no_signal(bool(_query.get("verified", false)))
	_ranked_toggle.set_pressed_no_signal(bool(_query.get("ranked", false)))
	_playable_toggle.set_pressed_no_signal(bool(_query.get("playable_only", false)))
	_duration_button.text = "Length: %s" % DURATION_LABELS[int(_query.get("duration_index", 0))]
	_nps_button.text = "NPS: %s" % NPS_LABELS[int(_query.get("nps_index", 0))]
	var picked: Array = _query.get("difficulties", [])
	for i in _difficulty_toggles.size():
		_difficulty_toggles[i].set_pressed_no_signal(picked.has(BeatSaverApi.DIFFICULTIES[i]))
	_back_button.visible = not _history.is_empty()


# --- control handlers ---------------------------------------------------------------------------

func _on_search_button_pressed() -> void:
	if keyboard == null:
		return
	keyboard._show()
	keyboard._text_edit.grab_focus()


func _on_text_changed() -> void:
	# The keyboard clears its TextEdit after Enter/Cancel, which would otherwise fire a second,
	# blank search; only live-type while the keyboard is actually open.
	if keyboard == null or not keyboard.visible:
		return
	_debounce.start()


func _on_debounce_timeout() -> void:
	if keyboard == null:
		return
	_apply_query_text(keyboard._text_edit.text)


func _on_text_enter(text: String) -> void:
	if keyboard != null:
		keyboard._hide()
	_debounce.stop()
	_apply_query_text(text)


func _on_text_cancel() -> void:
	if keyboard != null:
		keyboard._hide()
	_debounce.stop()


func _apply_query_text(text: String) -> void:
	var cleaned := text.strip_edges()
	if cleaned == String(_query.get("q", "")):
		return
	_query["q"] = cleaned
	if cleaned.is_empty() and String(_query.get("order", "")) == "Relevance":
		# Blank query + Relevance is at best a silent Latest, at worst a 500; drop to Latest.
		_query["order"] = BeatSaverApi.DEFAULT_ORDER
	_update_controls()
	_save_settings()
	_new_search()


func _sort_options() -> Array:
	if String(_query.get("q", "")).strip_edges().is_empty():
		return SORT_WITHOUT_QUERY
	return SORT_WITH_QUERY


func _on_sort_pressed() -> void:
	var options := _sort_options()
	var index := options.find(String(_query.get("order", BeatSaverApi.DEFAULT_ORDER)))
	index = (index + 1) % options.size()
	_query["order"] = options[index]
	_update_controls()
	_save_settings()
	_new_search()


func _on_filter_toggled(_pressed: bool) -> void:
	_query["curated"] = _curated_toggle.button_pressed
	_query["verified"] = _verified_toggle.button_pressed
	_query["ranked"] = _ranked_toggle.button_pressed
	_query["playable_only"] = _playable_toggle.button_pressed
	_update_controls()
	_save_settings()
	_new_search()


func _on_difficulty_toggled(_pressed: bool) -> void:
	var picked: Array = []
	for i in _difficulty_toggles.size():
		if _difficulty_toggles[i].button_pressed:
			picked.append(BeatSaverApi.DIFFICULTIES[i])
	_query["difficulties"] = picked
	_update_controls()
	_save_settings()
	_new_search()


func _on_duration_pressed() -> void:
	var index: int = (int(_query.get("duration_index", 0)) + 1) % DURATION_LABELS.size()
	_query["duration_index"] = index
	_apply_preset_bounds()
	_update_controls()
	_save_settings()
	_new_search()


func _on_nps_pressed() -> void:
	var index: int = (int(_query.get("nps_index", 0)) + 1) % NPS_LABELS.size()
	_query["nps_index"] = index
	_apply_preset_bounds()
	_update_controls()
	_save_settings()
	_new_search()


func _on_retry_pressed() -> void:
	_start_display_page(_page_starts[_page_index] if _page_index < _page_starts.size() else {"page": 0, "doc": 0})


func _on_back_pressed() -> void:
	if _history.is_empty():
		return
	_query = _history.pop_back()
	_update_controls()
	_new_search()


func _push_history() -> void:
	_history.append(_query.duplicate(true))
	if _history.size() > MAX_HISTORY:
		_history.pop_front()
	_update_controls()


func _on_prev_pressed() -> void:
	if _loading or _page_index == 0 or _page_starts.is_empty():
		return
	_page_index -= 1
	_page_starts.pop_back()
	_start_display_page(_page_starts[_page_index])
	_canvas_input_update()


func _on_next_pressed() -> void:
	if _loading or not _has_more:
		return
	_page_index += 1
	var cursor := {"page": _cursor_page, "doc": _cursor_doc}
	_page_starts.append(cursor)
	_start_display_page(cursor)
	_canvas_input_update()


# --- browse flow --------------------------------------------------------------------------------

func _new_search() -> void:
	_seq += 1
	_loading = true
	_error_message = ""
	_search_pool.cancel_all()
	_prefetch_pool.cancel_all()
	_prefetch_url = ""
	_cached_server_page = -1
	_cached_docs.clear()
	_page_index = 0
	_page_starts = [{"page": 0, "doc": 0}]
	_rows.clear()
	_rejected = 0
	_total = 0
	_has_more = false
	_selected_index = -1
	_clear_details()
	for card: Variant in _cards:
		card.clear()
	_update_pager()
	_start_display_page({"page": 0, "doc": 0})


func _start_display_page(cursor: Dictionary) -> void:
	_cursor_page = maxi(0, int(cursor.get("page", 0)))
	_cursor_doc = maxi(0, int(cursor.get("doc", 0)))
	_served_pages = 0
	_exhausted = false
	_pending_rows.clear()
	_pending_rejected = 0
	_pending_docs_seen = 0
	_loading = true
	_error_message = ""
	_selected_index = -1
	_update_pager()
	_fetch_chunk(_seq)
	_canvas_input_update()


func _fetch_chunk(seq: int) -> void:
	if seq != _seq:
		return
	if _pending_rows.size() >= PAGE_SIZE or _served_pages >= MAX_SERVER_PAGES_PER_PAGE or _exhausted:
		_finish_page(seq)
		return
	_served_pages += 1
	if _cached_server_page == _cursor_page:
		var cached := _cached_docs
		_on_docs.call_deferred(seq, _cursor_page, cached)
		return
	_search_pool.request(BeatSaverApi.build_search_url(_query, _cursor_page), {"seq": seq, "page": _cursor_page})


func _on_docs(seq: int, page: int, docs: Array) -> void:
	if seq != _seq:
		# Stale: a newer query owns the panel. Drop before parsing or repainting anything.
		return
	if docs.is_empty():
		_exhausted = true
		_finish_page(seq)
		return
	var budget: int = PAGE_SIZE - _pending_rows.size()
	var result := BeatSaverApi.consume_docs(docs, _cursor_doc, _query, budget)
	for row: Variant in result["rows"]:
		_pending_rows.append(row)
	_pending_rejected += int(result["rejected"])
	_pending_docs_seen += docs.size()
	_cursor_doc = int(result["doc"])
	if bool(result["done_with_page"]):
		_cursor_page = page + 1
		_cursor_doc = 0
	_fetch_chunk(seq)


func _finish_page(seq: int) -> void:
	if seq != _seq:
		return
	_loading = false
	_rows = _pending_rows.duplicate()
	_rejected = _pending_rejected
	# Docs were still available when we stopped only if the last server page was not exhausted.
	_has_more = not _exhausted
	_render_rows()
	_update_pager()
	_start_prefetch()
	_canvas_input_update()


func _render_rows() -> void:
	for i in _cards.size():
		var card = _cards[i]
		if i < _rows.size():
			card.set_map(_rows[i], i)
			_covers.request(_rows[i].cover_url, _on_cover_ready.bind(card, _rows[i].cover_url))
		else:
			card.clear()


func _on_cover_ready(texture: Texture2D, card: Variant, url: String) -> void:
	if not is_instance_valid(card):
		return
	card.apply_cover(url, texture)


func _start_prefetch() -> void:
	if not _has_more:
		return
	if _cached_server_page == _cursor_page:
		return
	var url := BeatSaverApi.build_search_url(_query, _cursor_page)
	if url == _prefetch_url:
		return
	_prefetch_url = url
	_prefetch_pool.request(url, {"seq": _seq, "page": _cursor_page})


func _on_prefetch_complete(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, _token: int, user_data: Dictionary) -> void:
	if int(user_data.get("seq", -1)) != _seq:
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var parsed := BeatSaverApi.parse_search(body)
	if not parsed.ok or not parsed.redirect.is_empty():
		return
	_cached_server_page = int(user_data.get("page", -1))
	_cached_docs = parsed.docs
	# Warm the covers for the page the player is about to ask for.
	for doc: Variant in parsed.docs:
		_covers.prefetch(doc.cover_url)


func _on_search_complete(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, _token: int, user_data: Dictionary) -> void:
	var seq := int(user_data.get("seq", -1))
	if seq != _seq:
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail_page("Could not reach BeatSaver. Check the connection and retry.")
		return
	if response_code != 200:
		_fail_page("BeatSaver returned HTTP %d." % response_code)
		return
	if bool(user_data.get("redirect", false)):
		_show_single_map(body)
		return
	var parsed := BeatSaverApi.parse_search(body)
	if not parsed.ok:
		_fail_page(parsed.error)
		return
	if not parsed.redirect.is_empty():
		_open_map_by_id(parsed.redirect)
		return
	var page := int(user_data.get("page", 0))
	_total = parsed.total
	_cached_server_page = page
	_cached_docs = parsed.docs
	_on_docs(seq, page, parsed.docs)
	_canvas_input_update()


## A pasted map key comes back as `{"redirect": "<id>"}` instead of docs (FR-014).
func _open_map_by_id(map_id: String) -> void:
	_seq += 1
	_search_pool.cancel_all()
	_search_pool.request(BeatSaverApi.map_url(map_id), {"seq": _seq, "redirect": true})


func _show_single_map(body: PackedByteArray) -> void:
	var map = BeatSaverApi.parse_map(body)
	if map == null:
		_fail_page("That map key could not be loaded.")
		return
	_loading = false
	_error_message = ""
	_total = 1
	_exhausted = true
	_has_more = false
	_page_index = 0
	_page_starts = [{"page": 0, "doc": 0}]
	_cursor_page = 0
	_cursor_doc = 0
	_rows = [map]
	_rejected = 0
	_pending_docs_seen = 1
	_render_rows()
	_update_pager()
	_on_card_pressed(0)
	_canvas_input_update()


func _fail_page(message: String) -> void:
	_loading = false
	_error_message = message
	# The previous page stays on screen; Retry re-runs the same query.
	_update_pager()
	_canvas_input_update()


func _update_pager() -> void:
	var picked: Array = _query.get("difficulties", [])
	var filtered := bool(_query.get("playable_only", false)) or not picked.is_empty()
	if _loading:
		_page_label.text = "Loading…"
	elif filtered:
		# `total` counts server pages, so "of m" would be a lie while client filters are on.
		_page_label.text = "Page %d" % (_page_index + 1)
	else:
		_page_label.text = "Page %d of %d" % [_page_index + 1, BeatSaverApi.total_pages(_total)]
	_prev_button.disabled = _loading or _page_index == 0
	_next_button.disabled = _loading or not _has_more

	if not _error_message.is_empty():
		_status_label.text = _error_message
		_retry_button.visible = true
		return
	_retry_button.visible = false
	if _loading:
		_status_label.text = "Loading maps…"
		return
	if _rows.is_empty():
		var scope := "these filters" if String(_query.get("q", "")).is_empty() else "\"%s\"" % String(_query.get("q", ""))
		_status_label.text = "No maps matched %s." % scope
		return
	var text := "%d maps" % _rows.size()
	if _rejected > 0:
		text += "  (%d hidden by Playable/Difficulty filters)" % _rejected
	if _pending_docs_seen > _rows.size() and not _has_more:
		text += "  - end of results"
	_status_label.text = text


# --- selection, details and download -----------------------------------------------------------

func _on_card_pressed(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	_selected_index = index
	_show_details(_rows[index])
	_canvas_input_update()


func _clear_details() -> void:
	_song_data.text = "Select a map to see the details.\n\nPress Download to add it to your library."
	_details_cover.texture = PLACEHOLDER_COVER
	_maps_by_button.text = "Maps by…"
	_maps_by_button.disabled = true


func _show_details(map) -> void:
	_details_cover.texture = PLACEHOLDER_COVER
	_covers.request(map.cover_url, _on_details_cover_ready)
	_maps_by_button.text = "Maps by %s" % map.mapper
	_maps_by_button.disabled = map.uploader_name.is_empty() and map.mapper.is_empty()
	_song_data.text = _details_text(map)
	if _preview_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_preview_request.cancel_request()
	if not map.preview_url.is_empty():
		_preview_request.request(map.preview_url, PackedStringArray(["User-Agent: " + BeatSaverApi.USER_AGENT]))


func _on_details_cover_ready(texture: Texture2D) -> void:
	if texture != null:
		_details_cover.texture = texture


func _bb(text: String) -> String:
	return text.replace("[", "[lb]")


func _details_text(map) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[center][b]%s[/b][/center]" % _bb(map.name))
	lines.append("")
	lines.append("Song: %s - %s" % [_bb(map.song_name), _bb(map.song_author)])
	var verified := " (verified mapper)" if map.uploader_verified else ""
	lines.append("Mapper: %s%s" % [_bb(map.mapper), verified])
	lines.append("Length: %s    BPM: %d    Key: %s" % [
		BeatSaverApi.format_duration(map.duration), roundi(map.bpm), map.id])
	if map.upvotes >= 0 and map.downvotes >= 0:
		lines.append("Rating: %s    %d up / %d down" % [
			BeatSaverApi.vote_percent(map), map.upvotes, map.downvotes])
	else:
		lines.append("Rating: %s" % BeatSaverApi.vote_percent(map))

	var mods: Array = map.required_mods()
	if not mods.is_empty():
		lines.append("Requires: %s" % " ".join(PackedStringArray(mods)))
	if map.curated:
		lines.append("Curated by BeatSaver")
	if not map.tags.is_empty():
		var tag_parts: PackedStringArray = PackedStringArray()
		for tag: Variant in map.tags:
			tag_parts.append(String(tag))
		lines.append("Tags: %s" % ", ".join(tag_parts))

	lines.append("")
	lines.append("[b]Difficulties[/b]")
	for diff: Variant in map.diffs:
		var stars := "not ranked"
		if diff.stars > 0.0:
			stars = "%.2f★ ScoreSaber" % diff.stars
		elif diff.bl_stars > 0.0:
			stars = "%.2f★ BeatLeader" % diff.bl_stars
		lines.append("  %s %s   %.1f NPS   %s   %s" % [
			String(diff.characteristic),
			BeatSaverApi.short_difficulty(diff.difficulty),
			diff.nps,
			BeatSaverApi.format_duration(int(diff.seconds)),
			stars,
		])

	if not map.description.strip_edges().is_empty():
		lines.append("")
		lines.append("[center]%s[/center]" % _bb(map.description))
	return "\n".join(lines)


func _on_preview_completed(result: int, _response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and main_menu_ref != null:
		# request preview to be played by the main menu node
		main_menu_ref.play_preview(body, 0, -1, "mp3")


func _on_maps_by_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _rows.size():
		return
	var map = _rows[_selected_index]
	var name: String = map.uploader_name if not map.uploader_name.is_empty() else map.mapper
	if name.is_empty():
		return
	_push_history()
	_query["q"] = "mapper:\"%s\"" % name.replace("\"", "")
	_query["order"] = "Rating"
	_update_controls()
	_save_settings()
	_new_search()


func _on_download_pressed() -> void:
	OS.request_permissions()
	if _selected_index < 0 or _selected_index >= _rows.size():
		return
	var map = _rows[_selected_index]
	if map.download_url.is_empty():
		return
	_download_queue.append([map.name, map.download_url])
	_download_next()


func _download_next() -> void:
	if _download_queue.is_empty():
		return
	_download_request.request(_download_queue[0][1], PackedStringArray(["User-Agent: " + BeatSaverApi.USER_AGENT]))
	_status_bar.text = "Downloading: %s - %d left" % [str(_download_queue[0][0]), _download_queue.size() - 1]


func _on_download_completed(result: int, _response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if body.slice(0, 10) == "<!DOCTYPE html>".to_utf8_buffer().slice(0, 10):
		result = -1
	if result == HTTPRequest.RESULT_SUCCESS:
		var has_error := false
		var tempdir := Constants.APPDATA_PATH + "temp"
		var error := DirAccess.make_dir_recursive_absolute(tempdir)
		if error != OK:
			vr.log_error(
				"_on_download_completed - " +
				"Failed to create temp directory '%s'" % tempdir)
			has_error = true

		# sanitize path separators from song directory name
		var song_dir_name: String = str(_download_queue[0][0]).replace("/", "")

		var zippath := Constants.APPDATA_PATH + "temp/%s.zip" % song_dir_name
		if not has_error:
			var file := FileAccess.open(zippath, FileAccess.WRITE)
			if file:
				file.store_buffer(body)
				file.close()
			else:
				vr.log_file_error(FileAccess.get_open_error(), zippath, "BeatSaverPanel.gd download")
				has_error = true

		var song_out_dir := Constants.APPDATA_PATH + ("Songs/%s/" % song_dir_name)
		if not has_error:
			error = DirAccess.make_dir_recursive_absolute(song_out_dir)
			if error != OK:
				vr.log_error(
					"_on_download_completed - " +
					"Failed to create song output dir '%s'" % song_out_dir)
				has_error = true

		if not has_error:
			Utils.unzip(zippath, song_out_dir)

		DirAccess.remove_absolute(zippath)

		_download_queue.remove_at(0)

		if _download_queue.is_empty():
			if main_menu_ref != null:
				main_menu_ref._on_LoadPlaylists_Button_pressed()
			_status_bar.text = "All downloaded"
	else:
		_status_bar.text = "Download error %d" % result
		if result == -1:
			_status_bar.text += "\nInvalid URL or server is down"
		vr.log_info("download error %d" % result)
		_download_queue.remove_at(0)

	_canvas_input_update()
	_download_next()
