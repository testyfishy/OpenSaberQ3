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
	var slider := panel.get_node_or_null("list_slider")
	if slider == null:
		fail("list_slider missing")
	elif panel.get_node_or_null("CardsScroll/CardList") == null:
		fail("CardsScroll/CardList missing")

	print("VERIFYPANELBS bad=%d" % _bad)
	panel.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _bad == 0 else 1)

func fail(message: String) -> void:
	push_error("VERIFYPANELBS " + message)
	_bad += 1
