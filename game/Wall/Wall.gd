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

var despawn_z: float
var speed: float

func _physics_process(delta: float) -> void:
	if Scoreboard.paused: return
	transform.origin.z += speed * delta
	
	# remove children that go to far
	if transform.origin.z > despawn_z:
		if Cost.enabled: Cost.objs_freed += 1
		# Pooled, not freed. A wall map can spawn ~74 walls a second; instantiating and freeing a
		# whole Mesh + Area3D + AnimationPlayer tree at that rate was the single largest cost
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
	var mesh := $WallMeshOrientation/WallMesh as MeshInstance3D
	var shape := ($WallMeshOrientation/WallArea/CollisionShape3D as CollisionShape3D).shape as BoxShape3D
	
	var x_size := wall_info.width * Constants.LANE_DISTANCE
	var y_size := wall_info.height * Constants.LANE_DISTANCE
	var z_size := wall_info.duration * Constants.BEAT_DISTANCE
	var depth := z_size * 0.5
	# Scale the mesh node, not the mesh. The BoxMesh is shared and unit-sized: mutating a
	# per-wall mesh (`resource_local_to_scene`) rebuilt and re-uploaded its buffers on every
	# spawn, which on a wall map is ~74 times a second. A BoxMesh's UVs are 0..1 per face at any
	# size, so scaling the node renders identically. The collision shape still needs its own
	# size - that is a cheap shape update, not a mesh rebuild.
	mesh.scale = Vector3(x_size, y_size, z_size)
	shape.size = Vector3(x_size, y_size, z_size)

	despawn_z = Constants.MISS_Z + depth
	_apply_material(Vector3(x_size, y_size, z_size))
	
	transform.origin.x = (0.5 * wall_info.width + wall_info.line_index - 2) * Constants.LANE_DISTANCE
	transform.origin.y = (0.5 * wall_info.height + wall_info.line_layer) * Constants.LANE_DISTANCE
	transform.origin.z = (current_beat - wall_info.beat) * Constants.BEAT_DISTANCE - depth
	
	speed = Constants.BEAT_DISTANCE * Map.current_info.beats_per_minute / 60.0
	($AnimationPlayer as AnimationPlayer).play(&"Spawn")

func _wall_mesh() -> MeshInstance3D:
	if _mesh_cache == null:
		_mesh_cache = get_node_or_null(^"WallMeshOrientation/WallMesh") as MeshInstance3D
	return _mesh_cache

func _apply_material(size_in: Vector3) -> void:
	_size = size_in
	var mesh := _wall_mesh()
	if mesh == null:
		return
	# Captured before anything can replace it, whichever call gets here first (spawn, not _ready).
	if _base_mat == null:
		_base_mat = mesh.material_override
	if mesh.material_override != _base_mat:
		mesh.material_override = _base_mat
	if _base_mat is ShaderMaterial:
		(_base_mat as ShaderMaterial).set_shader_parameter(&"size", size_in)
