extends Node3D
class_name Arc

# Spike attribution (FR-033): deferred free of a CSG ribbon on the main thread.
const Cost := preload("res://game/scripts/CostProbe.gd")

# A/B switch for spike attribution: each arc spawn rebuilds a CSGPolygon3D ribbon on the main
# thread. Set false to measure the game without arcs and prove or eliminate that cost.
static var spawn_enabled := true

# Arc instances are pooled instead of freed at despawn: spawning was instantiate() +
# add_child() + CSG rebuild per arc, and the instantiation half is pure churn. The CSG
# rebuild itself still happens (the curve differs per arc), but node creation/free stops.
static var _pool: Array = []

func _release_to_pool() -> void:
	if activator_cube and activator_cube.cutted.is_connected(_on_activator_cube_cutted):
		activator_cube.cutted.disconnect(_on_activator_cube_cutted)
	activator_cube = null
	_fly_head = null
	_tail_cube = null
	if arc_info != null and arc_info.spawned_arc == self:
		arc_info.spawned_arc = null
	hide()
	if get_parent() != null:
		get_parent().remove_child(self)
	_pool.append(self)

static var left_material := load("res://game/Arc/Arc.material").duplicate() as ShaderMaterial
static var right_material := left_material.duplicate() as ShaderMaterial

static var left_material_magnet := left_material.duplicate() as ShaderMaterial
static var right_material_magnet := right_material.duplicate() as ShaderMaterial

# The material's distance fade is fragment `length(VERTEX)`, the distance from the camera.
# 0.7.10 to 0.7.39 faded the ribbon out over the last 3 m before the spawn distance (owner
# feedback on 0.7.10: an arc must not be visible before the boxes it joins, when notes popped in
# at the spawn line). Since 0.7.37 notes fly in from 100 m beyond the jump start, and that 3 m
# ramp read as a long arc dying in mid-air. 0.7.40 replaces it with a per-arc boundary tied to the
# tail box (owner: "the arc goes off into the void and then connects when the next box spawns"):
# see _update_tail. The distance fade is pushed out of the way; the tip fade stays off; the magnet
# has its own ease in the shader.
const DISTANCE_FADE_OFF_M := 4000.0
# Before its tail box exists the ribbon trails into the void over the last VOID_FADE_M before the
# point where that box will appear (never past its head), and while the box flies in the last
# TAIL_STRETCH_M of ribbon stretch out to it.
const VOID_FADE_M := 8.0
const TAIL_STRETCH_M := 4.0
# 0.7.40: drawn after the walls (render_priority 0), so a translucent wall in front of an arc no
# longer paints over it: the ribbon reads as a layer on top of the wall (owner, 0.7.39 play-test).
# Depth test stays on, so opaque notes and sabers still hide it. With the bench-only wall variants
# (Wall.depth_prepass: wall_depth.tres writes depth in a prepass; Wall.opaque_walls:
# wall_opaque.tres) the wall is in the depth buffer and still hides an arc behind it.
const RENDER_PRIORITY := 1
static var _fades_configured := false
static var _arc_probe_logged := 0

static func _configure_fades() -> void:
	if _fades_configured:
		return
	_fades_configured = true
	for material: ShaderMaterial in [left_material, right_material, left_material_magnet, right_material_magnet]:
		material.render_priority = RENDER_PRIORITY
		material.set_shader_parameter(&"distance_fade_min", DISTANCE_FADE_OFF_M)
		material.set_shader_parameter(&"distance_fade_max", DISTANCE_FADE_OFF_M - 1.0)
		material.set_shader_parameter(&"void_fade_m", VOID_FADE_M)
		material.set_shader_parameter(&"tail_stretch_m", TAIL_STRETCH_M)
		material.set_shader_parameter(&"distance_fade_tip_min", -10.0)
		material.set_shader_parameter(&"distance_fade_tip_max", -5.0)
		# specs/027 0.7.6: a brighter, more solid ribbon reads as a light line rather than a
		# faint ribbon that seems to start in mid-air.
		material.set_shader_parameter(&"emission", 2.2)
		material.set_shader_parameter(&"noise_mult", 3.2)

## Called when a map is loaded: where a tail box appears depends on the map's motion.
static func apply_spawn_distance() -> void:
	_configure_fades()
	_tail_appear_d = NoteMotion.spawn_distance() + NoteMotion.njs() * NoteMotion.fly_in_seconds()

# How far down the track (travel) a note is when it appears: its jump start plus the fly-in.
static var _tail_appear_d := 16.0

## Fills the pool to `count` arcs at map load, so no arc is instantiated mid-song. Each is added to
## `parent` once (its _ready runs) and released straight back.
static func prewarm(count: int, parent: Node) -> void:
	while _pool.size() < count:
		var arc := preload("res://game/Arc/Arc.tscn").instantiate() as Arc
		parent.add_child(arc)
		arc._release_to_pool()

static func acquire() -> Arc:
	_configure_fades()
	if _pool.is_empty():
		if Cost.enabled:
			Cost.instantiated += 1
		return preload("res://game/Arc/Arc.tscn").instantiate() as Arc
	return _pool.pop_back() as Arc

@onready var visual: CSGPolygon3D = $Path3D/Visual

var arc_info: ArcInfo
var activator_cube: BeepCube

# Handle length as a fraction of the head-to-tail chord, and the loop guard as a fraction of
# the same chord. Tuning start: the arc's in-VR swing is still to be compared against the notes.
const ARC_HANDLE_FRACTION := 0.35
const ARC_HANDLE_CAP := 0.6

var speed: float
var despawn_z: float
# Fly-in (0.7.40): while its head note flies in, the arc comes in with it at the fly-in speed and
# switches to `speed` when the head's jump starts, at origin z `_fly_end_z`. INF when not flying,
# so _process pays one compare.
var _rate := 0.0
var _fly_end_z := INF
# A flying head note, followed directly (it moves on physics ticks, the arc on frames: at 200 m/s a
# tick apart is 1.7 m), and the head's z in the arc's own space.
var _fly_head: Cuttable = null
var _head_local_z := 0.0

# The tail box (0.7.40). Until it has reached its jump start the arc works out each frame where it
# is, from the arc's own travel (no tail note needed: an arc ending on nothing behaves the same):
#   TAIL_NOT_YET  it does not exist yet: the ribbon is cut at `void_z` (where it will appear)
#   TAIL_FLYING   it flies in: the ribbon's end is stretched `tail_fly` metres out onto it
#   TAIL_HERE     it is in its jump: nothing more to do (_process pays one compare)
enum { TAIL_HERE, TAIL_NOT_YET, TAIL_FLYING }
var _tail_state := TAIL_HERE
var _travel := 0.0
var _tail_path_z := 0.0
# The tail note, when the spawner links it (Playing._mark_arc_tail): followed directly while it
# flies in, as the head is. Mirrors of the instance uniforms, for the harness.
var _tail_cube: Cuttable = null
var void_z := -10000.0
var tail_fly := 0.0

func spawn(info: ArcInfo, current_beat: float, _activator_cube: BeepCube = null) -> void:
	arc_info = info
	# Pooled reuse: a recycled arc keeps the previous arc's travelled distance and hidden state.
	transform.origin.z = 0.0
	show()
	speed = NoteMotion.speed_at(info.head_beat)
	_rate = speed
	_fly_end_z = INF
	_fly_head = null
	_tail_cube = null
	_travel = 0.0
	visual = $Path3D/Visual
	visual.material_override = right_material if arc_info.color == 1 else left_material
	activator_cube = _activator_cube
	if activator_cube:
		# One-shot: a note that is released (missed) goes back to the pool, and a stale
		# connection would let the NEXT note reusing that cube fire this arc's magnet.
		activator_cube.cutted.connect(_on_activator_cube_cutted, CONNECT_ONE_SHOT)
	else:
		# No head note (missing/fake): attach the visible head to the saber. The old comment
		# against this assumed a head note that the player would cut; with none, the arc had no
		# visible anchor and started in mid-air.
		start_magnet()

	
	var head_pos := Vector3(
		Constants.LANE_DISTANCE * float(info.head_line_index) + Constants.LANE_ZERO_X,
		Constants.LANE_DISTANCE * float(info.head_line_layer) + Constants.LAYER_ZERO_Y,
		-NoteMotion.distance_between(current_beat, info.head_beat)
	)
	# specs/027 FR-021 (0.7.5): use the spawned head note's own position when it exists. The lane
	# formula and the note must place the head at the same point; Noodle position, precision lanes
	# or a different motion reference would otherwise leave the ribbon floating off the cube.
	if activator_cube != null and activator_cube.is_inside_tree():
		var lane := activator_cube.get_parent()
		if lane == null or not String(lane.name).begins_with("Lane"):
			lane = null
		var cube_pos := activator_cube.position
		# A head note still flying in (its own jump starts later than the arc's) is drawn further
		# out than its travel; the ribbon is built on the travel.
		cube_pos.z -= activator_cube.fly_offset()
		if lane != null and cube_pos.distance_to(head_pos) > 0.01:
			if _arc_probe_logged < 10:
				_arc_probe_logged += 1
				vr.log_info("ARC head off by %.3f m (note %s, lane %s)" % [
					cube_pos.distance_to(head_pos), str(cube_pos), str(head_pos)])
			head_pos = cube_pos
	var tail_pos := Vector3(
		Constants.LANE_DISTANCE * float(info.tail_line_index) + Constants.LANE_ZERO_X,
		Constants.LANE_DISTANCE * float(info.tail_line_layer) + Constants.LAYER_ZERO_Y,
		-NoteMotion.distance_between(current_beat, info.tail_beat)
	)
	despawn_z = Constants.MISS_Z - tail_pos.z

	# One cubic Bezier from the head note centre to the tail note centre. The old version
	# planted three extra points by rotating the head cut vector by PI/TAU and then smoothed
	# them; on any arc with a mid-anchor mode that produced a self-crossing loop, and on a
	# short hop the fixed 2 m handles threw the ribbon metres off the notes.
	var curve := ($Path3D as Path3D).curve
	curve.clear_points()

	# sets the origin of the tail at the tail point to use in the shader for a fade out effect
	$Path3D.position = tail_pos

	var chord := tail_pos - head_pos
	var chord_length := chord.length()
	var head_dir := _cut_direction(info.head_cut_direction)
	# the tail handle points back toward the head, as in the map's tail cut direction
	var tail_dir := -_cut_direction(info.tail_cut_direction)

	# midAnchorMode can only add information when the cut directions cannot describe the bow:
	# a dot head/tail, or directions about 180 degrees apart. Then the ribbon bows sideways
	# (a C, not an S) in the mode's direction.
	var opposed := head_dir != Vector3.ZERO and tail_dir != Vector3.ZERO and head_dir.dot(-tail_dir) < -0.94
	if info.mid_anchor_mode != 0 and (head_dir == Vector3.ZERO or tail_dir == Vector3.ZERO or opposed):
		var side := -1.0 if info.mid_anchor_mode == 1 else 1.0
		var perp := Vector3(-chord.y, chord.x, 0.0)
		if perp.length_squared() < 0.000001:
			perp = Vector3(1.0, 0.0, 0.0)
		head_dir = perp.normalized() * side
		tail_dir = head_dir
	elif head_dir == Vector3.ZERO:
		head_dir = chord.normalized()
	elif tail_dir == Vector3.ZERO:
		tail_dir = -chord.normalized()

	# Handle length follows the map's mu/tmu and the distance between the notes, so a 1 m hop
	# and an 8 m slide get the same shape. The cap leaves no room for a loop.
	var handle := chord_length * ARC_HANDLE_FRACTION
	var head_handle := minf(handle * info.head_control_point_length_multiplier, chord_length * ARC_HANDLE_CAP)
	var tail_handle := minf(handle * info.tail_control_point_length_multiplier, chord_length * ARC_HANDLE_CAP)

	curve.add_point(head_pos - tail_pos, Vector3.ZERO, head_dir * head_handle)
	curve.add_point(Vector3.ZERO, tail_dir * tail_handle, Vector3.ZERO)
	_rebuild_ribbon()
	_tail_path_z = tail_pos.z
	_head_local_z = tail_pos.z + (head_pos - tail_pos).z
	visual.set_instance_shader_parameter(&"head_z", (head_pos - tail_pos).z)
	visual.set_instance_shader_parameter(&"void_z", -10000.0)
	visual.set_instance_shader_parameter(&"tail_fly", 0.0)
	void_z = -10000.0
	tail_fly = 0.0
	_tail_state = TAIL_NOT_YET if NoteMotion.fly_in_seconds() > 0.0 else TAIL_HERE
	_update_tail()

## Called by the spawner right after spawn(), when the arc's head note (or, with none, a head at
## head_beat) has its jump start `rem_sec` from now: the arc is drawn as far out as that head
## (NoteMotion fly-in: 200 m/s, arriving at the jump start) and flies in with it, so the ribbon
## arrives attached to its head box. spawn() built the ribbon on the head's travel position, so
## this only moves the arc's origin.
func fly_in(rem_sec: float) -> void:
	if rem_sec <= 0.0 or speed <= 0.0:
		return
	var fly_speed := NoteMotion.fly_in_speed()
	if fly_speed <= speed:
		return
	_fly_end_z = speed * rem_sec
	transform.origin.z = -(fly_speed - speed) * rem_sec
	_rate = fly_speed
	# Followed only when it is a plain note drawn in the arc's own lane (a Noodle note's z is
	# animated; its arc keeps the computed fly-in).
	_fly_head = activator_cube if _followable(activator_cube) else null
	_update_tail()

func _followable(cube: Cuttable) -> bool:
	return cube != null and cube.is_flying() and cube.noodle == null and cube.get_parent() == get_parent()

## The spawner links the tail note when it appears (Playing._mark_arc_tail).
func set_tail_cube(cube: Cuttable) -> void:
	_tail_cube = cube if _followable(cube) else null
	_update_tail()

## Where the tail box is, from the arc's travel; writes the instance uniforms that changed.
func _update_tail() -> void:
	if _tail_state == TAIL_HERE:
		return
	var tail_travel := _travel + _tail_path_z
	# The ribbon's tail (its own space's origin) as drawn: the arc's origin carries the head's fly-in.
	var tail_drawn := transform.origin.z + _tail_path_z
	var left := -NoteMotion.spawn_distance() - tail_travel
	if _tail_cube != null and _tail_cube.is_flying():
		_set_tail(TAIL_FLYING, tail_drawn - _tail_cube.position.z)
	elif left <= 0.0 or _tail_cube != null:
		_set_tail(TAIL_HERE, 0.0)
	elif left <= speed * NoteMotion.fly_in_seconds():
		# The box is drawn (200 / speed - 1) x left beyond its travel (Cuttable.fly_in).
		var box_drawn := tail_travel - (NoteMotion.fly_in_speed() / speed - 1.0) * left
		_set_tail(TAIL_FLYING, tail_drawn - box_drawn)
	else:
		var vz := -_tail_appear_d - tail_drawn
		if vz != void_z:
			void_z = vz
			visual.set_instance_shader_parameter(&"void_z", vz)

func _set_tail(state: int, fly: float) -> void:
	if state != TAIL_NOT_YET and void_z != -10000.0:
		void_z = -10000.0
		visual.set_instance_shader_parameter(&"void_z", void_z)
	if fly != tail_fly:
		tail_fly = fly
		visual.set_instance_shader_parameter(&"tail_fly", fly)
	_tail_state = state
	if state == TAIL_HERE:
		_tail_cube = null

func is_flying() -> bool:
	return _fly_end_z != INF

func _fly_step(delta: float) -> void:
	if _fly_head != null:
		# On the head box wherever it is drawn; when its jump starts, on at the jump speed.
		transform.origin.z = _fly_head.position.z - _head_local_z
		if not _fly_head.is_flying():
			_fly_head = null
			_fly_end_z = INF
		return
	transform.origin.z += _rate * delta
	if transform.origin.z > _fly_end_z:
		# The jump started this frame: the rest of the frame at the jump speed.
		transform.origin.z = _fly_end_z + (transform.origin.z - _fly_end_z) * speed / _rate
		_fly_end_z = INF

# 0.7.39: the ribbon (a CSGPolygon3D following the Path3D) did not rebuild when spawn() rewrote the
# curve of a reused arc (out of the tree, and in the harness not even in it). Since 0.7.36 every
# arc is reused (Arc.prewarm fills the pool at map load with arcs built on the scene's default
# curve), so every arc drew that default:
# a straight 10 m rod running away from its tail, not the curve between its notes. With the
# saber magnet hiding everything nearer than the blade, the arc then seemed to vanish when its
# head was cut. Setting the path node marks the CSG dirty in any case, in or out of the tree.
func _rebuild_ribbon() -> void:
	visual.path_node = visual.path_node

# Note cut direction (0..7) as a unit vector in the play plane; a dot (8) has no direction.
func _cut_direction(cut_direction: int) -> Vector3:
	if cut_direction < 0 or cut_direction > 7:
		return Vector3.ZERO
	var unit := Constants.ROTATION_UNIT_VECTORS[cut_direction]
	return Vector3(unit.x, unit.y, 0.0)


func _on_activator_cube_cutted(correct_saber: bool) -> void:
	if activator_cube and activator_cube.cutted.is_connected(_on_activator_cube_cutted):
		activator_cube.cutted.disconnect(_on_activator_cube_cutted)
	if correct_saber:
		start_magnet()

# sets the magnet version of the material (and ensures correct magnet parameter)
func start_magnet() -> void:
	visual.material_override = right_material_magnet if arc_info.color == 1 else left_material_magnet
	visual.material_override.set_shader_parameter(&"saber_magnet", arc_info.color+1)

func _process(delta: float) -> void:
	if Scoreboard.paused or not is_visible_in_tree() or not Map.current_info: return
	var t0 := Time.get_ticks_usec() if Cost.enabled else 0
	if _fly_end_z == INF:
		transform.origin.z += speed * delta
	else:
		_fly_step(delta)
	if _tail_state != TAIL_HERE:
		_travel += speed * delta
		_update_tail()
	if Cost.enabled:
		Cost.arc_usec += Time.get_ticks_usec() - t0
	if transform.origin.z >= despawn_z:
		if Cost.enabled: Cost.objs_freed += 1
		_release_to_pool()


