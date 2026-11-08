# The lightsaber logic is mostly contained in the BeepSaber_Game.gd
# here I only track the extended/sheethed state and provide helper functions to
# trigger the necessary animations
extends Area3D
class_name LightSaber

# the type of note this saber can cut (0 -> left, 1 -> right)
@export var type := 0 # (int, 0, 1)
@export var song_player_ref: AudioStreamPlayer

# store the saber material in a variable so the main game can set the color on initialize
@onready var _anim := $AnimationPlayer as AnimationPlayer
@onready var _ray_cast := $RayCast3D as RayCast3D
@onready var _swing_cast := $SwingableRayCast as SwingableRayCast
@onready var saber_visual := $saber_holder.get_child(0) as DefaultSaber
@onready var controller := get_parent() as BeepSaberController

@export var offset_pos := Vector3.ZERO
@export var offset_rot := Vector3.ZERO
var extra_offset_pos := Vector3.ZERO
var extra_offset_rot := Vector3.ZERO
# True while the saber is driven from the hand tracker's palm pose instead of the controller.
# The saber is top-level in that mode so a sleeping controller's stale transform cannot drag it.
var hand_drive_active := false

var saber_end := Vector3.ZERO
var saber_end_past := Vector3.ZERO
# Last physics-tick blade segment, exposed for the saber-vs-saber clash check.
var last_blade_base := Vector3.ZERO
var last_blade_tip := Vector3.ZERO
var last_dt := 0.0

# Analytic hit path (specs/006-swing-hit-sweep). `_hit_mask` is the swing cast's
# collision mask, i.e. exactly the layers the ray fan could hit; `_hit_prev_*` is
# the blade segment at the previous physics tick, so the resolver sweeps between
# samples instead of testing one pose. `_hit_enabled` follows the play state
# (set_swingcast_enabled), same gate the ray fan has.
const HitResolver := preload("res://game/scripts/HitResolver.gd")

var _hit_mask := 0
var _hit_enabled := false
var _hit_sampled := false
var _hit_prev_base := Vector3.ZERO
var _hit_prev_tip := Vector3.ZERO

const Cost := preload("res://game/scripts/CostProbe.gd")

func _show() -> void:
	if not is_extended():
		_anim.play(&"Show")
		saber_visual._show()

func is_extended() -> bool:
	return saber_visual.is_extended

func _hide() -> void:
	# This check makes sure that we are not already in the hidden state
	# (where we translated the light saber to the hilt) to avoid playing it back
	# again from the fully extended light saber position
	if (is_extended() and _anim.current_animation != "QuickHide"):
		_anim.play(&"Hide")
		saber_visual._hide()

# The colour currently on the blade. Kept here because the floor streak and the glow strip
# read the LIGHT colour as a global (`light_left`/`light_right`), and the light has to be
# derived from whatever colour the blade is actually showing - the map's scheme after a load,
# or the player's choice from the panel. Nothing else stored it.
var light_color := Color.WHITE

func set_color(color: Color) -> void:
	light_color = color
	saber_visual.set_color(color)

func on_settings_changed(key: StringName) -> void:
	match key:
		&"color_left":
			if type == 0:
				saber_visual.set_color(Settings.color_left)
		&"color_right":
			if type == 1:
				saber_visual.set_color(Settings.color_right)
		&"thickness":
			saber_visual.set_thickness(Settings.thickness)
		&"saber_tail":
			saber_visual.set_trail(Settings.saber_tail)
		&"saber_visual":
			set_saber(Settings.SABER_VISUALS[Settings.saber_visual][1])
		&"saber_halo":
			# FR-046. Lives on the visual so a saber swap picks the setting up again.
			saber_visual.set_halo_enabled(Settings.saber_halo)
		&"mirror_reflections":
			# FR-047: the mirrored blade is a next_pass on the blade material.
			saber_visual.set_mirror_enabled(Settings.mirror_reflections)
		&"left_saber_offset_pos":
			if type == 0:
				extra_offset_pos = Settings.left_saber_offset_pos
		&"right_saber_offset_pos":
			if type == 1:
				extra_offset_pos = Settings.right_saber_offset_pos
		&"left_saber_offset_rot":
			if type == 0:
				@warning_ignore("unsafe_cast")
				extra_offset_rot = Settings.left_saber_offset_rot
		&"right_saber_offset_rot":
			if type == 1:
				extra_offset_rot = Settings.right_saber_offset_rot	

func _ready() -> void:
	set_saber(Settings.SABER_VISUALS[Settings.saber_visual][1])
	_anim.play(&"QuickHide")
	saber_visual.quickhide()
	saber_visual.set_thickness(Settings.thickness)
	saber_visual.set_trail(Settings.saber_tail)
	saber_visual.set_halo_enabled(Settings.saber_halo)
	saber_visual.set_mirror_enabled(Settings.mirror_reflections)
	saber_visual.set_side(type)
	
	@warning_ignore("return_value_discarded")
	Settings.changed.connect(on_settings_changed)
	
	if type == 0:
		_swing_cast._set_collision_mask_value(CollisionLayerConstants.LeftNote_bit, true)
	else:
		_swing_cast._set_collision_mask_value(CollisionLayerConstants.RightNote_bit, true)
	_swing_cast._set_collision_mask_value(CollisionLayerConstants.Bombs_bit, true)
	# Captured after the mask is set: the resolver filters the registry with the
	# same bits the rays use, so eligibility cannot drift from the ray path.
	_hit_mask = _swing_cast.collision_mask

func _process(_dt: float) -> void:
	if controller == null:
		return
	if controller.is_hand_tracking():
		if not hand_drive_active:
			hand_drive_active = true
			top_level = true
		# Palm pose * hand correction. The saber +Y runs along the palm -Z (finger direction),
		# which is what the -90 X default in BeepSaberController does.
		var correction_rot := controller.hand_saber_offset_rot * (PI / 180.0)
		var correction := Transform3D(Basis.from_euler(correction_rot), controller.hand_saber_offset_pos)
		global_transform = controller.hand_world_transform() * correction
		return
	if hand_drive_active and controller.get_is_active():
		# The controllers are back: return to the normal parented controller path.
		hand_drive_active = false
		top_level = false

func _physics_process(delta: float) -> void:
	if not hand_drive_active:
		position = offset_pos + extra_offset_pos
		rotation_degrees = offset_rot + extra_offset_rot
	saber_end_past = saber_end
	saber_end = saber_visual.tip.global_transform.origin
	last_dt = delta
	# The blade segment the fan casts from: the swing cast's origin and its
	# animated target_position (the Show/Hide animation drives it, so a retracted
	# saber sweeps nothing, exactly as the rays sweep nothing).
	var blade_xf := _swing_cast.global_transform
	var blade_base := blade_xf.origin
	var blade_tip := blade_xf * _swing_cast.target_position
	last_blade_base = blade_base
	last_blade_tip = blade_tip
	if _hit_sampled and _hit_enabled and is_extended() and HitResolver.is_analytic():
		_resolve_analytic_hits(blade_base, blade_tip)
	_hit_prev_base = blade_base
	_hit_prev_tip = blade_tip
	_hit_sampled = true
	if is_extended():
		#check floor collision for burn mark
		var probe := Cost.enabled
		var t0 := Time.get_ticks_usec() if probe else 0
		_ray_cast.force_raycast_update()
		var raycoli := _ray_cast.get_collider()
		if raycoli is Floor:
			var floor_body := raycoli as Floor
			var colipoint := _ray_cast.get_collision_point()
			floor_body.burn_mark(colipoint,type)
		if probe:
			Cost.floor_ray_usec += Time.get_ticks_usec() - t0
	# FR-045: the floor shader needs both ends of the blade, not just the tip. The base is
	# the swing cast's origin, which every saber visual has (the particle saber has no
	# `base` marker), so the streak tracks any saber the player selects.
	# A retracted saber must not leave a glowing streak parked on the floor, so park both
	# ends far below the world instead of publishing the last known pose.
	var tip_key := &"left_saber" if type == 0 else &"right_saber"
	var base_key := &"left_saber_base" if type == 0 else &"right_saber_base"
	if is_extended():
		RenderingServer.global_shader_parameter_set(tip_key, saber_end)
		RenderingServer.global_shader_parameter_set(base_key, blade_base)
	else:
		var away := Vector3(0.0, -1000.0, 0.0)
		RenderingServer.global_shader_parameter_set(tip_key, away)
		RenderingServer.global_shader_parameter_set(base_key, away)

func set_saber(saber_path: String) -> void:
	var newsaber := (load(saber_path) as PackedScene).instantiate()
	if newsaber is DefaultSaber:
		for i in $saber_holder.get_children():
			i.queue_free()
		saber_visual = newsaber
		$saber_holder.add_child(saber_visual)
		saber_visual.set_color(Settings.color_right if type else Settings.color_left)
		saber_visual.set_thickness(Settings.thickness)
		saber_visual.set_trail(Settings.saber_tail)
		saber_visual.set_halo_enabled(Settings.saber_halo)
		saber_visual.set_mirror_enabled(Settings.mirror_reflections)
		saber_visual.set_side(type)

func set_swingcast_enabled(value: bool) -> void:
	_hit_enabled = value
	# Re-seed the sweep on the next tick, so resuming after a pause does not
	# sweep from wherever the blade was before it.
	_hit_sampled = false
	# In analytic mode the fan is never switched on at all: its nine physics
	# queries per tick are the cost this change removes (FR-006).
	_swing_cast.set_raycasts_enabled(value and not HitResolver.is_analytic())

# Analytic counterpart of the ray fan (specs/006-swing-hit-sweep FR-003/FR-004).
# It only decides *whether* something was hit; the cut itself goes through
# _handle_cuttable, which is the same funnel the rays use.
func _resolve_analytic_hits(blade_base: Vector3, blade_tip: Vector3) -> void:
	var probe := Cost.enabled
	var t0 := Time.get_ticks_usec() if probe else 0
	# A blade that jumped (map load, controller reconnect, tracking loss) is not a
	# swing: cut nothing and let this pose become the new previous sample.
	if (_hit_prev_tip.distance_to(blade_tip) > HitResolver.MAX_JUMP_M
			or _hit_prev_base.distance_to(blade_base) > HitResolver.MAX_JUMP_M):
		if probe:
			Cost.swing_usec += Time.get_ticks_usec() - t0
		return
	var cuts := 0
	while cuts < HitResolver.MAX_HITS_PER_TICK:
		var cuttable := HitResolver.find_hit(
			_hit_mask, _hit_prev_base, _hit_prev_tip, blade_base, blade_tip)
		if cuttable == null: break
		_handle_cuttable(cuttable)
		cuts += 1
		# Every cuttable unregisters itself inside cut()/hide_cube(). If one does
		# not, stop instead of cutting the same note twice in one tick.
		var cut := cuttable as Cuttable
		if cut == null or not cut.is_hit_registered(): break
	if probe:
		Cost.swing_usec += Time.get_ticks_usec() - t0

func _handle_area_collided(area: Area3D) -> void:
	_handle_cuttable(area.get_parent() as Node3D)

func _handle_cuttable(cut_object: Node3D) -> void:
	if Scoreboard.paused: return
	if not cut_object is Cuttable: return
	var note := cut_object as Cuttable
	
	var time_offset: float = Map.beat_to_seconds(note.beat) - song_player_ref.get_playback_position()
	var o := controller.global_transform.origin
	var controller_speed: Vector3 = (saber_end - saber_end_past) / last_dt
	const BEAT_DISTANCE := 4.0
	var cutplane := Plane(o, saber_end, saber_end_past + Vector3(0, 0, BEAT_DISTANCE * Map.bpm_at_beat(note.beat) * last_dt / 30)) # Account for relative position to track speed
	# The cut scores the hit and hands back the components it computed, so the
	# hit sound is driven by the real numbers instead of a second copy of the
	# maths. `note` is not touched after this call (it may go back to the pool).
	var info := note.cut(type, controller_speed, cutplane, controller)
	saber_visual.hit(time_offset, info)
	controller.simple_rumble(0.75, 0.1)

func _on_AnimationPlayer_animation_started(_anim_name: StringName) -> void:
	_swing_cast.adjust_segments = true

func _on_AnimationPlayer_animation_finished(_anim_name: StringName) -> void:
	_swing_cast.adjust_segments = false

