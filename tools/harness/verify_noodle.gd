extends Node

# Noodle Extensions animation harness (docs/noodle-animation-brief.md). Headless.
#
# Every expected value below is a literal worked out by hand from the Heck formulas, never
# recomputed by the code under test. Each check prints one `NOODLE ok` / `NOODLE FAIL` line; the
# last line is the verdict (check.ps1 matches it), and the exit code is non-zero on failure.
#
# Run: godot --headless --path . res://tools/harness/verify_noodle.tscn

const EPS := 0.0005

var _fails := 0
var _checks := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("NOODLE %s %s%s" % ["ok  " if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _near(label: String, got: float, want: float) -> void:
	_check(label, absf(got - want) < EPS, "got %.5f want %.5f" % [got, want])


func _near3(label: String, got: Vector3, want: Vector3) -> void:
	_check(label, got.distance_to(want) < EPS, "got %s want %s" % [str(got), str(want)])


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_easings()
	_points()
	_named()
	print("NOODLE checks=%d failed=%d" % [_checks, _fails])
	print("NOODLE ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


# --- step 1: easings ------------------------------------------------------------------------
func _easings() -> void:
	var E := NoodleEasing
	_near("easeLinear 0.3", E.ease(0.3, E.from_name("easeLinear")), 0.3)
	_near("easeInQuad 0.5", E.ease(0.5, E.from_name("easeInQuad")), 0.25)
	_near("easeOutQuad 0.5", E.ease(0.5, E.from_name("easeOutQuad")), 0.75)
	_near("easeInOutQuad 0.25", E.ease(0.25, E.from_name("easeInOutQuad")), 0.125)
	_near("easeInCubic 0.5", E.ease(0.5, E.from_name("easeInCubic")), 0.125)
	_near("easeOutCubic 0.5", E.ease(0.5, E.from_name("easeOutCubic")), 0.875)
	_near("easeInOutCubic 0.25", E.ease(0.25, E.from_name("easeInOutCubic")), 0.0625)
	_near("easeInQuart 0.5", E.ease(0.5, E.from_name("easeInQuart")), 0.0625)
	_near("easeOutQuart 0.5", E.ease(0.5, E.from_name("easeOutQuart")), 0.9375)
	_near("easeInOutQuart 0.25", E.ease(0.25, E.from_name("easeInOutQuart")), 0.03125)
	_near("easeInQuint 0.5", E.ease(0.5, E.from_name("easeInQuint")), 0.03125)
	_near("easeOutQuint 0.5", E.ease(0.5, E.from_name("easeOutQuint")), 0.96875)
	_near("easeInOutQuint 0.25", E.ease(0.25, E.from_name("easeInOutQuint")), 0.015625)
	_near("easeInSine 0.5", E.ease(0.5, E.from_name("easeInSine")), 0.29289)
	_near("easeOutSine 0.5", E.ease(0.5, E.from_name("easeOutSine")), 0.70711)
	_near("easeInOutSine 0.25", E.ease(0.25, E.from_name("easeInOutSine")), 0.14645)
	_near("easeInCirc 0.6", E.ease(0.6, E.from_name("easeInCirc")), 0.2)
	_near("easeOutCirc 0.4", E.ease(0.4, E.from_name("easeOutCirc")), 0.8)
	_near("easeInOutCirc 0.25", E.ease(0.25, E.from_name("easeInOutCirc")), 0.06699)
	_near("easeInExpo 0", E.ease(0.0, E.from_name("easeInExpo")), 0.0)
	_near("easeInExpo 1", E.ease(1.0, E.from_name("easeInExpo")), 1.0)
	_near("easeInExpo 0.5", E.ease(0.5, E.from_name("easeInExpo")), 0.03030)
	_near("easeOutExpo 1", E.ease(1.0, E.from_name("easeOutExpo")), 1.0)
	_near("easeOutExpo 0.5", E.ease(0.5, E.from_name("easeOutExpo")), 0.96970)
	_near("easeInOutExpo 0.5", E.ease(0.5, E.from_name("easeInOutExpo")), 0.5)
	_near("easeInOutExpo 0.25", E.ease(0.25, E.from_name("easeInOutExpo")), 0.01515)
	_near("easeInElastic 1", E.ease(1.0, E.from_name("easeInElastic")), 1.0)
	_near("easeOutElastic 0", E.ease(0.0, E.from_name("easeOutElastic")), 0.0)
	_near("easeInOutElastic 0.5", E.ease(0.5, E.from_name("easeInOutElastic")), 0.5)
	_near("easeInBack 0.5", E.ease(0.5, E.from_name("easeInBack")), -0.375)
	_near("easeOutBack 0.5", E.ease(0.5, E.from_name("easeOutBack")), 1.375)
	_near("easeInOutBack 0.25", E.ease(0.25, E.from_name("easeInOutBack")), -0.1875)
	_near("easeOutBounce 1", E.ease(1.0, E.from_name("easeOutBounce")), 1.0)
	_near("easeOutBounce 0.2", E.ease(0.2, E.from_name("easeOutBounce")), 0.3025)
	_near("easeInBounce 0.8", E.ease(0.8, E.from_name("easeInBounce")), 0.6975)
	_near("easeInOutBounce 0.1", E.ease(0.1, E.from_name("easeInOutBounce")), 0.04388)
	_near("easeStep 0.99", E.ease(0.99, E.from_name("easeStep")), 0.0)
	_near("easeStep 1", E.ease(1.0, E.from_name("easeStep")), 1.0)
	_near("unknown easing is linear", E.ease(0.4, E.from_name("easeNoSuchThing")), 0.4)


# --- step 1: point definitions --------------------------------------------------------------
func _points() -> void:
	var P := NoodlePoints
	var lin := P.parse([[0, 0, 0, 0], [10, 20, 30, 1]], P.KIND_POSITION)
	_near3("vector midpoint (z flipped)", lin.eval_vec3(0.5), Vector3(5, 10, -15))
	_near3("vector clamps after last", lin.eval_vec3(2.0), Vector3(10, 20, -30))
	_near3("vector clamps before first", lin.eval_vec3(-1.0), Vector3.ZERO)
	var eased := P.parse([[0, 0, 0, 0], [10, 20, 30, 1, "easeInQuad"]], P.KIND_POSITION)
	_near3("easing of the right point", eased.eval_vec3(0.5), Vector3(2.5, 5, -7.5))
	var three := P.parse([[0, 0, 0, 0], [1, 0, 0, 0.5], [3, 0, 0, 1]], P.KIND_POSITION)
	_near3("second segment", three.eval_vec3(0.75), Vector3(2, 0, 0))
	_near3("exactly on a middle point", three.eval_vec3(0.5), Vector3(1, 0, 0))
	var spline := P.parse([[0, 0, 0, 0], [1, 0, 0, 0.5, "splineCatmullRom"], [2, 0, 0, 1]], P.KIND_POSITION)
	_near3("Catmull-Rom segment, clamped end", spline.eval_vec3(0.25), Vector3(0.4375, 0, 0))
	_near3("linear segment after spline", spline.eval_vec3(0.75), Vector3(1.5, 0, 0))
	var bare := P.parse([1, 2, 3], P.KIND_POSITION)
	_check("bare point is one point", bare != null and bare.count() == 1)
	_near3("bare point value", bare.eval_vec3(0.7), Vector3(1, 2, -3))
	var scale := P.parse([[1, 1, 1, 0], [3, 2, 1, 1]], P.KIND_SCALE)
	_near3("scale keeps z", scale.eval_vec3(0.5), Vector3(2, 1.5, 1))
	var f := P.parse([[0, 0], [1, 1, "easeOutQuad"]], P.KIND_FLOAT)
	_near("float eased", f.eval_float(0.5), 0.75)
	var f_bare := P.parse([0.5], P.KIND_FLOAT)
	_near("bare float", f_bare.eval_float(0.9), 0.5)
	var f_step := P.parse([[0, 0], [1, 0.5, "easeStep"], [0, 1]], P.KIND_FLOAT)
	_near("easeStep holds the previous value", f_step.eval_float(0.4), 0.0)
	_near("easeStep segment then lerps on", f_step.eval_float(0.75), 0.5)
	# Rotations: Beat Saber yaw +90 turns "forward" (away from the player) to the right. In
	# Godot forward is -z, so the turned forward must be +x.
	var yaw := P.parse([0, 90, 0], P.KIND_ROTATION)
	_near3("yaw 90 turns forward to the right", yaw.eval_quat(0.0) * Vector3(0, 0, -1), Vector3(1, 0, 0))
	# Pitch +90 in Unity turns up (+y) to forward (+z Unity), which is -z here.
	var pitch := P.parse([90, 0, 0], P.KIND_ROTATION)
	_near3("pitch 90 turns up to forward", pitch.eval_quat(0.0) * Vector3(0, 1, 0), Vector3(0, 0, -1))
	# Roll +90 in Unity turns up (+y) to -x (counter-clockwise seen from behind).
	var roll := P.parse([0, 0, 90], P.KIND_ROTATION)
	_near3("roll 90 turns up to the left", roll.eval_quat(0.0) * Vector3(0, 1, 0), Vector3(-1, 0, 0))
	var turn := P.parse([[0, 0, 0, 0], [0, 90, 0, 1]], P.KIND_ROTATION)
	_near3("rotation slerps", turn.eval_quat(0.5) * Vector3(0, 0, -1), Vector3(0.70711, 0, -0.70711))
	var base := P.parse([[0, 0, 0, 0, "baseHeadPosition"]], P.KIND_POSITION)
	_check("base provider flagged", base != null and base.unsupported != "" and base.count() == 0)
	var modifier := P.parse([[0, 0, 0, 0, [1, 1, 1, "opAdd"]]], P.KIND_POSITION)
	_check("point modifier flagged", modifier != null and modifier.unsupported != "")
	_check("too few numbers rejected", P.parse([[0, 0, 0]], P.KIND_POSITION) == null)
	_check("empty rejected", P.parse([], P.KIND_POSITION) == null)
	_check("non-array rejected", P.parse(3.0, P.KIND_FLOAT) == null)


func _named() -> void:
	var P := NoodlePoints
	var v3 := P.named_definitions({"version": "3.2.0", "customData": {"pointDefinitions": {
		"zig": [[0, 0, 0, 0], [2, 0, 0, 1]]}}})
	_near3("v3 named definition", P.from_value("zig", P.KIND_POSITION, v3).eval_vec3(0.5), Vector3(1, 0, 0))
	var v2 := P.named_definitions({"_version": "2.2.0", "_customData": {"_pointDefinitions": [
		{"_name": "zag", "_points": [[0, 0], [4, 1]]}]}})
	_near("v2 named definition", P.from_value("zag", P.KIND_FLOAT, v2).eval_float(0.25), 1.0)
	_check("unknown name is null", P.from_value("nope", P.KIND_FLOAT, v2) == null)
