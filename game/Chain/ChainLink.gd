extends Cuttable
class_name ChainLink

var which_saber: int

func spawn(chain_info: Map.ChainInfo, current_beat: float, color: Color, head_pos: Vector2, tail_pos: Vector2, mid_pos: Vector2, link_index: int) -> void:
	speed = Constants.BEAT_DISTANCE * Map.current_info.beats_per_minute * 0.016666666666666667
	which_saber = chain_info.color
	
	var lerp_factor := float(link_index) / float(chain_info.slice_count - 1) * chain_info.squish_factor
	beat = lerpf(chain_info.head_beat, chain_info.tail_beat, lerp_factor)
	
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

func cut(saber_type: int, cut_speed: Vector3, cut_plane: Plane, controller: BeepSaberController) -> void:
	if saber_type == which_saber:
		Scoreboard.chain_link_cut(transform.origin)
	else:
		Scoreboard.bad_cut(transform.origin)
	queue_free()

func on_miss() -> void:
	Scoreboard.reset_combo()
	queue_free()
