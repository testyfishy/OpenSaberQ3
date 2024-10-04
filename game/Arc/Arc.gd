extends Node3D
class_name Arc

static var left_material := load("res://game/Arc/Arc.material").duplicate() as ShaderMaterial
static var right_material := left_material.duplicate() as ShaderMaterial

var color: int
var speed: float

func spawn(info: ArcInfo, current_beat: float) -> void:
	speed = Constants.BEAT_DISTANCE * Map.current_info.beats_per_minute * 0.016666666666666667
	color = info.color
	
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
	var mid_pos := head_pos.lerp(tail_pos, 0.5)
	
	var path := $Path3D as Path3D
	print(head_pos)
	path.curve.set_point_position(0, head_pos)
	path.curve.set_point_position(1, mid_pos)
	path.curve.set_point_position(2, tail_pos)

func _process(delta: float) -> void:
	transform.origin.z += speed * delta
	if transform.origin.z > 16.0:
		queue_free()
