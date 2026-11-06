extends Node

# Map dump harness (v0.4 gate FR-002/SC-002).
#
# Parses every map under a root directory with the real loaders and writes a canonical text dump
# of everything the game derives from the file: notes, walls, arcs, chains, events, BPM segments
# and the resolved palette. Diff two dumps (threaded vs single-threaded, or v3 vs v4) and any
# behaviour change shows up as a line difference.
#
# Usage: godot --headless --path . res://tools/harness/map_dump.tscn -- <root> <outfile>

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var root := args[0] if args.size() > 0 else "user://OpenSaber/Songs"
	var out_path := args[1] if args.size() > 1 else "user://map_dump.txt"
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_error("map_dump: cannot write %s" % out_path)
		get_tree().quit(2)
		return
	var line_count := 0

	var dir := DirAccess.open(root)
	if dir == null:
		push_error("map_dump: cannot open %s" % root)
		get_tree().quit(2)
		return

	# A root that is itself a map (Info.dat at the top) is dumped directly; otherwise every
	# subdirectory is treated as one. One process per map keeps a native crash localised.
	var single := FileAccess.file_exists(root.path_join("Info.dat")) or FileAccess.file_exists(root.path_join("info.dat"))
	var folders := PackedStringArray()
	if single:
		folders.append(root.get_file())
	else:
		for name in dir.get_directories():
			folders.append(name)
	folders.sort()
	for folder in folders:
		var path := (root + "/") if single else (root.path_join(folder) + "/")
		print("DUMPMAP ", folder)
		var info := Map.load_map_info(path)
		if info == null:
			dump_line(f, "MAP %s ERROR" % folder)
			continue
		dump_line(f, "MAP %s env=%s bpm=%s" % [folder, info.environment_name, str(info.beats_per_minute)])
		for diff in info.difficulty_beatmaps:
			var data: Variant = vr.load_json_file(path + diff.beatmap_filename)
			if data == null or not (data is Dictionary):
				dump_line(f, "  DIFF %s ERROR" % diff.difficulty)
				continue
			var lightshow := {}
			if not diff.lightshow_filename.is_empty():
				var ls: Variant = vr.load_json_file(path + diff.lightshow_filename)
				if ls is Dictionary:
					lightshow = ls
			var audio := {}
			if info.version.begins_with("4."):
				var ad: Variant = vr.load_json_file(path + "AudioData.dat")
				if ad is Dictionary:
					audio = ad
			dump_line(f, "  DIFF %s njs=%s offset=%s" % [diff.difficulty, str(diff.note_jump_movement_speed), str(diff.note_jump_start_beat_offset)])
			if not Map.load_beatmap(info, diff, data as Dictionary, lightshow, audio):
				dump_line(f, "    LOAD FAILED")
				continue
			# Reversed stacks are the game's spawn order; dump the natural beat order so two
			# builds that reverse identically produce identical text.
			var notes := Map.note_stack.duplicate()
			notes.reverse()
			for note in notes:
				if note == null:
					continue
				dump_line(f, "    NOTE b=%.6f x=%d y=%d c=%d d=%d col=%s pos=%s" % [
					note.beat, note.line_index, note.line_layer, note.color, note.cut_direction,
					note.custom_color.to_html(), str(note.custom_position) if note.has_custom_position else "-"])
			var walls := Map.obstacle_stack.duplicate()
			walls.reverse()
			for wall in walls:
				if wall == null:
					continue
				dump_line(f, "    WALL b=%.6f d=%.6f x=%d y=%d w=%d h=%d fake=%s col=%s" % [
					wall.beat, wall.duration, wall.line_index, wall.line_layer, wall.width, wall.height,
					str(wall.fake), wall.custom_color.to_html()])
			for arc in Map.arc_stack:
				if arc == null:
					continue
				dump_line(f, "    ARC head=%.6f tail=%.6f c=%d" % [arc.head_beat, arc.tail_beat, arc.color])
			for chain in Map.chain_stack:
				if chain == null:
					continue
				dump_line(f, "    CHAIN head=%.6f tail=%.6f c=%d slices=%d squish=%.4f" % [
					chain.head_beat, chain.tail_beat, chain.color, chain.slice_count, chain.squish_factor])
			for event in Map.event_stack:
				if event == null:
					continue
				dump_line(f, "    EVENT b=%.6f t=%d v=%d f=%.4f col=%s" % [
					event.beat, event.type, event.value, event.float_value, event.color.to_html()])
			dump_line(f, "    BPM segments=%d" % Map.bpm_segments)
			dump_line(f, "    PALETTE notes=%s/%s room=%s/%s wall=%s mode=%d" % [
				Map.color_left.to_html(), Map.color_right.to_html(),
				Map.env_left.to_html(), Map.env_right.to_html(),
				Map.wall_color.to_html(), Settings.environment_mode])

	f.close()
	print("MAPDUMP wrote %s" % ProjectSettings.globalize_path(out_path))
	get_tree().quit()

# store_line cannot fail silently the way a giant accumulated string can; writing as we go also
# keeps peak memory flat when dumping hundreds of maps.
func dump_line(f: FileAccess, text: String) -> void:
	f.store_line(text)
