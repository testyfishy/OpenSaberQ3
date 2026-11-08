extends SceneTree

func _init() -> void:
	for path in ["res://game/hands/LeftHandHumanoid.gltf", "res://game/hands/RightHandHumanoid.gltf"]:
		print("=== ", path)
		var ps := load(path) as PackedScene
		if ps == null:
			print("LOAD FAILED")
			continue
		var inst := ps.instantiate()
		_dump(inst, 0)
		inst.free()
	quit()

func _dump(n: Node, depth: int) -> void:
	print("  ".repeat(depth), n.name, " [", n.get_class(), "]")
	if n is Skeleton3D:
		var sk := n as Skeleton3D
		print("  ".repeat(depth + 1), "bones=", sk.get_bone_count())
		for i in mini(5, sk.get_bone_count()):
			print("  ".repeat(depth + 2), sk.get_bone_name(i))
	for c in n.get_children():
		_dump(c, depth + 1)
