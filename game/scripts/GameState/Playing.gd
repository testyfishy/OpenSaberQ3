extends GameState
class_name GameStatePlaying

func _ready(game: BeepSaber_Game) -> void:
	game.main_menu._hide()
	game.settings_canvas._hide()
	game.show_MapSourceDialogs(false)
	game.endscore._hide()
	game.pause_menu._hide()
	game.highscore_canvas._hide()
	game.name_selector_canvas._hide()
	game.left_saber._show()
	game.right_saber._show()
	game.multiplier_label.visible = true
	game.point_label.visible = true
	game.percent_indicator.visible = true
	game.track.visible = true
	game.left_ui_raycast.visible = false
	game.right_ui_raycast.visible = false
	game.highscore_keyboard._hide()
	game.online_search_keyboard._hide()
	game.left_saber.set_swingcast_enabled(true)
	game.right_saber.set_swingcast_enabled(true)
	Scoreboard.paused = false

func _physics_process(game: BeepSaber_Game) -> void:
	if game.left_controller.by_just_pressed():
		game._transition_game_state(game.gamestate_paused)
	if game._audio_synced_after_restart:
		_process_map(game)
	else:
		# 0.5 seconds is a pretty concervative number to use for the audio
		# resync check. Having this duration be this long might only be an
		# issue for maps that spawn notes extremely early into the song.
		if game.song_player.get_playback_position() < 0.5:
			game._audio_synced_after_restart = true

var bomb_template := load("res://game/Bomb/Bomb.tscn") as PackedScene
var wall_template := load("res://game/Wall/Wall.tscn") as PackedScene
var chain_link_template := load("res://game/Chain/ChainLink.tscn") as PackedScene
const BEATS_AHEAD := 4.0

func _process_map(game: BeepSaber_Game) -> void:
	if (Map.current_info == null):
		return
	
	var current_beat := game.song_player.get_playback_position() * Map.current_info.beats_per_minute * 0.016666666666666667
	var look_ahead := current_beat + BEATS_AHEAD
	
	# chains connect to a regular colornote and modify it, so we have to keep
	# track of what notes were spawned this frame, in case any become the head
	# of a chain.
	# why did they do this?
	var note_info_refs: Array[Map.ColorNoteInfo] = []
	var cube_refs: Array[BeepCube] = []
	
	# spawn notes
	while not Map.note_stack.is_empty() and Map.note_stack[-1].beat <= look_ahead:
		var note := game.cube_pool.acquire()
		var note_info := Map.note_stack.pop_back() as Map.ColorNoteInfo
		var color := Map.color_left if note_info.color == 0 else Map.color_right
		note.spawn(note_info, current_beat, color)
		note_info_refs.append(note_info)
		cube_refs.append(note)
	
	# spawn bombs
	while not Map.bomb_stack.is_empty() and Map.bomb_stack[-1].beat <= look_ahead:
		var bomb := bomb_template.instantiate() as Bomb
		bomb.spawn(Map.bomb_stack.pop_back() as Map.BombInfo, current_beat)
		game.track.add_child(bomb)
	
	# spawn obstacles (walls)
	while not Map.obstacle_stack.is_empty() and Map.obstacle_stack[-1].beat <= look_ahead:
		var wall := wall_template.instantiate() as Wall
		wall.spawn(Map.obstacle_stack.pop_back() as Map.ObstacleInfo, current_beat)
		game.track.add_child(wall)
	
	while not Map.chain_stack.is_empty() and Map.chain_stack[-1].head_beat <= look_ahead:
		var chain_info := Map.chain_stack.pop_back() as Map.ChainInfo
		if chain_info.slice_count <= 1:
			continue
		var color := Map.color_left if chain_info.color == 0 else Map.color_right
		var i := 0
		while i < note_info_refs.size():
			var info_ref := note_info_refs[i]
			if (
				info_ref.beat == chain_info.head_beat
				and info_ref.line_index == chain_info.head_line_index
				and info_ref.line_layer == chain_info.head_line_layer
			):
				cube_refs[i].make_chain_head()
			i += 1
		i = 1
		while i <= chain_info.slice_count:
			var chain_link := chain_link_template.instantiate() as ChainLink
			chain_link.spawn(chain_info, current_beat, color, i)
			game.track.add_child(chain_link)
			i += 1
	
	while not Map.event_stack.is_empty() and Map.event_stack[-1].beat <= current_beat:
		game.event_driver.process_event(Map.event_stack.pop_back() as Map.EventInfo, Map.color_left, Map.color_right)
