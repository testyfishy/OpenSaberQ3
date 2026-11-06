extends GameState
class_name GameStateNewHighScore

func _ready(game) -> void:
	# populate highscore panel with records
	game.highscore_panel.load_highscores(
		Map.current_info, Map.current_difficulty.difficulty_rank)

	game.endscore.set_buttons_disabled(true)

	# fill name selector with most recent player names
	game._name_selector().clear_names()
	# WARNING: The get_all_player_names() method could become
	# costly for a very large highscore database (ie. many
	# songs and difficulties). If that ever becomes a
	# concern, we may want to consider caching a list of the
	# N most recent players instead.
	for player_name in Highscores.get_all_player_names():
		game._name_selector().add_name(player_name)

	_set_overlays(game, ["endscore", "highscore_canvas", "name_selector_canvas", "highscore_keyboard"])
	game.show_MapSourceDialogs(false)
	_set_sabers(game, false, false)
	_set_hud(game, false, false, true)
	game.set_colors_from_settings()
	game.hide_profile_panel()
