extends Node3D

# Desktop screenshot test (specs/024 FR-004, FR-012, SC-002/SC-006).
# Loads the real game scene, opens the menu, captures through the in-game service, and checks the
# saved PNG exists at 1920x1080 with non-black pixels.
#
# Run: godot --headless --path . res://tools/tests/test_screenshot.tscn

var _bad := 0

func _ready() -> void:
	var scene := load("res://game/BeepSaber_Game.tscn") as PackedScene
	var game := scene.instantiate()
	add_child(game)
	await get_tree().create_timer(6.0).timeout
	for _i in 10:
		await get_tree().process_frame
	if game.screenshot == null:
		_check(false, "screenshot service exists")
		_finish()
		return
	var result: Dictionary = await game.screenshot.capture()
	_check(bool(result.get("ok", false)), "capture ok (%s)" % str(result.get("error", "")))
	_check(int(result.get("width", 0)) == 1920, "width 1920")
	_check(int(result.get("height", 0)) == 1080, "height 1080")
	var path := str(result.get("path", ""))
	_check(not path.is_empty(), "path returned")
	if not path.is_empty():
		for _i in 50:
			if FileAccess.file_exists(path):
				break
			await get_tree().create_timer(0.1).timeout
		_check(FileAccess.file_exists(path), "file written (%s)" % path)
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			_check(img != null, "png loads")
			if img != null:
				_check(img.get_width() == 1920 and img.get_height() == 1080, "png is 1920x1080")
				var bright := false
				for y in 3:
					for x in 5:
						var c := img.get_pixel(int(img.get_width() * (x + 0.5) / 5.0),
							int(img.get_height() * (y + 0.5) / 3.0))
						if c.r > 0.02 or c.g > 0.02 or c.b > 0.02:
							bright = true
				_check(bright, "png is not black")
	_finish()

func _finish() -> void:
	print("SCREENSHOTTEST ", "PASS" if _bad == 0 else "FAIL")
	get_tree().quit(0 if _bad == 0 else 1)

func _check(condition: bool, what: String) -> void:
	if not condition:
		push_error("SCREENSHOTTEST " + what)
		_bad += 1
