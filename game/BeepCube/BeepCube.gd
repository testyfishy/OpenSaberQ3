# BeepCube is the standard cube that will get cut by the sabers
extends Cuttable
class_name BeepCube

# emitted when the cube gets cutted, correct_saber is true if the right saber was used
signal cutted(correct_saber: bool)

@onready var mi := $BeepCubeMesh as MeshInstance3D
@onready var collision_big := $BeepCube_Big/CollisionBig as CollisionShape3D
@onready var collision_small := $BeepCube_Small/CollisionSmall as CollisionShape3D

# Visual-only addition (FR-047). The mirrored copy is a `next_pass` on this note's material
# (see shaders/mirror_pass.gdshader): no node, no collision, nothing the physics server or
# Cuttable._register_hit can see, and no per-frame work at all.
# The note's own glow is EMISSION inside BeepCube.gdshader (FR-001).
const MIRROR_SHADER := preload("res://game/shaders/mirror_pass.gdshader")

# One material for every note, so switching the setting is one write (007 rule 2).
static var _mirror_material: ShaderMaterial

var which_saber: int
# The colour this note was drawn in; a cut tints its debris with it.
var _cut_color := Color.WHITE
var is_dot: bool
# Mapping Extensions any-direction: the arrow is drawn, but the cut angle is not scored.
var ignore_cut_angle := false
var line_index: float
var line_layer: float

# we store the mesh here as part of the BeepCube for easier access because we will
# reuse it when we create the cut cube pieces
var _mesh: Mesh
var _mat: ShaderMaterial
# Mesh-space half extent, for the edge mask in the shader. One value per note because the
# uniform is an `instance uniform`, so it costs one write per instance and no material.
var _half_extent := Vector3(0.5, 0.5, 0.5)
@export var min_speed := 0.5

var piece_left : CutPiece = null
var piece_right : CutPiece = null

func _ready() -> void:
	_mat = mi.material_override as ShaderMaterial
	_mesh = mi.mesh
	_half_extent = _mesh.get_aabb().size * 0.5
	# `note_half_extent` is an instance uniform: it is the same for every note but belongs
	# to the instance, so the shared material does not have to be duplicated (FR-002).
	mi.set_instance_shader_parameter(&"note_half_extent", _half_extent)
	_set_mirror_pass(Settings.mirror_reflections)
	
	if bool(ProjectSettings.get_setting(SETTING_ISOLATE_SHAPES, false)):
		# One-time, per instance: from here on spawn() only edits our own shapes.
		collision_big.shape = collision_big.shape.duplicate()
		collision_small.shape = collision_small.shape.duplicate()
	
	# init our cut pieces with unique copies of our own material for reference,
	# and enable "bouncy" physics behavior
	piece_left = CutPiece.new(self, _mesh, _mat.duplicate(true) as ShaderMaterial, true)
	piece_right = CutPiece.new(self, _mesh, _mat.duplicate(true) as ShaderMaterial, true)
	
func spawn(note_info: ColorNoteInfo, current_beat: float) -> void:
	# re-enable our process_mode first otherwise it seems like Godot-internals
	# can behave weirdly (ex. AnimationPlayer won't always play correctly)
	process_mode = Node.PROCESS_MODE_ALWAYS
	blade_min_dist = INF
	
	var color := MapPalette.color_left if note_info.color == 0 else MapPalette.color_right
	# FR-004: a colour the map puts on this one note wins over the scheme, which in turn
	# already fell back to Settings when the map had none. `disable_map_color` suppresses
	# both, so settings win outright.
	if Settings.note_map_colors and not Settings.disable_map_color and note_info.custom_color.a > 0.0:
		color = note_info.custom_color
	_cut_color = color
	speed = NoteMotion.speed_at(note_info.beat)
	beat = note_info.beat
	which_saber = note_info.color
	is_dot = note_info.cut_direction == 8
	ignore_cut_angle = note_info.ignore_cut_angle
	# Kept so an arc can find its head note unambiguously. Beat + colour alone picks the wrong
	# note when two same-colour notes share a beat (stacks and windows), which is how an arc ends
	# up attached to a note it does not belong to.
	line_index = note_info.line_index
	line_layer = note_info.line_layer
	
	if is_dot:
		(collision_big.shape as BoxShape3D).size.y = 0.8
	else:
		(collision_big.shape as BoxShape3D).size.y = 0.5
	
	if note_info.has_custom_position:
		# Noodle Extensions: the mapper placed this note in world space.
		transform.origin.x = note_info.custom_position.x
		transform.origin.y = note_info.custom_position.y
	else:
		transform.origin.x = Constants.LANE_DISTANCE * float(note_info.line_index) + Constants.LANE_ZERO_X
		transform.origin.y = Constants.LANE_DISTANCE * float(note_info.line_layer) + Constants.LAYER_ZERO_Y
	transform.origin.z = -(note_info.beat - current_beat) * Constants.BEAT_DISTANCE
	
	rotation.z = Constants.CUBE_ROTATIONS[note_info.cut_direction] + deg_to_rad(note_info.angle_offset)
	if note_info.has_custom_rotation:
		rotation_degrees += note_info.custom_euler
	if note_info.has_custom_scale:
		scale = note_info.custom_scale
	
	piece_left.set_color(color)
	piece_right.set_color(color)
	# Instance uniforms, not material parameters: `_mat` is shared by every live note now,
	# so a material write here would repaint all of them (FR-002).
	mi.set_instance_shader_parameter(&"note_color", color)
	mi.set_instance_shader_parameter(&"note_is_dot", 1.0 if is_dot else 0.0)
	# The mirrored pass reads its colour from the instance too, because that material is
	# shared by every note (and by the blades, which set the same key).
	mi.set_instance_shader_parameter(&"mirror_color", color)
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
	
	mi.visible = true
	_set_mirror_pass(Settings.mirror_reflections)

# FR-047 / 007 rule 2: the mirrored copy is a second pass on the shared note material, so
# this is one write for the whole pool, and `null` when the setting is off so the pass costs
# no draw at all rather than being hidden behind a uniform test.
func _set_mirror_pass(enabled: bool) -> void:
	if enabled:
		if _mirror_material == null:
			_mirror_material = ShaderMaterial.new()
			_mirror_material.shader = MIRROR_SHADER
			_mirror_material.render_priority = -1
		if _mat.next_pass != _mirror_material:
			_mat.next_pass = _mirror_material
	elif _mat.next_pass != null:
		_mat.next_pass = null

# Called on the settings change with any pooled instance (the material is shared, so the one
# call updates every live note immediately).
func apply_mirror_setting() -> void:
	_set_mirror_pass(Settings.mirror_reflections)

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
	process_mode = Node.PROCESS_MODE_DISABLED

func make_chain_head() -> void:
	mi.set_instance_shader_parameter(&"note_chain_head", 1.0)
	piece_left.set_chain_head(true)
	piece_right.set_chain_head(true)

func on_miss() -> void:
	if HitResolver.miss_probe():
		var kind := "no-contact" if blade_min_dist > 0.08 else "near-miss"
		vr.log_info("MISS beat=%.3f closest=%.3f kind=%s" % [beat, blade_min_dist, kind])
	Harness.log_miss(beat)
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
	info.note_pos = global_position
	
	if saber_type == which_saber:
		var cut_angle_accuracy := clampf((base_cut_angle_accuracy-0.7)/0.3, 0.0, 1.0)
		if is_dot or ignore_cut_angle: #ignore angle if is a dot or any-direction note
			cut_angle_accuracy = 1.0
		var cut_distance_accuracy := clampf((0.1 - absf(cut_distance))/0.1, 0.0, 1.0)
		var travel_distance_factor := controller.movement_aabb.get_longest_axis_size()
		travel_distance_factor = clampf((travel_distance_factor-0.5)/0.5, 0.0, 1.0)
		# allows a bit of save margin where the beat is considered 100% correct
		var beat_accuracy := clampf((1.0 - absf(global_transform.origin.z)) / 0.5, 0.0, 1.0)
		Scoreboard.note_cut(transform.origin, beat_accuracy, cut_angle_accuracy, cut_distance_accuracy, travel_distance_factor)
		Harness.log_cut(beat, true, cut_angle_accuracy, cut_distance_accuracy, travel_distance_factor, beat_accuracy)
		cutted.emit(true)
		info.angle_acc = cut_angle_accuracy
		info.dist_acc = cut_distance_accuracy
		info.travel = travel_distance_factor
		info.beat_acc = beat_accuracy
	else:
		Scoreboard.bad_cut(transform.origin)
		Harness.log_cut(beat, false, 0.0, 0.0, 0.0, 0.0)
		cutted.emit(false)
		info.kind = HitInfo.Kind.BAD
		info.is_correct_saber = false
	
	# reset the movement tracking volume for the next cut
	controller.reset_movement_aabb()
	
	hide_cube()
	# FR-003: a burst on the floor where the blade met the note. One float write into a
	# shader uniform, decayed by Floor._process; nothing is allocated or spawned.
	if Settings.hit_flash and Floor.instance != null:
		Floor.instance.flash_at(global_transform.origin)
	if Settings.cube_cuts_falloff:
		_start_cut_pieces(cut_plane, cut_speed)
		# release() will be called by Cuttable class when it sees both pieces die
	else:
		release() # release now instead of waiting for cut pieces to die off
	return info

# cut the cube by creating two rigid bodies and using a CSGBox to create
# the cut plane
func _start_cut_pieces(cutplane: Plane, _cut_speed: Vector3) -> void:
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
	
	# FR-013: debris that follows the slice. One draw call for the whole pool; the burst is
	# written as instance records and the vertex shader does the flight (no node, no physics).
	if DebrisField.instance != null:
		DebrisField.instance.emit_burst(global_transform.origin, cutplane.normal, _cut_speed, _cut_color)




