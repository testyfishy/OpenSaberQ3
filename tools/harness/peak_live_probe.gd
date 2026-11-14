extends Node

# Peak live objects per difficulty with and without the fly-in before the jump (NoteMotion,
# docs/note-motion-report.md): MapData.peak_live, as BeepSaber_Game sizes the pools. Headless.
# Run: godot --headless --path . res://tools/harness/peak_live_probe.tscn -- <map folder>

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var path := (args[0] if args.size() > 0 else "") + "/"
	var info := Map.load_map_info(path)
	if info == null:
		print("PEAK cannot load %s" % path)
		get_tree().quit(2)
		return
	for diff in info.difficulty_beatmaps:
		var data: Variant = vr.load_json_file(path + diff.beatmap_filename)
		if not (data is Dictionary):
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
		if not Map.load_beatmap(info, diff, data as Dictionary, lightshow, audio):
			continue
		var ahead := NoteMotion.spawn_beats()
		var row := PackedStringArray()
		for fly: float in [0.0, NoteMotion.MOVE_DURATION_S]:
			row.append("fly=%.1f notes=%d bombs=%d walls=%d arcs=%d" % [fly,
				MapData.peak_live(MapData.note_stack, ahead, 1.0, fly),
				MapData.peak_live(MapData.bomb_stack, ahead, 1.0, fly),
				MapData.peak_live(MapData.obstacle_stack, ahead, 1.0, fly),
				MapData.peak_live(MapData.arc_stack, ahead, 1.0, fly)])
		print("PEAK %s %s%s njs=%.1f half=%.2f beats %.1f m | %s" % [info.song_name, diff.difficulty,
			diff.characteristic if "characteristic" in diff else "", NoteMotion.njs(), ahead,
			NoteMotion.spawn_distance(), " | ".join(row)])
	get_tree().quit(0)
