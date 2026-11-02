extends Node3D
class_name DefaultSaber

var is_extended := false

@onready var _anim := $AnimationPlayer as AnimationPlayer
@onready var light_mesh := $LightSaber_Mesh as MeshInstance3D
@onready var _mat := light_mesh.material_override as ShaderMaterial
@onready var tip := $tip as Marker3D
@onready var tail := $tail as SaberTail
@onready var hitsound := $hitsound as AudioStreamPlayer3D

# Pending delayed hit sounds, in seconds remaining. A hit whose note is a little
# in the future plays its sound when that beat arrives; this used to be an
# `await get_tree().create_timer(...)`, i.e. a SceneTreeTimer plus a coroutine per
# hit (FR-033: per-hit allocation on the gameplay path). A SceneTreeTimer only
# fires on a process frame anyway, so polling here has the same timing.
var _pending_hits: Array[float] = []

func _ready() -> void:
	set_process(false)
	quickhide()

func _process(delta: float) -> void:
	if _pending_hits.is_empty():
		set_process(false)
		return
	var i := 0
	while i < _pending_hits.size():
		_pending_hits[i] -= delta
		if _pending_hits[i] <= 0.0:
			_pending_hits.remove_at(i)
			hitsound.play()
		else:
			i += 1

func set_color(color: Color) -> void:
	_mat.set_shader_parameter(&"color", color)
	tail.set_color(color)

func set_thickness(value: float) -> void:
	light_mesh.scale.x = value
	light_mesh.scale.z = value

func set_trail(enabled: bool = true) -> void:
	tail.visible = enabled

func _show() -> void:
	_anim.play(&"Show")
	is_extended = true
	
func _hide() -> void:
	_anim.play(&"Hide")
	is_extended = false
	
func quickhide() -> void:
	_anim.play(&"QuickHide")
	is_extended = false

func hit(time_offset: float) -> void:
	if time_offset>0.2 or time_offset<-0.05:
		hitsound.play()
	else:
		if time_offset <= 0:
			hitsound.play(-time_offset)
		else:
			_pending_hits.append(time_offset)
			set_process(true)
