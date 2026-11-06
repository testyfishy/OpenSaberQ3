extends Node

# MapData reload test (specs/016 FR-038): two loads of the same synthetic map must not duplicate a
# stack, and reset() must clear everything. Threads are joined per load; a second load starts while
# no thread is running.
#
# Run: godot --headless --path . res://tools/tests/test_map_reload.tscn

const MapData := preload("res://game/scripts/MapData.gd")

var _bad := 0

func _ready() -> void:
	var data := {
		"version": "3.0.0",
		"colorNotes": [
			{"b": 1.0, "x": 0, "y": 0, "c": 0, "d": 1, "a": 0},
			{"b": 2.0, "x": 1, "y": 0, "c": 1, "d": 1, "a": 0},
			{"b": 3.0, "x": 2, "y": 0, "c": 0, "d": 1, "a": 0},
		],
		"bombNotes": [{"b": 2.5, "x": 1, "y": 0}],
		"obstacles": [{"b": 4.0, "x": 0, "y": 0, "d": 2.0, "w": 1, "h": 1}],
		"basicBeatmapEvents": [{"b": 1.0, "et": 0, "i": 0, "f": 1.0}],
	}

	MapData.reset()
	_check(MapData.note_stack.is_empty(), "reset clears notes")
	MapData.load_v3(data.duplicate(true))
	var first := _sizes()
	_check(first == [3, 1, 1, 0, 0, 1], "first load sizes %s" % str(first))

	MapData.load_v3(data.duplicate(true))
	var second := _sizes()
	_check(second == first, "second load has the same sizes (no duplication): %s vs %s" % [str(second), str(first)])
	_check(MapData.note_stack.size() == 3, "notes not duplicated")

	MapData.reset()
	_check(_sizes() == [0, 0, 0, 0, 0, 0], "reset empties every stack")

	print("RELOADTEST ", "PASS" if _bad == 0 else "FAIL")
	get_tree().quit(0 if _bad == 0 else 1)

func _sizes() -> Array:
	return [
		MapData.note_stack.size(), MapData.bomb_stack.size(), MapData.obstacle_stack.size(),
		MapData.arc_stack.size(), MapData.chain_stack.size(), MapData.event_stack.size(),
	]

func _check(condition: bool, what: String) -> void:
	if not condition:
		push_error("RELOADTEST " + what)
		_bad += 1
