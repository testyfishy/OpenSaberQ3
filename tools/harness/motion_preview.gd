extends Node3D

# Stills of notes flying in and jumping (docs/note-motion-report.md). Windowed, not headless:
#   godot --path . res://tools/harness/motion_preview.tscn -- <out dir>
# The owner's play-test map: NJS 11.2, 192 BPM, half jump 2.29 beats (8.0 m). A stream of notes
# one beat apart is driven by a fixed clock, once with the fly-in (0.7.37) and once without
# (0.7.36), and the player's view is saved at the same song times in both:
#   motion_fly_<ms>.png / motion_nofly_<ms>.png, <ms> = song time in milliseconds.
# Note 0 (beat 8, 2500 ms) starts flying in at 1284 ms and starts its jump at 1784 ms.

const DT := 1.0 / 120.0
const BPM := 192.0
const NOTES := 8
const SHOTS: Array[float] = [1.30, 1.45, 1.60, 1.70, 1.784, 1.90, 2.05, 2.25, 2.45]

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
	env.environment.background_color = Color(0.02, 0.02, 0.05)
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.3, 0.0)
	add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.6, 0.0)
	cam.rotation = Vector3(-0.08, 0.0, 0.0)
	cam.fov = 90.0
	cam.far = 1024.0
	add_child(cam)
	cam.current = true
	_floor()
	var map_timer := preload("res://game/scripts/MapTimer.gd")
	map_timer.load_bpm_events({}, BPM)
	Map.current_info = MapInfo.new("3.0.0", "t", "", "a", "m", BPM, 0.0, 0.0, "", "", "", 0.0, {}, "", [])
	Map.current_difficulty = DifficultyInfo.new("Expert", 7, "x.dat", 11.2, -1.71, {}, "One")
	Scoreboard.paused = false
	for fly: bool in [true, false]:
		NoteMotion.fly_in_enabled = fly
		NoteMotion.configure(11.2, -1.71, BPM, 7, 1.0)
		await _stream("motion_fly" if fly else "motion_nofly")
	print("MOTIONPREVIEW done: %s (spawn %.2f m, half jump %.3f s)" % [_out, NoteMotion.spawn_distance(), NoteMotion.half_jump_seconds()])
	get_tree().quit(0)


func _floor() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3.0, 240.0)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0.0, 0.0, -110.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.12, 0.16)
	floor_mesh.material_override = m
	add_child(floor_mesh)
	# Distance marks every 10 m.
	for i in 12:
		var mark := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(3.0, 0.01, 0.05)
		mark.mesh = box
		mark.position = Vector3(0.0, 0.005, -10.0 * float(i + 1))
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(0.4, 0.4, 0.5)
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mark.material_override = mm
		add_child(mark)


func _stream(prefix: String) -> void:
	var holder := Node3D.new()
	add_child(holder)
	var scene := load("res://game/BeepCube/BeepCube.tscn") as PackedScene
	var cubes: Array[BeepCube] = []
	var anims: Array[AnimationPlayer] = []
	var infos: Array[ColorNoteInfo] = []
	for i in NOTES:
		infos.append(ColorNoteInfo.new_v3({"b": 8.0 + float(i), "x": 1 + (i % 2), "y": i % 3, "c": i % 2, "d": 1}))
	var spawn_beats := NoteMotion.spawn_beats()
	var fly_sec := NoteMotion.fly_in_seconds()
	var next := 0
	var t := 0.0
	var shot := 0
	while shot < SHOTS.size():
		t += DT
		# As Playing._process_map: spawn when the jump (or the fly-in before it) starts.
		while next < NOTES:
			var jump_sec := Map.beat_to_seconds(infos[next].beat - spawn_beats)
			if jump_sec - fly_sec > t:
				break
			var cube := scene.instantiate() as BeepCube
			holder.add_child(cube)
			cube.set_physics_process(false)
			var anim := cube.get_node("AnimationPlayer") as AnimationPlayer
			anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			cube.spawn(infos[next], Map.seconds_to_beat(t))
			if fly_sec > 0.0:
				cube.fly_in(jump_sec - t)
			cubes.append(cube)
			anims.append(anim)
			next += 1
		for i in cubes.size():
			if is_instance_valid(cubes[i]) and cubes[i].visible:
				cubes[i]._physics_process(DT)
				anims[i].advance(DT)
		if t >= SHOTS[shot] - 0.0001:
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_png(_out.path_join("%s_%04d.png" % [prefix, roundi(SHOTS[shot] * 1000.0)]))
			shot += 1
	holder.queue_free()
	await get_tree().process_frame
