extends Node

# View-state golden matrix (specs/016 Part 5, FR-042/FR-043).
#
# Runs each GameState _ready() against a fake game whose nodes record their final visibility and
# side-effect calls. The output is the behaviour the refactor must preserve. The harness was run
# before the refactor and its snapshot is frozen in GOLDEN below.
#
# Run: godot --headless --path . res://tools/tests/test_view_state.tscn

const STATES := {
	"MapComplete": preload("res://game/scripts/GameState/MapComplete.gd"),
	"MapSelection": preload("res://game/scripts/GameState/MapSelection.gd"),
	"NewHighscore": preload("res://game/scripts/GameState/NewHighscore.gd"),
	"Paused": preload("res://game/scripts/GameState/Paused.gd"),
	"Playing": preload("res://game/scripts/GameState/Playing.gd"),
	"Settings": preload("res://game/scripts/GameState/Settings.gd"),
}

const NODES := [
	"main_menu", "settings_canvas", "endscore", "pause_menu", "highscore_canvas",
	"name_selector_canvas", "highscore_keyboard", "online_search_keyboard",
	"left_saber", "right_saber",
	"multiplier_label", "point_label", "percent_indicator", "track",
	"left_ui_raycast", "right_ui_raycast",
]

const GOLDEN := {
	"MapComplete": "{\"colors_calls\":0,\"dialogs\":false,\"dialogs_calls\":1,\"endscore\":true,\"endscore_buttons\":false,\"highscore_canvas\":false,\"highscore_keyboard\":false,\"left_saber\":false,\"left_swingcast\":false,\"left_ui_raycast\":true,\"main_menu\":false,\"multiplier_label\":false,\"name_selector_canvas\":false,\"names_added\":0,\"online_search_keyboard\":false,\"pause_menu\":false,\"pause_name\":\"\",\"pause_position\":0.0,\"pause_text\":\"\",\"paused\":false,\"percent_indicator\":false,\"point_label\":false,\"profile_calls\":1,\"right_saber\":false,\"right_swingcast\":false,\"right_ui_raycast\":true,\"settings_canvas\":false,\"track\":false}",
	"MapSelection": "{\"colors_calls\":1,\"dialogs\":true,\"dialogs_calls\":1,\"endscore\":false,\"endscore_buttons\":true,\"highscore_canvas\":false,\"highscore_keyboard\":false,\"left_saber\":false,\"left_swingcast\":false,\"left_ui_raycast\":true,\"main_menu\":true,\"multiplier_label\":false,\"name_selector_canvas\":false,\"names_added\":0,\"online_search_keyboard\":false,\"pause_menu\":false,\"pause_name\":\"\",\"pause_position\":0.0,\"pause_text\":\"\",\"paused\":false,\"percent_indicator\":false,\"point_label\":false,\"profile_calls\":1,\"right_saber\":false,\"right_swingcast\":false,\"right_ui_raycast\":true,\"settings_canvas\":false,\"track\":false}",
	"NewHighscore": "{\"colors_calls\":1,\"dialogs\":false,\"dialogs_calls\":1,\"endscore\":true,\"endscore_buttons\":true,\"highscore_canvas\":true,\"highscore_keyboard\":true,\"left_saber\":false,\"left_swingcast\":false,\"left_ui_raycast\":true,\"main_menu\":false,\"multiplier_label\":false,\"name_selector_canvas\":true,\"names_added\":0,\"online_search_keyboard\":false,\"pause_menu\":false,\"pause_name\":\"\",\"pause_position\":0.0,\"pause_text\":\"\",\"paused\":false,\"percent_indicator\":false,\"point_label\":false,\"profile_calls\":1,\"right_saber\":false,\"right_swingcast\":false,\"right_ui_raycast\":true,\"settings_canvas\":false,\"track\":false}",
	"Paused": "{\"colors_calls\":0,\"dialogs\":false,\"dialogs_calls\":1,\"endscore\":false,\"endscore_buttons\":true,\"highscore_canvas\":false,\"highscore_keyboard\":false,\"left_saber\":true,\"left_swingcast\":false,\"left_ui_raycast\":true,\"main_menu\":false,\"multiplier_label\":true,\"name_selector_canvas\":false,\"names_added\":0,\"online_search_keyboard\":false,\"pause_menu\":true,\"pause_name\":\"One\",\"pause_position\":12.5,\"pause_text\":\"Song By Artist\\nMap author: Mapper\",\"paused\":true,\"percent_indicator\":true,\"point_label\":true,\"profile_calls\":1,\"right_saber\":true,\"right_swingcast\":false,\"right_ui_raycast\":true,\"settings_canvas\":false,\"track\":false}",
	"Playing": "{\"colors_calls\":0,\"dialogs\":false,\"dialogs_calls\":1,\"endscore\":false,\"endscore_buttons\":true,\"highscore_canvas\":false,\"highscore_keyboard\":false,\"left_saber\":true,\"left_swingcast\":true,\"left_ui_raycast\":false,\"main_menu\":false,\"multiplier_label\":true,\"name_selector_canvas\":false,\"names_added\":0,\"online_search_keyboard\":false,\"pause_menu\":false,\"pause_name\":\"\",\"pause_position\":0.0,\"pause_text\":\"\",\"paused\":false,\"percent_indicator\":true,\"point_label\":true,\"profile_calls\":1,\"right_saber\":true,\"right_swingcast\":true,\"right_ui_raycast\":false,\"settings_canvas\":false,\"track\":true}",
	"Settings": "{\"colors_calls\":0,\"dialogs\":true,\"dialogs_calls\":1,\"endscore\":false,\"endscore_buttons\":true,\"highscore_canvas\":false,\"highscore_keyboard\":false,\"left_saber\":false,\"left_swingcast\":true,\"left_ui_raycast\":true,\"main_menu\":false,\"multiplier_label\":false,\"name_selector_canvas\":false,\"names_added\":0,\"online_search_keyboard\":false,\"pause_menu\":false,\"pause_name\":\"\",\"pause_position\":0.0,\"pause_text\":\"\",\"paused\":false,\"percent_indicator\":false,\"point_label\":false,\"profile_calls\":1,\"right_saber\":false,\"right_swingcast\":true,\"right_ui_raycast\":true,\"settings_canvas\":true,\"track\":false}",
}

var _bad := 0

class Stub:
	var visible := true
	var swingcast := true
	var buttons := true
	var add_name_count := 0
	var ui_control: PausePanel
	func _show() -> void: visible = true
	func _hide() -> void: visible = false
	func set_swingcast_enabled(value: bool) -> void: swingcast = value
	func set_buttons_disabled(value: bool) -> void: buttons = value
	func load_highscores(_info, _rank) -> void: pass
	func clear_names() -> void: add_name_count = 0
	func add_name(_name) -> void: add_name_count += 1
	func get_playback_position() -> float: return 12.5
	func stop() -> void: pass

class FakePausePanel extends PausePanel:
	var last_text := ""
	var last_name := ""
	func set_pause_text(song_name, dificulty := "") -> void:
		last_text = song_name
		last_name = dificulty

class FakeGame:
	var main_menu := Stub.new()
	var settings_canvas := Stub.new()
	var endscore := Stub.new()
	var pause_menu := Stub.new()
	var highscore_canvas := Stub.new()
	var name_selector_canvas := Stub.new()
	var highscore_keyboard := Stub.new()
	var online_search_keyboard := Stub.new()
	var left_saber := Stub.new()
	var right_saber := Stub.new()
	var multiplier_label := Stub.new()
	var point_label := Stub.new()
	var percent_indicator := Stub.new()
	var track := Stub.new()
	var left_ui_raycast := Stub.new()
	var right_ui_raycast := Stub.new()
	var highscore_panel := Stub.new()
	var song_player := Stub.new()
	var pause_position := 0.0
	var dialogs := false
	var dialogs_calls := 0
	var colors_calls := 0
	var profile_calls := 0
	var name_selector := Stub.new()
	func show_MapSourceDialogs(showing: bool) -> void:
		dialogs = showing
		dialogs_calls += 1
	func set_colors_from_settings() -> void: colors_calls += 1
	func hide_profile_panel() -> void: profile_calls += 1
	func _name_selector() -> Stub: return name_selector

func _ready() -> void:
	var diff := DifficultyInfo.new("ExpertPlus", 9, "ExpertPlus.dat", 16.0, 0.0, {}, "One")
	var info := MapInfo.new("3.0.0", "Song", "", "Artist", "Mapper", 120.0, 0.0, 0.0, "", "", "DefaultEnvironment", 0.0, {}, "", [diff])
	Map.current_info = info
	Map.current_difficulty = diff
	MapSupport.unsupported_features = PackedStringArray()
	var collected := {}

	for state_name: String in STATES:
		var game := FakeGame.new()
		var pause_panel := FakePausePanel.new()
		game.pause_menu.ui_control = pause_panel
		var state = STATES[state_name].new()
		state._ready(game)
		state.free()

		var snap := {}
		for node_name: String in NODES:
			snap[node_name] = game.get(node_name).visible
		snap["left_swingcast"] = game.left_saber.swingcast
		snap["right_swingcast"] = game.right_saber.swingcast
		snap["endscore_buttons"] = game.endscore.buttons
		snap["dialogs"] = game.dialogs
		snap["dialogs_calls"] = game.dialogs_calls
		snap["colors_calls"] = game.colors_calls
		snap["profile_calls"] = game.profile_calls
		snap["paused"] = Scoreboard.paused
		snap["pause_position"] = game.pause_position
		snap["pause_text"] = pause_panel.last_text
		snap["pause_name"] = pause_panel.last_name
		snap["names_added"] = game.name_selector.add_name_count
		var line := JSON.stringify(snap)
		collected[state_name] = line
		print("VIEWSTATE %s %s" % [state_name, line])

	if GOLDEN.is_empty():
		print("VIEWSTATE CAPTURE")
		get_tree().quit(0)
		return

	for state_name: String in GOLDEN:
		if collected.get(state_name, "") != GOLDEN[state_name]:
			push_error("VIEWSTATETEST %s changed\n got %s\nwant %s" % [
				state_name, collected.get(state_name, ""), GOLDEN[state_name]])
			_bad += 1

	print("VIEWSTATETEST ", "PASS" if _bad == 0 else "FAIL")
	get_tree().quit(0 if _bad == 0 else 1)
