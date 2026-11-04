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
	game.hide_profile_panel()

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
var arc_template := load("res://game/Arc/Arc.tscn") as PackedScene
const BEATS_AHEAD := 4.0

const Cost := preload("res://game/scripts/CostProbe.gd")

func _process_map(game: BeepSaber_Game) -> void:
	if (Map.current_info == null):
		return
	if Map.spawn_disabled:
		return
	var probe := Cost.enabled
	var t0 := Time.get_ticks_usec() if probe else 0
	
	var current_beat := Map.seconds_to_beat(game.song_player.get_playback_position())
	var look_ahead := current_beat + BEATS_AHEAD
	
	# chains connect to a regular colornote and modify it, so we have to keep
	# track of what notes were spawned this frame, in case any become the head
	# of a chain.
	# why did they do this?
	var note_info_refs: Array[ColorNoteInfo] = []
	var cube_refs: Array[BeepCube] = []
	
	# spawn notes
	while not Map.note_stack.is_empty() and Map.note_stack[-1].beat <= look_ahead:
		var note := GlobalReferences.cube_pool.acquire() as BeepCube
		var note_info := Map.note_stack.pop_back() as ColorNoteInfo
		note.spawn(note_info, current_beat)
		note_info_refs.append(note_info)
		cube_refs.append(note)
	
	# spawn bombs
	while not Map.bomb_stack.is_empty() and Map.bomb_stack[-1].beat <= look_ahead:
		if probe: Cost.objs_spawned += 1
		var bomb := bomb_template.instantiate() as Bomb
		bomb.spawn(Map.bomb_stack.pop_back() as BombInfo, current_beat)
		game.track.add_child(bomb)
	
	# spawn obstacles (walls)
	while not Map.obstacle_stack.is_empty() and Map.obstacle_stack[-1].beat <= look_ahead:
		if probe: Cost.objs_spawned += 1
		# Pooled, not instantiated. The pool adds its scene to the track at creation, so the
		# node is already in the tree and spawn() can apply its material immediately.
		var wall := GlobalReferences.wall_pool.acquire() as Wall
		wall.spawn(Map.obstacle_stack.pop_back() as ObstacleInfo, current_beat)
	
	while not Map.arc_stack.is_empty() and Map.arc_stack[-1].head_beat <= look_ahead:
		if probe:
			Cost.objs_spawned += 1
			Cost.arcs_spawned += 1
		# A/B kill switch: arcs rebuild a CSGPolygon3D ribbon on the main thread at every
		# spawn. Disabling them is the cheap way to prove or eliminate that cost before
		# rewriting them. The stack is still popped so timing/spawn order is unchanged.
		if not Arc.spawn_enabled:
			Map.arc_stack.pop_back()
			continue
		var arc := Arc.acquire() as Arc
		var arc_info := Map.arc_stack.pop_back() as ArcInfo
		
		# Find the arc's head note: beat within a tolerance, plus colour AND grid position.
		# The old check compared beat and colour only, so with two same-colour notes on one beat
		# (stacks, windows) the arc could attach to the wrong one - which reads as an arc hanging
		# off the side of a block. The tolerance covers float round-trip differences.
		var cube : BeepCube
		var cube_id := cube_refs.size()-1
		while cube_id >= 0:
			var current_cube : BeepCube = cube_refs[cube_id]
			if (absf(current_cube.beat - arc_info.head_beat) < 0.001
				and current_cube.which_saber == arc_info.color
				and current_cube.line_index == arc_info.head_line_index
				and current_cube.line_layer == arc_info.head_line_layer
				):
					cube = current_cube
					break
			cube_id -= 1
		
		arc.spawn(arc_info, current_beat, cube)
		game.track.add_child(arc)
	
	while not Map.chain_stack.is_empty() and Map.chain_stack[-1].head_beat <= look_ahead:
		var chain_info := Map.chain_stack.pop_back() as ChainInfo
		if chain_info.slice_count > 1: # skip if the chain doesn't have any links
			ChainLink.construct_chain(chain_info, current_beat, note_info_refs, cube_refs)
	
	while not Map.event_stack.is_empty() and Map.event_stack[-1].beat <= current_beat:
		game.event_driver.process_event(Map.event_stack.pop_back() as EventInfo)
	
	if probe:
		Cost.spawn_usec += Time.get_ticks_usec() - t0
	game.hide_profile_panel()

