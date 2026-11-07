extends PooledNode3D
class_name Wall

# Spike attribution (FR-033): the deferred free of a whole wall/arc/bomb tree runs
# on the main thread, so it can be the spike rather than the spawn.
const Cost := preload("res://game/scripts/CostProbe.gd")

# The scene's own material, shared by every wall. The only per-wall value is `size`, a regular
# uniform on that material, so it is written per spawn. A fresnel variant (FR-009) was built and
# then removed: it filled pixels additively across large surfaces, which is overdraw on a tiled
# GPU for no gameplay gain, and it was the one visual the test map never exercised.

# Resolved on first use, not with @onready: Playing.gd calls spawn() BEFORE add_child(), so
# _ready() has not run when the wall needs its material and its size.
var _mesh_cache: MeshInstance3D
# The scene's own material, captured once on the first apply.
var _base_mat: Material
# The size the last spawn gave this wall.
var _size := Vector3.ONE


# 1.0 normally; lowered when the camera is inside this wall so the player can see out of it.
var _fade := 1.0
var _camera: Camera3D
var despawn_z: float
var speed: float

# specs/029/027: depth-based grow. Height is a function of the wall's own z, so every wall at the
# same depth has the same height and a wall surface stays continuous; the 0.6.5 age-based version
# staggered the columns and made wall art look torn.
const GROW_START_Z := -16.0
const GROW_END_Z := -8.0
const GROW_MIN := 0.1

# The wall's transform is its centre, so a long wall's front edge reaches the player while its
# centre is still far away. Grow from the front edge. The mesh is moved down as it shrinks so its
# bottom edge stays on the floor (0.7.5): scaling about the centre used to lift the wall off the
# ground and drop its top, which read as a broken barrier.
var _half_depth := 0.0
# True once the grow has written its full-height state, so a settled wall stops touching its
# mesh every physics tick.
var _grow_settled := false

func _apply_grow() -> void:
	var front_z := transform.origin.z + _half_depth
	var t := clampf((front_z - GROW_START_Z) / (GROW_END_Z - GROW_START_Z), 0.0, 1.0)
	var h := lerpf(GROW_MIN, 1.0, smoothstep(0.0, 1.0, t))
	if h >= 0.9999:
		if _grow_settled:
			return
		_grow_settled = true
	else:
		_grow_settled = false
	var mesh := _wall_mesh()
	if mesh == null:
		return
	var visible := Vector3(_size.x, _size.y * h, _size.z)
	mesh.scale = visible
	mesh.position.y = (h - 1.0) * _size.y * 0.5
	mesh.set_instance_shader_parameter(&"size", visible)

func _physics_process(delta: float) -> void:
	if Scoreboard.paused: return
	_update_inside_fade()
	transform.origin.z += speed * delta
	_apply_grow()
	
	# remove children that go to far
	if transform.origin.z > despawn_z:
		if Cost.enabled: Cost.objs_freed += 1
		# Pooled, not freed. A wall map can spawn ~74 walls a second; instantiating and freeing a
		# whole Mesh + Area3D + AnimationPlayer tree at that rate was the single largest cost. The
		# measured across the map matrix (Gloom: 92.9 fps, 24% dropped; Empires, no walls: 120).
		_despawn()

func hide_wall() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED

func _despawn() -> void:
	hide_wall()
	release()

# Called by BeepSaber_Game._clear_track() when a map ends. Pooled nodes MUST return to their pool
# here: _clear_track() frees anything without this method, and a freed wall left in the pool
# makes the next acquire() hand out a freed object ("Trying to cast a freed object", then
# spawn() on a null). Notes and chain links already implement this; walls now do too.
func clear_from_track() -> void:
	hide_wall()
	if not is_released():
		release()

func spawn(wall_info: ObstacleInfo, current_beat: float) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	var shape := ($WallMeshOrientation/WallArea/CollisionShape3D as CollisionShape3D).shape as BoxShape3D
	
	var x_size := maxf(wall_info.width * Constants.LANE_DISTANCE, 0.01)
	var y_size := maxf(wall_info.height * Constants.LANE_DISTANCE, 0.01)
	var z_size := maxf(wall_info.duration * Constants.BEAT_DISTANCE, 0.01)
	if wall_info.has_custom_scale:
		x_size *= absf(wall_info.custom_scale.x)
		y_size *= absf(wall_info.custom_scale.y)
		z_size *= absf(wall_info.custom_scale.z)
	var depth := z_size * 0.5
	_half_depth = depth
	# Scale the mesh node, not the mesh. The BoxMesh is shared and unit-sized: mutating a
	# per-wall mesh (`resource_local_to_scene`) rebuilt and re-uploaded its buffers on every
	# spawn, which on a wall map is ~74 times a second. The collision shape still needs its own
	# size - that is a cheap shape update, not a mesh rebuild.
	#
	# The wall shader reads VERTEX, so with a unit mesh it now multiplies by the `size` uniform
	# itself (wall_shared.tres). That is what makes node scaling render the same as the old
	# per-wall mesh did; without it the border and noise maths ran in a 1 m cube and the walls
	# turned into stretched red smears. `_apply_grow` below writes the visible size each time the
	# wall's height changes.
	shape.size = Vector3(x_size, y_size, z_size)
	_grow_settled = false

	despawn_z = Constants.MISS_Z + depth
	# A rim makes a wall read as a barrier. It is suppressed for Noodle/ME walls and for walls
	# outside the 4x3 grid, because adjacent wall art would otherwise turn into stripes (0.6.5).
	var rim_enabled := (
		not wall_info.has_custom_position
		and not wall_info.has_custom_rotation
		and not wall_info.has_custom_scale
		and is_equal_approx(wall_info.line_index, roundf(wall_info.line_index))
		and is_equal_approx(wall_info.line_layer, roundf(wall_info.line_layer))
		and is_equal_approx(wall_info.width, roundf(wall_info.width))
		and is_equal_approx(wall_info.height, roundf(wall_info.height))
		and wall_info.line_index >= 0.0 and wall_info.line_index < 4.0
		and wall_info.line_layer >= 0.0 and wall_info.line_layer < 3.0
	)
	_apply_material(Vector3(x_size, y_size, z_size), wall_info.custom_color, rim_enabled)
	
	transform.origin.x = (0.5 * wall_info.width + wall_info.line_index - 2) * Constants.LANE_DISTANCE
	transform.origin.y = (0.5 * wall_info.height + wall_info.line_layer) * Constants.LANE_DISTANCE
	transform.origin.z = (current_beat - wall_info.beat) * Constants.BEAT_DISTANCE - depth
	if wall_info.has_custom_position:
		transform.origin.x += wall_info.custom_position.x
		transform.origin.y += wall_info.custom_position.y
	if wall_info.has_custom_rotation:
		rotation_degrees = wall_info.custom_euler
	else:
		rotation_degrees = Vector3.ZERO
	
	speed = NoteMotion.speed_at(wall_info.beat)
	# specs/029: the depth-based grow sets the initial height from the spawn z.
	_apply_grow()

func _wall_mesh() -> MeshInstance3D:
	if _mesh_cache == null:
		_mesh_cache = get_node_or_null(^"WallMeshOrientation/WallMesh") as MeshInstance3D
	return _mesh_cache

func _apply_material(size_in: Vector3, shard_color := Color(0.0, 0.0, 0.0, 0.0), rim_enabled := true) -> void:
	_size = size_in
	var mesh := _wall_mesh()
	if mesh == null:
		return
	# Captured before anything can replace it, whichever call gets here first (spawn, not _ready).
	if _base_mat == null:
		_base_mat = mesh.material_override
	if mesh.material_override != _base_mat:
		mesh.material_override = _base_mat
	# One shared material, per-wall values as instance uniforms: no material switch per wall.
	if mesh != null:
		mesh.set_instance_shader_parameter(&"size", size_in)
		# 0.7.5: the v0.6 rim is back for ordinary walls; wall art and Noodle/ME walls keep the
		# flat panel so adjacent one-lane walls do not turn into vertical stripes.
		mesh.set_instance_shader_parameter(&"rim", 1.0 if rim_enabled else 0.0)
		var tint := MapPalette.wall_color
		if shard_color.a > 0.0:
			tint = shard_color
		# Cap the rim below note emission so a wall never outshines the thing to be cut.
		var cap := maxf(MapPalette.color_left.v, MapPalette.color_right.v) * 0.8
		if cap > 0.0 and tint.v > cap:
			# Scale to the cap. darkened() multiplies by (1 - amount), which turns an HDR
			# obstacle colour black and makes an additive wall invisible.
			tint = Color(tint.r, tint.g, tint.b) * (cap / tint.v)
		mesh.set_instance_shader_parameter(&"wall_color", tint)

# A crouch under an overhead wall can put the camera inside the box. With back-face culling no
# face is drawn then, so the player sees nothing and is surprised by the collision box. Fading the
# wall while the camera is inside makes the situation legible without making every wall two-sided.
func _update_inside_fade() -> void:
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d() as Camera3D
		if _camera == null:
			return
	var local := global_transform.affine_inverse() * _camera.global_position
	var half := _size * 0.5
	var inside := absf(local.x) < half.x and absf(local.y) < half.y and absf(local.z) < half.z
	var target := 0.12 if inside else 1.0
	if not is_equal_approx(target, _fade):
		_fade = target
		var mesh := _wall_mesh()
		if mesh != null:
			mesh.set_instance_shader_parameter(&"fade", _fade)
