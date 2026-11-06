extends Node3D

# Deterministic render check for the wall shader and the chain-link length fix.
# Desktop only. Run: godot --path . res://tools/visual_check.tscn
# Writes user://visual_walls.png and user://visual_chain.png.

var _frames := 0
var _cam: Camera3D
var _walls: Array[Node3D] = []
var _chain_links: Array[ChainLink] = []
# Pass "before" to render the pre-fix look: shader without the `size` multiply and 0.5 m chain plates.
var _before := OS.get_cmdline_user_args().has("before")

func _ready() -> void:
	# The tool runs without a map, so seed the palette statics the wall material reads.
	MapPalette.color_left = Color(0.85, 0.10, 0.12)
	MapPalette.color_right = Color(0.10, 0.25, 0.95)
	MapPalette.wall_color = Color(0.70, 0.06, 0.06)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.30, 0.32, 0.40)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	light.light_energy = 0.8
	add_child(light)

	_make_floor()
	_make_walls()
	_make_chain()

	_cam = Camera3D.new()
	add_child(_cam)
	_cam.fov = 70.0
	_cam.look_at_from_position(Vector3(0.0, 1.7, -0.4), Vector3(0.0, 1.7, -3.0))
	_cam.make_current()

func _make_floor() -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(18, 40)
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.11, 0.14)
	mi.material_override = mat
	mi.position = Vector3(0, 0, -10)
	add_child(mi)

func _make_walls() -> void:
	var scene := load("res://game/Wall/Wall.tscn") as PackedScene
	# lanes wide, layers tall, beats long, x, y, z
	var specs := [
		[3.0, 4.0, 3.0, 0.0, 2.0, -6.0],
		[2.0, 3.0, 2.0, -2.4, 1.5, -9.0],
		[1.0, 2.0, 1.0, 2.4, 1.0, -4.0],
	]
	for spec in specs:
		var w := scene.instantiate() as Wall
		add_child(w)
		_walls.append(w)
		var size := Vector3(
			spec[0] * Constants.LANE_DISTANCE,
			spec[1] * Constants.LANE_DISTANCE,
			spec[2] * Constants.BEAT_DISTANCE
		)
		var shape := (w.get_node("WallMeshOrientation/WallArea/CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
		var mesh := w.get_node("WallMeshOrientation/WallMesh") as MeshInstance3D
		mesh.scale = size
		shape.size = size
		w.despawn_z = 999.0
		w.transform.origin = Vector3(spec[3], spec[4], spec[5])
		w._apply_material(size)
		if _before:
			# The shader as it shipped in 88889ef: real metres assumed but VERTEX is a unit cube.
			var sm := mesh.material_override as ShaderMaterial
			var sh := sm.shader.duplicate() as Shader
			sh.code = sh.code.replace("pos = VERTEX * size;", "pos = VERTEX;")
			sm.shader = sh

func _make_chain() -> void:
	var scene := load("res://game/Chain/ChainLink.tscn") as PackedScene
	if _before:
		# The old look: detached plates at 1 m spacing.
		for i in 8:
			var link := scene.instantiate() as ChainLink
			add_child(link)
			link.transform.origin = Vector3(3.0, 1.9, -0.5 - i * 1.0)
			link.get_node("LinkBody").scale = Vector3(1, 1, 1.0)
			link.rotation.z = PI * 0.25
		return
	# The real spawn path with a curved chain, so the screenshot is what the game builds.
	Map.current_difficulty = DifficultyInfo.new("ExpertPlus", 9, "x.dat", 16.0, 0.0, {}, "One")
	var chain := ChainInfo.new(0, 0.0, 0, 0, 2, 1.0, 0, 0, 8, 1.0)
	var head_pos := Vector2(-3.0, 1.9)
	var tail_pos := Vector2(-1.8, 2.5)
	var mid_pos := head_pos + Constants.ROTATION_UNIT_VECTORS[chain.head_cut_direction] * head_pos.distance_to(tail_pos) * 0.5
	for i in range(1, chain.slice_count):
		var link := scene.instantiate() as ChainLink
		add_child(link)
		link.spawn(chain, 0.0, head_pos, tail_pos, mid_pos, i)
		_chain_links.append(link)

func _process(_delta: float) -> void:
	_frames += 1
	var tag := "before" if _before else "after"
	if _frames == 4:
		get_viewport().get_texture().get_image().save_png("user://visual_walls_%s.png" % tag)
		print("VISUALCHECK walls ", ProjectSettings.globalize_path("user://visual_walls_%s.png" % tag))
		for w in _walls:
			w.visible = false
		_cam.look_at_from_position(Vector3(-6.0, 2.6, -1.9), Vector3(-3.0, 2.2, -1.9))
		print("VISUALCHECK chainlinks=%d first=%s last=%s" % [_chain_links.size(), str(_chain_links[0].global_position) if _chain_links.size() > 0 else "-", str(_chain_links[-1].global_position) if _chain_links.size() > 0 else "-"])
		if _chain_links.size() > 0:
			var l0 = _chain_links[0]
			print("VISUALCHECK mesh aabb=%s body_scale=%s mesh_scale=%s visible=%s" % [str(l0._mesh.get_aabb()), str(l0.get_node("LinkBody").scale), str(l0.get_node("LinkBody/Mesh").scale), str(l0.get_node("LinkBody/Mesh").visible)])
	if _frames == 7:
		get_viewport().get_texture().get_image().save_png("user://visual_chain_%s.png" % tag)
		print("VISUALCHECK chain ", ProjectSettings.globalize_path("user://visual_chain_%s.png" % tag))
	if _frames > 9:
		get_tree().quit()
