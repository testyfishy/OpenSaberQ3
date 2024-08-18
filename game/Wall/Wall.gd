extends Node3D
class_name Wall

var despawn_z: float
var speed: float

func _physics_process(delta: float) -> void:
	if Scoreboard.paused: return
	transform.origin.z += speed * delta
	
	# remove children that go to far
	if transform.origin.z > despawn_z:
		queue_free()

func spawn(wall_info: ObstacleInfo, current_beat: float) -> void:
	var mesh := $WallMeshOrientation/WallMesh as MeshInstance3D
	var m := mesh.mesh as BoxMesh
	var shape := ($WallMeshOrientation/WallArea/CollisionShape3D as CollisionShape3D).shape as BoxShape3D
	
	var x := wall_info.width * Constants.LANE_DISTANCE
	var y := wall_info.height * Constants.LANE_DISTANCE
	var z := wall_info.duration * Constants.BEAT_DISTANCE
	var depth := z * 0.5
	m.size.x = x
	shape.size.x = x
	m.size.y = y
	shape.size.y = y
	m.size.z = z
	shape.size.z = z
	despawn_z = Constants.MISS_Z + depth
	(mesh.material_override as ShaderMaterial).set_shader_parameter(&"size", Vector3(x, y, z))
	
	transform.origin.x = (wall_info.line_index - ((4 - wall_info.width) * 0.5)) * Constants.LANE_DISTANCE
	transform.origin.y = (wall_info.line_layer + (wall_info.height * 0.5)) *  Constants.LANE_DISTANCE
	transform.origin.z = (current_beat - wall_info.beat) * Constants.BEAT_DISTANCE - depth
	
	speed = Constants.BEAT_DISTANCE * Map.current_info.beats_per_minute / 60.0
	($AnimationPlayer as AnimationPlayer).play(&"Spawn")
