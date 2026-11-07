extends Node3D

const HASH := "d921dfb5f0581f6e16cf312a2c16476e7c88b658"

func _ready() -> void:
	var canvas := preload("res://OQ_Toolkit/OQ_UI2D/OQ_UI2DCanvas.tscn").instantiate() as OQ_UI2DCanvas
	var panel := preload("res://game/HighscorePanel.tscn").instantiate() as HighscorePanel
	canvas.add_child(panel)
	add_child(canvas)
	await get_tree().process_frame
	panel._fetch_bl("probe", HASH, "ExpertPlus", "Standard")
	var waited := 0.0
	while panel._bl_status.text.begins_with("Loading") and waited < 20.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	panel._local_page.visible = false
	panel._bl_page.visible = true
	var viewport := canvas.get_node("SubViewport") as SubViewport
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("F:/Dev/BeepSaberBin/f025/hiscore_bl.png")
	print("HISCOREPREVIEW ", viewport.size, " status=", panel._bl_status.text)
	get_tree().quit()

