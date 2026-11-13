extends GameState
class_name GameStatePlaying

static var debug_skip_bombs := false
# Dense lightshows can issue several events for the same light type in one frame; only the last
# one is visible. Coalescing keeps the latest per type and leaves ring/speed events in order.
static var coalesce_lights := true

func _ready(game) -> void:
	_set_overlays(game, [])
	game.show_MapSourceDialogs(false)
	if not game.resuming_from_pause:
		_arc_tails.clear()
		_arcs_waiting.clear()
		_chains_waiting.clear()
	game.resuming_from_pause = false
	_set_sabers(game, true, true)
	_set_hud(game, true, true, false)
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


# Arcs whose tail note has not been spawned yet.
var _arc_tails: Array[ArcInfo] = []

func _mark_arc_tail(note: BeepCube) -> void:
	for i in range(_arc_tails.size() - 1, -1, -1):
		var arc_info := _arc_tails[i]
		if arc_info.tail_beat < note.beat - 8.0:
			# Long past: the tail note never came (or the arc ends on nothing).
			_arc_tails.remove_at(i)
			continue
		if (absf(arc_info.tail_beat - note.beat) < 0.001 and arc_info.color == note.which_saber
				and is_equal_approx(arc_info.tail_line_index, note.line_index)
				and is_equal_approx(arc_info.tail_line_layer, note.line_layer)):
			note.arc_tail = true
			_arc_tails.remove_at(i)

# Maps where notes have their own jumps link arcs and chains to their head notes at load
# (NoodleTracks.link_heads), because the head may spawn in an earlier or a later frame. An arc or
# chain whose head is still to spawn waits here and spawns with it.
var _arcs_waiting: Array[ArcInfo] = []
var _chains_waiting: Array[ChainInfo] = []
var _one_info: Array[ColorNoteInfo] = [null]
var _one_cube: Array[BeepCube] = [null]
var _no_infos: Array[ColorNoteInfo] = []
var _no_cubes: Array[BeepCube] = []

## The live cube drawing `info`, or null if it was never spawned or has gone back to the pool.
static func linked_head(info: ColorNoteInfo) -> BeepCube:
	var cube := info.spawned as BeepCube
	if cube == null or cube.is_released() or cube.beat != info.beat:
		return null
	return cube

func _spawn_arc(game: BeepSaber_Game, arc_info: ArcInfo, cube: BeepCube, current_beat: float, cube_refs: Array[BeepCube]) -> void:
	var arc := Arc.acquire() as Arc
	if cube != null:
		cube.arc_head = true
	# The tail note is later in the map: usually not spawned yet, sometimes in this same
	# pass. Remember the arc so the note can be marked when it appears, and check the
	# notes of this pass now. A tail linked at load is marked by the note itself.
	if not arc_info.tail_linked:
		_arc_tails.append(arc_info)
		for spawned in cube_refs:
			_mark_arc_tail(spawned)
	arc.spawn(arc_info, current_beat, cube)
	game.track.add_child(arc)
	TrackLanes.place(arc, arc_info.head_beat)

func _construct_linked_chain(chain_info: ChainInfo, current_beat: float) -> void:
	var cube := linked_head(chain_info.head_info)
	if cube == null:
		ChainLink.construct_chain(chain_info, current_beat, _no_infos, _no_cubes)
		return
	_one_info[0] = chain_info.head_info
	_one_cube[0] = cube
	ChainLink.construct_chain(chain_info, current_beat, _one_info, _one_cube)

# Arcs and chains waiting for a head note that spawns later: they spawn with it, or without a
# head once their beat has passed.
func _spawn_waiting(game: BeepSaber_Game, current_beat: float) -> void:
	for i in range(_arcs_waiting.size() - 1, -1, -1):
		var arc_info := _arcs_waiting[i]
		if arc_info.head_info.spawned != null or arc_info.head_beat < current_beat:
			_arcs_waiting.remove_at(i)
			_spawn_arc(game, arc_info, linked_head(arc_info.head_info), current_beat, _no_cubes)
	for i in range(_chains_waiting.size() - 1, -1, -1):
		var chain_info := _chains_waiting[i]
		if chain_info.head_info.spawned != null or chain_info.head_beat < current_beat:
			_chains_waiting.remove_at(i)
			_construct_linked_chain(chain_info, current_beat)

const Cost := preload("res://game/scripts/CostProbe.gd")

func _process_map(game: BeepSaber_Game) -> void:
	if (Map.current_info == null):
		return
	if Map.spawn_disabled:
		return
	var probe := Cost.enabled
	var t0 := Time.get_ticks_usec() if probe else 0
	
	Harness.tick()
	var song_position := Harness.song_time() if Harness.replay else game.song_player.get_playback_position()
	var current_beat := Map.seconds_to_beat(song_position)
	var look_ahead := current_beat + NoteMotion.spawn_beats()
	
	# chains connect to a regular colornote and modify it, so we have to keep
	# track of what notes were spawned this frame, in case any become the head
	# of a chain.
	# why did they do this?
	var note_info_refs: Array[ColorNoteInfo] = []
	var cube_refs: Array[BeepCube] = []
	
	# spawn notes
	# `spawn_lead` is 0 for every object of an ordinary map; a Noodle object with a longer own
	# half jump spawns that many beats earlier (game/noodle/NoodleTracks.apply_jumps).
	while not MapData.note_stack.is_empty() and MapData.note_stack[-1].beat - MapData.note_stack[-1].spawn_lead <= look_ahead:
		var note := GlobalReferences.cube_pool.acquire() as BeepCube
		var note_info := MapData.note_stack.pop_back() as ColorNoteInfo
		if Map.first_note_ms < 0.0:
			Map.first_note_ms = (Time.get_ticks_usec() - Map.load_finished_usec) / 1000.0
			Map.first_note_beat = note_info.beat
		note.spawn(note_info, current_beat)
		if NoodleTracks.heads_linked:
			note_info.spawned = note
			if note_info.arc_tail_link:
				note.arc_tail = true
		_mark_arc_tail(note)
		TrackLanes.place(note, note_info.beat)
		Harness.log_spawn(note_info)
		note_info_refs.append(note_info)
		cube_refs.append(note)
	if not _arcs_waiting.is_empty() or not _chains_waiting.is_empty():
		_spawn_waiting(game, current_beat)
	
	# spawn bombs
	while not MapData.bomb_stack.is_empty() and MapData.bomb_stack[-1].beat - MapData.bomb_stack[-1].spawn_lead <= look_ahead:
		if debug_skip_bombs:
			MapData.bomb_stack.pop_back()
			continue
		if probe: Cost.objs_spawned += 1
		var bomb := GlobalReferences.bomb_pool.acquire() as Bomb
		var bomb_info := MapData.bomb_stack.pop_back() as BombInfo
		bomb.spawn(bomb_info, current_beat)
		TrackLanes.place(bomb, bomb_info.beat)
	
	# spawn obstacles (walls)
	while not MapData.obstacle_stack.is_empty() and MapData.obstacle_stack[-1].beat - MapData.obstacle_stack[-1].spawn_lead <= look_ahead:
		# FR-026: a fake wall is decorative and must never block or score. Popped without
		# acquiring, so the pool is not touched at all.
		if MapData.obstacle_stack[-1].fake:
			MapData.obstacle_stack.pop_back()
			continue
		if probe: Cost.objs_spawned += 1
		# Pooled, not instantiated. The pool adds its scene to the track at creation, so the
		# node is already in the tree and spawn() can apply its material immediately.
		var wall := GlobalReferences.wall_pool.acquire() as Wall
		var wall_info := MapData.obstacle_stack.pop_back() as ObstacleInfo
		wall.spawn(wall_info, current_beat)
		TrackLanes.place(wall, wall_info.beat)
	
	while not MapData.arc_stack.is_empty() and MapData.arc_stack[-1].head_beat <= look_ahead:
		if probe:
			Cost.objs_spawned += 1
			Cost.arcs_spawned += 1
		# A/B kill switch: arcs rebuild a CSGPolygon3D ribbon on the main thread at every
		# spawn. Disabling them is the cheap way to prove or eliminate that cost before
		# rewriting them. The stack is still popped so timing/spawn order is unchanged.
		if not Arc.spawn_enabled:
			MapData.arc_stack.pop_back()
			continue
		var arc_info := MapData.arc_stack.pop_back() as ArcInfo
		if arc_info.head_info != null:
			# Linked at load: the head may have spawned in an earlier frame, or not yet.
			if arc_info.head_info.spawned == null:
				_arcs_waiting.append(arc_info)
			else:
				_spawn_arc(game, arc_info, linked_head(arc_info.head_info), current_beat, cube_refs)
			continue
		
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
				and is_equal_approx(current_cube.line_index, arc_info.head_line_index)
				and is_equal_approx(current_cube.line_layer, arc_info.head_line_layer)
				):
					cube = current_cube
					break
			cube_id -= 1
		
		_spawn_arc(game, arc_info, cube, current_beat, cube_refs)
	
	while not MapData.chain_stack.is_empty() and MapData.chain_stack[-1].head_beat <= look_ahead:
		var chain_info := MapData.chain_stack.pop_back() as ChainInfo
		if chain_info.slice_count > 1: # skip if the chain doesn't have any links
			if chain_info.head_info == null:
				ChainLink.construct_chain(chain_info, current_beat, note_info_refs, cube_refs)
			elif chain_info.head_info.spawned == null:
				_chains_waiting.append(chain_info)
			else:
				_construct_linked_chain(chain_info, current_beat)
	
	var event_t0 := Time.get_ticks_usec() if probe else 0
	# Noodle Extensions custom events (game/noodle): start the ones that are due, advance the
	# running animations, and draw the world relative to the player's track if there is one.
	# Skipped entirely for a map without tracks or custom events.
	if NoodleTracks.active:
		NoodleAnim.advance(song_position, game.get_physics_process_delta_time())
		NoodleEvents.dispatch_until(current_beat, NoodleAnim.song_sec)
		NoodleEvents.update(NoodleAnim.song_sec)
		game.track.transform = NoodleEvents.root_xform
	var coalesced := {}
	var uncoalesced: Array[EventInfo] = []
	while not MapData.event_stack.is_empty() and MapData.event_stack[-1].beat <= current_beat:
		var event := MapData.event_stack.pop_back() as EventInfo
		if coalesce_lights and event.type >= 0 and event.type <= 7:
			coalesced[event.type] = event
		else:
			uncoalesced.append(event)
	for event in uncoalesced:
		game.event_driver.process_event(event)
	for type in coalesced:
		game.event_driver.process_event(coalesced[type] as EventInfo)
	if probe:
		Cost.event_usec += Time.get_ticks_usec() - event_t0
	
	if probe:
		Cost.spawn_usec += Time.get_ticks_usec() - t0
	game.hide_profile_panel()




