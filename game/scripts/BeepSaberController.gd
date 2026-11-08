# This script contains the button logic for the controller
extends XRController3D
class_name BeepSaberController


var ax := false
var ax_last_frame := false
var by := false
var by_last_frame := false
var trigger := false
var trigger_last_frame := false
static var _hand_logged := false

# Hand interaction profile. Pinch is a float 0..1 on the `pinch` action (bound to
# pinch_ext/value in openxr_action_map.tres). `ready_ext` only means a pinch is possible, so it
# cannot be used as a click edge. Hysteresis keeps a value hovering at the press point from
# firing twice; the UI button layer already latches one press per pinch.
const PINCH_PRESS := 0.8
const PINCH_RELEASE := 0.5
var _pinch_down := false

# Hand-only saber correction. The Touch grip/aim pose and the hand aim pose do not share an
# origin, so the blade can sit shifted or tilted on the headset. Defaults are identity; the game
# applies these to the saber while hand tracking is live.
@export var hand_saber_offset_pos := Vector3.ZERO
@export var hand_saber_offset_rot := Vector3.ZERO

var movement_aabb := AABB()

func ax_pressed() -> bool:
	return ax

func ax_just_pressed() -> bool:
	return ax and not ax_last_frame

func ax_just_released() -> bool:
	return ax_last_frame and not ax

func by_pressed() -> bool:
	return by

func by_just_pressed() -> bool:
	return by and not by_last_frame

func by_just_released() -> bool:
	return by_last_frame and not by

func trigger_pressed() -> bool:
	return trigger

func trigger_just_pressed() -> bool:
	return trigger and not trigger_last_frame

func trigger_just_released() -> bool:
	return trigger_last_frame and not trigger

func _update_buttons_and_sticks() -> void:
	ax_last_frame = ax
	by_last_frame = by
	trigger_last_frame = trigger
	ax = is_button_pressed(&"ax_button")
	by = is_button_pressed(&"by_button")
	trigger = is_button_pressed(&"trigger")
	# With the hand interaction profile the pose and inputs arrive on the same left_hand/
	# right_hand tracker. Pinch drives the internal trigger, which is what the UI raycast
	# already polls, so a pinch clicks buttons exactly once per press.
	if is_hand_tracking():
		var pinch := get_float(&"pinch")
		if _pinch_down:
			if pinch < PINCH_RELEASE:
				_pinch_down = false
		elif pinch >= PINCH_PRESS:
			_pinch_down = true
		trigger = trigger or _pinch_down
		if not _hand_logged:
			_hand_logged = true
			vr.log_info("HAND tracking active on %s (pinch = trigger/UI click)" % tracker)
	else:
		# Tracking lost mid-pinch: clear it so the next live frame cannot fire a stale press.
		_pinch_down = false

func _update_movement_aabb() -> void:
	movement_aabb = movement_aabb.expand(global_transform.origin)

func reset_movement_aabb() -> void:
	movement_aabb = AABB(global_transform.origin, Vector3.ZERO)

var _is_simple_rumbling := false
var _rumble_duration_remaining := 0.0

func simple_rumble(intensity: float, duration: float) -> void:
	# FR-008: hands have no motors; never send a haptic pulse while hand tracking is live.
	if is_hand_tracking():
		return
	_rumble_duration_remaining = duration;
	_is_simple_rumbling = true
	trigger_haptic_pulse("haptic", 20, intensity, duration, 0)
	
func is_simple_rumbling() -> bool:
	return _is_simple_rumbling
	
func _update_rumble(dt: float) -> void:
	if _rumble_duration_remaining > 0.0:
		_rumble_duration_remaining -= dt
	if _rumble_duration_remaining <= 0.0:
		_rumble_duration_remaining = 0.0
		_is_simple_rumbling = false

var first_time := true

func _physics_process(dt: float) -> void:
	if not Scoreboard.paused:
		_update_movement_aabb()
	
	if get_is_active(): # wait for active controller
		_update_rumble(dt)
		_update_buttons_and_sticks()
		# this avoid getting just_pressed events when a key is pressed and the controller becomes
		# active (like it happens on vr.scene_change!)
		if first_time:
			_update_buttons_and_sticks()
			first_time = false


func is_hand_tracking() -> bool:
	# Hand joints live on their own OpenXR tracker at /user/hand_tracker/<side>; the
	# left_hand/right_hand tracker this node uses carries the hand's pose and pinch input.
	var side := "left" if String(tracker).begins_with("left") else "right"
	var hand := XRServer.get_tracker("/user/hand_tracker/%s" % side)
	if not (hand is XRHandTracker):
		return false
	# The tracker object exists from startup; only treat it as hand input when joints are live,
	# otherwise a sleeping hand would keep the pinch mapping on while controllers play.
	return (hand as XRHandTracker).has_tracking_data
