extends GameState
class_name GameStatePaused

func _ready(game) -> void:
	# FR-036: no hit voice or music duck survives a state change.
	if GlobalReferences.hit_audio != null:
		GlobalReferences.hit_audio.call("stop_all")
	_set_overlays(game, ["pause_menu"])
	game.show_MapSourceDialogs(false)
	_set_hud(game, true, false, true)
	# Paused leaves the sabers visible but disables their swing hits.
	_set_swingcast(game, false)
	Scoreboard.paused = true

	game.pause_position = game.song_player.get_playback_position()
	game.song_player.stop()
	var pause_text := "%s By %s\nMap author: %s" % [
		Map.current_info.song_name,
		Map.current_info.song_author_name,
		Map.current_info.level_author_name
	]
	# FR-030: say plainly which parts of this map we cannot render faithfully.
	if not MapSupport.unsupported_features.is_empty():
		pause_text += "\nNot fully supported: " + ", ".join(MapSupport.unsupported_features)
	(game.pause_menu.ui_control as PausePanel).set_pause_text(pause_text, Map.current_difficulty.custom_name)
	game.hide_profile_panel()
