extends Node

# BPM segment test (FR-025 / SC-012). Synthetic map: 120 BPM until beat 16, then 180 BPM.
# Runs as a scene (not --script) because Map.gd uses the Utils autoload.
# Run: godot --headless --path . res://tools/tests/test_bpm.tscn

const MapTimer := preload("res://game/scripts/MapTimer.gd")

func _ready() -> void:
	var info := MapInfo.new("3.0.0", "t", "", "a", "m", 120.0, 0.0, 0.0, "", "", "", 0.0, {}, "", [])
	Map.current_info = info
	var data := {
		"version": "3.0.0",
		"bpmEvents": [
			{"b": 0.0, "m": 120.0},
			{"b": 16.0, "m": 180.0},
		],
	}
	MapTimer.load_bpm_events(data, 120.0)

	var ok := true
	var cases := {0.0: 0.0, 8.0: 4.0, 16.0: 8.0, 24.0: 10.6667}
	for beat: float in cases:
		var got := Map.beat_to_seconds(beat)
		var want: float = cases[beat]
		var good := absf(got - want) < 0.002
		ok = ok and good
		print("beat %.1f -> %.4f s (want %.4f) %s" % [beat, got, want, "ok" if good else "FAIL"])

	for beat: float in [3.0, 15.5, 16.0, 22.0]:
		var back := Map.seconds_to_beat(Map.beat_to_seconds(beat))
		var good := absf(back - beat) < 0.001
		ok = ok and good
		print("round trip beat %.2f -> %.4f s -> %.4f beat %s" % [beat, Map.beat_to_seconds(beat), back, "ok" if good else "FAIL"])

	print("bpm at 15: %.1f (want 120), at 17: %.1f (want 180)" % [Map.bpm_at_beat(15.0), Map.bpm_at_beat(17.0)])
	ok = ok and Map.bpm_at_beat(15.0) == 120.0 and Map.bpm_at_beat(17.0) == 180.0
	print("BPMTEST ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
