extends Node

# specs/027 FR-006: v3/v2 rotation events, early/late, and the node transform.

func _ready() -> void:
	Map._build_track_rotations({"rotationEvents": [
		{"b": 10.0, "e": 0.0, "r": 90.0},
		{"b": 15.0, "e": 1.0, "r": 15.0},
	]})
	print("ROTPROBE v3 at9=%.1f at10=%.1f at14=%.1f at15=%.1f at16=%.1f" % [
		Map.track_rotation_at(9.0), Map.track_rotation_at(10.0), Map.track_rotation_at(14.0),
		Map.track_rotation_at(15.0), Map.track_rotation_at(16.0)])

	Map._build_track_rotations({"_events": [
		{"_time": 10.0, "_type": 14.0, "_value": 4.0},
		{"_time": 15.0, "_type": 15.0, "_value": 0.0},
	]})
	print("ROTPROBE v2 at9=%.1f at10=%.1f at15=%.1f at16=%.1f" % [
		Map.track_rotation_at(9.0), Map.track_rotation_at(10.0), Map.track_rotation_at(15.0),
		Map.track_rotation_at(16.0)])

	var node := Node3D.new()
	node.position = Vector3(1.0, 0.0, 0.0)
	Map._build_track_rotations({"rotationEvents": [{"b": 0.0, "e": 0.0, "r": 90.0}]})
	Map.apply_track_rotation(node, 1.0)
	print("ROTPROBE node pos=%.2f,%.2f,%.2f yaw=%.1f" % [
		node.position.x, node.position.y, node.position.z, rad_to_deg(node.rotation.y)])
	node.free()
	get_tree().quit()
