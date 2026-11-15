extends Node3D

# Arc after its head note is cut (the saber magnet), rendered for real. Windowed, not headless:
#   godot --path . res://tools/harness/arc_magnet_preview.tscn -- <out dir>
# ODDS&ENDS ExpertPlus motion (NJS 17, 192 BPM). One arc per case from a head note on beat 8 to a
# tail on beat 10; the head is cut on its beat and the saber tip global follows a down swing and its
# follow-through. Saves arc_<case>_<ms>.png (ms from the head's beat) and prints the arc's
# coloured pixel count per frame, so a vanished ribbon shows as a number, not only in a picture.
# 0.7.40 cases (ARC_CASES=wall,long): "wall", a right arc passing behind and through a translucent
# wall; "long", a right arc whose tail is 29 m beyond its head, spawned at the head's fly-in start
# and run through the cut. ARC_OLD=1 renders them as 0.7.39 drew them (no render priority, the
# fade at the spawn line, no fly-in); files then end in _old. Their pixel count is the arc's own
# blue pixels, not the wall's red.

const DT := 1.0 / 120.0
const BPM := 192.0
const SHOTS: Array[float] = [-0.15, 0.0, 0.05, 0.15, 0.3, 0.45, 0.6]

var _out := ""
var _old := false
var _cam: Camera3D = null
const ARC_BLUE := Color(0.15, 0.45, 1.0, 1.0)
# Head cut at 0; the tail box appears at +0.59 s, its jump starts at +1.09 s, its beat is +1.72 s.
const LONG_SHOTS: Array[float] = [-0.8, -0.6, -0.3, 0.15, 0.45, 0.65, 0.8, 0.95, 1.2, 1.5]


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
	_cam = cam
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
	_old = OS.get_environment("ARC_OLD") == "1"
	if _old:
		for m: ShaderMaterial in [Arc.left_material, Arc.right_material, Arc.left_material_magnet, Arc.right_material_magnet]:
			m.render_priority = 0
			m.set_shader_parameter(&"distance_fade_min", NoteMotion.spawn_distance())
			m.set_shader_parameter(&"distance_fade_max", NoteMotion.spawn_distance() - 3.0)
	Arc.right_material.set_shader_parameter(&"color", ARC_BLUE)
	Arc.right_material_magnet.set_shader_parameter(&"color", ARC_BLUE)
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
	if name == "wall" or name == "long":
		await _case_0740(name)
		return
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


# 0.7.40: the arc against a wall, and a long arc through its fly-in and the cut.
func _case_0740(name: String) -> void:
	var long := name == "long"
	var tail_beat := 13.5 if long else 10.0
	var info := ArcInfo.new_v3({"c": 1.0, "b": 8.0, "x": 2.0, "y": 0.0, "d": 1.0, "mu": 1.0,
		"tb": tail_beat, "tx": 2.0 if long else 1.0, "ty": 2.0, "tc": 0.0, "tmu": 1.0, "m": 0.0})
	var holder := Node3D.new()
	add_child(holder)
	var hit_sec := Map.beat_to_seconds(8.0)
	var jump_sec := hit_sec - NoteMotion.half_jump_seconds()
	var start := jump_sec - NoteMotion.fly_in_seconds() if long else hit_sec - 0.4
	if not long:
		# A wall over lanes 1-2, 1.6 m high, from 1 m to 6 m beyond the head note's lane z: the arc
		# from lane 2 (bottom) to lane 1 (top) runs behind it and up through it.
		var wall := MeshInstance3D.new()
		var box := BoxMesh.new()
		var size := Vector3(1.2, 1.6, 5.0)
		box.size = Vector3.ONE
		wall.mesh = box
		wall.scale = size
		wall.material_override = Wall.WALL_MATERIAL
		holder.add_child(wall)
		wall.set_instance_shader_parameter(&"size", size)
		wall.position = Vector3(0.0, 0.8, 0.0)
		_wall = wall
	var head := (load("res://game/BeepCube/BeepCube.tscn") as PackedScene).instantiate() as BeepCube
	holder.add_child(head)
	head.set_physics_process(false)
	head.spawn(ColorNoteInfo.new_v3({"b": 8.0, "x": 2.0, "y": 0.0, "c": 1.0, "d": 1.0}), Map.seconds_to_beat(start))
	if long:
		head.fly_in(jump_sec - start)
	Arc.prewarm(Arc._pool.size() + 1, holder)
	var arc := Arc.acquire()
	holder.add_child(arc)
	arc.spawn(info, Map.seconds_to_beat(start), head)
	if long and not _old:
		arc.fly_in(head.fly_seconds_left())
	if _old:
		# 0.7.39: no void, no stretch (its 3 m ramp at the spawn line is set on the materials).
		arc._tail_state = Arc.TAIL_HERE
		arc.visual.set_instance_shader_parameter(&"void_z", -10000.0)
	arc.set_process(false)
	var tail: BeepCube = null
	var tail_appear := Map.beat_to_seconds(tail_beat) - NoteMotion.half_jump_seconds() - NoteMotion.fly_in_seconds()
	if long:
		# Seen from the side and above, so the far end and the tail box show.
		_cam.position = Vector3(9.0, 6.0, 4.0)
		_cam.fov = 55.0
		_cam.look_at(Vector3(0.3, -1.5, -24.0))
	# The note meshes are not drawn in this scene: plain markers stand in for the boxes, white for
	# the head, yellow for the tail, at their drawn positions.
	var marks: Array[MeshInstance3D] = []
	for c: Color in [Color(1, 1, 1), Color(1, 0.9, 0.1)]:
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.45, 0.45, 0.45)
		m.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = c
		m.material_override = mat
		m.visible = false
		holder.add_child(m)
		marks.append(m)
	var shots := LONG_SHOTS if long else SHOTS
	var t := start
	var shot := 0
	var cut_done := false
	while shot < shots.size():
		t += DT
		var rel := t - hit_sec
		RenderingServer.global_shader_parameter_set(&"left_saber", _tip(rel, 0))
		RenderingServer.global_shader_parameter_set(&"right_saber", _tip(rel, 1))
		if not cut_done and rel >= 0.0:
			cut_done = true
			head.cutted.emit(true)
			head.hide()
		if not cut_done:
			head._physics_process(DT)
		if long and tail == null and t >= tail_appear:
			tail = (load("res://game/BeepCube/BeepCube.tscn") as PackedScene).instantiate() as BeepCube
			holder.add_child(tail)
			tail.set_physics_process(false)
			tail.spawn(ColorNoteInfo.new_v3({"b": tail_beat, "x": 2.0, "y": 2.0, "c": 1.0, "d": 0.0}), Map.seconds_to_beat(t))
			tail.fly_in(Map.beat_to_seconds(tail_beat) - NoteMotion.half_jump_seconds() - t)
			if not _old:
				arc.set_tail_cube(tail)
		if tail != null:
			tail._physics_process(DT)
		arc._process(DT)
		if _wall != null:
			# The wall moves with the notes: its near face 1 m beyond the head's lane z.
			_wall.position.z = arc._head_local_z + arc.position.z - 3.5
		if rel >= shots[shot] - 0.0001:
			marks[0].visible = head.visible
			marks[0].position = head.position
			marks[1].visible = tail != null
			if tail != null:
				marks[1].position = tail.position
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var file := "arc_%s_%+05d%s.png" % [name, roundi(shots[shot] * 1000.0), "_old" if _old else ""]
			img.save_png(_out.path_join(file))
			var head_z := arc.position.z + (arc.get_node("Path3D") as Path3D).position.z 				+ (arc.get_node("Path3D") as Path3D).curve.get_point_position(0).z
			var meshes := arc.visual.get_meshes()
			var aabb: AABB = (meshes[1] as Mesh).get_aabb() if meshes.size() > 1 and meshes[1] != null else AABB()
			print("ARCPIX %s%s t=%+.2f arc_pixels=%d head_box_z=%.2f arc_head_z=%.2f ribbon_min_y=%.2f tail_box_z=%s ribbon_tail_z=%.2f void_z=%.1f" % [
				name, " old" if _old else "", shots[shot], _blue(img), head.position.z, head_z,
				(arc.get_node("Path3D") as Path3D).position.y + aabb.position.y,
				("%.2f" % tail.position.z) if tail != null else "none", arc.position.z + arc._tail_path_z - arc.tail_fly,
				arc.void_z + arc.position.z + arc._tail_path_z if arc.void_z > -9999.0 else -9999.0])
			shot += 1
	_wall = null
	if tail != null:
		tail.release()
	_cam.position = Vector3(0.0, 1.6, 0.0)
	_cam.rotation = Vector3(-0.15, 0.0, 0.0)
	_cam.fov = 90.0
	arc._release_to_pool()
	holder.queue_free()
	await get_tree().process_frame


var _wall: MeshInstance3D = null


func _blue(img: Image) -> int:
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var p := img.get_pixel(x, y)
			if p.b > 0.35 and p.b > p.r + 0.15:
				n += 1
	return n
