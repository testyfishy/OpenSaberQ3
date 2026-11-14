extends PooledNode3D
class_name Wall

# Spike attribution (FR-033): the deferred free of a whole wall/arc/bomb tree runs
# on the main thread, so it can be the spike rather than the spawn.
const Cost := preload("res://game/scripts/CostProbe.gd")

# A/B for wall overdraw (0.7.6): the normal material never writes depth, so overlapping walls
# shade every layer. The prepass material renders depth first and lets the colour pass reject the
# hidden layers. Set from the benchmark flag; default is the normal visual.
const WALL_MATERIAL := preload("res://game/Wall/wall_shared.tres")
const WALL_PREPASS_MATERIAL := preload("res://game/Wall/wall_depth.tres")
const WALL_OPAQUE_MATERIAL := preload("res://game/Wall/wall_opaque.tres")
static var depth_prepass := false
static var opaque_walls := false
# Attribution only: hide the visual while collision/motion keep running.
static var debug_hide_visuals := false

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

# Noodle Extensions animation (game/noodle/NoodleAnim.gd); null for an ordinary wall, which then
# runs exactly the code it always ran. The animated pose pivots on the wall's front face (Beat
# Saber's obstacle origin); `_n_front` is that face's travel z.
var noodle: NoodleObject = null
var _n_front := 0.0
var _n_base := Vector3.ZERO
var _n_rot := Quaternion.IDENTITY
var _n_half_sec := 1.0
var _n_span_sec := 2.0
var _n_can_hit := true
# A decorative (fake) wall: drawn and animated, with no collision, so no energy drain or rumble.
var _fake := false
var _n_shown := true
# The last Noodle dissolve written to the mesh (1 = fully drawn); reset to 1 on every spawn.
var _n_dissolve := 1.0
# A physics tick moved the wall since the last frame pass (it is on NoodleFrame's list), and
# whether the pose has been worked out for the current front (see _noodle_frame).
var _n_ticked := false
var _n_posed := false

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
	var front_z := _n_front if noodle != null else transform.origin.z + _half_depth
	# The grow runs over the far half of the approach. Those were fixed at 16 m and 8 m when
	# every map spawned 16 m out; they follow the map's spawn distance now (same numbers at 16 m).
	var grow_start := -NoteMotion.spawn_distance()
	var grow_end := grow_start * (GROW_END_Z / GROW_START_Z)
	var t := clampf((front_z - grow_start) / (grow_end - grow_start), 0.0, 1.0)
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
	var t0 := Time.get_ticks_usec() if Cost.enabled else 0
	var z: float
	if noodle == null:
		_update_inside_fade()
		transform.origin.z += speed * delta
		z = transform.origin.z
		_apply_grow()
	else:
		# A Noodle wall travels every tick (its front decides the despawn); its animated pose is
		# only drawn once per frame, so it is worked out in the frame pass (_noodle_frame), except
		# where the collision box must follow every tick (see _needs_tick_pose).
		z = _noodle_travel(delta)
		if _needs_tick_pose():
			_noodle_pose()
	
	# remove children that go to far
	if Cost.enabled:
		Cost.wall_usec += Time.get_ticks_usec() - t0
	if z > despawn_z:
		if Cost.enabled: Cost.objs_freed += 1
		# Pooled, not freed. A wall map can spawn ~74 walls a second; instantiating and freeing a
		# whole Mesh + Area3D + AnimationPlayer tree at that rate was the single largest cost. The
		# measured across the map matrix (Gloom: 92.9 fps, 24% dropped; Empires, no walls: 120).
		_despawn()

# Once per drawn frame, for a Noodle wall that ticked (NoodleFrame.flush): the inside fade, pose,
# dissolve and grow the frame shows, from the state the frame's last physics tick left. When a
# frame runs several physics ticks (the catch-up after a slow frame) this is done once, not once
# per tick.
func _noodle_frame() -> void:
	if not _n_ticked:
		return
	_n_ticked = false
	if noodle == null or is_released():
		return
	_update_inside_fade()
	if not _n_posed:
		_noodle_pose()
	_apply_grow()

# A hittable wall near the player's head is posed every physics tick: the head-in-wall check
# (PlayerHead's Area3D against the wall's) runs in the physics step and must see where the wall is
# that tick. A wall more than POSE_NEAR_M from the head (its centre minus its half diagonal) cannot
# travel there within one frame (8 catch-up ticks at 120 Hz is 67 ms, 1.7 m at 25 m/s), and a
# wall that is not hittable has no collision at all, so neither needs its pose before the frame is
# drawn. The distance uses the last pose and the head in track space, worked out once per tick.
const POSE_NEAR_M := 4.0
static var _head_tick := -1
static var _head_local := Vector3.ZERO

func _needs_tick_pose() -> bool:
	if not _n_can_hit:
		return false
	var tick := Engine.get_physics_frames()
	if tick != _head_tick:
		_head_tick = tick
		if _camera == null or not is_instance_valid(_camera):
			_camera = get_viewport().get_camera_3d() as Camera3D
		var parent := get_parent() as Node3D
		if _camera == null or parent == null:
			return true
		_head_local = parent.global_transform.affine_inverse() * _camera.global_position
	var extent := (transform.basis * (_size * 0.5)).length()
	return transform.origin.distance_to(_head_local) - extent < POSE_NEAR_M

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
	var own_njs := wall_info.noodle.njs if wall_info.noodle != null else 0.0
	var z_size := maxf(NoteMotion.distance_between(wall_info.beat, wall_info.beat + wall_info.duration, own_njs), 0.01)
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
	
	# One transform write: each write notifies the mesh and collision children and moves the
	# wall's Area3D in the physics server, and this used to write it four times (x, y, z, rotation)
	# before _noodle_spawn reset the scale and posed it again.
	var origin := Vector3(
		(0.5 * wall_info.width + wall_info.line_index - 2) * Constants.LANE_DISTANCE,
		(0.5 * wall_info.height + wall_info.line_layer) * Constants.LANE_DISTANCE,
		-NoteMotion.distance_between(current_beat, wall_info.beat, own_njs) - depth)
	if wall_info.has_custom_position:
		origin.x += wall_info.custom_position.x
		origin.y += wall_info.custom_position.y
	var basis := Basis.IDENTITY
	if wall_info.has_custom_rotation:
		# World * local, converted to the Godot frame like the animated rotations.
		basis = Basis(wall_info.custom_world * wall_info.custom_local)
	transform = Transform3D(basis, origin)
	
	speed = NoteMotion.speed_at(wall_info.beat, own_njs)
	var half_sec := NoteMotion.half_jump_seconds()
	if wall_info.noodle != null and wall_info.noodle.half_sec > 0.0:
		half_sec = wall_info.noodle.half_sec
	_noodle_spawn(wall_info, half_sec)
	# specs/029: the depth-based grow sets the initial height from the spawn z.
	_apply_grow()
	var mesh := _wall_mesh()
	if mesh != null:
		# _n_shown is false when a Noodle wall spawns at dissolve 0; a plain wall is always shown.
		mesh.visible = _n_shown and not debug_hide_visuals

func _wall_shape() -> CollisionShape3D:
	return $WallMeshOrientation/WallArea/CollisionShape3D as CollisionShape3D

func _noodle_spawn(wall_info: ObstacleInfo, half_sec: float) -> void:
	# A pooled wall may carry the last Noodle pose and switches; an ordinary wall's scale is 1
	# (spawn() has just written a transform without scale, so this only writes for tools that
	# call this directly).
	if scale != Vector3.ONE:
		scale = Vector3.ONE
	_fake = wall_info.fake
	# Hittable unless fake or marked uninteractable; an animated `interactable` is applied by the
	# first pose.
	var can_hit := not _fake and (wall_info.noodle == null or not wall_info.noodle.uninteractable)
	if can_hit != _n_can_hit:
		_wall_shape().set_deferred(&"disabled", not can_hit)
	_n_can_hit = can_hit
	_n_shown = true
	if _n_dissolve != 1.0:
		_set_dissolve(1.0)
	var info_noodle := wall_info.noodle
	if info_noodle == null or not info_noodle.animated or not NoodleTracks.active:
		noodle = null
		return
	noodle = info_noodle
	_n_front = transform.origin.z + _half_depth
	_n_base = Vector3(transform.origin.x, transform.origin.y, _n_front)
	_n_rot = Quaternion.from_euler(rotation)
	_n_half_sec = maxf(half_sec, 0.001)
	var dur_sec := Map.beat_to_seconds(wall_info.beat + wall_info.duration) - Map.beat_to_seconds(wall_info.beat)
	# Heck ObstacleUpdateNoodlifier: lifetime over the jump plus the wall's own duration.
	_n_span_sec = maxf(2.0 * _n_half_sec + maxf(dur_sec, 0.0), 0.001)
	# The pose waits for the frame pass, like every later one, unless the wall may be hittable
	# near the head (its interactable animation is not known until it is posed).
	_noodle_travel(0.0)
	if _needs_tick_pose():
		_noodle_pose()

# Travel and pose in one step (spawn, tools). The game ticks _noodle_travel every physics tick and
# _noodle_pose once per drawn frame (or every tick where collision needs it).
func _noodle_tick(delta: float) -> float:
	var z := _noodle_travel(delta)
	_noodle_pose()
	return z

# The wall's front moves on exactly as an un-animated wall's would. Returns the back's travel z,
# which decides the despawn.
func _noodle_travel(delta: float) -> float:
	_n_front += speed * delta
	_n_base.z = _n_front
	_n_posed = false
	if not _n_ticked:
		_n_ticked = true
		NoodleFrame.walls.append(self)
	return _n_front - _half_depth

# The animated pose for the current front and song time: transform, hittable, dissolve, shown.
func _noodle_pose() -> void:
	_n_posed = true
	var life := clampf(((_n_front / speed) + _n_half_sec) / _n_span_sec, 0.0, 1.0)
	NoodleAnim.evaluate(noodle, life)
	var pivot := NoodleAnim.compose(_n_base, _n_rot, Vector3.ONE)
	transform = pivot * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -_half_depth))
	var can_hit := not _fake and NoodleAnim.out_interactable >= 1.0
	if can_hit != _n_can_hit:
		_n_can_hit = can_hit
		# Deferred: the shape may be read by the physics step this tick runs in.
		_wall_shape().set_deferred(&"disabled", not can_hit)
	var d := clampf(NoodleAnim.out_dissolve, 0.0, 1.0)
	if d != _n_dissolve:
		_set_dissolve(d)
	var shown := d > 0.0
	if shown != _n_shown:
		_n_shown = shown
		var mesh := _wall_mesh()
		if mesh != null:
			mesh.visible = shown and not debug_hide_visuals

# Noodle dissolve as a fade: an instance uniform that scales the panel's alpha (the wall
# materials already blend). The bench-only opaque material has no alpha, so a dissolving wall
# uses the blended one until it is back at 1. At 0 the mesh is hidden by the caller.
func _set_dissolve(d: float) -> void:
	_n_dissolve = d
	var mesh := _wall_mesh()
	if mesh == null:
		return
	mesh.set_instance_shader_parameter(&"dissolve", d)
	if opaque_walls and _base_mat != null:
		var mat: Material = WALL_MATERIAL if d < 1.0 else _base_mat
		if mesh.material_override != mat:
			mesh.material_override = mat

func _wall_mesh() -> MeshInstance3D:
	if _mesh_cache == null:
		_mesh_cache = get_node_or_null(^"WallMeshOrientation/WallMesh") as MeshInstance3D
	return _mesh_cache

func _apply_material(size_in: Vector3, shard_color := Color(0.0, 0.0, 0.0, 0.0), rim_enabled := true) -> void:
	_size = size_in
	var mesh := _wall_mesh()
	if mesh == null:
		return
	# The only material choice is the A/B prepass switch; instance uniforms stay per wall.
	if opaque_walls:
		_base_mat = WALL_OPAQUE_MATERIAL
	elif depth_prepass:
		_base_mat = WALL_PREPASS_MATERIAL
	else:
		_base_mat = WALL_MATERIAL
	if mesh.material_override != _base_mat:
		mesh.material_override = _base_mat
	# 0.7.5: the v0.6 rim is back for ordinary walls; wall art and Noodle/ME walls keep the
	# flat panel so adjacent one-lane walls do not turn into vertical stripes.
	var rim := 1.0 if rim_enabled else 0.0
	var tint := MapPalette.wall_color
	if shard_color.a > 0.0:
		tint = shard_color
	# Cap the rim below note emission so a wall never outshines the thing to be cut.
	var cap := maxf(MapPalette.color_left.v, MapPalette.color_right.v) * 0.8
	if cap > 0.0 and tint.v > cap:
		# Scale to the cap. darkened() multiplies by (1 - amount), which turns an HDR
		# obstacle colour black and makes an additive wall invisible.
		tint = Color(tint.r, tint.g, tint.b) * (cap / tint.v)
	# One shared material, per-wall values as instance uniforms: no material switch per wall.
	mesh.set_instance_shader_parameter(&"size", size_in)
	mesh.set_instance_shader_parameter(&"rim", rim)
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
