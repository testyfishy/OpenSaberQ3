extends Node

# Desktop render of the real main menu (specs/020 SC-005: source tag and filter visible, no
# overlap). Runs the actual game scene, lets the menu populate from the user's Songs folder,
# selects the first song so the info panel is exercised, then filters to BeatSaver and saves a
# second screenshot. Desktop only; there is no headset in this path.
#
# Run: godot --path . res://tools/menu_visual_check.tscn

func _ready() -> void:
	var scene := load("res://game/BeepSaber_Game.tscn") as PackedScene
	var game := scene.instantiate()
	add_child(game)
	# The boot splash runs for 3 s of wall time before the menu is on screen.
	await get_tree().create_timer(6.0).timeout
	for _i in 10:
		await get_tree().process_frame

	var canvas := game.get_node("MainMenu_OQ_UI2DCanvas") as OQ_UI2DCanvas
	var menu := canvas.ui_control as MainMenu
	menu._select_song(0)
	# The menu canvas renders only on input; programmatic changes need this nudge.
	canvas._input_update()
	await get_tree().process_frame
	_save("user://visual_menu.png")

	# Exercise the filter through the same handler the OptionButton uses.
	menu.source_filter.select(1)
	menu._on_SourceFilter_item_selected(1)
	canvas._input_update()
	await get_tree().process_frame
	for i in menu.songs_menu.item_count:
		print("MENUVISUAL filtered ", menu.songs_menu.get_item_text(i))
	_save("user://visual_menu_filtered.png")
	menu.source_filter.select(0)
	menu._on_SourceFilter_item_selected(0)

	get_tree().quit()

func _save(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("MENUVISUAL ", ProjectSettings.globalize_path(path))
