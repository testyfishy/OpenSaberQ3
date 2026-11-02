extends SceneTree
func _init() -> void:
	for p in ["res://game/Chain/ChainLink.material"]:
		var r = load(p)
		print(p, " -> ", r, " local_to_scene=", r.resource_local_to_scene if r is Resource else "n/a")
		if r is ShaderMaterial:
			print("  shader=", r.shader, " uniforms=", r.shader.get_shader_uniform_list().size())
	quit()
