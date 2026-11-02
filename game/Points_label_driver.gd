extends Node3D
class_name PointsLabelDriver

# Spike attribution (FR-033). `labels_spawned` counts node instantiations here:
# this driver pre-pools a fixed set of labels and reuses them, so the honest
# expected value for a whole run is 4 (at startup) and 0 during gameplay. The
# counter exists so that claim is measured rather than asserted.
const Cost := preload("res://game/scripts/CostProbe.gd")
const POOL_SIZE := 4

var points_label := [null, null, null, null]
var current_point_label :int = 0


func _ready():
	var points_label_ref := preload("res://game/points_label.tscn")
	for i in range(0, POOL_SIZE):
		var instance := points_label_ref.instantiate()
		Cost.labels_spawned += 1
		points_label[i] = instance
		add_child(instance)


func show_points(_position: Vector3, value: String):
	if value == "0":
		value = "x"
	var color := Color(1,0,0) if value == "x" else Color(1,1,1)
	points_label[current_point_label].show_points(_position,value,color)
	current_point_label += 1
	current_point_label %= POOL_SIZE
