extends StaticBody3D
class_name Floor

const FLOOR_LIGHT_SHADER := preload("res://game/shaders/floor_light.gdshader")
# Same light, plus ALPHA. A shader that writes ALPHA puts the floor in the transparent pass
# even at alpha 1.0 (no depth prepass, no early-z over a large screen area), so the opaque
# variant is used unless mirrored copies actually need to be seen through the floor.
const FLOOR_LIGHT_ALPHA_SHADER := preload("res://game/shaders/floor_light_alpha.gdshader")
# The floor is only see-through when the mirrored copies (FR-047) need a surface to show
# through; the rest of the time it stays fully opaque.
const MIRROR_FLOOR_ALPHA := 0.86

var left_last_position := Vector2(0,-50)
var right_last_position := Vector2(0,-50)

var C_LEFT := Color()
var C_RIGHT := Color()

@onready var sub_viewport := $SubViewport as SubViewport
@onready var color_rect := $SubViewport/ColorRect as ColorRect
@onready var burn_l := $SubViewport/ColorRect/burn_l as Node2D
@onready var burn_r := $SubViewport/ColorRect/burn_r as Node2D
@onready var l_sprite := $SubViewport/ColorRect/burn_l/sprite as Panel
@onready var r_sprite := $SubViewport/ColorRect/burn_r/sprite as Panel
@onready var timer_clear := $TimerClear as Timer
@onready var _floor_mesh := $Node3D/cutFloor as MeshInstance3D

# The pre-006 material (burn trail only) and the analytic-light one (same trail plus the
# saber pools). Both are built once; apply_visual_settings() assigns whichever the current
# settings need, so the floor is opaque whenever nothing requires the shader.
var _opaque_mat: StandardMaterial3D
var _light_mat: ShaderMaterial

var is_disabled := false

func _ready() -> void:
	_opaque_mat = _floor_mesh.material_override as StandardMaterial3D
	_opaque_mat.albedo_texture = sub_viewport.get_texture()
	_opaque_mat.emission_texture = sub_viewport.get_texture()
	_light_mat = ShaderMaterial.new()
	_light_mat.shader = FLOOR_LIGHT_SHADER
	_light_mat.set_shader_parameter(&"burn_tex", sub_viewport.get_texture())
	update_left_color(Settings.color_left)
	update_right_color(Settings.color_right)
	apply_visual_settings()
	
	if OS.get_name() == &"Web":
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		is_disabled = true

# Single funnel for the visual settings that touch the floor (FR-045, FR-047), so the
# material in use and the shader uniforms can never disagree.
func apply_visual_settings() -> void:
	if _light_mat == null:
		return
	var light_on: bool = Settings.floor_light
	var mirror_on: bool = Settings.mirror_reflections
	_light_mat.set_shader_parameter(&"streak_energy", 1.0 if light_on else 0.0)
	_light_mat.set_shader_parameter(&"floor_alpha", MIRROR_FLOOR_ALPHA if mirror_on else 1.0)
	_light_mat.shader = FLOOR_LIGHT_ALPHA_SHADER if mirror_on else FLOOR_LIGHT_SHADER
	_floor_mesh.material_override = _light_mat if (light_on or mirror_on) else _opaque_mat

func update_left_color(color: Color) -> void:
	C_LEFT = color
	burn_l.modulate = color*6
	if _light_mat != null:
		_light_mat.set_shader_parameter(&"left_color", color)

func update_right_color(color: Color) -> void:
	C_RIGHT = color
	burn_r.modulate = color*6
	if _light_mat != null:
		_light_mat.set_shader_parameter(&"right_color", color)

var left_is_out := false
var right_is_out := false
func burn_mark(pos:=Vector3(0,0,-50),type:=0) -> void:
	if is_disabled:
		return
	var newpos := Vector2(
		(pos.x+1)*256,
		pos.z*256
	)
	var burn_mark_sprite: Node2D
	var burn_mark_sprite_long: Panel
	var dist: float
	if type == 0:
		burn_mark_sprite = burn_l
		burn_mark_sprite_long = l_sprite
		left_is_out = false
		burn_mark_sprite.rotation = newpos.angle_to_point(left_last_position)
		dist = left_last_position.distance_to(newpos)
	elif type == 1:
		burn_mark_sprite = burn_r
		burn_mark_sprite_long = r_sprite
		right_is_out = false
		burn_mark_sprite.rotation = newpos.angle_to_point(right_last_position)
		dist = right_last_position.distance_to(newpos)
	else:
		return
	var was_out := !burn_mark_sprite.visible
	burn_mark_sprite.visible = true
	
	burn_mark_sprite.position = newpos
	
	burn_mark_sprite.rotation_degrees += 180
	if dist > 12 and not was_out:
		burn_mark_sprite_long.size.x = dist+12
	else:
		burn_mark_sprite_long.size.x = 24
	
	if type == 0:
		left_last_position = newpos
	elif type == 1:
		right_last_position = newpos

func _process(_delta: float) -> void:
	if left_is_out:
		burn_l.visible = false
	if right_is_out:
		burn_r.visible = false
	left_is_out = true
	right_is_out = true

func _on_timer_clear_timeout() -> void:
	color_rect.self_modulate.a = 1
	await get_tree().process_frame
	color_rect.self_modulate.a = 0
	timer_clear.start()
