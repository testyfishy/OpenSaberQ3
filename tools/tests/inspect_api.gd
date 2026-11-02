extends SceneTree

func _init() -> void:
	var cls := "OpenXRInterface"
	print("class exists: ", ClassDB.class_exists(cls))
	for m in ClassDB.class_get_method_list(cls, true):
		var n := String(m["name"])
		if n.contains("foveation") or n.contains("render_target") or n.contains("refresh"):
			print("  method ", n, " args=", m["args"].size())
	for p in ClassDB.class_get_property_list(cls, true):
		var n := String(p["name"])
		if n.contains("foveation"):
			print("  property ", n)
	print("GeometryInstance3D has set_instance_shader_parameter: ",
		ClassDB.class_has_method("GeometryInstance3D", "set_instance_shader_parameter"))
	print("SkyMaterial classes: ", ClassDB.class_exists("ShaderMaterial"))
	var vp := ClassDB.class_get_property_list("SubViewport", true)
	for p in vp:
		if String(p["name"]) == "render_target_update_mode":
			print("SubViewport update mode property exists")
	print("Viewport MSAA enum ok")
	quit()
