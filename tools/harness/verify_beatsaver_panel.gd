extends Node

# BeatSaver panel resolve gate (UI-4).
#
# Instantiates the real scene and asserts that every object-typed script variable resolved, that
# the extracted views exist with their controls, and that the full-size view containers do not
# intercept the ray. This is the same class of check that caught the settings panel's %Name bug,
# applied to the code-built browser.
#
# Run: godot --headless --path . res://tools/harness/verify_beatsaver_panel.tscn

const PANEL := preload("res://game/ui/BeatSaverPanel/BeatSaverPanel.tscn")
const API := preload("res://game/ui/BeatSaverPanel/BeatSaverApi.gd")
const COVER_STUB := preload("res://tools/beatsaver_cover_stub.gd")
const SEARCH_FIXTURE := "res://specs/003-beatsaver-api-research/samples/search-sc001.json"

var _bad := 0

func _ready() -> void:
	var panel := PANEL.instantiate()
	add_child(panel)
	for i in 4:
		await get_tree().process_frame

	# Set from the game scene, not by the panel itself.
	var optional := {"main_menu_ref": true, "keyboard": true}
	for prop in panel.get_property_list():
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if prop.type != TYPE_OBJECT:
			continue
		if optional.has(prop.name):
			continue
		if panel.get(prop.name) == null:
			fail("null reference: %s" % prop.name)

	var detail := panel.get_node_or_null("DetailView") as Control
	if detail == null:
		fail("DetailView missing")
	else:
		for child_name: String in ["DetailsCover", "SongData"]:
			if detail.get_node_or_null(child_name) == null:
				fail("DetailView/%s missing" % child_name)
		if detail.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			fail("DetailView intercepts the mouse")
		if detail.size != Vector2(1536, 960):
			fail("DetailView size %s" % str(detail.size))

	# The scroller still points at the cards list that exists.
	var results := panel.get_node_or_null("ResultsView") as Control
	if results == null:
		fail("ResultsView missing")
	else:
		if results.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			fail("ResultsView intercepts the mouse")
		if results.size != Vector2(1536, 960):
			fail("ResultsView size %s" % str(results.size))
		if results.get_node_or_null("CardsScroll/CardList") == null:
			fail("ResultsView/CardsScroll/CardList missing")

	if panel.call("get_list_slider") == null:
		fail("list_slider missing")
	if panel.call("get_cards_list") == null:
		fail("get_cards_list() missing")
	if panel.call("get_results_view") != results:
		fail("get_results_view() does not return ResultsView")

	# Click routing through the views: a card press selects, Download queues.
	var docs: Array = API.parse_search(FileAccess.get_file_as_bytes(SEARCH_FIXTURE)).docs
	var stub := COVER_STUB.new()
	panel.add_child(stub)
	panel.set("_covers", stub)
	panel.set("_rows", docs)
	panel.call("_render_rows")
	var cards: Array = panel.call("get_results_view").cards
	if cards.is_empty() or not cards[0].visible:
		fail("card 0 not visible after set_rows")
	else:
		cards[0].pressed.emit()
		if int(panel.get("_selected_index")) != 0:
			fail("card press did not select index 0")
		panel.get_node("DetailView").download_button.pressed.emit()
		if (panel.get("_download_queue") as Array).is_empty():
			fail("Download press did not queue a download")
		(panel.get("_download_request") as HTTPRequest).cancel_request()
		(panel.get("_download_queue") as Array).clear()

	print("VERIFYPANELBS bad=%d" % _bad)
	panel.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _bad == 0 else 1)

func fail(message: String) -> void:
	push_error("VERIFYPANELBS " + message)
	_bad += 1
