extends Node

# UI screenshot harness (desktop). Renders the settings panel exactly as authored and saves it,
# so layout problems can be seen and fixed without a headset. The panel's root is a Control, so a
# SubViewport renders it directly.
#
# Run: godot --path . res://tools/ui_shots.tscn
# Writes user://ui_settings_top.png and user://ui_settings_bottom.png.

func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(896, 576)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var panel := (load("res://game/settings_Panel.tscn") as PackedScene).instantiate() as Control
	viewport.add_child(panel)
	# Let _ready finish, the vr slider attach and the containers lay out.
	for i in 4:
		await get_tree().process_frame
	viewport.get_texture().get_image().save_png("user://ui_settings_top.png")
	print("UISHOT top ", ProjectSettings.globalize_path("user://ui_settings_top.png"))

	var scroll := panel.get_node("ScrollContainer") as ScrollContainer
	scroll.scroll_vertical = 500
	for i in 4:
		await get_tree().process_frame
	viewport.get_texture().get_image().save_png("user://ui_settings_mid.png")
	print("UISHOT mid ", ProjectSettings.globalize_path("user://ui_settings_mid.png"))
	scroll.scroll_vertical = 100000
	for i in 4:
		await get_tree().process_frame
	viewport.get_texture().get_image().save_png("user://ui_settings_bottom.png")
	print("UISHOT bottom ", ProjectSettings.globalize_path("user://ui_settings_bottom.png"),
		"  scroll_max=", scroll.get_v_scroll_bar().max_value)

	get_tree().quit()
