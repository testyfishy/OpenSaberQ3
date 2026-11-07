extends Node3D

# Renders the left-side BeatLeader launcher through an OQ_UI2DCanvas so the panel's layout
# can be checked without the headset.

func _ready() -> void:
	var canvas := preload("res://OQ_Toolkit/OQ_UI2D/OQ_UI2DCanvas.tscn").instantiate() as OQ_UI2DCanvas
	var panel := preload("res://game/ui/BeatLeaderPanel/BeatLeaderLauncher.tscn").instantiate() as Control
	canvas.add_child(panel)
	add_child(canvas)
	await get_tree().process_frame
	await get_tree().process_frame
	var viewport := canvas.get_node("SubViewport") as SubViewport
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("F:/Dev/BeepSaberBin/f025/bleader_launcher.png")
	print("LAUNCHER saved ", viewport.size)
	get_tree().quit()
