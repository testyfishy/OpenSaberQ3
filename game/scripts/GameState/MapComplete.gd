extends GameState
class_name GameStateMapComplete

func _ready(game) -> void:
	game.endscore.set_buttons_disabled(false)
	_set_overlays(game, ["endscore"])
	game.show_MapSourceDialogs(false)
	_set_sabers(game, false, false)
	_set_hud(game, false, false, true)
	game.hide_profile_panel()
