# BeepCube is the standard cube that will get cut by the sabers
extends Cuttable
class_name BeepCube

# emitted when the cube gets cutted, correct_saber is true if the right saber was used
signal cutted(correct_saber: bool)

@onready var mi := $BeepCubeMesh as MeshInstance3D
@onready var collision_big := $BeepCube_Big/CollisionBig as CollisionShape3D
@onready var collision_small := $BeepCube_Small/CollisionSmall as CollisionShape3D
@onready var slice_particles := $SliceParticles as BeepCubeSliceParticles

# Visual-only additions (FR-046, FR-047). Both are plain MeshInstance3D nodes: no Area3D,
# no CollisionShape3D and no script, so Cuttable._register_hit (which only ever walks Area3D
# children) and the physics server cannot see them.
# The note's own glow is no longer a node: it is EMISSION inside BeepCube.gdshader (FR-001).
@onready var mirror := $Mirror as MeshInstance3D

var which_saber: int
var is_dot: bool

# we store the mesh here as part of the BeepCube for easier access because we will
# reuse it when we create the cut cube pieces
var _mesh: Mesh
var _mat: ShaderMaterial
var _mirror_mat: ShaderMaterial
# Mesh-space half extent, for the edge mask in the shader. One value per note because the
# uniform is an `instance uniform`, so it costs one write per instance and no material.
var _half_extent := Vector3(0.5, 0.5, 0.5)
@export var min_speed := 0.5

# The mirror is a flip about the world y = 0 plane, applied in the cube's own parent frame.
# The note's transform only changes in z after spawn, and a z shift commutes with a flip in
# y, so this composes to a constant local transform: one write per spawn, none per frame.
const MIRROR_FLIP := Transform3D(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3.ZERO)
# BeepCubeMesh's own scale, which the mirror has to reproduce because the flip is applied to
# the cube root and this node is its sibling, not its child.
const MIRROR_MESH_SCALE := 0.8

var piece_left : CutPiece = null
var piece_right : CutPiece = null

func _ready() -> void:
	_mat = mi.material_override as ShaderMaterial
	_mirror_mat = mirror.material_override as ShaderMaterial
	_mesh = mi.mesh
	# The mirror shares the cube's own mesh instead of duplicating it: same vertices, same
	# vertex budget, one extra draw call per note and nothing else. The mirror hides unless
	# the setting is on (spawn() decides), so it gets its mesh here either way.
	mirror.mesh = _mesh
	_half_extent = _mesh.get_aabb().size * 0.5
	# `note_half_extent` is an instance uniform: it is the same for every note but belongs
	# to the instance, so the shared material does not have to be duplicated (FR-002).
	mi.set_instance_shader_parameter(&"note_half_extent", _half_extent)
	mirror.visible = false
	
	if bool(ProjectSettings.get_setting(SETTING_ISOLATE_SHAPES, false)):
		# One-time, per instance: from here on spawn() only edits our own shapes.
		collision_big.shape = collision_big.shape.duplicate()
		collision_small.shape = collision_small.shape.duplicate()
	
	# init our cut pieces with unique copies of our own material for reference,
	# and enable "bouncy" physics behavior
	piece_left = CutPiece.new(self, _mesh, _mat.duplicate(true) as ShaderMaterial, true)
	piece_right = CutPiece.new(self, _mesh, _mat.duplicate(true) as ShaderMaterial, true)
	
	# slice_particles are within cube's tree, but want then to move in global space
	slice_particles.top_level = true
	
func spawn(note_info: ColorNoteInfo, current_beat: float) -> void:
	# re-enable our process_mode first otherwise it seems like Godot-internals
	# can behave weirdly (ex. AnimationPlayer won't always play correctly)
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	var color := Map.color_left if note_info.color == 0 else Map.color_right
	# FR-004: a colour the map puts on this one note wins over the scheme, which in turn
	# already fell back to Settings when the map had none. `disable_map_color` suppresses
	# both, so settings win outright.
	if Settings.note_map_colors and not Settings.disable_map_color and note_info.custom_color.a > 0.0:
		color = note_info.custom_color
	speed = Constants.BEAT_DISTANCE * Map.current_info.beats_per_minute * 0.016666666666666667
	beat = note_info.beat
	which_saber = note_info.color
	is_dot = note_info.cut_direction == 8
	
	if is_dot:
		(collision_big.shape as BoxShape3D).size.y = 0.8
	else:
		(collision_big.shape as BoxShape3D).size.y = 0.5
	
	transform.origin.x = Constants.LANE_DISTANCE * float(note_info.line_index) + Constants.LANE_ZERO_X
	transform.origin.y = Constants.LANE_DISTANCE * float(note_info.line_layer) + Constants.LAYER_ZERO_Y
	transform.origin.z = -(note_info.beat - current_beat) * Constants.BEAT_DISTANCE
	
	rotation.z = Constants.CUBE_ROTATIONS[note_info.cut_direction] + deg_to_rad(note_info.angle_offset)
	
	piece_left.set_color(color)
	piece_right.set_color(color)
	# Instance uniforms, not material parameters: `_mat` is shared by every live note now,
	# so a material write here would repaint all of them (FR-002).
	mi.set_instance_shader_parameter(&"note_color", color)
	mi.set_instance_shader_parameter(&"note_is_dot", 1.0 if is_dot else 0.0)
	_mirror_mat.set_shader_parameter(&"color", color)
	# since cube instances get recycled, we gotta reset cubes that were chain
	# heads in a past life
	mi.set_instance_shader_parameter(&"note_chain_head", 0.0)
	piece_left.set_chain_head(false)
	piece_right.set_chain_head(false)
	
	# separate cube collision layers to allow a diferent collider on right/wrong cuts.
	# opposing collision layers (ie. right note & left saber) will be placed on the
	# smalling collision shape, while similar collision layers (ie right note &
	# right saber) are placed on the larger collision shape.
	var is_left_note := note_info.color == 0
	var big_coll_area := $BeepCube_Big as Area3D
	big_coll_area.collision_layer = 0x0
	big_coll_area.set_collision_layer_value(CollisionLayerConstants.LeftNote_bit, is_left_note)
	big_coll_area.set_collision_layer_value(CollisionLayerConstants.RightNote_bit, not is_left_note)
	var small_coll_area := $BeepCube_Small as Area3D
	small_coll_area.collision_layer = 0x0
	small_coll_area.set_collision_layer_value(CollisionLayerConstants.LeftNote_bit, not is_left_note)
	small_coll_area.set_collision_layer_value(CollisionLayerConstants.RightNote_bit, is_left_note)
	
	# play the spawn animation when this cube enters the scene
	var anim := $AnimationPlayer as AnimationPlayer
	var anim_speed := Map.current_difficulty.note_jump_movement_speed / 9.0
	anim.speed_scale = maxf(min_speed,anim_speed)
	anim.play(&"Spawn")
	
	slice_particles.reset()
	mi.visible = true
	_update_mirror()
	mirror.visible = Settings.mirror_reflections

# One write per spawn, for the reason in the MIRROR_FLIP comment above.
func _update_mirror() -> void:
	var local := transform.affine_inverse() * (MIRROR_FLIP * transform)
	local.basis = local.basis.scaled(Vector3.ONE * MIRROR_MESH_SCALE)
	mirror.transform = local

# FR-038: the mirrored copy ships off, so without this its material would compile the first
# time the setting is switched on - i.e. mid-song. The pool shows each cube for one frame at
# load; this puts the mirror on screen for that same frame, under the opaque floor.
func warm_mirror() -> void:
	mirror.visible = true

# call this when clearing the track
func clear_from_track() -> void:
	hide_cube()
	piece_left.hide_piece()
	piece_right.hide_piece()
	if ! is_released():
		release()

func hide_cube() -> void:
	mi.visible = false
	# The mirror is a sibling of the mesh, not its child, so hiding the mesh does not
	# hide it: without this a cut cube would leave its reflection behind.
	mirror.visible = false
	set_collision_enabled(false)
	# disable processing on this node and all children to help with performance
	process_mode = Node.PROCESS_MODE_DISABLED

func make_chain_head() -> void:
	mi.set_instance_shader_parameter(&"note_chain_head", 1.0)
	piece_left.set_chain_head(true)
	piece_right.set_chain_head(true)

func on_miss() -> void:
	Scoreboard.reset_combo()
	hide_cube()
	release()

func set_collision_disabled(value: bool) -> void:
	collision_big.disabled = value
	collision_small.disabled = value

func cut(saber_type: int, cut_speed: Vector3, cut_plane: Plane, controller: BeepSaberController) -> HitInfo:
	# compute the angle between the cube orientation and the cut direction
	var cut_direction_xy := -Vector3(cut_speed.x, cut_speed.y, 0.0).normalized()
	var base_cut_angle_accuracy := global_transform.basis.y.dot(cut_direction_xy)
	var cut_distance := cut_plane.distance_to(global_transform.origin)
	
	# The hit sound needs these, so they are returned rather than re-derived by
	# the sabre (specs/002-hit-audio-research/research.md §3).
	var info := HitInfo.new()
	info.speed_len = cut_speed.length()
	info.note_pos = transform.origin
	
	if saber_type == which_saber:
		var cut_angle_accuracy := clampf((base_cut_angle_accuracy-0.7)/0.3, 0.0, 1.0)
		if is_dot: #ignore angle if is a dot
			cut_angle_accuracy = 1.0
		var cut_distance_accuracy := clampf((0.1 - absf(cut_distance))/0.1, 0.0, 1.0)
		var travel_distance_factor := controller.movement_aabb.get_longest_axis_size()
		travel_distance_factor = clampf((travel_distance_factor-0.5)/0.5, 0.0, 1.0)
		# allows a bit of save margin where the beat is considered 100% correct
		var beat_accuracy := clampf((1.0 - absf(global_transform.origin.z)) / 0.5, 0.0, 1.0)
		Scoreboard.note_cut(transform.origin, beat_accuracy, cut_angle_accuracy, cut_distance_accuracy, travel_distance_factor)
		cutted.emit(true)
		info.angle_acc = cut_angle_accuracy
		info.dist_acc = cut_distance_accuracy
		info.travel = travel_distance_factor
		info.beat_acc = beat_accuracy
	else:
		Scoreboard.bad_cut(transform.origin)
		cutted.emit(false)
		info.kind = HitInfo.Kind.BAD
		info.is_correct_saber = false
	
	# reset the movement tracking volume for the next cut
	controller.reset_movement_aabb()
	
	hide_cube()
	if Settings.cube_cuts_falloff:
		_start_cut_pieces(cut_plane)
		# release() will be called by Cuttable class when it sees both pieces die
	else:
		release() # release now instead of waiting for cut pieces to die off
	return info

# cut the cube by creating two rigid bodies and using a CSGBox to create
# the cut plane
func _start_cut_pieces(cutplane: Plane) -> void:
	piece_left.global_transform = global_transform
	piece_right.global_transform = global_transform
	
	# calculate angle and position of the cut
	var cut_angle_abs := Vector2(cutplane.normal.x, cutplane.normal.y).angle()
	var cut_dist_from_center := cutplane.distance_to(global_transform.origin)
	var cut_angle_rel := cut_angle_abs - global_rotation.z
	
	_piece_death_count = 0
	piece_left.start_cut(-cut_dist_from_center, cut_angle_rel + PI)
	piece_right.start_cut(cut_dist_from_center, cut_angle_rel)
	
	# some impulse so the cube half moves
	var split_vector := cutplane.normal * 2.0
	piece_left.apply_central_impulse(-split_vector)
	piece_right.apply_central_impulse(split_vector)
	
	slice_particles.global_transform.origin = global_transform.origin
	slice_particles.rotation.z = cut_angle_abs+TAU*0.25
	slice_particles.fire()
