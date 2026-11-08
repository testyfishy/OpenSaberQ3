extends SceneTree

func _init() -> void:
	for prop: Dictionary in ClassDB.class_get_property_list("XRHandTracker", true):
		print("PROP ", prop.get("name", ""))
	for method: Dictionary in ClassDB.class_get_method_list("XRHandTracker", true):
		print("METHOD ", method.get("name", ""), " args=", method.get("args", []))
	for c in ClassDB.class_get_integer_constant_list("XRHandTracker", true):
		print("CONST ", c, " = ", ClassDB.class_get_integer_constant("XRHandTracker", c))
	quit()
