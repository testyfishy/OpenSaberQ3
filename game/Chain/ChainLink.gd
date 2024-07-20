extends Cuttable
class_name ChainLink

var UNIT_VECTORS := PackedVector2Array([Vector2(0,1), Vector2(0,-1), Vector2(-1, 0), Vector2(1, 0), Vector2(-0.7071, 0.7071), Vector2(0.7071, 0.7071), Vector2(-0.7071, -0.7071), Vector2(0.7071, -0.7071), Vector2(0,1)])

func spawn(chain_info: Map.ChainInfo, current_beat: float, color: Color, link_index: int) -> void:
	var lerp_factor := float(link_index) / float(chain_info.slice_count - 1) * chain_info.squish_factor
	speed = Constants.BEAT_DISTANCE * Map.current_info.beats_per_minute * 0.016666666666666667
	beat = lerpf(chain_info.head_beat, chain_info.tail_beat, lerp_factor)
	
	var head_pos := Vector2(Constants.LANE_X[chain_info.head_line_index], Constants.LAYER_Y[chain_info.head_line_layer])
	var tail_pos := Vector2(Constants.LANE_X[chain_info.tail_line_index], Constants.LAYER_Y[chain_info.tail_line_layer])
	var mid_pos := head_pos + (UNIT_VECTORS[chain_info.head_cut_direction] * head_pos.distance_to(tail_pos) * 0.5)
	
	var q0 := head_pos.lerp(mid_pos, lerp_factor)
	var q1 := mid_pos.lerp(tail_pos, lerp_factor)
	var bezier_pos := q0.lerp(q1, lerp_factor)
	
	transform.origin.x = bezier_pos.x
	transform.origin.y = bezier_pos.y
	transform.origin.z = -(beat - current_beat) * Constants.BEAT_DISTANCE
	
	rotation.z = q0.angle_to_point(q1) - TAU*0.25
	
	var instance := $MeshInstance3D as MeshInstance3D
	var material := instance.material_override as StandardMaterial3D
	material.albedo_color = color
	
	visible = true

func on_miss() -> void:
	Scoreboard.reset_combo()
	queue_free()
