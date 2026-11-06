extends GameState
class_name GameStateSettings

func _ready(game) -> void:
	_set_overlays(game, ["settings_canvas"])
	game.show_MapSourceDialogs(true)
	# Settings hides the sabers but leaves their swingcast flag as it was.
	_set_sabers(game, false)
	_set_hud(game, false, false, true)
	game.hide_profile_panel()
