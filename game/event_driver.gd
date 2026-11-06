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

func _process(delta: float) -> void:
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

var prev_tweeners: Array[Tween] = [null,null,null,null,null]

func stop_prev_tween(type: int) -> void:
	if prev_tweeners[type] != null:
		prev_tweeners[type].kill()
		prev_tweeners[type] = null

func turn_light_off(type: int) -> void:
	stop_prev_tween(type)
	_on_Tween_tween_step(Color.BLACK, type)
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
	sphere_material.set_shader_parameter(TINT_PARAMS[type], color)
	stop_prev_tween(type)
	_on_Tween_tween_step(color, type)
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
	sphere_material.set_shader_parameter(TINT_PARAMS[type], color)
	if type == EventInfo.TYPE_CENTRE_LIGHTS:
		_publish_light_color(color)
	fade_light(type, color * 3.0, color, false, Tween.TRANS_LINEAR, Tween.EASE_OUT)

func flash_light_then_fade_off(type: int, color: Color) -> void:
	sphere_material.set_shader_parameter(TINT_PARAMS[type], color)
	if type == EventInfo.TYPE_CENTRE_LIGHTS:
		_publish_light_color(color)
	fade_light(type, color * 3.0, Color.BLACK, true, Tween.TRANS_QUAD, Tween.EASE_IN)

func fade_light_from_current(type: int, to_color: Color) -> void:
	var current_color: Color
	match type:
		EventInfo.TYPE_DIAGONAL_LASERS:
			current_color = diagonal_lasers_material.albedo_color
		EventInfo.TYPE_SQUARE_LASERS:
			current_color = square_lasers_material.albedo_color
		EventInfo.TYPE_LEFT_WAVING_LASERS:
			current_color = left_waving_lasers_material.albedo_color
		EventInfo.TYPE_RIGHT_WAVING_LASERS:
			current_color = right_waving_lasers_material.albedo_color
		EventInfo.TYPE_CENTRE_LIGHTS:
			current_color = floor_material.albedo_color
	fade_light(type, current_color, to_color, false, Tween.TRANS_LINEAR, Tween.EASE_IN)

func fade_light(type: int, from: Color, to: Color, turn_off_after_fade: bool, trans_type: Tween.TransitionType, ease_type: Tween.EaseType) -> void:
	stop_prev_tween(type)
	
	var group: Node3D
	# Reused buffer: this function runs once per light event.
	_fade_materials.clear()
	match type:
		EventInfo.TYPE_DIAGONAL_LASERS:
			group = diagonal_lasers_holder
			_fade_materials.append(diagonal_lasers_material)
		EventInfo.TYPE_SQUARE_LASERS:
			group = square_lasers_holder
			_fade_materials.append(square_lasers_material)
		EventInfo.TYPE_LEFT_WAVING_LASERS:
			group = left_waving_lasers_holder
			_fade_materials.append(left_waving_lasers_material)
		EventInfo.TYPE_RIGHT_WAVING_LASERS:
			group = right_waving_lasers_holder
			_fade_materials.append(right_waving_lasers_material)
		EventInfo.TYPE_CENTRE_LIGHTS:
			group = track_lights_holder
			_fade_materials.append(track_lights_material)
			_fade_materials.append(floor_material)
	
	group.visible = true
	
	var tween := group.create_tween()
	@warning_ignore("return_value_discarded")
	tween.set_parallel().set_trans(trans_type).set_ease(ease_type)
	for m in _fade_materials:
		@warning_ignore("return_value_discarded")
		tween.tween_property(m, ^"albedo_color", to, 1).from(from)
	@warning_ignore("return_value_discarded")
	tween.tween_method(_on_Tween_tween_step.bind(type), from, to, 1)
	# The end-of-fade work used to be an `await tween.finished`, which allocates a
	# coroutine and a signal connection per light event. A sequenced callback fires
	# on the same frame the await would have resumed, and a killed tween (see
	# stop_prev_tween) still skips it exactly as before.
	@warning_ignore("return_value_discarded")
	tween.set_parallel(false)
	tween.tween_callback(_finish_fade.bind(group, turn_off_after_fade, type, to))
	tween.play()
	prev_tweeners[type] = tween

func _finish_fade(group: Node3D, turn_off_after_fade: bool, type: int, to: Color) -> void:
	if turn_off_after_fade:
		group.visible = false
		_on_Tween_tween_step(Color.BLACK, type)
	# The tint follows the fade only when it is over: a map that fades the room to black must
	# not leave the last flash colour on the floor until the next event (FR-005).
	if type == EventInfo.TYPE_CENTRE_LIGHTS:
		_publish_light_color(Color.BLACK if turn_off_after_fade else to)

func _on_Tween_tween_step(value: Color, id: int) -> void:
	sphere_material.set_shader_parameter(INTENSITY_PARAMS[id], value.v)
