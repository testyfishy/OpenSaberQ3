extends Node

# Records real hand-tracking data on the headset so hand geometry can be debugged off-device.
#
# Why: the synthetic hand in tools/harness/verify_hand_path proves the maths, not the feel. Where
# the hilt sits in a real fist, which way a real palm pose faces, how far a real pinch moves the
# knuckles - none of that can be known without real joints. This writes them to a file that
# tools/harness/hand_replay.tscn plays back on a PC, with the real controller and saber scripts,
# and renders to images.
#
# Trigger (same folder as bench.flag, works on a release APK):
#   /sdcard/Android/data/<package>/files/hand_capture.flag     any content
# The recording starts at the first frame either hand is tracked, runs for DURATION_SEC, and is
# written next to the flag as hand_capture.csv. The flag is renamed to hand_capture.flag.consumed
# when the file is complete, so one flag is one recording. Nothing runs without the flag.
#
# File: one header line, then one line per sample (every SAMPLE_EVERY rendered frames):
#   t_usec, head(12), then for each hand (left, right):
#     tracked(0/1), source, gripping(0/1), trigger(0/1), palm_pose(12),
#     26 x [flags, px, py, pz, qx, qy, qz, qw]
# Transforms are 12 floats: basis x, y, z columns then origin. Everything is in tracking space
# (the XR origin's space), exactly as the engine hands it over.

const FLAG_NAME := "hand_capture.flag"
const OUT_NAME := "hand_capture.csv"
const DURATION_SEC := 60.0
const SAMPLE_EVERY := 3
const TRACKERS: Array[StringName] = [&"/user/hand_tracker/left", &"/user/hand_tracker/right"]

var _dir := ""
var _lines := PackedStringArray()
var _started_usec := -1
var _frame := 0
var _done := false
var _controllers: Array[BeepSaberController] = []


static func flag_dir() -> String:
	var runner: Script = load("res://game/scripts/BenchmarkRunner.gd")
	if runner == null:
		return ""
	var external := str(runner.call("_android_external_files_dir"))
	if not external.is_empty() and FileAccess.file_exists(external.path_join(FLAG_NAME)):
		return external
	if FileAccess.file_exists("user://" + FLAG_NAME):
		return "user://"
	return ""


func setup(dir: String, left: BeepSaberController, right: BeepSaberController) -> void:
	_dir = dir
	_controllers = [left, right]
	vr.log_info("HANDCAP: armed, waiting for a tracked hand (%s)" % dir)


func _process(_dt: float) -> void:
	if _done:
		return
	var hands: Array[XRHandTracker] = []
	var any := false
	for tracker_name in TRACKERS:
		var hand := XRServer.get_tracker(tracker_name) as XRHandTracker
		hands.append(hand)
		if hand != null and hand.has_tracking_data:
			any = true
	if _started_usec < 0:
		if not any:
			return
		_started_usec = Time.get_ticks_usec()
		vr.log_info("HANDCAP: recording %.0f s" % DURATION_SEC)
	_frame += 1
	var elapsed := Time.get_ticks_usec() - _started_usec
	if _frame % SAMPLE_EVERY == 0:
		_lines.append(_sample(elapsed, hands))
	if float(elapsed) / 1000000.0 >= DURATION_SEC:
		_finish()


func _sample(t_usec: int, hands: Array[XRHandTracker]) -> String:
	var out := PackedStringArray([str(t_usec)])
	_put_transform(out, XRServer.get_hmd_transform())
	for i in hands.size():
		var hand := hands[i]
		var tracked := hand != null and hand.has_tracking_data
		var controller := _controllers[i] if i < _controllers.size() else null
		out.append("1" if tracked else "0")
		out.append(str(int(hand.hand_tracking_source)) if hand != null else "-1")
		out.append("1" if controller != null and controller.is_gripping() else "0")
		out.append("1" if controller != null and controller.trigger_pressed() else "0")
		var palm := Transform3D.IDENTITY
		if hand != null:
			var pose := hand.get_pose(&"default")
			if pose != null:
				palm = pose.get_adjusted_transform()
		_put_transform(out, palm)
		for joint in XRHandTracker.HAND_JOINT_MAX:
			if hand == null:
				out.append("0,0,0,0,0,0,0,1")
				continue
			var xf := hand.get_hand_joint_transform(joint)
			var q := xf.basis.orthonormalized().get_rotation_quaternion()
			out.append("%d,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f" % [
				int(hand.get_hand_joint_flags(joint)), xf.origin.x, xf.origin.y, xf.origin.z, q.x, q.y, q.z, q.w])
	return ",".join(out)


func _put_transform(out: PackedStringArray, xf: Transform3D) -> void:
	for v: Vector3 in [xf.basis.x, xf.basis.y, xf.basis.z, xf.origin]:
		out.append("%.5f,%.5f,%.5f" % [v.x, v.y, v.z])


func _finish() -> void:
	_done = true
	var path := _dir.path_join(OUT_NAME)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		vr.log_file_error(FileAccess.get_open_error(), path, "HandCapture._finish")
		return
	file.store_line("hand_capture v1 joints=%d sample_every=%d" % [XRHandTracker.HAND_JOINT_MAX, SAMPLE_EVERY])
	for line in _lines:
		file.store_line(line)
	file.close()
	var dir := DirAccess.open(_dir)
	if dir != null:
		@warning_ignore("return_value_discarded")
		dir.rename(FLAG_NAME, FLAG_NAME + ".consumed")
	vr.log_info("HANDCAP: wrote %d samples to %s" % [_lines.size(), path])
	_lines.clear()
