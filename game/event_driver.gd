extends Node3D
class_name EventDriver

var ring_rot_speed := 0.0
var ring_rot_inv_dir := false
var rings_in := false

var left_color: Color
var right_color: Color

@onready var ring_holder := $Level/rings as Node3D
@onready var diagonal_lasers_holder := $Level/DiagonalLasers as Node3D
@onready var square_lasers_holder := $Level/SquareLasers as Node3D
@onready var left_waving_lasers_holder := $Level/LeftWavingLasers as Node3D
@onready var right_waving_lasers_holder := $Level/RightWavingLasers as Node3D
@onready var track_lights_holder := $Level/TrackLights as Node3D

@onready var sphere_material := ($Level/Sphere as MeshInstance3D).material_override as ShaderMaterial
@onready var diagonal_lasers_material := ($Level/DiagonalLasers/laser1/Bar7 as MeshInstance3D).material_override as StandardMaterial3D
@onready var square_lasers_material := ($Level/SquareLasers/Bar7 as MeshInstance3D).material_override as StandardMaterial3D
@onready var left_waving_lasers_material := ($Level/LeftWavingLasers/laser1/Bar7 as MeshInstance3D).material_override as StandardMaterial3D
@onready var right_waving_lasers_material := ($Level/RightWavingLasers/laser1/Bar7 as MeshInstance3D).material_override as StandardMaterial3D
@onready var track_lights_material := ($Level/TrackLights/Bar1 as MeshInstance3D).material_override as StandardMaterial3D
@onready var floor_material := ($Level/floor as MeshInstance3D).material_override as StandardMaterial3D

@onready var ring_anim_player := $Level/rings/AnimationPlayer as AnimationPlayer
@onready var left_laser_anim_player := $Level/LeftWavingLasers/AnimationPlayer as AnimationPlayer
@onready var right_laser_anim_player := $Level/RightWavingLasers/AnimationPlayer as AnimationPlayer

@export var disabled := false

# Precomputed shader-parameter names. Building "bg_%d_tint" % type allocates a
# String per light event (dozens per second in a dense map), and
# set_shader_parameter() has to convert it to a StringName anyway.
const TINT_PARAMS: Array[StringName] = [
	&"bg_0_tint", &"bg_1_tint", &"bg_2_tint", &"bg_3_tint", &"bg_4_tint"]
const INTENSITY_PARAMS: Array[StringName] = [
	&"bg_0_intensity", &"bg_1_intensity", &"bg_2_intensity", &"bg_3_intensity", &"bg_4_intensity"]

# Reused instead of a fresh Array per fade call: this runs once per light event.
var _fade_materials: Array[StandardMaterial3D] = []

# The colour the room is currently lit with, for the floor streak and the blade glow
# (specs/007-visual-options FR-005). Emitted from ONE group - the floor lights, the group the
# eye reads as "the room's light" - because publishing from every group would let whichever
# group fired last win the beat and make the tint flicker between colours.
signal light_event_color(color: Color)

func _publish_light_color(color: Color) -> void:
	light_event_color.emit(color)

func _ready() -> void:
	# get_rendering_device() returns null in opengl, meaning this block is skipped in vulkan
	if not RenderingServer.get_rendering_device():
		sphere_material.set_shader_parameter("contrast", 1)
		for background_side in 5:
			var shader_param := StringName("bg_%s_intensity_mult" % background_side)
			sphere_material.set_shader_parameter(
				shader_param,
				(sphere_material.get_shader_parameter(shader_param) as float) * 2.2
			)

	_build_light_tables()

func _process(delta: float) -> void:
	if not Scoreboard.paused:
		_step_fades(delta)
	# update the level animations
	#procces ring rotations
	if ring_rot_speed > 0:
		for ring in ring_holder.get_children():
			if ring is Node3D:
				var rot := ring_rot_speed
				if ring_rot_inv_dir: rot *= -1
				(ring as Node3D).rotate_z((rot * delta) * (float(ring.get_index()+1)/5))

func update_left_color(color: Color) -> void:
	left_color = color
	turn_light_on(EventInfo.TYPE_DIAGONAL_LASERS, color)
	turn_light_on(EventInfo.TYPE_LEFT_WAVING_LASERS, color)
	turn_light_on(EventInfo.TYPE_RIGHT_WAVING_LASERS, color)

func update_right_color(color: Color) -> void:
	right_color = color
	turn_light_on(EventInfo.TYPE_SQUARE_LASERS, color)
	turn_light_on(EventInfo.TYPE_CENTRE_LIGHTS, color)

func set_all_off() -> void:
	if disabled:
		for i in range(1,4):
			turn_light_off(i)
		ring_holder.visible = false
	else:
		for i in range(5):
			turn_light_off(i)

func set_all_on(left: Color, right: Color) -> void:
	if !disabled:
		update_left_color(left)
		update_right_color(right)
		ring_holder.visible = true

func process_event(data: EventInfo) -> void:
	if disabled: return
	if data.type == 5:
		# FR-029: light boost (v2 type 5, and v3 colorBoostBeatmapEvents converted to it).
		# It swaps the palette future on-events use; it does not force lights on.
		MapPalette.boost_active = data.value != 0
		left_color = MapPalette.env_left_boost if MapPalette.boost_active else MapPalette.env_left
		right_color = MapPalette.env_right_boost if MapPalette.boost_active else MapPalette.env_right
		return
	# 6/7 are the extra left/right light sets. Our room has one set per side, so they fold into
	# the side they belong to instead of being dropped (FR-030 / C1).
	if data.type == 6:
		data.type = 2
	elif data.type == 7:
		data.type = 3
	if data.type in range(0,5):
		# Chroma (FR-030): a colour on the event itself wins over the side's colour. White
		# events stay white, and events without a colour keep the old behaviour.
		var left_pt := data.color if data.color.a > 0.0 else left_color
		var right_pt := data.color if data.color.a > 0.0 else right_color
		match data.value:
			EventInfo.VALUE_LIGHTS_OFF:
				turn_light_off(data.type)
			EventInfo.VALUE_LIGHTS_RIGHT_ON:
				turn_light_on(data.type, right_pt)
			EventInfo.VALUE_LIGHTS_RIGHT_FLASH:
				flash_light_on(data.type, right_pt)
			EventInfo.VALUE_LIGHTS_RIGHT_FADE:
				flash_light_then_fade_off(data.type, right_pt)
			EventInfo.VALUE_LIGHTS_FADE_TO_RIGHT:
				fade_light_from_current(data.type, right_pt)
			EventInfo.VALUE_LIGHTS_LEFT_ON:
				turn_light_on(data.type, left_pt)
			EventInfo.VALUE_LIGHTS_LEFT_FLASH:
				flash_light_on(data.type, left_pt)
			EventInfo.VALUE_LIGHTS_LEFT_FADE:
				flash_light_then_fade_off(data.type, left_pt)
			EventInfo.VALUE_LIGHTS_FADE_TO_LEFT:
				fade_light_from_current(data.type, left_pt)
			EventInfo.VALUE_LIGHTS_WHITE_ON:
				turn_light_on(data.type, Color.WHITE)
			EventInfo.VALUE_LIGHTS_WHITE_FLASH:
				flash_light_on(data.type, Color.WHITE)
			EventInfo.VALUE_LIGHTS_WHITE_FADE:
				flash_light_then_fade_off(data.type, Color.WHITE)
			EventInfo.VALUE_LIGHTS_FADE_TO_WHITE:
				fade_light_from_current(data.type, Color.WHITE)
	else:
		match data.type:
			8:
				var ringtween := ring_holder.create_tween()
				if absf(ring_rot_speed) < 1.0:
					ring_rot_inv_dir = not ring_rot_inv_dir
				@warning_ignore("return_value_discarded")
				ringtween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).tween_property(self, ^"ring_rot_speed", 0.0, 2.0).from(3.0)
				ringtween.play()
			9:
				ring_anim_player.stop(false)
				ring_anim_player.play(&"out" if rings_in else &"in")
				rings_in = not rings_in
			12:
				var val := float(data.value) * 0.125
				left_laser_anim_player.speed_scale = val
				left_laser_anim_player.seek(randf_range(0.0, left_laser_anim_player.current_animation_length), true)
			13:
				var val := float(data.value) * 0.125
				right_laser_anim_player.speed_scale = val
				right_laser_anim_player.seek(randf_range(0.0, right_laser_anim_player.current_animation_length), true)

# specs/027 FR-020 (0.7.5): a light fade used to allocate a Tween and three tweeners per event.
# A group show can issue dozens of transitions a second, so the cost scaled with the map. Each
# light type now keeps one interpolation state, stepped in _process: five states per frame, no
# matter how many events the map carries.
var _fade_from: Array[Color] = [Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK]
var _fade_to: Array[Color] = [Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK]
var _fade_tint: Array[Color] = [Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK]
var _fade_t: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _fade_dur: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0]
var _fade_active: Array[bool] = [false, false, false, false, false]
var _fade_off: Array[bool] = [false, false, false, false, false]
var _fade_ease_in: Array[bool] = [false, false, false, false, false]
var _fade_linear: Array[bool] = [false, false, false, false, false]
var _type_materials: Array = []
var _type_groups: Array[Node3D] = []

func _build_light_tables() -> void:
	_type_materials = [
		[diagonal_lasers_material],
		[square_lasers_material],
		[left_waving_lasers_material],
		[right_waving_lasers_material],
		[track_lights_material, floor_material],
	]
	_type_groups = [diagonal_lasers_holder, square_lasers_holder, left_waving_lasers_holder,
		right_waving_lasers_holder, track_lights_holder]

func _step_fades(delta: float) -> void:
	for type in 5:
		if not _fade_active[type]:
			continue
		_fade_t[type] = minf(_fade_t[type] + delta / _fade_dur[type], 1.0)
		var t := _fade_t[type]
		var eased := t
		if not _fade_linear[type]:
			eased = t * t if _fade_ease_in[type] else 1.0 - (1.0 - t) * (1.0 - t)
		_apply_light_step(type, _fade_from[type].lerp(_fade_to[type], eased))
		if t < 1.0:
			continue
		_fade_active[type] = false
		if _fade_off[type]:
			_finish_light_off(type)
		elif type == EventInfo.TYPE_CENTRE_LIGHTS:
			_publish_light_color(_fade_to[type])

# The tint is the colour the light is, independent of the fade curve. A flash starts at three
# times the brightness but must keep the target tint, or the sphere (tint * intensity) peaks at
# 9x and the flash-to-off dims quadratically (G4 0.7.5).
func _set_tint(type: int, color: Color) -> void:
	sphere_material.set_shader_parameter(TINT_PARAMS[type], color)

func _apply_light_step(type: int, color: Color) -> void:
	if type < 0 or type >= 5:
		return
	sphere_material.set_shader_parameter(INTENSITY_PARAMS[type], color.v)
	for material: StandardMaterial3D in _type_materials[type]:
		material.albedo_color = color

func _cancel_fade(type: int) -> void:
	if type >= 0 and type < 5:
		_fade_active[type] = false

func _start_fade(type: int, from: Color, to: Color, off_after: bool, ease_in: bool,
		tint: Color, linear := false, duration := 1.0) -> void:
	if type < 0 or type >= 5:
		return
	_cancel_fade(type)
	_fade_from[type] = from
	_fade_to[type] = to
	_fade_tint[type] = tint
	_fade_t[type] = 0.0
	_fade_dur[type] = maxf(duration, 0.001)
	_fade_off[type] = off_after
	_fade_ease_in[type] = ease_in
	_fade_linear[type] = linear
	_fade_active[type] = true
	_type_groups[type].visible = true
	_set_tint(type, tint)
	_apply_light_step(type, from)
	if type == EventInfo.TYPE_CENTRE_LIGHTS:
		_publish_light_color(tint)

func _finish_light_off(type: int) -> void:
	_type_groups[type].visible = false
	_apply_light_step(type, Color.BLACK)
	if type == EventInfo.TYPE_CENTRE_LIGHTS:
		_publish_light_color(Color.BLACK)

func turn_light_off(type: int) -> void:
	_cancel_fade(type)
	_apply_light_step(type, Color.BLACK)
	if type == EventInfo.TYPE_CENTRE_LIGHTS:
		_publish_light_color(Color.BLACK)
	match type:
		EventInfo.TYPE_DIAGONAL_LASERS:
			diagonal_lasers_holder.visible = false
			diagonal_lasers_material.albedo_color = Color.BLACK
		EventInfo.TYPE_SQUARE_LASERS:
			square_lasers_holder.visible = false
			square_lasers_material.albedo_color = Color.BLACK
		EventInfo.TYPE_LEFT_WAVING_LASERS:
			left_waving_lasers_holder.visible = false
			left_waving_lasers_material.albedo_color = Color.BLACK
		EventInfo.TYPE_RIGHT_WAVING_LASERS:
			right_waving_lasers_holder.visible = false
			right_waving_lasers_material.albedo_color = Color.BLACK
		EventInfo.TYPE_CENTRE_LIGHTS:
			track_lights_holder.visible = false
			track_lights_material.albedo_color = Color.BLACK
			floor_material.albedo_color = Color.BLACK

func turn_light_on(type: int, color: Color) -> void:
	_cancel_fade(type)
	_set_tint(type, color)
	_apply_light_step(type, color)
	if type == EventInfo.TYPE_CENTRE_LIGHTS:
		_publish_light_color(color)
	match type:
		EventInfo.TYPE_DIAGONAL_LASERS:
			diagonal_lasers_holder.visible = true
			diagonal_lasers_material.albedo_color = color
		EventInfo.TYPE_SQUARE_LASERS:
			square_lasers_holder.visible = true
			square_lasers_material.albedo_color = color
		EventInfo.TYPE_LEFT_WAVING_LASERS:
			left_waving_lasers_holder.visible = true
			left_waving_lasers_material.albedo_color = color
		EventInfo.TYPE_RIGHT_WAVING_LASERS:
			right_waving_lasers_holder.visible = true
			right_waving_lasers_material.albedo_color = color
		EventInfo.TYPE_CENTRE_LIGHTS:
			track_lights_holder.visible = true
			track_lights_material.albedo_color = color
			floor_material.albedo_color = color

func flash_light_on(type: int, color: Color) -> void:
	# A linear ramp, as the old TRANS_LINEAR tween was.
	_start_fade(type, color * 3.0, color, false, false, color, true)

func flash_light_then_fade_off(type: int, color: Color) -> void:
	# TRANS_QUAD / EASE_IN in the old tween.
	_start_fade(type, color * 3.0, Color.BLACK, true, true, color)

func fade_light_from_current(type: int, to_color: Color) -> void:
	var current := Color.BLACK
	if type >= 0 and type < 5:
		current = _type_materials[type][0].albedo_color
	# Linear fade, as the old TRANS_LINEAR tween was.
	_start_fade(type, current, to_color, false, false, to_color, true)
