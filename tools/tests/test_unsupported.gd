extends Node

# MapSupport test (specs/013 FR-007 slice 3, spec FR-030).
#
# The canonical map dump covers fake-note filtering indirectly (filtered notes are absent from the
# stacks), but it does not print the unsupported-feature list, so this checks that list directly on
# synthetic maps.
#
# Run: godot --headless --path . res://tools/tests/test_unsupported.tscn

const MapSupport := preload("res://game/scripts/MapSupport.gd")

func _ready() -> void:
	var ok := true
	ok = _case("empty", {}, null, [], 0) and ok
	ok = _case("box lighting", {"lightColorEventBoxGroups": [{}]}, null, ["box-group lighting"], 0) and ok
	ok = _case("360 rotation", {"rotationEvents": [{"b": 1.0}]}, null, ["360 rotation"], 0) and ok
	ok = _case("lane rotation", {"_events": [{"_type": 14.0}]}, null, ["lane rotation"], 0) and ok
	ok = _case("chroma", {"customData": {"customEvents": {}}}, null, ["Chroma/Noodle animation"], 0) and ok
	ok = _case("fake notes", {"customData": {"fakeColorNotes": [{}, {}], "fakeObstacles": [{}]}}, null, [], 3) and ok

	var bundled := MapInfo.new("3.0.0", "t", "", "a", "m", 120.0, 0.0, 0.0, "", "", "", 0.0, {"_assetBundle": true}, "", [])
	ok = _case("unity assets", {}, bundled, ["custom Unity assets"], 0) and ok

	print("SUPPORTTEST ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)

func _case(label: String, data: Dictionary, info: MapInfo, want: Array, want_fakes: int) -> bool:
	MapSupport.reset()
	MapSupport.detect_unsupported(data, info)
	var got: Array = []
	for f in MapSupport.unsupported_features:
		got.append(String(f))
	var good := got == want and MapSupport.fakes_filtered == want_fakes
	print("%s: features=%s fakes=%d %s" % [label, str(got), MapSupport.fakes_filtered, "ok" if good else "FAIL"])
	return good
