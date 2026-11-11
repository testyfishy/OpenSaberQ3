extends Node

# specs/027 FR-006: lanes keep the rotation in effect at each object's beat.

func _ready() -> void:
	Map._build_track_rotations({"rotationEvents": [
		{"b": 10.0, "e": 0.0, "r": 90.0},
		{"b": 15.0, "e": 1.0, "r": 15.0},
	]})
	var track := Node3D.new()
	add_child(track)
	var early := Node3D.new()
	track.add_child(early)
	TrackLanes.place(early, 9.0)
	var late := Node3D.new()
	track.add_child(late)
	TrackLanes.place(late, 11.0)
	# An object is positioned (lane-local) by spawn() and then placed: the placement must not
	# rewrite that position, in either direction.
	var mover := Node3D.new()
	track.add_child(mover)
	mover.position = Vector3(0.3, 1.0, -16.0)
	TrackLanes.place(mover, 11.0)
	var into_rotated := mover.position.is_equal_approx(Vector3(0.3, 1.0, -16.0))
	mover.transform = Transform3D(Basis.IDENTITY, Vector3(-0.3, 1.5, -16.0))
	TrackLanes.place(mover, 9.0)
	var back_to_straight := mover.transform.is_equal_approx(Transform3D(Basis.IDENTITY, Vector3(-0.3, 1.5, -16.0)))
	print("LANEPROBE local transform kept: into_rotated=%s back_to_straight=%s %s" % [
		into_rotated, back_to_straight, "PASS" if into_rotated and back_to_straight else "FAIL"])
	var early_parent := early.get_parent() as Node3D
	var late_parent := late.get_parent() as Node3D
	print("LANEPROBE early=%s yaw=%.1f late=%s yaw=%.1f early_still=%s" % [
		early_parent.name, rad_to_deg(early_parent.rotation.y),
		late_parent.name, rad_to_deg(late_parent.rotation.y),
		early.get_parent() == early_parent])
	print("LANEPROBE rotation at 9=%.1f 10=%.1f 14=%.1f 15=%.1f 16=%.1f" % [
		Map.track_rotation_at(9.0), Map.track_rotation_at(10.0), Map.track_rotation_at(14.0),
		Map.track_rotation_at(15.0), Map.track_rotation_at(16.0)])
	get_tree().quit()
