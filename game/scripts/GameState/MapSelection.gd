extends GameState
class_name GameStateMapSelection

func _ready(game) -> void:
	_set_overlays(game, ["main_menu"])
	game.show_MapSourceDialogs(true)
	_set_sabers(game, false, false)
	_set_hud(game, false, false, true)
	game.set_colors_from_settings()
	game.hide_profile_panel()
