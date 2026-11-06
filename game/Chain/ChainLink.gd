extends Cuttable
class_name ChainLink

var which_saber: int
var _mesh: Mesh
var _mat: ShaderMaterial
@export var min_speed := 0.5

@onready var mi := $LinkBody/Mesh as MeshInstance3D
@onready var _link_body := $LinkBody as Node3D

var piece_left : CutPiece = null
var piece_right : CutPiece = null

func _ready() -> void:
	_mat = mi.material_override as ShaderMaterial
	_mesh = mi.mesh
	
	if bool(ProjectSettings.get_setting(SETTING_ISOLATE_SHAPES, false)):
		# spawn() mutates size.z per link; without a private copy every live
		# link would share the most recently spawned link's hitbox.
		var cs := $Area3D/CollisionShape3D as CollisionShape3D
		cs.shape = cs.shape.duplicate()
	
	# init our cut pieces with unique copies of our own material for reference,
	# and disable "bouncy" physics behavior
	piece_left = CutPiece.new(self, _mesh, _mat.duplicate(true) as ShaderMaterial, false)
	piece_right = CutPiece.new(self, _mesh, _mat.duplicate(true) as ShaderMaterial, false)
	piece_left.set_chain_head(false)
	piece_right.set_chain_head(false)

static func construct_chain(chain_info: ChainInfo, current_beat: float, note_info_refs: Array[ColorNoteInfo], cube_refs: Array[BeepCube]) -> void:
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
	var head_pos := Vector2(
		Constants.LANE_DISTANCE * float(chain_info.head_line_index) + Constants.LANE_ZERO_X,
		Constants.LANE_DISTANCE * float(chain_info.head_line_layer) + Constants.LAYER_ZERO_Y
	)
	var tail_pos := Vector2(
		Constants.LANE_DISTANCE * float(chain_info.tail_line_index) + Constants.LANE_ZERO_X,
		Constants.LANE_DISTANCE * float(chain_info.tail_line_layer) + Constants.LAYER_ZERO_Y
	)
	var mid_pos := head_pos + (Constants.ROTATION_UNIT_VECTORS[chain_info.head_cut_direction] * head_pos.distance_to(tail_pos) * 0.5)
	i = 1
	while i < chain_info.slice_count:
		var chain_link := GlobalReferences.link_pool.acquire() as ChainLink
		chain_link.spawn(chain_info, current_beat, head_pos, tail_pos, mid_pos, i)
		i += 1

static func _bezier_point(head_pos: Vector2, mid_pos: Vector2, tail_pos: Vector2, t: float) -> Vector2:
	var q0 := head_pos.lerp(mid_pos, t)
	var q1 := mid_pos.lerp(tail_pos, t)
	return q0.lerp(q1, t)

# Distance from this link to its neighbour, along the same curve the positions come from.
# The link mesh is 0.5 m deep; slices are one beat-step apart, which on a fast chain is over a
# metre, so without this the links render as detached squares.
static func _link_length(chain_info: ChainInfo, head_pos: Vector2, mid_pos: Vector2, tail_pos: Vector2, t0: float) -> float:
	var links := maxi(chain_info.slice_count - 1, 1)
	var dt := chain_info.squish_factor / float(links)
	if dt <= 0.00001:
		return 0.5
	var t1 := t0 + dt
	if t1 > 1.0 + 0.0001:
		t1 = t0 - dt   # last link: measure back to the one before it
	var p0 := _bezier_point(head_pos, mid_pos, tail_pos, t0)
	var p1 := _bezier_point(head_pos, mid_pos, tail_pos, clampf(t1, 0.0, 1.0))
	var dz := (
		lerpf(chain_info.head_beat, chain_info.tail_beat, clampf(t1, 0.0, 1.0))
		- lerpf(chain_info.head_beat, chain_info.tail_beat, t0)
	) * Constants.BEAT_DISTANCE
	# Clamped so a malformed slice count cannot produce a link metres long.
	return clampf(Vector3(p1.x - p0.x, p1.y - p0.y, dz).length(), 0.1, 4.0)

func spawn(chain_info: ChainInfo, current_beat: float, head_pos: Vector2, tail_pos: Vector2, mid_pos: Vector2, link_index: int) -> void:
	# re-enable our process_mode first otherwise it seems like Godot-internals
	# can behave weirdly (ex. AnimationPlayer won't always play correctly)
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	var color := MapPalette.color_left if chain_info.color == 0 else MapPalette.color_right
	speed = NoteMotion.speed_at(chain_info.head_beat)
	which_saber = chain_info.color
	
	var lerp_factor := float(link_index) / float(chain_info.slice_count - 1) * chain_info.squish_factor
	beat = lerpf(chain_info.head_beat, chain_info.tail_beat, lerp_factor)
	
	var q0 := head_pos.lerp(mid_pos, lerp_factor)
	var q1 := mid_pos.lerp(tail_pos, lerp_factor)
	var bezier_pos := q0.lerp(q1, lerp_factor)
	
	transform.origin.x = bezier_pos.x
	transform.origin.y = bezier_pos.y
	transform.origin.z = -(beat - current_beat) * Constants.BEAT_DISTANCE
	
	# Orient the link along the chord to the next link in 3D. Rotating only in the XY plane left
	# the link's length axis pointing down world z while the chain curved sideways, so a curved
	# chain rendered as parallel bars running past each other ("a line between the boxes").
	var t_next := clampf(lerp_factor + chain_info.squish_factor / float(maxi(chain_info.slice_count - 1, 1)), 0.0, 1.0)
	var q0n := head_pos.lerp(mid_pos, t_next)
	var q1n := mid_pos.lerp(tail_pos, t_next)
	var next_pos := q0n.lerp(q1n, t_next)
	var next_z := -(lerpf(chain_info.head_beat, chain_info.tail_beat, t_next) - current_beat) * Constants.BEAT_DISTANCE
	var here := Vector3(bezier_pos.x, bezier_pos.y, transform.origin.z)
	var there := Vector3(next_pos.x, next_pos.y, next_z)
	var chord := there - here
	if chord.length_squared() > 0.000001:
		var dir := chord.normalized()
		var side := Vector3.UP.cross(dir)
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT
		side = side.normalized()
		transform.basis = Basis(side, dir.cross(side), dir)
	
	# The link model is a 0.5 m plate, but slices are far apart: a 1-beat chain with two links
	# puts them 2 m apart, so the old build showed a row of detached squares with a gap between
	# each. Stretch each link along z to exactly span the distance to its neighbour (plus 6% so
	# the ends meet at bends), which is what the hitbox already assumed - it is 1 m deep while
	# the mesh was 0.5 m. The last link measures backwards to the one before it.
	_link_body.scale = Vector3(1.0, 1.0, _link_length(chain_info, head_pos, mid_pos, tail_pos, lerp_factor) * 2.12)
	
	# little bit of forgiveness.  if the chain link is more than a meter away
	# from the chain head, its hitbox is extended to halfway between the link
	# and the head.
	var z_distance_from_head := (beat - chain_info.head_beat) * Constants.BEAT_DISTANCE
	if z_distance_from_head > 1.0:
		var collision := $Area3D/CollisionShape3D as CollisionShape3D
		var new_size := z_distance_from_head * 0.5
		(collision.shape as BoxShape3D).size.z = new_size
		collision.transform.origin.z = new_size * 0.5 - 0.25
	
	piece_left.set_color(color)
	piece_right.set_color(color)
	_mat.set_shader_parameter(&"color", color)
	
	var anim := $AnimationPlayer as AnimationPlayer
	var anim_speed := Map.current_difficulty.note_jump_movement_speed / 9.0
	anim.speed_scale = maxf(min_speed,anim_speed)
	anim.play(&"Spawn")
	
	mi.visible = true

# call this when clearing the track
func clear_from_track() -> void:
	hide_cube()
	piece_left.hide_piece()
	piece_right.hide_piece()
	if ! is_released():
		release()

func hide_cube() -> void:
	mi.visible = false
	set_collision_enabled(false)
	# disable processing on this node and all children to help with performance
	process_mode = Node.PROCESS_MODE_DISABLED # disable to help with performance

func cut(saber_type: int, _cut_speed: Vector3, cut_plane: Plane, _controller: BeepSaberController) -> HitInfo:
	if saber_type == which_saber:
		Scoreboard.chain_link_cut(transform.origin)
	else:
		Scoreboard.bad_cut(transform.origin)
	
	hide_cube()
	if Settings.cube_cuts_falloff:
		_start_cut_pieces(cut_plane)
		# release() will be called by Cuttable class when it sees both pieces die
	else:
		release()# release now instead of waiting for cut pieces to die off
	# Chain links carry no hit data: the sabre plays its light tap. Nullable by
	# design, see HitInfo.gd.
	return null

func on_miss() -> void:
	Scoreboard.reset_combo()
	hide_cube()
	release()

func set_collision_disabled(value: bool) -> void:
	($Area3D/CollisionShape3D as CollisionShape3D).disabled = value

func _start_cut_pieces(cutplane: Plane) -> void:
	piece_left.global_transform = global_transform
	piece_right.global_transform = global_transform
	
	# calculate angle and position of the cut
	var cut_angle_abs := Vector2(cutplane.normal.x, cutplane.normal.y).angle()
	var cut_dist_from_center := cutplane.distance_to(transform.origin)
	var cut_angle_rel := cut_angle_abs - global_rotation.z
	
	_piece_death_count = 0
	piece_left.start_cut(-cut_dist_from_center, cut_angle_rel + PI)
	piece_right.start_cut(cut_dist_from_center, cut_angle_rel)
	
	# some impulse so the cube half moves
	var split_vector := cutplane.normal * 2.0
	piece_left.apply_central_impulse(-split_vector)
	piece_right.apply_central_impulse(split_vector)
