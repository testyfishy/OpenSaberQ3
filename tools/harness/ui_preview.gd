extends Node3D

# Renders the BeastSaber panel and the Online Map Sources tiles through OQ_UI2DCanvas so
# their layout can be checked without the headset.

func _ready() -> void:
	await _render_panel(preload("res://game/ui/BeastSaberPanel/BeastSaberPanel.tscn"),
		"beastsaber_panel.png", true)
	await _render_panel(preload("res://game/ui/MapDownloadPanel/MapDownloadPanel.tscn"),
		"map_sources_panel.png", false)
	get_tree().quit()

func _render_panel(scene: PackedScene, file: String, load_list: bool) -> void:
	var canvas := preload("res://OQ_Toolkit/OQ_UI2D/OQ_UI2DCanvas.tscn").instantiate() as OQ_UI2DCanvas
	var panel := scene.instantiate() as Control
	canvas.add_child(panel)
	add_child(canvas)
	await get_tree().process_frame
	if load_list and panel is BeastSaberPanel:
		panel._load_page(0)
		var waited := 0.0
		while (panel as BeastSaberPanel)._busy != BeastSaberPanel.Busy.NONE and waited < 15.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
		(panel as BeastSaberPanel)._on_playlist_pressed(1)
	var viewport := canvas.get_node("SubViewport") as SubViewport
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("F:/Dev/BeepSaberBin/f025/" + file)
	print("UIPREVIEW saved ", file, " ", viewport.size)
	canvas.queue_free()
	await get_tree().process_frame
