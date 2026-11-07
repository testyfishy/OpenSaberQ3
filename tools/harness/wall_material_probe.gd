extends SceneTree

func _init() -> void:
	for path in ["res://game/Wall/wall_new.material", "res://game/Wall/wall.material"]:
		var mat := load(path)
		print("WALLMAT %s -> %s" % [path, str(mat)])
		if mat is BaseMaterial3D:
			var b := mat as BaseMaterial3D
			print("  albedo=%s texture=%s transparency=%d shading=%d" % [
				str(b.albedo_color), str(b.albedo_texture), b.transparency, b.shading_mode])
		elif mat is ShaderMaterial:
			var sm := mat as ShaderMaterial
			if sm.shader != null:
				print("  shader=%s" % sm.shader.resource_path)
				for info: Dictionary in sm.shader.get_shader_uniform_list():
					print("  %s=%s" % [info["name"], str(sm.get_shader_parameter(info["name"]))])
	quit()
