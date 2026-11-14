extends Node3D

# Arc after its head note is cut (the saber magnet), rendered for real. Windowed, not headless:
#   godot --path . res://tools/harness/arc_magnet_preview.tscn -- <out dir>
# ODDS&ENDS ExpertPlus motion (NJS 17, 192 BPM). One arc per case from a head note on beat 8 to a
# tail on beat 10; the head is cut on its beat and the saber tip global follows a down swing and its
# follow-through. Saves arc_<case>_<ms>.png (ms from the head's beat) and prints the arc's
# coloured pixel count per frame, so a vanished ribbon shows as a number, not only in a picture.

const DT := 1.0 / 120.0
const BPM := 192.0
const SHOTS: Array[float] = [-0.15, 0.0, 0.05, 0.15, 0.3, 0.45, 0.6]

var _out := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = (args[0] if args.size() > 0 else OS.get_environment("TEMP").path_join("opensaber_previews")).replace("\\", "/")
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.0, 0.0, 0.0)
	add_child(env)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.6, 0.0)
	cam.rotation = Vector3(-0.15, 0.0, 0.0)
	cam.fov = 90.0
	add_child(cam)
	cam.current = true
	var map_timer := preload("res://game/scripts/MapTimer.gd")
	map_timer.load_bpm_events({}, BPM)
	Map.current_info = MapInfo.new("3.0.0", "t", "", "a", "m", BPM, 0.0, 0.0, "", "", "", 0.0, {}, "", [])
	Map.current_difficulty = DifficultyInfo.new("ExpertPlus", 9, "x.dat", 17.0, 0.0, {}, "One")
	Scoreboard.paused = false
	NoteMotion.configure(17.0, 0.0, BPM, 9, 1.0)
	Arc.apply_spawn_distance()
	# Experiments: ARC_SET="distance_effect=0.01;distance_fade_magnet_max=0.3" on all arc materials.
	for kv: String in OS.get_environment("ARC_SET").split(";", false):
		var parts := kv.split("=")
		for m: ShaderMaterial in [Arc.left_material, Arc.right_material, Arc.left_material_magnet, Arc.right_material_magnet]:
			m.set_shader_parameter(StringName(parts[0]), float(parts[1]))
	var arg := OS.get_environment("ARC_CASES")
	var cases: PackedStringArray = PackedStringArray(["right_cut", "left_cut", "wrong_saber", "missed_head", "no_head"]) if arg == "" else arg.split(",")
	for c: String in cases:
		await _case(c)
	print("ARCPREVIEW done ", _out)
	get_tree().quit(0)


func _tip(t: float, hand: int) -> Vector3:
	# A down swing through the hit at t = 0 (head note low in its lane), then the follow-through
	# and the return: realistic tip positions in front of the player.
	var x := 0.35 if hand == 1 else -0.35
	if t < -0.1:
		return Vector3(x, 1.7, -0.45)
	if t < 0.05:
		var k := (t + 0.1) / 0.15
		return Vector3(x, lerpf(1.7, 0.55, k), lerpf(-0.45, -0.75, sin(k * PI)))
	if t < 0.3:
		return Vector3(x, 0.45, -0.55)
	return Vector3(x, lerpf(0.45, 1.2, clampf((t - 0.3) / 0.3, 0.0, 1.0)), -0.5)


func _case(name: String) -> void:
	var color := 0 if name == "left_cut" else 1
	# Floats, as in a map file (ArcInfo reads every field as a float).
	var lane := 1.0 if color == 0 else 2.0
	var info := ArcInfo.new_v3({"c": float(color), "b": 8.0, "x": lane, "y": 0.0, "d": 1.0, "mu": 1.0,
		"tb": 10.0, "tx": lane, "ty": 2.0, "tc": 0.0, "tmu": 1.0, "m": 0.0})
	var holder := Node3D.new()
	add_child(holder)
	var head: BeepCube = null
	var hit_sec := Map.beat_to_seconds(8.0)
	var start := hit_sec - 0.4
	if name != "no_head":
		head = (load("res://game/BeepCube/BeepCube.tscn") as PackedScene).instantiate() as BeepCube
		holder.add_child(head)
		head.set_physics_process(false)
		head.spawn(ColorNoteInfo.new_v3({"b": 8.0, "x": info.head_line_index, "y": 0.0, "c": float(color), "d": 1.0}), Map.seconds_to_beat(start))
	# From the prewarmed pool and spawned before it is in the tree, as the game did until 0.7.39.
	Arc.prewarm(Arc._pool.size() + 1, holder)
	var arc := Arc.acquire()
	arc.spawn(info, Map.seconds_to_beat(start), head)
	holder.add_child(arc)
	# Driven by this loop only: the engine would also tick it every rendered frame.
	arc.set_process(false)
	var t := start
	var shot := 0
	var cut_done := false
	while shot < SHOTS.size():
		t += DT
		var rel := t - hit_sec
		RenderingServer.global_shader_parameter_set(&"left_saber", _tip(rel, 0))
		RenderingServer.global_shader_parameter_set(&"right_saber", _tip(rel, 1))
		if not cut_done and rel >= 0.0 and head != null and name != "missed_head":
			cut_done = true
			# The right saber cuts the head: correct for a right arc, wrong for "wrong_saber".
			head.cutted.emit(name != "wrong_saber")
		if head != null and not cut_done:
			head._physics_process(DT)
		arc._process(DT)
		if rel >= SHOTS[shot] - 0.0001:
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var file := "arc_%s_%+04d.png" % [name, roundi(SHOTS[shot] * 1000.0)]
			img.save_png(_out.path_join(file))
			print("ARCPIX %s t=%+.2f pixels=%d magnet=%d visible=%s z=%.2f despawn=%.2f" % [name, SHOTS[shot], _coloured(img, color),
				int(arc.visual.material_override.get_shader_parameter(&"saber_magnet")), str(arc.is_visible_in_tree()),
				arc.transform.origin.z, arc.despawn_z])
			shot += 1
	arc._release_to_pool()
	holder.queue_free()
	await get_tree().process_frame


# Bright pixels: the background is black and the arc is the only thing drawn.
func _coloured(img: Image, color: int) -> int:
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var p := img.get_pixel(x, y)
			if maxf(p.r, maxf(p.g, p.b)) > 0.25:
				n += 1
	return n
