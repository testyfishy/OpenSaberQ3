extends SceneTree

func _init() -> void:
	for prop: Dictionary in ProjectSettings.get_property_list():
		var name := String(prop.get("name", ""))
		if name.contains("hand") or name.contains("xr/openxr"):
			print("SETTING ", name, " = ", ProjectSettings.get_setting(name))
	quit()
