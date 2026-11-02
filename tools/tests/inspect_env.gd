extends SceneTree

# Throwaway probe (not shipped): dumps the resource types the visual work has to
# touch, so the plan is based on what is actually in the files rather than on
# assumptions about the binary .material resources.

func _init() -> void:
	for path in ["res://game/Wall/wall_new2.material", "res://game/LightSaber.material",
			"res://game/BeepCube/BeepCube.gdshader"]:
		var res = load(path)
		print("=== ", path, " -> ", res)
		if res is BaseMaterial3D:
			var m := res as BaseMaterial3D
			print("  local_to_scene=", m.resource_local_to_scene,
				" shading=", m.shading_mode, " blend=", m.blend_mode,
				" albedo=", m.albedo_color, " emission=", m.emission_enabled,
				" cull=", m.cull_mode, " alpha=", m.transparency)
		if res is ShaderMaterial:
			var sm := res as ShaderMaterial
			print("  local_to_scene=", sm.resource_local_to_scene, " shader=", sm.shader)
			var list := sm.shader.get_shader_uniform_list()
			for u in list:
				print("  uniform ", u)
	var iface := XRServer.primary_interface
	print("=== xr iface: ", iface)
	if iface != null:
		var names := []
		for m in iface.get_method_list():
			if String(m["name"]).contains("foveation"):
				names.append(m["name"])
		print("  foveation methods: ", names)
		var props := []
		for p in iface.get_property_list():
			if String(p["name"]).contains("foveation"):
				props.append(p["name"])
		print("  foveation props: ", props)
	quit()
