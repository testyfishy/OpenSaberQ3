extends SceneTree

func _init() -> void:
	var mat := load("res://game/Arc/Arc.material") as ShaderMaterial
	if mat == null:
		print("ARCPROBE no material")
		quit()
		return
	for info: Dictionary in mat.shader.get_shader_uniform_list():
		var name := String(info["name"])
		print("ARCPROBE %s = %s" % [name, str(mat.get_shader_parameter(name))])
	quit()
