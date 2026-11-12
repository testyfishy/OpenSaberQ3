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
	hide()
	if get_parent() != null:
		get_parent().remove_child(self)
	_pool.append(self)

static var left_material := load("res://game/Arc/Arc.material").duplicate() as ShaderMaterial
static var right_material := left_material.duplicate() as ShaderMaterial

static var left_material_magnet := left_material.duplicate() as ShaderMaterial
static var right_material_magnet := right_material.duplicate() as ShaderMaterial

# The material's distance fade is fragment `length(VERTEX)`, the distance from the camera. Notes
# spawn 4 beats (16 m) ahead, and an arc's tail can be many beats beyond its head, so an arc
# drawn at full length reaches into space where no note exists yet. Owner feedback on 0.7.10:
# an arc must not be visible before the boxes it joins. The ribbon therefore fades in across the
# last 3 m before the spawn distance and grows out of the horizon with its notes. (0.6.5 pushed
# the fade out to 40..60 m to stop the far end popping in at 15 m; this keeps that fix - the
# fade is smooth and ends at full strength 13 m out - without showing the far end early.)
# The tip fade stays off; the magnet has its own ease in the shader.
const SPAWN_DISTANCE_M := 16.0
const FADE_IN_M := 3.0
static var _fades_configured := false
static var _arc_probe_logged := 0

static func _configure_fades() -> void:
	if _fades_configured:
		return
	_fades_configured = true
	for material: ShaderMaterial in [left_material, right_material, left_material_magnet, right_material_magnet]:
		material.set_shader_parameter(&"distance_fade_min", SPAWN_DISTANCE_M)
		material.set_shader_parameter(&"distance_fade_max", SPAWN_DISTANCE_M - FADE_IN_M)
		material.set_shader_parameter(&"distance_fade_tip_min", -10.0)
		material.set_shader_parameter(&"distance_fade_tip_max", -5.0)
		# specs/027 0.7.6: a brighter, more solid ribbon reads as a light line rather than a
		# faint ribbon that seems to start in mid-air.
		material.set_shader_parameter(&"emission", 2.2)
		material.set_shader_parameter(&"noise_mult", 3.2)

static func acquire() -> Arc:
	_configure_fades()
	if _pool.is_empty():
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

func spawn(info: ArcInfo, current_beat: float, _activator_cube: BeepCube = null) -> void:
	arc_info = info
	# Pooled reuse: a recycled arc keeps the previous arc's travelled distance and hidden state.
	transform.origin.z = 0.0
	show()
	speed = NoteMotion.speed_at(info.head_beat)
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
		-(info.head_beat - current_beat) * Constants.BEAT_DISTANCE
	)
	# specs/027 FR-021 (0.7.5): use the spawned head note's own position when it exists. The lane
	# formula and the note must place the head at the same point; Noodle position, precision lanes
	# or a different motion reference would otherwise leave the ribbon floating off the cube.
	if activator_cube != null and activator_cube.is_inside_tree():
		var lane := activator_cube.get_parent()
		if lane == null or not String(lane.name).begins_with("Lane"):
			lane = null
		var cube_pos := activator_cube.position
		if lane != null and cube_pos.distance_to(head_pos) > 0.01:
			if _arc_probe_logged < 10:
				_arc_probe_logged += 1
				vr.log_info("ARC head off by %.3f m (note %s, lane %s)" % [
					cube_pos.distance_to(head_pos), str(cube_pos), str(head_pos)])
			head_pos = cube_pos
	var tail_pos := Vector3(
		Constants.LANE_DISTANCE * float(info.tail_line_index) + Constants.LANE_ZERO_X,
		Constants.LANE_DISTANCE * float(info.tail_line_layer) + Constants.LAYER_ZERO_Y,
		-(info.tail_beat - current_beat) * Constants.BEAT_DISTANCE
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
	transform.origin.z += speed * delta
	if Cost.enabled:
		Cost.arc_usec += Time.get_ticks_usec() - t0
	if transform.origin.z >= despawn_z:
		if Cost.enabled: Cost.objs_freed += 1
		_release_to_pool()


