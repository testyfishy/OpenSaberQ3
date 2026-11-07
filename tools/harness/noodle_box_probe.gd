extends Node

# specs/027: Noodle static transforms (v3 keys and underscored keys), box-group colour expansion and
# the local cut angle used by the cut pieces.

func _ready() -> void:
	var note := ColorNoteInfo.new_v2({
		"_time": 1.0, "_lineIndex": 1.0, "_lineLayer": 0.0, "_type": 0.0, "_cutDirection": 1.0,
		"_customData": {
			"_position": [1.5, 2.5, 0.0],
			"_rotation": [0.0, 90.0, 0.0],
			"_scale": [1.5, 1.5, 1.5],
		},
	})
	print("NOODLEPROBE note pos=%.2f,%.2f rot=%s scale=%s" % [
		note.custom_position.x, note.custom_position.y, str(note.custom_euler),
		str(note.custom_scale)])
	# v3 spelling: coordinates / localRotation / size, position as an object.
	var note_v3 := ColorNoteInfo.new_v2({
		"_time": 1.0, "_lineIndex": 1.0, "_lineLayer": 0.0, "_type": 0.0, "_cutDirection": 1.0,
		"_customData": {
			"coordinates": {"x": -0.5, "y": 3.25},
			"localRotation": [0.0, 0.0, 45.0],
			"size": 2.0,
		},
	})
	print("NOODLEPROBE note_v3 pos=%.2f,%.2f rot=%s scale=%s" % [
		note_v3.custom_position.x, note_v3.custom_position.y, str(note_v3.custom_euler),
		str(note_v3.custom_scale)])
	var wall := ObstacleInfo.new_v2({
		"_time": 2.0, "_duration": 1.0, "_lineIndex": 0.0, "_type": 0.0, "_width": 1.0,
		"_customData": {"_position": [0.5, 1.0, 0.0], "_scale": [2.0, 1.0, 1.0]},
	})
	print("NOODLEPROBE wall pos=%.2f,%.2f scale=%s" % [
		wall.custom_position.x, wall.custom_position.y, str(wall.custom_scale)])
	var wall_v3 := ObstacleInfo.new_v2({
		"_time": 2.0, "_duration": 1.0, "_lineIndex": 0.0, "_type": 0.0, "_width": 1.0,
		"_customData": {"coordinates": {"x": 1.0, "y": 0.0}, "size": [1.0, 2.0, 1.0]},
	})
	print("NOODLEPROBE wall_v3 pos=%.2f,%.2f scale=%s" % [
		wall_v3.custom_position.x, wall_v3.custom_position.y, str(wall_v3.custom_scale)])

	# Real v3/v4 payload: c is a colour index (0 red, 1 blue, 2 white), s is brightness and i is
	# the transition type (0 instant, 1 transition, 2 extend).
	var data := {
		"lightColorEventBoxGroups": [
			{"b": 10.0, "g": 0.0, "e": [{"e": [
				{"b": 0.0, "c": 0.0, "s": 1.0, "i": 0.0},
				{"b": 1.0, "c": 1.0, "s": 1.0, "i": 1.0},
				{"b": 2.0, "c": 2.0, "s": 1.0, "i": 0.0},
				{"b": 3.0, "c": 0.0, "s": 1.0, "i": 2.0},
				{"b": 4.0, "c": 0.0, "s": 0.0, "i": 0.0},
			]}]},
			{"b": 20.0, "g": 7.0, "e": [{"e": [{"b": 0.0, "c": 1.0, "s": 1.0, "i": 1.0}]}]},
			{"b": 30.0, "g": -1.0, "e": [{"e": [{"b": 0.0, "c": 0.0, "s": 1.0, "i": 0.0}]}]},
			{"b": 40.0, "g": 2.5, "e": [{"e": [{"b": 0.0, "c": 0.0, "s": 1.0, "i": 0.0}]}]},
		],
	}
	MapData.expand_box_group_colors(data, {})
	var events: Array = data.get("basicBeatmapEvents", [])
	print("NOODLEPROBE box_events=%d" % events.size())
	for ev in events:
		print("NOODLEPROBE box %s" % str(ev))

	# specs/027 FR-019: the cut plane must round-trip through a Noodle-tilted basis, with and
	# without a non-uniform scale, and fall back when the basis is degenerate or the plane lies
	# along the object's z.
	var rot := Basis.from_euler(Vector3(deg_to_rad(35.0), deg_to_rad(20.0), deg_to_rad(50.0)))
	var authored := 0.4
	var normal := rot * Vector3(cos(authored), sin(authored), 0.0)
	var got := Cuttable.local_cut_angle(rot, normal, -99.0)
	print("NOODLEPROBE cut rot=%.4f authored=%.4f" % [got, authored])
	var scaled := rot * Basis.from_scale(Vector3(2.0, 0.5, 1.0))
	print("NOODLEPROBE cut scaled=%.4f" % Cuttable.local_cut_angle(scaled, normal, -99.0))
	var degenerate := rot * Basis.from_scale(Vector3(0.0, 1.0, 1.0))
	print("NOODLEPROBE cut degenerate=%.4f" % Cuttable.local_cut_angle(degenerate, normal, -99.0))
	var along_z := rot * Vector3(0.0, 0.0, 1.0)
	print("NOODLEPROBE cut along_z=%.4f" % Cuttable.local_cut_angle(rot, along_z, -99.0))
	var old_angle := Vector2(normal.x, normal.y).angle() - rot.get_euler().z
	print("NOODLEPROBE cut old=%.4f new=%.4f diff_deg=%.2f" % [
		old_angle, got, rad_to_deg(absf(angle_difference(old_angle, got)))])
	get_tree().quit()
