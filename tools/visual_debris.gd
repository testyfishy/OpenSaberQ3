extends Node3D

# Deterministic render check for the cut debris (spec FR-013). Desktop only.
# Run: godot --path . res://tools/visual_debris.tscn
# Writes user://visual_debris.png. Two bursts: a horizontal cut (normal +Y) on the left and a
# diagonal cut (normal 45 degrees) on the right, so the direction difference is visible.

var _frames := 0
var _field: DebrisField

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.03, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.35, 0.42)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	_field = (load("res://game/BeepCube/DebrisField.tscn") as PackedScene).instantiate() as DebrisField
	add_child(_field)

	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 60.0
	cam.look_at_from_position(Vector3(0.0, 1.3, 1.6), Vector3(0.0, 1.15, 0.0))
	cam.make_current()

func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 2:
		_field.emit_burst(Vector3(-0.45, 1.2, 0.0), Vector3(0, 1, 0), Vector3(3.0, 0, 0), Color(1.0, 0.1, 0.1))
		_field.emit_burst(Vector3(0.45, 1.2, 0.0), Vector3(0.707, 0.707, 0), Vector3(0, 3.0, 0), Color(0.1, 0.4, 1.0))
	if _frames == 8:
		get_viewport().get_texture().get_image().save_png("user://visual_debris.png")
		print("VISUALCHECK debris ", ProjectSettings.globalize_path("user://visual_debris.png"),
			" bursts=", _field.bursts_total)
	if _frames > 10:
		get_tree().quit()
