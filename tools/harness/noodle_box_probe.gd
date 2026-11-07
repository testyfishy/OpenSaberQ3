extends Node

# specs/027: Noodle static transforms and box-group colour expansion.

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
	var wall := ObstacleInfo.new_v2({
		"_time": 2.0, "_duration": 1.0, "_lineIndex": 0.0, "_type": 0.0, "_width": 1.0,
		"_customData": {"_position": [0.5, 1.0, 0.0], "_scale": [2.0, 1.0, 1.0]},
	})
	print("NOODLEPROBE wall pos=%.2f,%.2f scale=%s" % [
		wall.custom_position.x, wall.custom_position.y, str(wall.custom_scale)])

	var data := {
		"lightColorEventBoxGroups": [{
			"b": 10.0, "g": 0.0,
			"e": [{"e": [{"b": 0.0, "c": [1.0, 0.0, 0.0], "i": 1.0}]}],
		}],
	}
	MapData.expand_box_group_colors(data, {})
	var events: Array = data.get("basicBeatmapEvents", [])
	print("NOODLEPROBE box_events=%d first=%s" % [events.size(), str(events[0]) if events else "-"])
	get_tree().quit()
