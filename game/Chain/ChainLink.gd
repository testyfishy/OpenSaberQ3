extends Cuttable
class_name ChainLink

var which_saber: int

# do not make this a preload.  doing so will make the scene show up as corrupt
# in the editor.
static var CHAIN_LINK_TEMPLATE := load("res://game/Chain/ChainLink.tscn") as PackedScene
static var UNIT_VECTORS := PackedVector2Array([
	Vector2(0, 1), Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0),
	Vector2(-0.70710678, 0.70710678), Vector2(0.70710678, 0.70710678),
	Vector2(-0.70710678, -0.70710678), Vector2(0.70710678, -0.70710678), Vector2(0,1)
])

static func construct_chain(chain_info: ChainInfo, track_ref: Node3D, current_beat: float, note_info_refs: Array[ColorNoteInfo], cube_refs: Array[BeepCube]) -> void:
	var color := Map.color_left if chain_info.color == 0 else Map.color_right
	# instead of just making a new note head for a new chain, beat saber
	# modifies an already-existing note to be the head, which is why we have to
	# do all this garbage with keeping references to other notes that were
	# spawned this frame.
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
	
	# the curve of the chain is gotten from a 3-point bezier curve.  the first
	# point is the head position, the last point is the tail position, and the
	# mid point is based on the head and tail points.
	#
	# to get the mid point, draw a straight line from the head note, in the
	# direction the head note is pointing, with length equal to half the length
	# of a straight line from the head to the tail.  the end point of the line
	# you just drew is the mid point of the curve.
	var head_pos := Vector2(Constants.LANE_X[chain_info.head_line_index], Constants.LAYER_Y[chain_info.head_line_layer])
	var tail_pos := Vector2(Constants.LANE_X[chain_info.tail_line_index], Constants.LAYER_Y[chain_info.tail_line_layer])
	var mid_pos := head_pos + (UNIT_VECTORS[chain_info.head_cut_direction] * head_pos.distance_to(tail_pos) * 0.5)
	i = 1
	while i <= chain_info.slice_count:
		var chain_link := CHAIN_LINK_TEMPLATE.instantiate() as ChainLink
		chain_link.spawn(chain_info, current_beat, color, head_pos, tail_pos, mid_pos, i)
		track_ref.add_child(chain_link)
		i += 1

func spawn(chain_info: ChainInfo, current_beat: float, color: Color, head_pos: Vector2, tail_pos: Vector2, mid_pos: Vector2, link_index: int) -> void:
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
	
	# little bit of forgiveness.  if the chain link is more than a meter away
	# from the chain head, its hitbox is extended to halfway between the link
	# and the head.
	var z_distance_from_head := (beat - chain_info.head_beat) * Constants.BEAT_DISTANCE
	if z_distance_from_head > 1.0:
		var collision := $Area3D/CollisionShape3D as CollisionShape3D
		var new_size := z_distance_from_head * 0.5
		(collision.shape as BoxShape3D).size.z = new_size
		collision.transform.origin.z = new_size * 0.5 - 0.25
	
	var instance := $Mesh as MeshInstance3D
	var material := instance.material_override as ShaderMaterial
	material.set_shader_parameter(&"color", color)
	
	visible = true

func cut(saber_type: int, _cut_speed: Vector3, _cut_plane: Plane, _controller: BeepSaberController) -> void:
	if saber_type == which_saber:
		Scoreboard.chain_link_cut(transform.origin)
	else:
		Scoreboard.bad_cut(transform.origin)
	queue_free()

func on_miss() -> void:
	Scoreboard.reset_combo()
	queue_free()
