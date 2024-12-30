extends Node3D
class_name Arc

static var left_material := load("res://game/Arc/Arc.material").duplicate() as ShaderMaterial
static var right_material := left_material.duplicate() as ShaderMaterial

static var left_material_magnet := left_material.duplicate() as ShaderMaterial
static var right_material_magnet := right_material.duplicate() as ShaderMaterial

@onready var visual: CSGPolygon3D = $Path3D/Visual

var arc_info: ArcInfo
var activator_cube: BeepCube

var speed: float
var despawn_z: float

func spawn(info: ArcInfo, current_beat: float, _activator_cube: BeepCube = null) -> void:
	arc_info = info
	speed = Constants.BEAT_DISTANCE * Map.current_info.beats_per_minute * 0.016666666666666667
	visual = $Path3D/Visual
	visual.material_override = right_material if arc_info.color == 1 else left_material
	activator_cube = _activator_cube
	if activator_cube:
		activator_cube.cutted.connect(_on_activator_cube_cutted)
	else:
		start_magnet()
	
	var head_pos := Vector3(
		Constants.LANE_DISTANCE * float(info.head_line_index) + Constants.LANE_ZERO_X,
		Constants.LANE_DISTANCE * float(info.head_line_layer) + Constants.LAYER_ZERO_Y,
		-(info.head_beat - current_beat) * Constants.BEAT_DISTANCE
	)
	var tail_pos := Vector3(
		Constants.LANE_DISTANCE * float(info.tail_line_index) + Constants.LANE_ZERO_X,
		Constants.LANE_DISTANCE * float(info.tail_line_layer) + Constants.LAYER_ZERO_Y,
		-(info.tail_beat - current_beat) * Constants.BEAT_DISTANCE
	)
	despawn_z = Constants.MISS_Z - tail_pos.z
	
	var head_rotation: Vector2
	var tail_rotation: Vector2
	if info.head_cut_direction == 8:
		head_rotation = Vector2.ZERO
	else:
		head_rotation = Constants.ROTATION_UNIT_VECTORS[info.head_cut_direction] * info.head_control_point_length_multiplier
	if info.tail_cut_direction == 8:
		tail_rotation = Vector2.ZERO
	else:
		tail_rotation = -Constants.ROTATION_UNIT_VECTORS[info.tail_cut_direction] * info.tail_control_point_length_multiplier
	var curve := ($Path3D as Path3D).curve
	curve.set_point_position(0, head_pos)
	curve.set_point_position(1, tail_pos)
	curve.set_point_out(0, Vector3(head_rotation.x, head_rotation.y, 0.0))
	curve.set_point_in(1, Vector3(tail_rotation.x, tail_rotation.y, 0.0))

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
	transform.origin.z += speed * delta
	if transform.origin.z >= despawn_z:
		if activator_cube and activator_cube.cutted.is_connected(_on_activator_cube_cutted):
			activator_cube.cutted.disconnect(_on_activator_cube_cutted)
		queue_free()
