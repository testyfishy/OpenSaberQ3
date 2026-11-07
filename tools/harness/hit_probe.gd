extends Node

const HitResolver := preload("res://game/scripts/HitResolver.gd")

# specs/028 FR-011: the miss-probe distance helper and its debug-only switch.

func _ready() -> void:
	var half := Vector3(0.25, 0.25, 0.25)
	var through := HitResolver._segment_box_distance(Vector3(-1, 0, 0), Vector3(1, 0, 0), half)
	var outside := HitResolver._segment_box_distance(Vector3(1.0, 0, 0), Vector3(1.5, 0, 0), half)
	var graze := HitResolver._segment_box_distance(Vector3(0.3, 0, 0), Vector3(1.3, 0, 0), half)
	print("HITPROBE through=%.3f outside=%.3f graze=%.3f" % [through, outside, graze])
	var before := HitResolver.miss_probe()
	ProjectSettings.set_setting("gameplay/debug/miss_probe", true)
	HitResolver._miss_probe = -1
	var after := HitResolver.miss_probe()
	print("HITPROBE probe before=%s after=%s" % [before, after])
	get_tree().quit()
