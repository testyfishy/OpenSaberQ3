extends Node

# Hand-path harness (specs/030). Runs headless with no XR runtime.
#
# It registers a synthetic XRHandTracker at /user/hand_tracker/left - the same tracker name the
# OpenXR module uses - while the `left_hand` controller tracker does not exist, which is the state
# the Quest is in once the controllers are asleep: XRController3D.get_is_active() is false and the
# controller node keeps its last transform.
#
# Run: godot --headless --path . res://tools/harness/verify_hand_path.tscn
# Prints one HANDPATH line per check and `HANDPATH PASS` / `HANDPATH FAIL`.

const SABER_SCENE := preload("res://game/LightSaber.tscn")
const ControllerScript := preload("res://game/scripts/BeepSaberController.gd")
const HitResolver := preload("res://game/scripts/HitResolver.gd")
const RenderedHandScript := preload("res://game/hands/RenderedHand.gd")

const TRACKER_NAME := &"/user/hand_tracker/left"
# Deliberately not at the world origin and rotated, so a pose left in XR-origin space is caught.
const ORIGIN_XF := Transform3D(Basis(Vector3.UP, 0.5), Vector3(1.0, 0.0, 2.0))
# Where the controller was when it fell asleep (origin-local).
const STALE_CONTROLLER_POS := Vector3(-0.25, 1.5, -0.5)

var _hand: XRHandTracker
var _origin: XROrigin3D
var _controller: BeepSaberController
var _saber: LightSaber
var _palm := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.2, -0.3))
var _pinch_gap := 0.10
var _fails := 0
var _hands_setting_before := true


func _ready() -> void:
	_hands_setting_before = Settings.hand_tracking_enabled
	Settings.hand_tracking_enabled = true

	_hand = XRHandTracker.new()
	_hand.name = TRACKER_NAME
	_hand.hand = XRPositionalTracker.TRACKER_HAND_LEFT
	_hand.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
	# A script-made tracker does not zero its joint flags (the engine array is uninitialised;
	# OpenXR writes every joint each frame, so this only matters here). Start them all invalid.
	for joint in XRHandTracker.HAND_JOINT_MAX:
		_hand.set_hand_joint_flags(joint, 0)
	XRServer.add_tracker(_hand)

	_origin = XROrigin3D.new()
	_origin.transform = ORIGIN_XF
	add_child(_origin)
	_origin.add_child(XRCamera3D.new())
	_controller = ControllerScript.new() as BeepSaberController
	_controller.tracker = &"left_hand"
	_controller.position = STALE_CONTROLLER_POS
	_origin.add_child(_controller)
	_saber = SABER_SCENE.instantiate() as LightSaber
	_controller.add_child(_saber)

	_run.call_deferred()


# Runs first in every physics tick (this node is the rig's ancestor), which is where the XR server
# delivers poses on the headset: before any node's _physics_process or _process.
func _physics_process(_dt: float) -> void:
	if _lag_check:
		# The saber's segment from the tick that just finished, against the pose that tick was given.
		_lag_worst = maxf(_lag_worst, _saber.last_blade_base.distance_to(_expected_saber_origin()))
		_palm.origin += Vector3(0.05, 0.0, 0.0)
	_publish()


func _publish() -> void:
	if _hand == null or not _hand.has_tracking_data:
		return
	var flags := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED \
		| XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_TRACKED
	_hand.set_pose(&"default", _palm, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	_hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM, _palm)
	_hand.set_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM, flags)
	var thumb := _palm.origin + Vector3(0.0, 0.0, -0.08)
	_hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_TIP, Transform3D(Basis.IDENTITY, thumb))
	_hand.set_hand_joint_flags(XRHandTracker.HAND_JOINT_THUMB_TIP, flags)
	_hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP,
		Transform3D(Basis.IDENTITY, thumb + Vector3(_pinch_gap, 0.0, 0.0)))
	_hand.set_hand_joint_flags(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, flags)
	if _grip != GRIP_UNPUBLISHED:
		# Enough of the hand for the grip test and the hilt pose. Hand size (wrist to middle
		# knuckle) is 0.10 m; fingertips sit 0.10 m from the palm when open, 0.04 m in a fist.
		var o := _palm.origin
		var reach := Vector3(0.0, 0.0, -0.10) if _grip == GRIP_OPEN else Vector3(0.0, -0.03, -0.025)
		# Middle joints: straight out when open, folded 4 cm toward the palm side in a fist.
		var fold := Vector3(0.0, 0.0, -0.04) if _grip == GRIP_OPEN else Vector3(0.0, -0.04, 0.0)
		var placed := {
			XRHandTracker.HAND_JOINT_WRIST: o + Vector3(0.0, 0.0, 0.07),
			XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_PROXIMAL: o + Vector3(0.0, 0.0, -0.03),
			XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL: o + KNUCKLE_INDEX,
			XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_PROXIMAL: o + KNUCKLE_LITTLE,
			XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_INTERMEDIATE: o + KNUCKLE_INDEX + fold,
			XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_INTERMEDIATE: o + KNUCKLE_LITTLE + fold,
			XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP: o + reach,
			XRHandTracker.HAND_JOINT_RING_FINGER_TIP: o + reach + Vector3(0.015, 0.0, 0.0),
			XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP: o + reach + Vector3(0.03, 0.0, 0.0),
		}
		for joint: int in placed:
			_hand.set_hand_joint_transform(joint as XRHandTracker.HandJoint, Transform3D(Basis.IDENTITY, placed[joint]))
			_hand.set_hand_joint_flags(joint as XRHandTracker.HandJoint, flags)
	if _publish_all_joints:
		for joint in XRHandTracker.HAND_JOINT_MAX:
			_hand.set_hand_joint_transform(joint, Transform3D(Basis.IDENTITY, _joint_position(joint)))
			_hand.set_hand_joint_flags(joint, flags)


# A made-up but distinct position per joint, relative to the palm, for the rendered-hand check.
func _joint_position(joint: int) -> Vector3:
	return _palm.origin + Vector3(0.01 * float(joint % 5), 0.004 * float(joint), -0.006 * float(joint))


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
	print("HANDPATH %s %s%s" % ["ok  " if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
	# `process_frame` fires before the nodes' _process, so the second one guarantees a whole
	# frame's _process has run since the last tick.
	await get_tree().process_frame
	await get_tree().process_frame


# Where the open-hand pointer must start: midway between the thumb tip and the index tip.
func _expected_pointer_origin() -> Vector3:
	return ORIGIN_XF * (_palm.origin + Vector3(_pinch_gap * 0.5, 0.0, -0.08))


# The world-space pose the blade root must have for the current palm pose.
func _expected_saber_origin() -> Vector3:
	return (ORIGIN_XF * _palm).origin


func _run() -> void:
	# --- 0. premise: this is the "controllers asleep" state --------------------------------
	_hand.has_tracking_data = true
	await _ticks(3)
	_check("premise: controller node is inactive", not _controller.get_is_active())
	_check("premise: hand path is live", _controller.is_hand_tracking())

	# --- 1. the blade sits in the hand, in world space --------------------------------------
	var err := _saber.global_position.distance_to(_expected_saber_origin())
	_check("saber follows the palm in world space", err < 0.001, "error %.3f m" % err)

	# --- 1b. the rendered hand: bars sit on the tracked joints, in world space ---------------
	var drawn := RenderedHandScript.new() as Node3D
	drawn.set("hand", 0)
	_origin.add_child(drawn)
	await _ticks(2)
	_check("rendered hand is visible while tracked", drawn.visible)
	_check("rendered hand has one bar per bone", int(drawn.call(&"segment_count")) == 27,
		"bars=%d" % int(drawn.call(&"segment_count")))
	# This harness only publishes palm, thumb tip and index tip, so every bar touches a joint
	# with no valid position: all of them must be hidden rather than drawn to the origin.
	var stray := 0
	for i in int(drawn.call(&"segment_count")):
		var xf: Transform3D = drawn.call(&"segment_transform", i)
		if xf.basis.z.length() > 0.0001:
			stray += 1
	_check("bars to untracked joints are hidden", stray == 0, "visible bars=%d" % stray)
	_publish_all_joints = true
	await _ticks(2)
	var bar: Transform3D = drawn.call(&"segment_transform", 0)
	var bar_world := drawn.global_transform * bar.origin
	var want := ORIGIN_XF * ((_joint_position(XRHandTracker.HAND_JOINT_WRIST) + _joint_position(XRHandTracker.HAND_JOINT_THUMB_METACARPAL)) * 0.5)
	_check("a bar is centred between its two joints, in world space", bar_world.distance_to(want) < 0.001,
		"error %.3f m" % bar_world.distance_to(want))
	Settings.hand_tracking_enabled = false
	await _ticks(1)
	_check("Hands off hides the rendered hand", not drawn.visible)
	Settings.hand_tracking_enabled = true
	_publish_all_joints = false
	# Back to the three-joint hand: joints that are no longer published must not stay "tracked".
	for joint in XRHandTracker.HAND_JOINT_MAX:
		_hand.set_hand_joint_flags(joint, 0)
	drawn.queue_free()
	await _ticks(2)

	# --- 2. the cut segment is the pose of the same tick, not the previous frame's ----------
	# Move the hand every tick; the segment the resolver sweeps must be the one just delivered.
	_lag_worst = 0.0
	_lag_check = true
	await _ticks(8)
	_lag_check = false
	await _ticks(1)
	_check("cut segment has no one-frame lag behind the hand", _lag_worst < 0.001, "worst %.3f m" % _lag_worst)

	# --- 3. pinch drives the trigger while the controller is asleep -------------------------
	_pinch_gap = 0.10
	await _ticks(2)
	_pinch_gap = 0.01
	await _ticks(2)
	_check("pinch presses the trigger with the controller asleep", _controller.trigger_pressed())
	_pinch_gap = 0.10
	await _ticks(2)
	_check("opening the hand releases the trigger", not _controller.trigger_pressed())

	# --- 3b. hand data drops mid-pinch: the trigger releases, and does not re-fire on return ---
	_pinch_gap = 0.01
	await _ticks(2)
	_check("premise: pinching again", _controller.trigger_pressed())
	_hand.has_tracking_data = false
	await _ticks(2)
	_check("a dropout mid-pinch releases the trigger", not _controller.trigger_pressed())
	_hand.has_tracking_data = true
	await _ticks(2)
	_check("a hand that returns still pinched does not click", not _controller.trigger_pressed())
	_pinch_gap = 0.10
	await _ticks(2)
	_pinch_gap = 0.01
	await _ticks(2)
	_check("after opening once, a pinch clicks again", _controller.trigger_pressed())
	_pinch_gap = 0.10
	await _ticks(2)

	# --- 4. swing travel is measured at the hand, not at the sleeping controller ------------
	_controller.reset_movement_aabb()
	for i in 10:
		_palm.origin += Vector3(0.0, 0.08, 0.0)
		await _ticks(1)
	var travel := _controller.movement_aabb.get_longest_axis_size()
	_check("swing travel follows the hand", travel > 0.5, "longest axis %.2f m" % travel)

	# --- 5. the cut plane hinges on the hand, not on the sleeping controller ----------------
	var hinge := _saber.cut_origin().distance_to(_expected_saber_origin())
	_check("cut plane origin is the hand", hinge < 0.001, "error %.3f m" % hinge)

	# --- 6. a parked blade (hand data lost, no controller) cuts nothing ---------------------
	# Driven through the real detection path of whichever mode the project ships
	# (gameplay/swing_hit/detection): the stub is both a physics area and a resolver entry.
	var player := AudioStreamPlayer.new()
	add_child(player)
	_saber.song_player_ref = player
	# --- 5b. grip to ignite ---------------------------------------------------------------
	_grip = GRIP_OPEN
	_saber._show()
	await _ticks(4)
	_check("open hand: not gripping", not _controller.is_gripping())
	_check("open hand: the blade stays sheathed even though the game wants it", not _saber.is_extended())
	# The UI ray runs along the saber node's +Y. It is the arm's ray, shoulder to index knuckle,
	# not the hand's: with no headset the head is at the tracking origin, so the left shoulder
	# is 0.18 m to the left of it and 0.22 m below.
	await _ticks(90)
	var ray_dir := _saber.global_transform.basis.y.normalized()
	var shoulder := Vector3(-_controller.POINTER_SHOULDER_SIDE_M, -_controller.POINTER_SHOULDER_DROP_M, 0.0)
	var arm_dir := (ORIGIN_XF.basis * (_palm.origin + KNUCKLE_INDEX - shoulder)).normalized()
	_check("open hand: the pointer is the arm's ray, shoulder to index knuckle", ray_dir.dot(arm_dir) > 0.9999,
		"dot %.5f" % ray_dir.dot(arm_dir))
	var start_before := _saber.global_position
	_pinch_gap = 0.10
	await _ticks(2)
	_pinch_gap = 0.01
	await _ticks(30)
	var pinched_dir := _saber.global_transform.basis.y.normalized()
	var start_shift := _saber.global_position.distance_to(start_before)
	_check("open hand: a pinch clicks", _controller.trigger_pressed())
	_check("open hand: a pinch moves neither the ray's direction nor its start",
		pinched_dir.dot(ray_dir) > 0.999999 and start_shift < 0.0005,
		"direction dot %.7f, start moved %.4f m" % [pinched_dir.dot(ray_dir), start_shift])
	# A finger twitch that is not a pinch (tips 6 cm apart instead of 10) moves the start by
	# the 2 cm the midpoint moved, and the direction not at all.
	_pinch_gap = 0.06
	await _ticks(90)
	var twitch_dir := _saber.global_transform.basis.y.normalized()
	_check("open hand: finger movement does not swing the ray", twitch_dir.dot(ray_dir) > 0.999999,
		"direction dot %.7f" % twitch_dir.dot(ray_dir))
	_pinch_gap = 0.10
	await _ticks(90)
	# In a menu the game does not ask for the blade; a fist still ignites it.
	_saber._hide()
	_grip = GRIP_FIST
	await _ticks(4)
	_check("menu: a fist ignites the saber even when the game has not asked for it", _saber.is_extended())
	_grip = GRIP_OPEN
	await _ticks(200)
	_check("menu: opening the hand puts it away again", not _saber.is_extended())
	_saber._show()
	await _ticks(90)
	var pointer_err := _saber.global_position.distance_to(_expected_pointer_origin())
	_check("open hand: the pointer starts midway between thumb tip and index tip", pointer_err < 0.001, "error %.3f m" % pointer_err)
	_check("open hand: nothing of the saber is drawn, hilt included", not (_saber.get_node("saber_holder") as Node3D).visible)
	_grip = GRIP_FIST
	await _ticks(4)
	_check("fist: gripping", _controller.is_gripping())
	_check("fist: the blade ignites", _saber.is_extended())
	_pinch_gap = 0.10
	await _ticks(2)
	_pinch_gap = 0.01
	await _ticks(2)
	_check("fist: thumb on index is not a click", not _controller.trigger_pressed())
	_pinch_gap = 0.10
	_saber.set_swingcast_enabled(true)
	# The Show animation extends the blade over a second; wait it out.
	await _ticks(200)
	_check("premise: the blade is extended",
		_saber.is_extended() and _saber.last_blade_base.distance_to(_saber.last_blade_tip) > 1.0)
	var blade_dir := (_saber.last_blade_tip - _saber.last_blade_base).normalized()
	var knuckle_dir := (ORIGIN_XF.basis * (KNUCKLE_INDEX - KNUCKLE_LITTLE)).normalized()
	# Palm is 0.07 m in front of the wrist along -Z in the synthetic hand.
	var hand_forward := (ORIGIN_XF.basis * Vector3(0.0, 0.0, -1.0)).normalized()
	var lean_deg := rad_to_deg(acos(clampf(blade_dir.dot(knuckle_dir), -1.0, 1.0)))
	_check("fist: the blade leans %.0f degrees off the knuckle line" % _controller.grip_blade_lean_deg,
		absf(lean_deg - _controller.grip_blade_lean_deg) < 0.5, "measured %.1f" % lean_deg)
	_check("fist: the lean is forward, away from the wrist, and still out of the thumb side",
		blade_dir.dot(hand_forward) > knuckle_dir.dot(hand_forward) and blade_dir.dot(knuckle_dir) > 0.8)
	_check("fist: the hilt is drawn", (_saber.get_node("saber_holder") as Node3D).visible)
	# The hilt mesh is centred 3 cm below the saber origin. Its centre must sit in the loop of
	# the curled fingers: close to the knuckle row, on the palm side of it, and well away from
	# the wrist.
	var hilt_center := _saber.global_position - blade_dir * 0.03
	var knuckle_row := ORIGIN_XF * (_palm.origin + (KNUCKLE_INDEX + KNUCKLE_LITTLE) * 0.5)
	var wrist := ORIGIN_XF * (_palm.origin + Vector3(0.0, 0.0, 0.07))
	_check("fist: the hilt is held in the curled fingers, not at the wrist",
		hilt_center.distance_to(knuckle_row) < 0.04 and hilt_center.distance_to(wrist) > 0.07
		and hilt_center.y < knuckle_row.y,
		"%.3f m from the knuckle row, %.3f m from the wrist" % [hilt_center.distance_to(knuckle_row), hilt_center.distance_to(wrist)])
	var target := _StubNote.new()
	add_child(target)
	# Positive control first: a note resting on a live, extended blade is cut.
	target.global_position = _saber.last_blade_base.lerp(_saber.last_blade_tip, 0.5)
	target.arm(_saber._hit_mask)
	await _ticks(4)
	_check("control: a live blade cuts a note resting on it (%s mode)" % ("analytic" if HitResolver.is_analytic() else "rays"),
		target.cuts >= 1, "cuts=%d" % target.cuts)
	target.disarm()
	# The same note on the same blade, with the hand gone and the controller asleep.
	_hand.has_tracking_data = false
	await _ticks(2)
	_check("premise: hand path dropped", not _controller.is_hand_tracking())
	_check("premise: the blade is parked, still extended", _saber.hand_drive_active and _saber.is_extended())
	_check("a dropout does not drop the grip", _controller.is_gripping())
	target.cuts = 0
	target.global_position = _saber.last_blade_base.lerp(_saber.last_blade_tip, 0.5)
	target.arm(_saber._hit_mask)
	await _ticks(30)
	_check("a parked blade cuts nothing", target.cuts == 0, "cuts=%d" % target.cuts)
	target.disarm()
	target.queue_free()

	# --- 6b. opening the hand sheathes the blade --------------------------------------------
	_hand.has_tracking_data = true
	await _ticks(2)
	_check("premise: still ignited when the hand returns as a fist", _saber.is_extended())
	_grip = GRIP_OPEN
	await _ticks(4)
	_check("open hand: the blade retracts", not _saber.is_extended())
	# The Hide animation shrinks the blade over a second; the pointer pose returns after it.
	await _ticks(200)
	_check("open hand: the hilt is gone once the blade has retracted", not (_saber.get_node("saber_holder") as Node3D).visible)

	# --- 7. hand data returns: the blade follows again --------------------------------------
	_palm.origin += Vector3(0.1, 0.0, 0.0)
	await _ticks(90)
	err = _saber.global_position.distance_to(_expected_pointer_origin())
	_check("saber follows again when hand data returns", err < 0.001, "error %.3f m" % err)

	# --- 8. Hands off: the hand path stops, pinch cannot press the trigger ------------------
	Settings.hand_tracking_enabled = false
	_pinch_gap = 0.10
	await _ticks(2)
	_pinch_gap = 0.01
	await _ticks(2)
	_check("Hands off: hand path is not live", not _controller.is_hand_tracking())
	_check("Hands off: pinch does not press the trigger", not _controller.trigger_pressed())

	# --- 9. controller-inferred hand data never enters the hand path ------------------------
	Settings.hand_tracking_enabled = true
	_hand.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER
	await _ticks(2)
	_check("controller-inferred hand data is rejected", not _controller.is_hand_tracking())

	# --- 10. the controller wakes up: back to the parented path, unchanged -------------------
	_hand.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
	await _ticks(2)
	_check("premise: hand-driven before the controller returns", _saber.hand_drive_active and _saber.top_level)
	_hand.has_tracking_data = false
	var pad := XRControllerTracker.new()
	pad.name = &"left_hand"
	pad.hand = XRPositionalTracker.TRACKER_HAND_LEFT
	var pad_pose := Transform3D(Basis.IDENTITY, Vector3(0.3, 1.1, -0.4))
	pad.set_pose(&"default", pad_pose, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(pad)
	await _ticks(2)
	pad.set_pose(&"default", pad_pose, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	await _ticks(2)
	_check("controller is active again", _controller.get_is_active())
	_check("saber is parented again", not _saber.hand_drive_active and not _saber.top_level)
	_check("controller mode: the hilt is always drawn", (_saber.get_node("saber_holder") as Node3D).visible)
	var local_err := _saber.position.distance_to(_saber.offset_pos + _saber.extra_offset_pos)
	_check("saber is back on its controller offset", local_err < 0.0001, "error %.4f m" % local_err)
	var pad_world := (ORIGIN_XF * pad_pose).origin
	_check("controller node follows the controller pose", _controller.global_position.distance_to(pad_world) < 0.001)
	# Controller mode must read exactly what it read before the hand path existed.
	_check("controller mode: cut plane origin is the controller node",
		_saber.cut_origin() == _controller.global_transform.origin)
	_check("controller mode: swing origin is the controller node",
		_controller.swing_origin() == _controller.global_transform.origin)
	_check("controller mode: no pinch left on the trigger", not _controller.trigger_pressed())
	pad.set_input(&"trigger", true)
	await _ticks(2)
	_check("controller mode: the trigger button presses the trigger", _controller.trigger_pressed())
	XRServer.remove_tracker(pad)

	Settings.hand_tracking_enabled = _hands_setting_before
	XRServer.remove_tracker(_hand)
	print("HANDPATH ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


var _lag_check := false
var _publish_all_joints := false
# What the synthetic hand is doing with its three grip fingers.
const GRIP_UNPUBLISHED := 0
const GRIP_OPEN := 1
const GRIP_FIST := 2
var _grip := GRIP_UNPUBLISHED
# Knuckle positions relative to the palm; the blade of a gripped saber runs little -> index.
const KNUCKLE_INDEX := Vector3(-0.035, 0.0, -0.03)
const KNUCKLE_LITTLE := Vector3(0.03, 0.0, -0.02)
var _lag_worst := 0.0


# A cuttable that only counts. It carries a real Area3D for the ray fan and registers with the
# analytic resolver by hand, so no map has to be loaded for either detection mode.
class _StubNote extends Cuttable:
	var cuts := 0
	var _area := Area3D.new()
	var _shape_node := CollisionShape3D.new()
	var _armed := false

	func _init() -> void:
		var box := BoxShape3D.new()
		box.size = Vector3(0.4, 0.4, 0.4)
		_shape_node.shape = box
		_area.collision_layer = 0
		_area.collision_mask = 0
		_area.add_child(_shape_node)
		add_child(_area)

	func arm(mask: int) -> void:
		disarm()
		_area.collision_layer = mask
		HitResolver.add(self, mask, _shape_node)
		_armed = true

	func disarm() -> void:
		if _armed:
			_area.collision_layer = 0
			HitResolver.remove(self)
			_armed = false

	func cut(_saber_type: int, _cut_speed: Vector3, _cut_plane: Plane, _controller: BeepSaberController) -> HitInfo:
		cuts += 1
		return HitInfo.new()
