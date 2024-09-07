extends Node3D

var currentPosition: Vector3
var movePosition: Vector3
var targetPosition: Vector3
var distance := 3.0
var time_to_move := 0.5
var time_remaining := 3.0

@export var camera: Node3D
@onready var opensaber_material := ($opensaber as MeshInstance3D).material_override as StandardMaterial3D
@onready var godot_material := ($Godot as MeshInstance3D).material_override as StandardMaterial3D
@onready var view_blocker := $ViewBlocker as MeshInstance3D
@onready var view_blocker_material := view_blocker.material_override as StandardMaterial3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var viewDir := -camera.global_transform.basis.z
	var camPos := -camera.global_transform.origin
	currentPosition = camPos + viewDir * distance
	targetPosition = currentPosition
	movePosition = currentPosition
	
	look_at_from_position(currentPosition, camPos, Vector3(0,1,0))
	
	($DebugLabel as Node3D).visible = OS.is_debug_build()

var moving := false
var moveTimer := 0.0

func _process(dt: float) -> void:
	time_remaining -= dt
	if time_remaining < 0.0:
		queue_free()
		return
	elif time_remaining < 1.0:
		opensaber_material.albedo_color.a = time_remaining
		godot_material.albedo_color.a = time_remaining
		view_blocker_material.albedo_color.a = time_remaining
	
	var viewDir := -camera.global_transform.basis.z
	viewDir.y = 0.0
	viewDir = viewDir.normalized()
	
	var camPos := camera.global_transform.origin
	
	#TODO: rotate instead of move
	targetPosition = camPos + viewDir * distance
	var distToTarget := (targetPosition - currentPosition).length()
	if moving:
		currentPosition = currentPosition + (movePosition - currentPosition) * dt
		if (distToTarget < 0.05):
			moving = false
	
	if (distToTarget > 0.5):
		moveTimer += dt
	else:
		moveTimer = 0.0
	
	if (moveTimer > time_to_move):
		moving = true
		movePosition = targetPosition
	
	look_at_from_position(currentPosition, camPos, Vector3(0,1,0))
	view_blocker.global_position = camera.global_position
