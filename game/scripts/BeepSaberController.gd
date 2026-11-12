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

# Hand input. Quest's native runtime does not implement XR_EXT_hand_interaction, so the pinch
# float from the action map never arrives. The XR_EXT_hand_tracking joints are live, so pinch is
# computed from the thumb-tip/index-tip distance instead. The rendered hand and the saber both use
# the hand tracker's palm pose, which keeps the blade in the visible hand.
const PINCH_PRESS_M := 0.030
const PINCH_RELEASE_M := 0.050
const PINCH_FLAGS := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
var _pinch_down := false
# A hand that appears already pinched must not fire a click. Wait for one open-hand frame first.
var _pinch_open_seen := false

# Hand-only saber correction. The Touch grip/aim pose and the hand palm pose do not share an
# origin or a basis; -90 about X points the blade (+Y in saber space) along the palm's -Z, which is
# the finger direction. X rotation is symmetric across hands; any Y/Z tweak is mirror-sensitive.
@export var hand_saber_offset_pos := Vector3.ZERO
@export var hand_saber_offset_rot := Vector3(-90, 0, 0)

# Grip to ignite (owner decision, 0.7.13): a fist holds the saber, an open hand is the pointer.
#
# Curl is measured as fingertip-to-palm distance for the middle, ring and little fingers, divided
# by the wrist-to-middle-knuckle length so hand size cancels out. The index finger and thumb are
# left out on purpose: they are the pinch, and a pinch must not read as a grip. Roughly 0.45 in a
# fist and 1.0 with the hand open; the gap between the two thresholds is the hysteresis.
const GRIP_ON_RATIO := 0.62
const GRIP_OFF_RATIO := 0.80
const _GRIP_FINGERTIPS: Array[int] = [
	XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP,
	XRHandTracker.HAND_JOINT_RING_FINGER_TIP,
	XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP,
]
var _gripping := false
# Where the hilt sits relative to the fist, in the grip frame (y along the blade, z out of the
# back of the hand): a little back along the blade so it emerges from the fist, and into the
# palm so it runs through the curled fingers.
@export var grip_saber_offset := Vector3(0.0, -0.03, -0.025)
# How far the blade leans forward (away from the wrist) from the knuckle line, in degrees.
# A stick held in a relaxed fist does not stand square to the forearm: with the wrist neutral it
# leans forward, and a sword is held with the point further forward still. The knuckle line
# itself already leans about 15 degrees (the index knuckle sits further from the wrist than the
# little one); this adds the rest, to roughly the 40 degrees a controller-held saber has.
@export var grip_blade_lean_deg := 25.0

# True from the first live hand frame until a controller is tracked again. Deliberately sticky
# across a tracking dropout: while the hand is occluded the controller is still asleep, and its
# node still holds the transform it had when it went to sleep, so falling back to it would
# teleport everything that follows this controller.
var hand_driven := false
# World-space palm origin of the last live hand frame; what `swing_origin()` reports during a
# dropout.
var _last_hand_origin := Vector3.ZERO

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
	# A sleeping controller is not a button source: only read it while it is tracked, so a value
	# left on the tracker cannot hold a button down under the pinch.
	var controller_live := get_is_active()
	ax = controller_live and is_button_pressed(&"ax_button")
	by = controller_live and is_button_pressed(&"by_button")
	trigger = controller_live and is_button_pressed(&"trigger")
	# With hand tracking the pose and joints arrive on /user/hand_tracker/<side>. Pinch drives
	# the internal trigger, which is what the UI raycast already polls.
	if is_hand_tracking():
		_update_hand_pinch()
		trigger = trigger or _pinch_down
		if not _hand_logged:
			_hand_logged = true
			vr.log_info("HAND tracking active on %s (joint pinch = trigger/UI click)" % tracker)
	else:
		# Tracking lost mid-pinch: clear it so the next live frame cannot fire a stale press.
		_pinch_down = false
		_pinch_open_seen = false

# True while the hands drive the sabers and this hand is closed into a fist. Sticky through a
# tracking dropout: a fist hides its own fingers from the cameras, and a blade that flickered
# off every time that happened would be worse than one that holds its last state.
func is_gripping() -> bool:
	return hand_driven and _gripping

func _joint_tracked(hand: XRHandTracker, joint: int) -> bool:
	return (hand.get_hand_joint_flags(joint as XRHandTracker.HandJoint) & PINCH_FLAGS) == PINCH_FLAGS

func _joint_origin(hand: XRHandTracker, joint: int) -> Vector3:
	return hand.get_hand_joint_transform(joint as XRHandTracker.HandJoint).origin

func _update_grip() -> void:
	var hand := _hand_tracker()
	if hand == null:
		return
	var needed: Array[int] = [XRHandTracker.HAND_JOINT_PALM, XRHandTracker.HAND_JOINT_WRIST,
		XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_PROXIMAL]
	needed.append_array(_GRIP_FINGERTIPS)
	for joint in needed:
		if not _joint_tracked(hand, joint):
			return
	var palm := _joint_origin(hand, XRHandTracker.HAND_JOINT_PALM)
	var hand_size := _joint_origin(hand, XRHandTracker.HAND_JOINT_WRIST).distance_to(
		_joint_origin(hand, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_PROXIMAL))
	if hand_size < 0.03:
		return
	var most_open := 0.0
	var total := 0.0
	for joint in _GRIP_FINGERTIPS:
		var ratio := _joint_origin(hand, joint).distance_to(palm) / hand_size
		most_open = maxf(most_open, ratio)
		total += ratio
	if most_open < GRIP_ON_RATIO:
		_gripping = true
	elif total / float(_GRIP_FINGERTIPS.size()) > GRIP_OFF_RATIO:
		_gripping = false

# The saber pose for a gripped hand, in world space: the blade runs along the knuckle line and
# leaves the fist on the thumb side, the way a held hilt does. The knuckle line (little-finger
# knuckle to index knuckle) points to the thumb side on both hands, so nothing here is mirrored.
# Falls back to the palm pose when the knuckles are not tracked.
func hand_grip_transform() -> Transform3D:
	var hand := _hand_tracker()
	if hand == null:
		return hand_world_transform()
	var index_knuckle := XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL
	var little_knuckle := XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_PROXIMAL
	if not _joint_tracked(hand, index_knuckle) or not _joint_tracked(hand, little_knuckle):
		return hand_world_transform()
	var palm := hand.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM)
	var along := _joint_origin(hand, index_knuckle) - _joint_origin(hand, little_knuckle)
	if along.length() < 0.01:
		return hand_world_transform()
	var y := along.normalized()
	# Lean the blade forward: rotate it toward the wrist-to-knuckle direction, in the plane the
	# two span. Skipped when the wrist is not tracked.
	if _joint_tracked(hand, XRHandTracker.HAND_JOINT_WRIST):
		var forward := _joint_origin(hand, XRHandTracker.HAND_JOINT_PALM) - _joint_origin(hand, XRHandTracker.HAND_JOINT_WRIST)
		forward -= y * forward.dot(y)
		if forward.length() > 0.005:
			var lean := deg_to_rad(grip_blade_lean_deg)
			y = (y * cos(lean) + forward.normalized() * sin(lean)).normalized()
	# Back of the hand, made perpendicular to the blade.
	var back := palm.basis.y - y * palm.basis.y.dot(y)
	if back.length() < 0.01:
		return hand_world_transform()
	var z := back.normalized()
	var x := y.cross(z)
	var grip := Transform3D(Basis(x, y, z), palm.origin)
	grip.origin += grip.basis * grip_saber_offset
	# Joint transforms are in the XR origin's space, like the palm pose (see hand_world_transform).
	var parent := get_parent() as Node3D
	var base := parent.global_transform if parent != null else Transform3D.IDENTITY
	return base * grip

# The saber-node pose for an open hand, in world space: at the palm, with the saber's +Y (the
# axis the UI ray runs along) pointing the way the hand points, wrist to middle knuckle.
#
# Built from joint positions, not from the palm pose's orientation. 0.7.8-0.7.14 rotated the palm
# pose by -90 degrees about X on the assumption that its -Z runs along the fingers; on the headset
# the pointer came out square to the hand. Joint positions leave nothing to assume, and a pinch
# moves the thumb and index tips, not the wrist or the knuckles, so the ray holds still while
# clicking. Falls back to the old palm-pose construction when the joints are not tracked.
func hand_pointer_transform() -> Transform3D:
	var fallback := hand_world_transform() * Transform3D(
		Basis.from_euler(hand_saber_offset_rot * (PI / 180.0)), hand_saber_offset_pos)
	var hand := _hand_tracker()
	if hand == null:
		return fallback
	var middle_knuckle := XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_PROXIMAL
	var index_knuckle := XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL
	var little_knuckle := XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_PROXIMAL
	for joint: int in [XRHandTracker.HAND_JOINT_WRIST, XRHandTracker.HAND_JOINT_PALM,
			middle_knuckle, index_knuckle, little_knuckle]:
		if not _joint_tracked(hand, joint):
			return fallback
	var y := _joint_origin(hand, middle_knuckle) - _joint_origin(hand, XRHandTracker.HAND_JOINT_WRIST)
	var across := _joint_origin(hand, index_knuckle) - _joint_origin(hand, little_knuckle)
	if y.length() < 0.01:
		return fallback
	y = y.normalized()
	across -= y * across.dot(y)
	if across.length() < 0.005:
		return fallback
	var x := across.normalized()
	var pointer := Transform3D(Basis(x, y, x.cross(y)), _joint_origin(hand, XRHandTracker.HAND_JOINT_PALM))
	var parent := get_parent() as Node3D
	var base := parent.global_transform if parent != null else Transform3D.IDENTITY
	return base * pointer

func _update_hand_pinch() -> void:
	# A fist brings the thumb and index tips together; that is a grip, not a click.
	if _gripping:
		_pinch_down = false
		_pinch_open_seen = false
		return
	var hand := _hand_tracker()
	if hand == null:
		_pinch_down = false
		_pinch_open_seen = false
		return
	var thumb_flags := hand.get_hand_joint_flags(XRHandTracker.HAND_JOINT_THUMB_TIP)
	var index_flags := hand.get_hand_joint_flags(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP)
	if (thumb_flags & PINCH_FLAGS) != PINCH_FLAGS or (index_flags & PINCH_FLAGS) != PINCH_FLAGS:
		_pinch_down = false
		_pinch_open_seen = false
		return
	var thumb := hand.get_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_TIP).origin
	var index := hand.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP).origin
	var distance := thumb.distance_to(index)
	if distance > PINCH_RELEASE_M:
		_pinch_open_seen = true
		_pinch_down = false
	elif _pinch_open_seen and distance < PINCH_PRESS_M:
		_pinch_down = true

# Where the swing is measured from, in world space: the controller while it is tracked, the palm
# while the hands drive the sabers. The controller node cannot be used for both - asleep, it
# keeps its last transform, so every hand swing would measure zero travel and hinge its cut
# plane on wherever the controller was put down.
func swing_origin() -> Vector3:
	return _last_hand_origin if hand_driven else global_transform.origin

func _update_movement_aabb() -> void:
	movement_aabb = movement_aabb.expand(swing_origin())

func reset_movement_aabb() -> void:
	movement_aabb = AABB(swing_origin(), Vector3.ZERO)

# Keeps `hand_driven` and the palm origin current. Called from both _process and
# _physics_process, ahead of the saber (a child, so it runs after this node in either callback).
func _refresh_hand_mode() -> void:
	if is_hand_tracking():
		_last_hand_origin = hand_world_transform().origin
		_update_grip()
		if not hand_driven:
			hand_driven = true
			# The travel box must not span the sleeping controller and the hand.
			reset_movement_aabb()
	elif hand_driven and get_is_active():
		hand_driven = false
		_gripping = false
		reset_movement_aabb()

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

func _process(_dt: float) -> void:
	_refresh_hand_mode()

func _physics_process(dt: float) -> void:
	_refresh_hand_mode()
	if not Scoreboard.paused:
		_update_movement_aabb()
	
	# Wait for a live input source. With the controllers asleep get_is_active() is false, and
	# the pinch is computed in _update_buttons_and_sticks, so live hand data has to open this
	# gate too or a pinch can never click.
	# `hand_driven`, not is_hand_tracking(): it stays true through a dropout, and that tick has
	# to run too, or a pinch held when the hand was lost would stay pressed with no release.
	if get_is_active() or hand_driven:
		_update_rumble(dt)
		_update_buttons_and_sticks()
		# this avoid getting just_pressed events when a key is pressed and the controller becomes
		# active (like it happens on vr.scene_change!)
		if first_time:
			_update_buttons_and_sticks()
			first_time = false


# Built on first use: this is asked for several times a frame per hand.
var _hand_tracker_name := &""

func _hand_tracker() -> XRHandTracker:
	# Hand joints live on their own OpenXR tracker at /user/hand_tracker/<side>; the
	# left_hand/right_hand tracker this node uses carries the controller pose and inputs.
	if _hand_tracker_name.is_empty():
		var side := "left" if String(tracker).begins_with("left") else "right"
		_hand_tracker_name = StringName("/user/hand_tracker/%s" % side)
	return XRServer.get_tracker(_hand_tracker_name) as XRHandTracker

func is_hand_tracking() -> bool:
	if not Settings.hand_tracking_enabled:
		return false
	var hand := _hand_tracker()
	if hand == null or not hand.has_tracking_data:
		return false
	# Only optical/unobstructed hand data may take over the sabers. Controller-inferred data is
	# rejected so holding a controller can never enter the hand path (FR-005); UNKNOWN is allowed
	# because this project does not request the controller data source at all.
	var source := hand.hand_tracking_source
	return source == XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED \
		or source == XRHandTracker.HAND_TRACKING_SOURCE_UNKNOWN

# The palm pose, in world space, used by both the rendered hand and the saber. The XR node and
# this call see the same tracker pose, so the blade sits in the visible hand.
func hand_world_transform() -> Transform3D:
	var hand := _hand_tracker()
	if hand == null:
		return Transform3D.IDENTITY
	var palm := hand.get_pose(&"default")
	if palm == null:
		return Transform3D.IDENTITY
	# get_adjusted_transform() is in the XR origin's space (the hand XRNode3D is a child of the
	# origin and uses it directly). The saber is top-level while hand-driven, so lift it to world.
	var parent := get_parent() as Node3D
	var base := parent.global_transform if parent != null else Transform3D.IDENTITY
	return base * palm.get_adjusted_transform()
