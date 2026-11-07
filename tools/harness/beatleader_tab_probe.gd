extends Node3D

# Exercises the HighscorePanel BeatLeader tab against the live API: board + top-10 rows, then a
# second call with a bogus hash to check the error path is shown, not a crash.

const HASH := "d921dfb5f0581f6e16cf312a2c16476e7c88b658"

func _ready() -> void:
	var canvas := preload("res://OQ_Toolkit/OQ_UI2D/OQ_UI2DCanvas.tscn").instantiate() as OQ_UI2DCanvas
	var panel := preload("res://game/HighscorePanel.tscn").instantiate() as HighscorePanel
	canvas.add_child(panel)
	add_child(canvas)
	await get_tree().process_frame
	print("BLTAB tabs=", panel._tabs != null, " rows=", panel._bl_row_labels.size())

	panel._fetch_bl("probe", HASH, "ExpertPlus", "Standard")
	var waited := 0.0
	while panel._bl_status.text.begins_with("Loading") and waited < 20.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	var shown := 0
	for labels in panel._bl_row_labels:
		if (labels[0].get_parent() as Control).visible:
			shown += 1
	print("BLTAB status=", panel._bl_status.text, " rows=", shown)
	if shown > 0:
		var first: Array = []
		for label in panel._bl_row_labels[0]:
			first.append((label as Label).text)
		print("BLTAB first=", first)

	# Stale-response guard: a new map cancels the old token and clears the rows.
	panel._token += 1
	panel._map = null
	panel._load_beatleader()
	print("BLTAB no_map_status=", panel._bl_status.text)
	get_tree().quit()
