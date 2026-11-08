extends SceneTree

func _init() -> void:
	_run()

func _run() -> void:
	var script := load("res://game/hands/RenderedHand.gd")
	var nodes: Array[XRNode3D] = []
	for hand in [0, 1]:
		var node := script.new() as XRNode3D
		node.hand = hand
		root.add_child(node)
		nodes.append(node)
	await process_frame
	for i in nodes.size():
		var node := nodes[i]
		print("HAND ", i, " tracker=", node.tracker, " pose=", node.pose, " show=", node.show_when_tracked)
		var skeleton := node.find_child("Skeleton3D", true, false) as Skeleton3D
		print("  skeleton=", skeleton != null, " bones=", skeleton.get_bone_count() if skeleton else -1)
		var modifier: XRHandModifier3D = null
		if skeleton:
			for c in skeleton.get_children():
				if c is XRHandModifier3D:
					modifier = c
		print("  modifier=", modifier != null, " hand_tracker=", modifier.hand_tracker if modifier else "")
		var meshes := node.find_children("*", "MeshInstance3D", true, false)
		print("  meshes=", meshes.size(), " unshaded=", (meshes[0] as MeshInstance3D).material_override is StandardMaterial3D if meshes.size() > 0 else false)
		node.queue_free()
	quit()
