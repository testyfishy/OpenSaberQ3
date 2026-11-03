extends Node3D
class_name Wall

# Spike attribution (FR-033): the deferred free of a whole wall/arc/bomb tree runs
# on the main thread, so it can be the spike rather than the spawn.
const Cost := preload("res://game/scripts/CostProbe.gd")

# Optional fresnel material (specs/007-visual-options FR-009). Default off: it is an additive,
# unshaded wall, which trades the original noise texture for glow and overdraw, so it waits
# for a measurement like every other addition in this sheet.
const FRESNEL_SHADER := preload("res://game/shaders/wall_fresnel.gdshader")
# One material for every wall. The size that differs per wall is an `instance uniform` in the
# shader, written on the MeshInstance3D - with a regular uniform, one spawn would resize every
# wall on screen (the material is shared by design).
static var _fresnel_mat: ShaderMaterial

# Resolved on first use, not with @onready: Playing.gd calls spawn() BEFORE add_child(), so
# _ready() has not run when the wall needs its material and its size.
var _mesh_cache: MeshInstance3D
# The scene's own material, captured before anything can replace it.
var _base_mat: Material
# The size the last spawn gave this wall, so a runtime toggle can re-apply it.
var _size := Vector3.ONE

var despawn_z: float
var speed: float

func _physics_process(delta: float) -> void:
	if Scoreboard.paused: return
	transform.origin.z += speed * delta
	
	# remove children that go to far
	if transform.origin.z > despawn_z:
		if Cost.enabled: Cost.objs_freed += 1
		queue_free()

func spawn(wall_info: ObstacleInfo, current_beat: float) -> void:
	var mesh := $WallMeshOrientation/WallMesh as MeshInstance3D
	var m := mesh.mesh as BoxMesh
	var shape := ($WallMeshOrientation/WallArea/CollisionShape3D as CollisionShape3D).shape as BoxShape3D
	
	var x_size := wall_info.width * Constants.LANE_DISTANCE
	var y_size := wall_info.height * Constants.LANE_DISTANCE
	var z_size := wall_info.duration * Constants.BEAT_DISTANCE
	var depth := z_size * 0.5
	m.size.x = x_size
	shape.size.x = x_size
	m.size.y = y_size
	shape.size.y = y_size
	m.size.z = z_size
	shape.size.z = z_size
	despawn_z = Constants.MISS_Z + depth
	_apply_material(Vector3(x_size, y_size, z_size))
	
	transform.origin.x = (0.5 * wall_info.width + wall_info.line_index - 2) * Constants.LANE_DISTANCE
	transform.origin.y = (0.5 * wall_info.height + wall_info.line_layer) * Constants.LANE_DISTANCE
	transform.origin.z = (current_beat - wall_info.beat) * Constants.BEAT_DISTANCE - depth
	
	speed = Constants.BEAT_DISTANCE * Map.current_info.beats_per_minute / 60.0
	($AnimationPlayer as AnimationPlayer).play(&"Spawn")

# Called from spawn (new walls) and from BeepSaber_Game.on_settings_changed for the walls
# already on the track, so the setting works without a restart.
func apply_visual_settings() -> void:
	_apply_material(_size)

func _wall_mesh() -> MeshInstance3D:
	if _mesh_cache == null:
		_mesh_cache = get_node_or_null(^"WallMeshOrientation/WallMesh") as MeshInstance3D
	return _mesh_cache

func _apply_material(size_in: Vector3) -> void:
	_size = size_in
	var mesh := _wall_mesh()
	if mesh == null:
		return
	# Captured before the first swap, whichever call gets here first (spawn, not _ready).
	if _base_mat == null:
		_base_mat = mesh.material_override
	if Settings.wall_fresnel:
		if _fresnel_mat == null:
			_fresnel_mat = ShaderMaterial.new()
			_fresnel_mat.shader = FRESNEL_SHADER
		# Instance parameter: per wall, on the shared material.
		mesh.set_instance_shader_parameter(&"size", size_in)
		if mesh.material_override != _fresnel_mat:
			mesh.material_override = _fresnel_mat
	else:
		if mesh.material_override != _base_mat:
			mesh.material_override = _base_mat
		# The scene material carries its own regular `size` uniform (the noise pattern's
		# scale), which is a property of the material rather than of the instance.
		if _base_mat is ShaderMaterial:
			(_base_mat as ShaderMaterial).set_shader_parameter(&"size", size_in)
