extends Node3D

# Renders the settings panel (every tab) and the results screen to PNG files, so their layout
# can be reviewed on a PC instead of described from inside the headset. Needs a real renderer:
# run WITHOUT --headless.
#
#   godot --path . res://tools/harness/screens_preview.tscn -- <output-folder>
#
# Writes settings_<tab>.png, results_new_record.png and results_plain.png, then quits.

var _out := "user://screens/"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0].replace("\\", "/")
	if not _out.ends_with("/"):
		_out += "/"
	DirAccess.make_dir_recursive_absolute(_out)
	await _settings()
	await _results()
	print("SCREENS done ", _out)
	get_tree().quit()


func _settings() -> void:
	var canvas := preload("res://OQ_Toolkit/OQ_UI2D/OQ_UI2DCanvas.tscn").instantiate() as OQ_UI2DCanvas
	var panel := preload("res://game/settings_Panel.tscn").instantiate() as SettingsPanel
	canvas.add_child(panel)
	add_child(canvas)
	await get_tree().process_frame
	await get_tree().process_frame
	var viewport := canvas.get_node("SubViewport") as SubViewport
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i in panel.TAB_NAMES.size():
		panel._set_tab(i)
		for f in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var file := "settings_%d_%s.png" % [i, str(panel.TAB_NAMES[i]).to_lower()]
		viewport.get_texture().get_image().save_png(_out + file)
		print("SCREENS saved ", file, " ", viewport.size)
	canvas.queue_free()
	await get_tree().process_frame


func _results() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.0, 0.0, 0.0)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.62, 0.68)
	add_child(env)
	var end := preload("res://game/EndScore.tscn").instantiate() as EndScore
	add_child(end)
	end.position = Vector3(0.0, 1.5, -2.0)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 1.5, 0.6)
	cam.fov = 60.0
	cam.current = true
	get_window().size = Vector2i(1400, 1000)
	for shot in [
		["results_new_record.png", 123456, 123456, 0.94, true, true],
		["results_plain.png", 45210, 98765, 0.71, false, false],
	]:
		end.show_saved_as("Player") if shot[5] else end.hide_saved()
		end.show_score(int(shot[1]), int(shot[2]), float(shot[3]),
			"Song Title Goes Here By Some Artist\nExpertPlus     Map author: A Mapper", bool(shot[4]), bool(shot[5]))
		# show_score animates for about five seconds of real time before everything is in place.
		await get_tree().create_timer(6.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out + str(shot[0]))
		print("SCREENS saved ", shot[0])
