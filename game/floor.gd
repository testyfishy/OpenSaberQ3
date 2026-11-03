extends StaticBody3D
class_name Floor

const FLOOR_LIGHT_SHADER := preload("res://game/shaders/floor_light.gdshader")

# There is one floor material now. The mirrored copies (FR-047) are a `next_pass` on the
# notes and blades that clips itself to this pad (see shaders/mirror_pass.gdshader), so the
# floor never has to become translucent - a shader that writes ALPHA would put this whole
# surface in the transparent pass and lose early-z for everything behind it.

# How long the cut burst lasts and how far it reaches (FR-003). Both are floats on this
# node: no node, tween or allocation is created per cut.
const FLASH_DECAY := 12.0
const FLASH_RADIUS := 0.55

# Cheap handle for the cut path: `Floor.instance.flash_at(pos)` instead of a group lookup or
# a tree walk on every cut.
static var instance: Floor

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

# Decaying cut burst (FR-003). Only written to the shader while it is not zero, so a floor
# with no cuts pays one float comparison per frame.
var _flash_energy := 0.0

var is_disabled := false

func _ready() -> void:
	instance = self
	_opaque_mat = _floor_mesh.material_override as StandardMaterial3D
	_opaque_mat.albedo_texture = sub_viewport.get_texture()
	_opaque_mat.emission_texture = sub_viewport.get_texture()
	_light_mat = ShaderMaterial.new()
	_light_mat.shader = FLOOR_LIGHT_SHADER
	_light_mat.set_shader_parameter(&"burn_tex", sub_viewport.get_texture())
	_light_mat.set_shader_parameter(&"flash_radius", FLASH_RADIUS)
	update_left_color(Settings.color_left)
	update_right_color(Settings.color_right)
	apply_visual_settings()
	
	if OS.get_name() == &"Web":
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		is_disabled = true

# A cut raises the burst at the point where the blade met the note, projected onto the floor
# plane. One float write; the shader draws the ring.
func flash_at(pos: Vector3) -> void:
	if not Settings.hit_flash or _light_mat == null:
		return
	_flash_energy = 1.0
	_light_mat.set_shader_parameter(&"flash_pos", Vector3(pos.x, 0.0, pos.z))

# Single funnel for the visual settings that touch the floor (FR-045, FR-003, FR-006), so
# the material in use and the shader uniforms can never disagree.
func apply_visual_settings() -> void:
	if _light_mat == null:
		return
	var light_on: bool = Settings.floor_light
	_light_mat.set_shader_parameter(&"streak_energy", 1.0 if light_on else 0.0)
	RenderingServer.global_shader_parameter_set(
		&"floor_grid", 1.0 if Settings.floor_grid else 0.0)
	# The shader also carries the grid and the cut burst, so it is used whenever either of
	# those is on as well as when the streak is.
	_floor_mesh.material_override = _light_mat if (
		light_on or Settings.floor_grid or Settings.hit_flash) else _opaque_mat

func update_left_color(color: Color) -> void:
	C_LEFT = color
	burn_l.modulate = color*6

func update_right_color(color: Color) -> void:
	C_RIGHT = color
	burn_r.modulate = color*6

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

func _process(delta: float) -> void:
	if left_is_out:
		burn_l.visible = false
	if right_is_out:
		burn_r.visible = false
	left_is_out = true
	right_is_out = true
	# FR-003: the burst decays here rather than in a tween or a Timer node.
	if _flash_energy > 0.0:
		_flash_energy = maxf(0.0, _flash_energy - FLASH_DECAY * delta)
		if _light_mat != null:
			_light_mat.set_shader_parameter(&"flash_energy", _flash_energy)

func _on_timer_clear_timeout() -> void:
	color_rect.self_modulate.a = 1
	await get_tree().process_frame
	color_rect.self_modulate.a = 0
	timer_clear.start()
