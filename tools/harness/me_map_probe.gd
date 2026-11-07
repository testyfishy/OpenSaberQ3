extends Node

# Real Mapping Extensions map: parse every note/obstacle and report fractional placements.

const DIR := "F:/Dev/BeepSaberBin/me_test/"

func _ready() -> void:
	var info := Map.load_map_info(DIR)
	print("MEMAP info=", info != null, " name=", info.song_name if info else "?", " diffs=", info.difficulty_beatmaps.size() if info else 0)
	var data: Dictionary = vr.load_json_file(DIR + "ExpertStandard.dat")
	var notes: Array = data.get("_notes", data.get("colorNotes", []))
	var obs: Array = data.get("_obstacles", data.get("obstacles", []))
	var frac_notes := 0
	var frac_min := 999.0
	var cut_precise := 0
	for i in range(mini(notes.size(), 400)):
		var n := ColorNoteInfo.new_v2(notes[i]) if data.has("_notes") else ColorNoteInfo.new_v3(notes[i])
		if absf(n.line_index - roundf(n.line_index)) > 0.001 or absf(n.line_layer - roundf(n.line_layer)) > 0.001:
			frac_notes += 1
			frac_min = minf(frac_min, absf(n.line_index - roundf(n.line_index)))
		if n.angle_offset != 0:
			cut_precise += 1
	var big_walls := 0
	var zero_walls := 0
	for i in range(mini(obs.size(), 800)):
		var o := ObstacleInfo.new_v2(obs[i]) if data.has("_obstacles") else ObstacleInfo.new_v3(obs[i])
		if o.height > 5.5:
			big_walls += 1
		if o.width <= 0.0:
			zero_walls += 1
	print("MEMAP notes=%d sample=400 fractional=%d min_frac=%.3f precise_cut=%d" % [
		notes.size(), frac_notes, frac_min, cut_precise])
	print("MEMAP obstacles=%d sample=800 tall=%d zero_width=%d" % [obs.size(), big_walls, zero_walls])
	var first := ColorNoteInfo.new_v2(notes[0])
	print("MEMAP first x=%.3f y=%.3f dir=%d off=%d" % [first.line_index, first.line_layer, first.cut_direction, first.angle_offset])
	var wall := ObstacleInfo.new_v2(obs[0])
	print("MEMAP first_wall x=%.3f y=%.3f w=%.3f h=%.3f" % [wall.line_index, wall.line_layer, wall.width, wall.height])
	get_tree().quit()
