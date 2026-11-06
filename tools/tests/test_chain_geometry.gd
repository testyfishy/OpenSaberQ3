extends Node3D

# Chain geometry test (specs/019 FR-001..FR-003).
#
# Spawns real ChainLink scenes along synthetic straight/curved/squished chains and asserts:
#  - every link's hitbox covers exactly its segment (endpoints within 2 cm of the curve points);
#  - consecutive hitboxes touch but do not overlap (cut order cannot swap);
#  - the visual mesh covers the segment plus half its width at each joint (no wedge gap).
#
# Run: godot --headless --path . res://tools/tests/test_chain_geometry.tscn

const LINK_SCENE := preload("res://game/Chain/ChainLink.tscn")

var _bad := 0

func _ready() -> void:
	Map.current_difficulty = DifficultyInfo.new("ExpertPlus", 9, "x.dat", 16.0, 0.0, {}, "One")
	MapPalette.color_left = Color(1, 0, 0)
	MapPalette.color_right = Color(0, 0, 1)
	_check_chain("straight", 1, 0, 0, 4, 0, 8, 1.0)
	_check_chain("curved", 2, 0, 0, 4, 2, 8, 1.0)
	_check_chain("squished", 6, 1, 1, 3, 3, 8, 0.8)
	_check_chain("two links", 0, 0, 0, 2, 0, 2, 1.0)
	print("CHAINGEOMETRY ", "PASS" if _bad == 0 else "FAIL")
	get_tree().quit(0 if _bad == 0 else 1)

func _check_chain(label: String, cut_dir: int, hx: float, hy: float, tx: float, ty: float, slices: int, squish: float) -> void:
	var chain := ChainInfo.new(
		0, 0.0, int(hx / Constants.LANE_DISTANCE), int(hy / Constants.LANE_DISTANCE), cut_dir,
		16.0, int(tx / Constants.LANE_DISTANCE), int(ty / Constants.LANE_DISTANCE), slices, squish)
	var head_pos := Vector2(hx, hy)
	var tail_pos := Vector2(tx, ty)
	var mid_pos := head_pos + Constants.ROTATION_UNIT_VECTORS[chain.head_cut_direction] * head_pos.distance_to(tail_pos) * 0.5
	var links: Array[ChainLink] = []
	for i in range(1, slices):
		var link := LINK_SCENE.instantiate() as ChainLink
		add_child(link)
		link.spawn(chain, 0.0, head_pos, tail_pos, mid_pos, i)
		links.append(link)

	for i in links.size():
		var link := links[i]
		var span := ChainLink.link_segment_t(chain, i + 1)
		var p0 := ChainLink.chain_point(chain, head_pos, mid_pos, tail_pos, span.x, 0.0)
		var p1 := ChainLink.chain_point(chain, head_pos, mid_pos, tail_pos, span.y, 0.0)
		var cs := link.get_node("Area3D/CollisionShape3D") as CollisionShape3D
		var box := cs.shape as BoxShape3D
		var half := box.size.z * 0.5
		var start := cs.global_transform * Vector3(0, 0, -half)
		var finish := cs.global_transform * Vector3(0, 0, half)
		_check(start.distance_to(p0) < 0.02, "%s link %d hitbox start (%.3f m off)" % [label, i + 1, start.distance_to(p0)])
		_check(finish.distance_to(p1) < 0.02, "%s link %d hitbox end (%.3f m off)" % [label, i + 1, finish.distance_to(p1)])
		if i > 0:
			var prev := links[i - 1]
			var pcs := prev.get_node("Area3D/CollisionShape3D") as CollisionShape3D
			var pbox := pcs.shape as BoxShape3D
			var prev_end := pcs.global_transform * Vector3(0, 0, pbox.size.z * 0.5)
			_check(prev_end.distance_to(start) < 0.02, "%s joint %d hitboxes touch (%.3f m)" % [label, i + 1, prev_end.distance_to(start)])

		# The mesh may extend half a width per end, but must not fall short of the segment.
		var body := link.get_node("LinkBody") as Node3D
		var mesh := body.get_node("Mesh") as MeshInstance3D
		var aabb := mesh.get_aabb()
		_check(is_equal_approx(mesh.scale.z, 1.0), "%s link %d mesh scale reset (%.3f)" % [label, i + 1, mesh.scale.z])
		var half_mesh := aabb.size.z * body.scale.z * mesh.scale.z * 0.5
		var m0 := body.global_transform * Vector3(0, 0, -half_mesh)
		var m1 := body.global_transform * Vector3(0, 0, half_mesh)
		var axis := (p1 - p0).normalized()
		var along0 := (m0 - p0).dot(axis)
		var along1 := (m1 - p1).dot(axis)
		_check(along0 <= 0.021, "%s link %d mesh covers the start (%.3f m short)" % [label, i + 1, maxf(0.0, along0)])
		_check(along1 >= -0.021, "%s link %d mesh covers the end (%.3f m short)" % [label, i + 1, maxf(0.0, -along1)])

	for link in links:
		link.queue_free()

func _check(condition: bool, what: String) -> void:
	if not condition:
		push_error("CHAINGEOMETRY " + what)
		_bad += 1
