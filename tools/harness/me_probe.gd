extends Node

# specs/027 ME decoding: positions, cut angles and wall types.

func _ready() -> void:
	print("MEPROBE pos 1000=%.3f 2000=%.3f -1000=%.3f -2000=%.3f 1500=%.3f" % [
		BeatmapPrecision.decode_position(1000.0), BeatmapPrecision.decode_position(2000.0),
		BeatmapPrecision.decode_position(-1000.0), BeatmapPrecision.decode_position(-2000.0),
		BeatmapPrecision.decode_position(1500.0)])
	print("MEPROBE cut 1000=%s 1090=%s 1180=%s 1270=%s 2000=%s" % [
		str(BeatmapPrecision.cut_angle(1000)), str(BeatmapPrecision.cut_angle(1090)),
		str(BeatmapPrecision.cut_angle(1180)), str(BeatmapPrecision.cut_angle(1270)),
		str(BeatmapPrecision.cut_angle(2000))])
	print("MEPROBE wall 1000=%s 2000=%s 4000=%s 2304301=%s" % [
		str(BeatmapPrecision.wall_height(1000)), str(BeatmapPrecision.wall_height(2000)),
		str(BeatmapPrecision.wall_height(4000)), str(BeatmapPrecision.wall_height(2304301))])

	var note := ColorNoteInfo.new_v2({
		"_time": 1.0, "_lineIndex": 1500.0, "_lineLayer": -2000.0, "_type": 0.0, "_cutDirection": 1090.0,
	})
	print("MEPROBE note v2 x=%.3f y=%.3f dir=%d offset=%d any=%s" % [
		note.line_index, note.line_layer, note.cut_direction, note.angle_offset, note.ignore_cut_angle])
	var any_note := ColorNoteInfo.new_v3({"b": 1.0, "x": 1000.0, "y": 2000.0, "c": 1.0, "d": 2000.0, "a": 0.0})
	print("MEPROBE note v3 x=%.3f y=%.3f dir=%d offset=%d any=%s" % [
		any_note.line_index, any_note.line_layer, any_note.cut_direction, any_note.angle_offset,
		any_note.ignore_cut_angle])
	var wall := ObstacleInfo.new_v2({
		"_time": 2.0, "_duration": 1.0, "_lineIndex": 1500.0, "_type": 2000.0, "_width": 1500.0,
	})
	print("MEPROBE wall v2 x=%.3f y=%.3f w=%.3f h=%.3f" % [
		wall.line_index, wall.line_layer, wall.width, wall.height])
	var tall := ObstacleInfo.new_v2({
		"_time": 2.0, "_duration": 1.0, "_lineIndex": 3000.0, "_type": 4000.0, "_width": 1000.0,
	})
	print("MEPROBE wall tall x=%.3f w=%.3f h=%.3f" % [tall.line_index, tall.width, tall.height])
	get_tree().quit()

