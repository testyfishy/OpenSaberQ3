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

	# --- 7. hand data returns: the blade follows again --------------------------------------
	_hand.has_tracking_data = true
	_palm.origin += Vector3(0.1, 0.0, 0.0)
	await _ticks(3)
	err = _saber.global_position.distance_to(_expected_saber_origin())
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
var _lag_worst := 0.0
