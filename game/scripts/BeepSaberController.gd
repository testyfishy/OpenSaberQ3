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
# Measured on the owner's hands (hand_capture.csv, 0.7.18): a deliberate pinch closes the tips to
# 0.2-1.1 cm, while a relaxed hand rests with them 1.7-3.6 cm apart. The first values here
# (3 cm press, 5 cm release) sat inside that resting range, so the trigger read as held for most
# of a minute of ordinary hand movement. These are the fallback for when the runtime's own pinch
# is not available.
const PINCH_PRESS_M := 0.012
const PINCH_RELEASE_M := 0.022
const PINCH_FLAGS := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
var _pinch_down := false
# A hand that appears already pinched must not fire a click. Wait for one open-hand frame first.
var _pinch_open_seen := false

# Hand-only saber correction. The Touch grip/aim pose and the hand palm pose do not share an
# origin or a basis; -90 about X points the blade (+Y in saber space) along the palm's -Z, which is
# the finger direction. X rotation is symmetric across hands; any Y/Z tweak is mirror-sensitive.
@export var hand_saber_offset_pos := Vector3.ZERO
# Zero since 0.7.20: the recording shows the palm pose's +Y already runs along the hand (wrist to
# knuckles, cosine 1.00 on both hands), and +Y is the saber's blade axis. The -90 degrees about
# X used until then assumed -Z ran along the fingers, which is what stood the saber square to the
# hand. Only the fallback path uses this now; the normal poses are built from joint positions.
@export var hand_saber_offset_rot := Vector3.ZERO

# Grip to ignite (owner decision, 0.7.13): a fist holds the saber, an open hand is the pointer.
#
# Curl is measured as fingertip-to-palm distance for the middle, ring and little fingers, divided
# by the wrist-to-middle-knuckle length so hand size cancels out. The index finger and thumb are
# left out on purpose: they are the pinch, and a pinch must not read as a grip.
# Measured on the owner's hands (hand_capture.csv, 0.7.18): about 0.3 in a fist, 1.0-1.2 open,
# and 0.7-0.8 for a relaxed, half-curled hand. The release threshold was 0.80, so a hand that
# merely relaxed after a fist never let go of the saber; both now sit between fist and relaxed.
const GRIP_ON_RATIO := 0.50
const GRIP_OFF_RATIO := 0.58
const _GRIP_FINGERTIPS: Array[int] = [
	XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP,
	XRHandTracker.HAND_JOINT_RING_FINGER_TIP,
	XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP,
]
var _gripping := false
const GRIP_CENTER_REACH_M := 0.03
# Where the saber's origin sits relative to the centre of the grip, in the grip frame (y along
# the blade). The hilt mesh is centred 3 cm below the saber origin, so +3 cm along the blade
# puts the middle of the hilt in the middle of the fist.
@export var grip_saber_offset := Vector3(0.0, 0.03, 0.0)
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

# The saber pose for a gripped hand, in world space.
#
# Where: in the channel a fist makes. A held stick lies against the palm, wrapped by the fingers
# from the knuckles (MCP) round the middle joints (PIP) to the fingertips; the centre of that
# loop is the centre of the grip. It is taken from those joints directly, so the hilt sits in
# the curled fingers whatever the hand size - not at the palm joint, which is back toward the
# wrist and is where 0.7.13/0.7.14 put it.
# Which way: along the knuckle line (little knuckle to index knuckle, which points to the thumb
# side on both hands, so nothing is mirrored), leaned forward by grip_blade_lean_deg.
# Falls back to the palm pose when those joints are not tracked.
func hand_grip_transform() -> Transform3D:
	var hand := _hand_tracker()
	if hand == null:
		return hand_world_transform()
	var index_mcp := XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL
	var little_mcp := XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_PROXIMAL
	var index_pip := XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_INTERMEDIATE
	var little_pip := XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_INTERMEDIATE
	var needed: Array[int] = [index_mcp, little_mcp, index_pip, little_pip,
		XRHandTracker.HAND_JOINT_WRIST, XRHandTracker.HAND_JOINT_PALM]
	needed.append_array(_GRIP_FINGERTIPS)
	for joint in needed:
		if not _joint_tracked(hand, joint):
			return hand_world_transform()
	var knuckles := (_joint_origin(hand, index_mcp) + _joint_origin(hand, little_mcp)) * 0.5
	var middles := (_joint_origin(hand, index_pip) + _joint_origin(hand, little_pip)) * 0.5
	var tips := Vector3.ZERO
	for joint in _GRIP_FINGERTIPS:
		tips += _joint_origin(hand, joint)
	tips /= float(_GRIP_FINGERTIPS.size())
	var center := (knuckles + middles + tips) / 3.0
	# In a song the saber stays out with the hand open too, and an open hand's fingertips would
	# drag that centroid out along the fingers. Keep it within reach of the knuckle row: 1.8 cm
	# is where it sits in a real fist (hand_capture.csv), 3 cm is the limit.
	var from_knuckles := center - knuckles
	if from_knuckles.length() > GRIP_CENTER_REACH_M:
		center = knuckles + from_knuckles.normalized() * GRIP_CENTER_REACH_M

	var along := _joint_origin(hand, index_mcp) - _joint_origin(hand, little_mcp)
	if along.length() < 0.01:
		return hand_world_transform()
	var y := along.normalized()
	# Forward: the way the hand points, wrist to palm, made square to the knuckle line.
	var forward := _joint_origin(hand, XRHandTracker.HAND_JOINT_PALM) - _joint_origin(hand, XRHandTracker.HAND_JOINT_WRIST)
	forward -= y * forward.dot(y)
	if forward.length() < 0.005:
		return hand_world_transform()
	forward = forward.normalized()
	var lean := deg_to_rad(grip_blade_lean_deg)
	var blade := (y * cos(lean) + forward * sin(lean)).normalized()
	# The roll about the blade does not matter to a round hilt; any square frame will do.
	var side := (forward - blade * forward.dot(blade)).normalized()
	var grip := Transform3D(Basis(side.cross(blade), blade, side), center)
	grip.origin += grip.basis * grip_saber_offset
	# Joint transforms are in the XR origin's space, like the palm pose (see hand_world_transform).
	var parent := get_parent() as Node3D
	var base := parent.global_transform if parent != null else Transform3D.IDENTITY
	return base * grip

# --- Open-hand pointer --------------------------------------------------------------------
#
# The saber-node pose for an open hand, in world space; the UI ray runs along its +Y.
#
# This follows the way the Quest system pointer behaves rather than pointing "where the hand
# points". A ray along the hand swings with every finger and wrist twitch, and a pinch is exactly
# such a twitch, so the far end of the line jumped off the button being clicked (owner feedback,
# 0.7.16). The system pointer avoids that with three ideas, all used here:
#   1. Direction comes from the arm, not the hand: a ray from an estimated shoulder through a
#      stable point on the hand (the index knuckle). Fingers and wrist roll barely move it.
#   2. The ray is low-pass filtered, so tracking noise does not reach the far end.
#   3. While the fingers are closing to pinch, the start point is held where it was relative to
#      the hand, so the click itself does not drag the line.
# The start is still midway between thumb tip and index tip, where the click happens.
#
# Everything is computed in tracking space (the XR origin's space), which is where both the
# joints and XRServer.get_hmd_transform() live, then lifted to world.
#
# The runtime's own aim pose (XR_FB_hand_tracking_aim) is not reachable from core Godot; it
# needs the open-source Godot OpenXR Vendors extension. This is an emulation of it.
const POINTER_SHOULDER_SIDE_M := 0.18
const POINTER_SHOULDER_DROP_M := 0.22
const POINTER_SMOOTH_SEC := 0.06
# A jump larger than this is a new hand position, not noise: snap instead of gliding.
const POINTER_SNAP_M := 0.25
var _pointer_dir := Vector3.ZERO
var _pointer_start := Vector3.ZERO
var _pointer_usec := 0
# Pinch-point offset from the index knuckle, in the hand's own frame, from the last open frame.
var _pointer_start_local := Vector3.ZERO
var _pointer_start_known := false

func hand_pointer_transform() -> Transform3D:
	# The runtime's own pointer, when the Godot OpenXR Vendors extension is installed and the
	# runtime supports XR_FB_hand_tracking_aim: exactly the ray the Quest system UI draws, with
	# Meta's stabilisation. Everything below this block is the emulation used without it.
	var runtime_aim := _aim_pose()
	if runtime_aim != null:
		var xf := runtime_aim.get_adjusted_transform()
		# OpenXR aim poses look down their -Z; the UI ray runs along the saber node's +Y.
		var runtime_pointer := Transform3D(Basis(xf.basis.x, -xf.basis.z, xf.basis.y).orthonormalized(), xf.origin)
		var origin_node := get_parent() as Node3D
		return (origin_node.global_transform if origin_node != null else Transform3D.IDENTITY) * runtime_pointer
	var fallback := hand_world_transform() * Transform3D(
		Basis.from_euler(hand_saber_offset_rot * (PI / 180.0)), hand_saber_offset_pos)
	var hand := _hand_tracker()
	if hand == null:
		return fallback
	var middle_knuckle := XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_PROXIMAL
	var index_knuckle := XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL
	var little_knuckle := XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_PROXIMAL
	for joint: int in [XRHandTracker.HAND_JOINT_WRIST, middle_knuckle, index_knuckle, little_knuckle]:
		if not _joint_tracked(hand, joint):
			return fallback
	var anchor := _joint_origin(hand, index_knuckle)

	# 1. Direction: shoulder -> index knuckle. The shoulder is estimated from the head: out to
	# this hand's side along the head's level right vector, and down.
	var head := XRServer.get_hmd_transform()
	var right := Vector3(head.basis.x.x, 0.0, head.basis.x.z)
	right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
	var side := -1.0 if String(tracker).begins_with("left") else 1.0
	var shoulder := head.origin + right * (POINTER_SHOULDER_SIDE_M * side) + Vector3.DOWN * POINTER_SHOULDER_DROP_M
	var aim := anchor - shoulder
	if aim.length() < 0.05:
		return fallback
	aim = aim.normalized()

	# 3. Start point: the pinch midpoint while the hand is open, remembered in the hand's frame
	# and replayed from that memory while the fingers close.
	var hand_y := (_joint_origin(hand, middle_knuckle) - _joint_origin(hand, XRHandTracker.HAND_JOINT_WRIST)).normalized()
	var across := _joint_origin(hand, index_knuckle) - _joint_origin(hand, little_knuckle)
	across -= hand_y * across.dot(hand_y)
	var hand_frame := Basis.IDENTITY
	if across.length() > 0.005:
		var hand_x := across.normalized()
		hand_frame = Basis(hand_x, hand_y, hand_x.cross(hand_y))
	var start := anchor
	if _joint_tracked(hand, XRHandTracker.HAND_JOINT_THUMB_TIP) and _joint_tracked(hand, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP):
		var thumb := _joint_origin(hand, XRHandTracker.HAND_JOINT_THUMB_TIP)
		var index := _joint_origin(hand, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP)
		if thumb.distance_to(index) > PINCH_RELEASE_M or not _pointer_start_known:
			_pointer_start_local = hand_frame.inverse() * ((thumb + index) * 0.5 - anchor)
			_pointer_start_known = true
	if _pointer_start_known:
		start = anchor + hand_frame * _pointer_start_local

	# 2. Low-pass both, by elapsed time so the feel does not depend on the frame rate.
	var now := Time.get_ticks_usec()
	var dt := float(now - _pointer_usec) / 1000000.0
	_pointer_usec = now
	if _pointer_dir == Vector3.ZERO or dt > 0.25 or start.distance_to(_pointer_start) > POINTER_SNAP_M:
		_pointer_dir = aim
		_pointer_start = start
	else:
		var blend := 1.0 - exp(-dt / POINTER_SMOOTH_SEC)
		_pointer_dir = _pointer_dir.lerp(aim, blend).normalized()
		_pointer_start = _pointer_start.lerp(start, blend)

	var y := _pointer_dir
	var x := Vector3.UP.cross(y)
	x = x.normalized() if x.length() > 0.01 else Vector3.RIGHT
	var pointer := Transform3D(Basis(x, y, x.cross(y)), _pointer_start)
	var parent := get_parent() as Node3D
	var base := parent.global_transform if parent != null else Transform3D.IDENTITY
	return base * pointer

func _update_hand_pinch() -> void:
	# A fist brings the thumb and index tips together; that is a grip, not a click.
	if _gripping:
		_pinch_down = false
		_pinch_open_seen = false
		return
	# The runtime's own index pinch, when it is available (see _aim_tracker): the same gesture
	# recognition the system UI uses. The open-hand arming still applies.
	var aim_tracker := _aim_tracker()
	if aim_tracker != null and _aim_pose() != null:
		var pinched := bool(aim_tracker.get_input(&"index_pinch"))
		if not pinched:
			_pinch_open_seen = true
			_pinch_down = false
		elif _pinch_open_seen:
			_pinch_down = true
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
var _aim_tracker_name := &""
static var _aim_logged := false

# The XR_FB_hand_tracking_aim tracker for this hand (Godot OpenXR Vendors extension), or null
# when the extension or the runtime feature is missing - on a desktop, or another headset.
func _aim_tracker() -> XRPositionalTracker:
	if _aim_tracker_name.is_empty():
		var side := "left" if String(tracker).begins_with("left") else "right"
		_aim_tracker_name = StringName("/user/fbhandaim/%s" % side)
	return XRServer.get_tracker(_aim_tracker_name) as XRPositionalTracker

# The runtime's aim pose for this hand, or null unless it is live right now.
func _aim_pose() -> XRPose:
	var aim_tracker := _aim_tracker()
	if aim_tracker == null:
		return null
	var pose := aim_tracker.get_pose(&"default")
	if pose == null or not pose.has_tracking_data:
		return null
	if not _aim_logged:
		_aim_logged = true
		vr.log_info("HAND aim: using the runtime pointer on %s" % _aim_tracker_name)
	return pose

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
