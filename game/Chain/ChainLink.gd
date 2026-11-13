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
	
	# spawn() sets size.z to this link's segment; without a private copy every live link
	# would share the most recently spawned link's hitbox.
	var cs := $Area3D/CollisionShape3D as CollisionShape3D
	if cs.shape != null:
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
			and is_equal_approx(info_ref.line_index, chain_info.head_line_index)
			and is_equal_approx(info_ref.line_layer, chain_info.head_line_layer)
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
		TrackLanes.place(chain_link, chain_info.head_beat)
		i += 1

static func _bezier_point(head_pos: Vector2, mid_pos: Vector2, tail_pos: Vector2, t: float) -> Vector2:
	var q0 := head_pos.lerp(mid_pos, t)
	var q1 := mid_pos.lerp(tail_pos, t)
	return q0.lerp(q1, t)

# One point on the chain curve, in 3D: bezier XY plus the beat's distance along z.
# `t` runs 0..squish along the chain (the spawner's range), not 0..1 of the raw tail.
static func chain_point(chain_info: ChainInfo, head_pos: Vector2, mid_pos: Vector2, tail_pos: Vector2, t: float, current_beat: float) -> Vector3:
	var q0 := head_pos.lerp(mid_pos, t)
	var q1 := mid_pos.lerp(tail_pos, t)
	var xy := q0.lerp(q1, t)
	var beat := lerpf(chain_info.head_beat, chain_info.tail_beat, t)
	return Vector3(xy.x, xy.y, -NoteMotion.distance_between(current_beat, beat))

# The segment link_index occupies: link 1 spans head -> first slice point, the last spans the
# previous point -> the tail point. Both t values are inside 0..squish.
static func link_segment_t(chain_info: ChainInfo, link_index: int) -> Vector2:
	var links := maxi(chain_info.slice_count - 1, 1)
	return Vector2(
		float(link_index - 1) / float(links) * chain_info.squish_factor,
		float(link_index) / float(links) * chain_info.squish_factor
	)

func spawn(chain_info: ChainInfo, current_beat: float, head_pos: Vector2, tail_pos: Vector2, mid_pos: Vector2, link_index: int) -> void:
	# re-enable our process_mode first otherwise it seems like Godot-internals
	# can behave weirdly (ex. AnimationPlayer won't always play correctly)
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	var color := MapPalette.color_left if chain_info.color == 0 else MapPalette.color_right
	speed = NoteMotion.speed_at(chain_info.head_beat)
	which_saber = chain_info.color
	
	var span := link_segment_t(chain_info, link_index)
	var p0 := chain_point(chain_info, head_pos, mid_pos, tail_pos, span.x, current_beat)
	var p1 := chain_point(chain_info, head_pos, mid_pos, tail_pos, span.y, current_beat)
	var segment := p1 - p0
	var segment_len := segment.length()
	var center := (p0 + p1) * 0.5
	beat = lerpf(chain_info.head_beat, chain_info.tail_beat, (span.x + span.y) * 0.5)
	transform.origin = center
	if segment_len > 0.0001:
		var dir := segment / segment_len
		var side := Vector3.UP.cross(dir)
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT
		side = side.normalized()
		transform.basis = Basis(side, dir.cross(side).normalized(), dir)
	
	# The mesh spans exactly its segment, plus half its width at each end so the outside of a
	# bend is covered instead of showing a wedge-shaped gap. The link material is additive, so
	# the small joint overlap brightens the joint rather than z-fighting.
	var aabb := _mesh.get_aabb()
	var width := maxf(aabb.size.x, 0.0001)
	var depth := maxf(aabb.size.z, 0.0001)
	_link_body.scale = Vector3(1.0, 1.0, (segment_len + width) / depth)
	
	# The hitbox is the exact segment: segments touch but never overlap, so a swing cannot hit
	# two links out of order. The old "forgiveness" extension to the head is gone with it.
	var cs := $Area3D/CollisionShape3D as CollisionShape3D
	var box := cs.shape as BoxShape3D
	if box != null:
		box.size.z = maxf(segment_len, 0.05)
	cs.transform.origin = Vector3.ZERO
	
	piece_left.set_color(color)
	piece_right.set_color(color)
	# The cut halves only belong on screen after a cut; a freshly pooled link can still have
	# them visible from the scene's default state, which reads as white patches over the line.
	piece_left.hide_piece()
	piece_right.hide_piece()
	_mat.set_shader_parameter(&"color", color)
	
	# Do NOT play the authored "Spawn" fly-in: its scale track shrinks the mesh to 10% for
	# 0.8 s and its position track pulls it 2 m back. On a note cube that is a spawn pop; on a
	# chain link it breaks the line between the boxes into detached dashes. Reset the mesh
	# transform so a reused pooled link cannot inherit the middle of a previous animation.
	var anim := $AnimationPlayer as AnimationPlayer
	anim.stop()
	var mesh_node := $LinkBody/Mesh as MeshInstance3D
	mesh_node.position = Vector3.ZERO
	mesh_node.rotation_degrees = Vector3.ZERO
	mesh_node.scale = Vector3.ONE
	
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
		Scoreboard.bad_cut(transform.origin, Scoreboard.LINK_POINTS)
	
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
	Scoreboard.reset_combo(Scoreboard.LINK_POINTS)
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
	# specs/027 FR-019: the object's own frame, so Noodle x/y rotation splits along the visible plane.
	var cut_angle_rel := local_cut_angle(
		global_transform.basis, cutplane.normal, cut_angle_abs - global_rotation.z)
	
	_piece_death_count = 0
	piece_left.start_cut(-cut_dist_from_center, cut_angle_rel + PI)
	piece_right.start_cut(cut_dist_from_center, cut_angle_rel)
	
	# some impulse so the cube half moves
	var split_vector := cutplane.normal * 2.0
	piece_left.apply_central_impulse(-split_vector)
	piece_right.apply_central_impulse(split_vector)


