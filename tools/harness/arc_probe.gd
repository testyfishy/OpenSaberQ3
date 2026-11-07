extends Node3D

# Renders synthetic arcs with endpoint markers and a green straight chord, then samples the
# baked path to prove the endpoints, monotonic Z and no self-intersection. Writes PNGs to
# F:/Dev/BeepSaberBin/f025/ so the fix can be checked without the headset.

const OUT_DIR := "F:/Dev/BeepSaberBin/f025/"

var cam: Camera3D

func _ready() -> void:
	var wall_mat := load("res://game/Wall/wall_shared.tres") as ShaderMaterial
	print("WALLMAT ok=", wall_mat != null, " shader=", wall_mat.shader != null if wall_mat != null else false)
	Arc._configure_fades()
	for p in ["distance_fade_min", "distance_fade_max", "distance_fade_tip_min", "distance_fade_tip_max"]:
		print("ARCPARAM ", p, "=", Arc.left_material.get_shader_parameter(p))
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 12.0
	add_child(cam)
	cam.current = true

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60, 40, 0)
	light.light_energy = 2.0
	add_child(light)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	await _case("arc_straight", 1, 0, 0, 2, 1, 1, 0, 1.0)
	await _case("arc_short", 0, 0, 1, 1, 0, 3, 0, 0.25)
	await _case("arc_mid_cw", 2, 2, 8, 3, 0, 8, 1, 1.0)
	await _case("arc_mid_ccw", 2, 2, 8, 3, 0, 8, 2, 1.0)
	await _case("arc_mid_opposed", 1, 0, 0, 2, 0, 1, 1, 1.0)

	# Player's-eye view: a straight arc with note-sized boxes at both ends.
	var holder := Node3D.new()
	add_child(holder)
	var head_pos := Vector3(0.0, 0.8, 0.0)
	var tail_pos := Vector3(0.6, 1.4, -4.0)
	_note_box(holder, head_pos, Color(0.9, 0.15, 0.5))
	_note_box(holder, tail_pos, Color(0.9, 0.15, 0.5))
	var info := ArcInfo.new(0, 4.0, 1, 0, 0, 1.0, 5.0, 2, 1, 1, 1.0, 0)
	var arc := preload("res://game/Arc/Arc.tscn").instantiate() as Arc
	Arc.left_material.set_shader_parameter(&"color", Color(0.9, 0.15, 0.5))
	arc.spawn(info, 4.0, null)
	arc.set_process(false)
	holder.add_child(arc)
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 75.0
	cam.position = Vector3(0.0, 1.7, 3.0)
	cam.look_at(Vector3(0.0, 1.1, -6.0))
	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_DIR + "arc_player_view.png")
	get_tree().quit()

func _note_box(parent: Node3D, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.6
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _case(name: String, hx: int, hy: int, hd: int, tx: int, ty: int, td: int, mid: int, beats: float) -> void:
	var holder := Node3D.new()
	add_child(holder)
	var head_pos := Vector3(
		Constants.LANE_DISTANCE * float(hx) + Constants.LANE_ZERO_X,
		Constants.LANE_DISTANCE * float(hy) + Constants.LAYER_ZERO_Y,
		0.0)
	var tail_pos := Vector3(
		Constants.LANE_DISTANCE * float(tx) + Constants.LANE_ZERO_X,
		Constants.LANE_DISTANCE * float(ty) + Constants.LAYER_ZERO_Y,
		-beats * Constants.BEAT_DISTANCE)
	_marker(holder, head_pos, Color(1, 1, 1))
	_marker(holder, tail_pos, Color(1, 0.8, 0.1))
	_line(holder, head_pos, tail_pos)

	var info := ArcInfo.new(0, 0.0, hx, hy, hd, 1.0, beats, tx, ty, td, 1.0, mid)
	var arc := preload("res://game/Arc/Arc.tscn").instantiate() as Arc
	Arc.left_material.set_shader_parameter(&"color", Color(1, 0.05, 0.25))
	arc.spawn(info, 0.0, null)
	arc.set_process(false)
	holder.add_child(arc)

	var curve := (arc.get_node("Path3D") as Path3D).curve
	var path3d := arc.get_node("Path3D") as Path3D
	var first := path3d.position + curve.samplef(0.0)
	var last := path3d.position + curve.samplef(1.0)
	var samples: Array[Vector3] = []
	for i in range(101):
		samples.append(path3d.position + curve.samplef(float(i) / 100.0))
	var z_mono := true
	var crossings := 0
	for i in range(1, samples.size()):
		if samples[i].z > samples[i - 1].z + 0.0001:
			z_mono = false
	for i in range(1, samples.size()):
		for j in range(i + 2, samples.size()):
			if _segments_cross(samples[i - 1], samples[i], samples[j - 1], samples[j]):
				crossings += 1
	var max_bulge := 0.0
	var chord := tail_pos - head_pos
	for p in samples:
		var t := clampf((p - head_pos).dot(chord) / chord.length_squared(), 0.0, 1.0)
		max_bulge = maxf(max_bulge, p.distance_to(head_pos + chord * t))
	print("ARCTEST %s head_err=%.4f tail_err=%.4f z_mono=%s crossings=%d bulge=%.3f chord=%.2f" % [
		name, first.distance_to(head_pos), last.distance_to(tail_pos), z_mono, crossings,
		max_bulge, chord.length()])

	# side view of this arc
	var mid_world := (head_pos + tail_pos) * 0.5
	cam.position = mid_world + Vector3(7.0, 0.6, 2.5)
	cam.look_at(mid_world, Vector3.UP)
	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_DIR + name + ".png")
	holder.queue_free()
	await get_tree().process_frame

func _segments_cross(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> bool:
	# 2D crossing test in the XY (player-facing) plane, ignoring shared endpoints.
	var r := Vector2(b.x - a.x, b.y - a.y)
	var s := Vector2(d.x - c.x, d.y - c.y)
	var denom := r.cross(s)
	if absf(denom) < 0.000001:
		return false
	var qp := Vector2(c.x - a.x, c.y - a.y)
	var t := qp.cross(s) / denom
	var u := qp.cross(r) / denom
	return t > 0.001 and t < 0.999 and u > 0.001 and u < 0.999

func _marker(parent: Node3D, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)

func _line(parent: Node3D, a: Vector3, b: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.03, 0.03, a.distance_to(b))
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 1.0, 0.2)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	parent.add_child(mi)
	mi.look_at_from_position((a + b) * 0.5, b, Vector3.UP)



