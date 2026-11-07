extends SceneTree
func _init():
	Arc._configure_fades()
	for p in ["distance_fade_min","distance_fade_max","distance_fade_tip_min","distance_fade_tip_max"]:
		print("ARCPARAM ", p, "=", Arc.left_material.get_shader_parameter(p))
	quit()
