extends Node

# BeatSaver panel screenshot harness (UI-4 step 0).
#
# Renders every panel state from deterministic fixtures, so a refactor can be compared against a
# baseline without a headset or the network:
#   loading, list, detail, downloading, downloaded, error, empty, paging
#
# The list and detail come from the real parser over the checked-in BeatSaver samples; covers are
# served by a stub that always returns the placeholder, so no state depends on request timing.
#
# Run: godot --path . res://tools/beatsaver_shots.tscn
# Writes user://beatsaver_<state>.png and prints one BEATSAVERSHOT line per state.

const PANEL := preload("res://game/ui/BeatSaverPanel/BeatSaverPanel.tscn")
const API := preload("res://game/ui/BeatSaverPanel/BeatSaverApi.gd")
const COVER_STUB := preload("res://tools/beatsaver_cover_stub.gd")
const SEARCH_FIXTURE := "res://specs/003-beatsaver-api-research/samples/search-sc001.json"

var _viewport: SubViewport
var _panel: Control
var _parsed: Variant

func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1536, 960)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	_parsed = API.parse_search(FileAccess.get_file_as_bytes(SEARCH_FIXTURE))
	if not _parsed.ok:
		printerr("BEATSAVERSHOTS fixture failed to parse: ", _parsed.error)
		get_tree().quit(1)
		return

	_panel = PANEL.instantiate()
	# The first show would start a live query; the harness drives the states itself.
	_panel.set("_is_first_show", false)
	_viewport.add_child(_panel)
	for i in 4:
		await get_tree().process_frame

	# Deterministic covers.
	var stub := COVER_STUB.new()
	stub.name = "CoverLoaderStub"
	_panel.add_child(stub)
	_panel.set("_covers", stub)
	var slider := _panel.get_node_or_null("list_slider")
	if slider != null:
		slider.set_process(false)

	await _shot("loading", _state_loading)
	await _shot("list", _state_list)
	await _shot("detail", _state_detail)
	await _shot("downloading", _state_downloading)
	await _shot("downloaded", _state_downloaded)
	await _shot("error", _state_error)
	await _shot("empty", _state_empty)
	await _shot("paging", _state_paging)

	get_tree().quit()

func _state_loading() -> void:
	_panel.set("_loading", true)
	_panel.call("_update_pager")
	_panel.call("_canvas_input_update")

func _state_list() -> void:
	_set_rows(_parsed.docs)

func _state_detail() -> void:
	_panel.call("_on_card_pressed", 0)

func _state_downloading() -> void:
	(_panel.get("_status_bar") as Label).text = "Downloading: %s - 0 left" % [_parsed.docs[0].name]

func _state_downloaded() -> void:
	(_panel.get("_status_bar") as Label).text = "All downloaded"

func _state_error() -> void:
	_panel.call("_fail_page", "Could not reach BeatSaver. Check your connection.")

func _state_empty() -> void:
	_panel.set("_rows", [])
	_panel.set("_rejected", 0)
	_panel.set("_pending_docs_seen", 0)
	_panel.set("_has_more", false)
	_panel.set("_error_message", "")
	_panel.call("_clear_details")
	_panel.call("_render_rows")
	_panel.call("_update_pager")

func _state_paging() -> void:
	_panel.set("_page_index", 1)
	_panel.set("_page_starts", [{"page": 0, "doc": 0}, {"page": 1, "doc": 0}])
	_panel.set("_has_more", true)
	_set_rows(_parsed.docs)

func _set_rows(docs: Array) -> void:
	_panel.set("_rows", docs.duplicate())
	_panel.set("_total", _parsed.total)
	_panel.set("_loading", false)
	_panel.set("_error_message", "")
	_panel.set("_has_more", true)
	_panel.set("_rejected", 0)
	_panel.set("_pending_docs_seen", docs.size())
	_panel.call("_render_rows")
	_panel.call("_update_pager")
	_panel.call("_update_controls")

func _shot(state: String, setup: Callable) -> void:
	setup.call()
	# The panel's refresh authority disables the viewport when idle; the harness wants every state
	# rendered, so hold the viewport live for the capture window.
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i in 4:
		await get_tree().process_frame
	var path := "user://beatsaver_%s.png" % state
	_viewport.get_texture().get_image().save_png(path)
	print("BEATSAVERSHOT %s %s" % [state, ProjectSettings.globalize_path(path)])
