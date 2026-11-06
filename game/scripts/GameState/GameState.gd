extends Object
class_name GameState

# Shared view-state application (specs/016 Part 5, FR-042).
#
# Each state declares which overlays it shows and the HUD/saber flags; the helpers write each node
# once. Hiding then re-showing a panel that stays visible would fire its visibility side effects
# twice, so `_set_overlays` only writes nodes whose target differs from the shown set.

const OVERLAYS: Array[String] = [
	"main_menu", "settings_canvas", "endscore", "pause_menu", "highscore_canvas",
	"name_selector_canvas", "highscore_keyboard", "online_search_keyboard", "leaderboard_canvas",
]

func _ready(game) -> void:
	return

@warning_ignore("unused_parameter")
func _physics_process(game: BeepSaber_Game) -> void:
	return

func _set_overlays(game, shown: Array) -> void:
	for overlay: String in OVERLAYS:
		var node: Variant = game.get(overlay)
		if node == null:
			continue
		if shown.has(overlay):
			node.call("_show")
		else:
			node.call("_hide")

func _set_hud(game, hud: bool, track: bool, raycasts: bool) -> void:
	game.multiplier_label.visible = hud
	game.point_label.visible = hud
	game.percent_indicator.visible = hud
	game.track.visible = track
	game.left_ui_raycast.visible = raycasts
	game.right_ui_raycast.visible = raycasts

# `swingcast = null` leaves the sabers' swingcast flag untouched (Settings does this): only pass it
# when the state owns the value. Visibility is always applied, in the old code's order: sabers
# first, then swingcast.
func _set_sabers(game, visible: bool, swingcast = null) -> void:
	if visible:
		game.left_saber._show()
		game.right_saber._show()
	else:
		game.left_saber._hide()
		game.right_saber._hide()
	if swingcast != null:
		_set_swingcast(game, swingcast)

func _set_swingcast(game, enabled: bool) -> void:
	game.left_saber.set_swingcast_enabled(enabled)
	game.right_saber.set_swingcast_enabled(enabled)
