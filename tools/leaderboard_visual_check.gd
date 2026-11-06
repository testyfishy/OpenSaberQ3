extends Node

# Desktop check of the real BeatLeader panel (specs/020 SC-003): opens the game scene, picks a
# map whose hash is known (Phoenix), opens the board through the game's own handler, waits for
# the live response, and saves screenshots of a populated board and of the no-hash message.
#
# Run: godot --path . res://tools/leaderboard_visual_check.tscn

func _ready() -> void:
	var scene := load("res://game/BeepSaber_Game.tscn") as PackedScene
	var game := scene.instantiate()
	add_child(game)
	await get_tree().create_timer(6.0).timeout
	for _i in 10:
		await get_tree().process_frame

	var canvas := game.get_node("MainMenu_OQ_UI2DCanvas") as OQ_UI2DCanvas
	var menu := canvas.ui_control as MainMenu
	var idx := -1
	for i in menu._all_songs.size():
		if menu._all_songs[i].song_name.to_lower().contains("phoenix"):
			idx = i
			break
	if idx < 0:
		print("LEADERVISUAL SKIP: Phoenix is not in the library")
		get_tree().quit(1)
		return
	var map: MapInfo = menu._all_songs[idx]
	if map.level_hash.is_empty():
		map.level_hash = MapSource.compute_level_hash(map.filepath)
	print("LEADERVISUAL hash=", map.level_hash)
	var diff: DifficultyInfo = map.difficulty_beatmaps[0]
	for d: DifficultyInfo in map.difficulty_beatmaps:
		if d.difficulty == "ExpertPlus" and d.characteristic == "Standard":
			diff = d
	print("LEADERVISUAL difficulty=", diff.difficulty, " mode=", BeatLeaderApi.mode_for_characteristic(diff.characteristic))

	game._leaderboard_button(map, diff)
	# The fetch is two sequential requests; poll the status instead of guessing a frame count.
	var panel = game.leaderboard_panel
	for _i in 200:
		await get_tree().create_timer(0.1).timeout
		if not String(panel._status.text).begins_with("Loading"):
			break
	game.leaderboard_canvas._input_update()
	await get_tree().process_frame
	print("LEADERVISUAL status=", panel._status.text)
	_save("user://visual_leaderboard.png")

	# The explanatory path for a map BeatLeader cannot identify.
	var orphan := MapInfo.new(
		"2.1.0", "No Hash Song", "", "Artist", "Mapper", 120.0,
		0.0, 0.0, "song.ogg", "", "", 0.0, {}, "user://none/", [])
	panel.open(orphan, diff)
	game.leaderboard_canvas._input_update()
	await get_tree().process_frame
	print("LEADERVISUAL nohash=", panel._status.text)
	_save("user://visual_leaderboard_nohash.png")
	get_tree().quit()

func _save(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("LEADERVISUAL ", ProjectSettings.globalize_path(path))
