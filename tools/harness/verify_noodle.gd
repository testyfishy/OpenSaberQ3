extends Node

# Noodle Extensions animation harness (docs/noodle-animation-brief.md). Headless.
#
# Every expected value below is a literal worked out by hand from the Heck formulas, never
# recomputed by the code under test. Each check prints one `NOODLE ok` / `NOODLE FAIL` line; the
# last line is the verdict (check.ps1 matches it), and the exit code is non-zero on failure.
#
# Run: godot --headless --path . res://tools/harness/verify_noodle.tscn

const EPS := 0.0005
const MapTimer := preload("res://game/scripts/MapTimer.gd")

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
	_tracks()
	_fixtures()
	_events()
	_fixture_events()
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


# --- step 2: track registry -----------------------------------------------------------------
func _tracks() -> void:
	var T := NoodleTracks
	_check("no customData, no NoodleObject", NoodleObject.from_entry({"b": 1.0}) == null)
	_check("customData without track, no NoodleObject", NoodleObject.from_entry({"customData": {"color": [1, 0, 0]}}) == null)
	_check("empty track name ignored", NoodleObject.from_entry({"customData": {"track": ""}}) == null)
	var one := NoodleObject.from_entry({"customData": {"track": "solo"}})
	_check("v3 track string", one != null and one.track_names == PackedStringArray(["solo"]))
	var many := NoodleObject.from_entry({"customData": {"track": ["move", "leftnotes"]}})
	_check("v3 track array", many != null and many.track_names == PackedStringArray(["move", "leftnotes"]))
	var v2 := NoodleObject.from_entry({"_customData": {"_track": "zig"}})
	_check("v2 _track string", v2 != null and v2.track_names == PackedStringArray(["zig"]))
	var v2a := NoodleObject.from_entry({"_customData": {"_track": ["a", 3, "b"]}})
	_check("v2 _track array skips non-strings", v2a != null and v2a.track_names == PackedStringArray(["a", "b"]))

	# Through the real parsers, both spellings, every object type.
	var n3 := ColorNoteInfo.new_v3({"b": 4.0, "x": 1, "y": 0, "c": 0, "d": 1, "customData": {"track": ["move", "leftnotes"]}})
	_check("v3 note joins its tracks", n3.noodle != null and n3.noodle.track_names.size() == 2)
	var n2 := ColorNoteInfo.new_v2({"_time": 4.0, "_lineIndex": 1, "_lineLayer": 0, "_type": 0, "_cutDirection": 1, "_customData": {"_track": "zig"}})
	_check("v2 note joins its track", n2.noodle != null and n2.noodle.track_names[0] == "zig")
	var plain := ColorNoteInfo.new_v3({"b": 4.0, "x": 1, "y": 0, "c": 0, "d": 1})
	_check("plain note has no Noodle data", plain.noodle == null)
	var b3 := BombInfo.new_v3({"b": 2.0, "x": 0, "y": 0, "customData": {"track": "bombs"}})
	var b2 := BombInfo.new_v2({"_time": 2.0, "_lineIndex": 0, "_lineLayer": 0, "_type": 3, "_customData": {"_track": "bombs"}})
	_check("bombs join tracks (v3, v2)", b3.noodle != null and b2.noodle != null and b2.noodle.track_names[0] == "bombs")
	var w3 := ObstacleInfo.new_v3({"b": 2.0, "d": 1.0, "x": 0, "y": 0, "w": 1, "h": 5, "customData": {"track": "walls"}})
	var w2 := ObstacleInfo.new_v2({"_time": 2.0, "_duration": 1.0, "_lineIndex": 0, "_type": 0, "_width": 1, "_customData": {"_track": ["walls"]}})
	_check("walls join tracks (v3, v2)", w3.noodle != null and w2.noodle != null and w3.noodle.track_names[0] == "walls")

	# Registry: indices are stable, lookups do not create.
	T.reset()
	_check("registry starts inactive", not T.active and T.tracks.is_empty())
	var ia := T.index_of("a")
	var ib := T.index_of("b")
	_check("index_of creates in order", ia == 0 and ib == 1 and T.index_of("a") == 0 and T.tracks.size() == 2)
	_check("find does not create", T.find("c") == -1 and T.tracks.size() == 2)
	var track := T.get_track(ia)
	_check("a new track has nothing set", track.has[T.P_SCALE] == 0 and track.has[T.P_OFFSET_POSITION] == 0 and not track.has_path_for(T.P_DEFINITE_POSITION))
	track.set_from_points(T.P_OFFSET_POSITION, NoodlePoints.parse([[0, 0, 0, 0], [2, 4, 6, 1]], NoodlePoints.KIND_POSITION), 0.5)
	_check("a track holds its value", track.has[T.P_OFFSET_POSITION] == 1)
	_near3("held value", track.vec[T.P_OFFSET_POSITION], Vector3(1, 2, -3))
	track.set_from_points(T.P_DISSOLVE, NoodlePoints.parse([[1, 0], [0, 1]], NoodlePoints.KIND_FLOAT), 0.25)
	_near("held float", track.flt[T.P_DISSOLVE], 0.75)
	track.clear_value(T.P_DISSOLVE)
	_check("null clears a value", track.has[T.P_DISSOLVE] == 0)

	# Resolution after load: names become indices and the registry turns active.
	T.reset()
	MapData.reset()
	MapData.note_stack = [n3, plain]
	MapData.bomb_stack = [b2]
	MapData.obstacle_stack = [w3]
	T.resolve_objects()
	_check("resolution activates the registry", T.active)
	_check("note tracks resolved", n3.noodle.tracks == PackedInt32Array([0, 1]) and T.tracks[1].name == "leftnotes")
	_check("bomb and wall tracks resolved", b2.noodle.tracks == PackedInt32Array([2]) and w3.noodle.tracks == PackedInt32Array([3]))
	MapData.reset()
	T.reset()


# --- real fixture maps (skipped when the fixture folder is not on this machine) -------------
func _fixture_dir(folder: String) -> String:
	return OS.get_environment("TEMP").replace("\\", "/") + "/toolchain/allsongs/" + folder + "/"


func _load_fixture(folder: String, file: String) -> bool:
	var path := _fixture_dir(folder)
	if not FileAccess.file_exists(path + file):
		print("NOODLE skip fixture %s/%s (not on this machine)" % [folder, file])
		return false
	var info := Map.load_map_info(path)
	if info == null:
		_check("fixture %s info loads" % folder, false)
		return false
	for diff in info.difficulty_beatmaps:
		if diff.beatmap_filename == file:
			var data: Variant = vr.load_json_file(path + file)
			var ok := data is Dictionary and Map.load_beatmap(info, diff, data as Dictionary)
			_check("fixture %s/%s loads" % [folder, file], ok)
			return ok
	_check("fixture %s/%s listed in Info.dat" % [folder, file], false)
	return false


func _fixtures() -> void:
	# 4a2b3 Hard (v3): notes on ["move", "leftnotes"]; a plain map must leave the registry off.
	if _load_fixture("4a2b3", "HardStandard.dat"):
		var with_tracks := 0
		for note in MapData.note_stack:
			if note != null and note.noodle != null:
				with_tracks += 1
		_check("v3 fixture: notes carry tracks", with_tracks > 0, "%d notes" % with_tracks)
		_check("v3 fixture: move and leftnotes exist", NoodleTracks.find("move") >= 0 and NoodleTracks.find("leftnotes") >= 0)
		_check("v3 fixture: registry active", NoodleTracks.active and not NoodleTracks.is_v2)
	# 198f3 ExpertPlus (v2): `_track` spelling end to end.
	if _load_fixture("198f3", "ExpertPlus.dat"):
		_check("v2 fixture: registry active with tracks", NoodleTracks.active and NoodleTracks.is_v2 and not NoodleTracks.tracks.is_empty(), "%d tracks" % NoodleTracks.tracks.size())
	if _load_fixture("3af66", _first_dat("3af66")):
		_check("plain fixture: registry stays off", not NoodleTracks.active and NoodleTracks.tracks.is_empty())
	MapData.reset()
	NoodleTracks.reset()


func _first_dat(folder: String) -> String:
	var info := Map.load_map_info(_fixture_dir(folder))
	if info == null or info.difficulty_beatmaps.is_empty():
		return "-"
	return info.difficulty_beatmaps[0].beatmap_filename


# --- step 3: custom events ------------------------------------------------------------------
# A fixed tempo of 120 BPM makes one beat half a second, so durations are easy to check.
func _events_setup(map_data: Dictionary) -> void:
	MapTimer.load_bpm_events({}, 120.0)
	NoodleTracks.begin_load(map_data)
	NoodleEvents.reset()
	NoodleEvents.load_events(map_data)


func _tr(track_name: String) -> NoodleTrack:
	return NoodleTracks.tracks[NoodleTracks.find(track_name)]


func _events() -> void:
	var T := NoodleTracks
	var E := NoodleEvents
	# v3 spelling.
	_events_setup({"version": "3.2.0", "customData": {"customEvents": [
		{"b": 2, "t": "AnimateTrack", "d": {"track": "a", "duration": 4, "offsetPosition": [[0, 0, 0, 0], [8, 0, 0, 1]]}},
		{"b": 2, "t": "AnimateTrack", "d": {"track": ["a", "b"], "duration": 0, "scale": [[1, 1, 1, 0], [2, 2, 2, 1]]}},
		{"b": 1, "t": "AssignPathAnimation", "d": {"track": "a", "dissolve": [[0, 0], [1, 1]]}},
		{"b": 0, "t": "Blit", "d": {}},
		{"b": 0, "t": "AnimateTrack", "d": {"track": "r", "duration": 2, "repeat": 1, "easing": "easeInQuad", "dissolve": [[0, 0], [1, 1]]}},
		{"b": 3, "t": "AnimateTrack", "d": {"track": "s", "scale": [3, 3, 3]}},
		{"b": 3, "t": "AnimateTrack", "d": {"track": "s", "scale": [4, 4, 4]}},
	]}})
	_check("v3: unknown types counted, not queued", E.stack.size() == 6 and int(E.ignored.get("Blit", 0)) == 1)
	_check("v3: stack is in beat order", E.stack[-1].beat == 0.0 and E.stack[0].beat == 3.0)
	_check("v3: events create their tracks", T.find("a") >= 0 and T.find("b") >= 0 and T.find("r") >= 0 and T.active)
	E.dispatch_until(2.0, 1.0)
	_check("v3: dispatch stops at the current beat", E.stack.size() == 2)
	_near3("v3: animation starts at its own time", _tr("a").vec[T.P_OFFSET_POSITION], Vector3.ZERO)
	_near3("v3: duration 0 sets the last point", _tr("a").vec[T.P_SCALE], Vector3(2, 2, 2))
	_near3("v3: one event, several tracks", _tr("b").vec[T.P_SCALE], Vector3(2, 2, 2))
	_check("v3: path assigned", _tr("a").has_path_for(T.P_DISSOLVE))
	_near("v3: path evaluated at object time", _tr("a").path_float(T.P_DISSOLVE, 0.25), 0.25)
	# "r": 2 beats = 1 s per play, easeInQuad, played twice from t = 0. Dispatched late (at 1 s)
	# it is already in its second play, which started at 1 s.
	E.update(1.5)
	_near("v3: repeat restarts the animation, eased", _tr("r").flt[T.P_DISSOLVE], 0.25)
	_near3("v3: 4 beats = 2 s, a quarter after 0.5 s", _tr("a").vec[T.P_OFFSET_POSITION], Vector3(2, 0, 0))
	E.update(2.0)
	_near3("v3: half way after 1 s", _tr("a").vec[T.P_OFFSET_POSITION], Vector3(4, 0, 0))
	_near("v3: repeat ends on the last point", _tr("r").flt[T.P_DISSOLVE], 1.0)
	E.update(3.5)
	_near3("v3: finished animation holds the end", _tr("a").vec[T.P_OFFSET_POSITION], Vector3(8, 0, 0))
	_check("v3: finished tweens are dropped", E._tweens.is_empty())
	E.dispatch_until(3.0, 1.5)
	_near3("v3: same beat, last in the file wins", _tr("s").vec[T.P_SCALE], Vector3(4, 4, 4))

	# Overwrite, null, events already in the past, path transitions.
	_events_setup({"version": "3.2.0", "customData": {"customEvents": [
		{"b": 0, "t": "AnimateTrack", "d": {"track": "o", "duration": 8, "offsetPosition": [[0, 0, 0, 0], [8, 0, 0, 1]]}},
		{"b": 2, "t": "AnimateTrack", "d": {"track": "o", "offsetPosition": [1, 1, 1]}},
		{"b": 0, "t": "AssignPathAnimation", "d": {"track": "p", "offsetPosition": [[0, 0, 0, 0], [2, 0, 0, 1]]}},
		{"b": 0, "t": "AssignPathAnimation", "d": {"track": "p", "duration": 2, "offsetPosition": [[0, 0, 0, 0], [0, 4, 0, 1]]}},
		{"b": 0, "t": "AnimateTrack", "d": {"track": "late", "duration": 2, "dissolve": [[0, 0], [1, 1]]}},
	]}})
	E.dispatch_until(0.0, 0.0)
	_near3("transition starts on the old path", _tr("p").path_vec(T.P_OFFSET_POSITION, 0.5), Vector3(1, 0, 0))
	E.update(0.5)
	_near3("transition half way", _tr("p").path_vec(T.P_OFFSET_POSITION, 0.5), Vector3(0.5, 1, 0))
	E.update(1.0)
	_near3("transition done", _tr("p").path_vec(T.P_OFFSET_POSITION, 0.5), Vector3(0, 2, 0))
	_check("transition drops the old path", _tr("p").path_prev[T.P_OFFSET_POSITION] == null)
	E.dispatch_until(2.0, 1.0)
	_near3("a new animation of a property stops the old one", _tr("o").vec[T.P_OFFSET_POSITION], Vector3(1, 1, -1))
	E.update(2.0)
	_near3("the stopped animation stays stopped", _tr("o").vec[T.P_OFFSET_POSITION], Vector3(1, 1, -1))
	var nulled := E._parse({"b": 3, "t": "AnimateTrack", "d": {"track": "o", "offsetPosition": null}}, false)
	E.dispatch(nulled, 1.5)
	_check("null erases a property", _tr("o").has[T.P_OFFSET_POSITION] == 0)
	var past := E._parse({"b": 0, "t": "AnimateTrack", "d": {"track": "late", "duration": 2, "dissolve": [[0, 0], [1, 1]]}}, false)
	E.dispatch(past, 10.0)
	_near("an event entirely in the past sets its end at once", _tr("late").flt[T.P_DISSOLVE], 1.0)

	# Parents and the player's track (v3 units: metres).
	_events_setup({"version": "3.2.0", "customData": {"customEvents": [
		{"b": 0, "t": "AssignTrackParent", "d": {"childrenTracks": ["c"], "parentTrack": "par"}},
		{"b": 0, "t": "AnimateTrack", "d": {"track": "par", "localPosition": [0, 10, 0], "localRotation": [0, 90, 0]}},
		{"b": 0, "t": "AssignTrackParent", "d": {"childrenTracks": ["par"], "parentTrack": "gp"}},
		{"b": 0, "t": "AnimateTrack", "d": {"track": "gp", "position": [1, 0, 0]}},
		{"b": 0, "t": "AssignPlayerToTrack", "d": {"track": "par"}},
		{"b": 0, "t": "AssignPlayerToTrack", "d": {"track": "gp", "target": "Head"}},
		{"b": 0, "t": "AssignTrackParent", "d": {"childrenTracks": ["self"], "parentTrack": "self"}},
	]}})
	E.dispatch_until(0.0, 0.0)
	E.update(0.0)
	_check("v3: child points at its parent", _tr("c").parent == T.find("par") and _tr("par").is_transform)
	_near3("v3: parent position in metres, chained to its own parent", _tr("par").xform.origin, Vector3(1, 10, 0))
	_near3("v3: parent rotation", _tr("par").xform.basis * Vector3(0, 0, -1), Vector3(1, 0, 0))
	_check("v3: player on the parent track", E.player_track == T.find("par"))
	_near3("v3: the world is drawn relative to the player", E.root_xform * Vector3(1, 10, 0), Vector3.ZERO)
	_check("v3: head target not applied", E.unsupported_targets == 1)
	_check("v3: a track cannot parent itself", _tr("self").parent == -1)

	# v2 spelling: `_position` on a parent is in lanes and turned by `_rotation`.
	_events_setup({"_version": "2.2.0", "_customData": {
		"_pointDefinitions": [{"_name": "up", "_points": [[0, 0, 0, 0], [0, 2, 0, 1]]}],
		"_customEvents": [
			{"_time": 2, "_type": "AnimateTrack", "_data": {"_track": "a", "_duration": 4, "_position": [[0, 0, 0, 0], [8, 0, 0, 1]]}},
			{"_time": 2, "_type": "AnimateTrack", "_data": {"_track": "n", "_duration": 2, "_position": "up"}},
			{"_time": 1, "_type": "AssignPathAnimation", "_data": {"_track": "a", "_dissolve": [[0, 0], [1, 1]], "_definitePosition": [[0, 0, 0, 0], [0, 0, 10, 1]]}},
			{"_time": 0, "_type": "AssignTrackParent", "_data": {"_childrenTracks": ["c"], "_parentTrack": "par"}},
			{"_time": 0, "_type": "AnimateTrack", "_data": {"_track": "par", "_position": [0, 0, 1], "_rotation": [0, 90, 0]}},
			{"_time": 0, "_type": "AssignPlayerToTrack", "_data": {"_track": "par"}},
		]}})
	_check("v2: events parsed and sorted", E.stack.size() == 6 and E.stack[-1].beat == 0.0)
	E.dispatch_until(2.0, 1.0)
	E.update(1.5)
	_near3("v2: named point definition", _tr("n").vec[T.P_OFFSET_POSITION], Vector3(0, 1, 0))
	E.update(2.0)
	_near3("v2: _position is offsetPosition", _tr("a").vec[T.P_OFFSET_POSITION], Vector3(4, 0, 0))
	_near("v2: _dissolve path", _tr("a").path_float(T.P_DISSOLVE, 0.5), 0.5)
	_near3("v2: _definitePosition path", _tr("a").path_vec(T.P_DEFINITE_POSITION, 0.5), Vector3(0, 0, -5))
	_check("v2: parent assigned", _tr("c").parent == T.find("par"))
	_near3("v2: parent position in lanes, turned by _rotation", _tr("par").xform.origin, Vector3(0.6, 0, 0))
	_near3("v2: player track inverse", E.root_xform * Vector3(0.6, 0, 0), Vector3.ZERO)
	E.reset()
	T.reset()
	MapTimer.reset()


# The fixture maps, run through every event: nothing may produce a non-finite transform, and in
# 4a2b3 the notes' parent track and the player's track are the same rising track, so a note on
# `move` must stay where the player sees it however high the elevator goes.
func _fixture_events() -> void:
	if _load_fixture("4a2b3", "HardStandard.dat"):
		NoodleEvents.reset()
		NoodleEvents.load_events(_fixture_data("4a2b3", "HardStandard.dat"))
		var move := NoodleTracks.find("move")
		var helo := NoodleTracks.find("helo")
		var worst := 0.0
		var finite := true
		var beat := 0.0
		while beat < 520.0:
			var sec := Map.beat_to_seconds(beat)
			NoodleEvents.dispatch_until(beat, sec)
			NoodleEvents.update(sec)
			if beat > 200.0 and beat < 201.0:
				_check("4a2b3: the elevator has risen", NoodleTracks.tracks[helo].xform.origin.y > 50.0, "y=%.1f" % NoodleTracks.tracks[helo].xform.origin.y)
			var parent := NoodleTracks.tracks[move].parent
			if parent >= 0:
				var seen := NoodleEvents.root_xform * NoodleTracks.tracks[parent].xform
				worst = maxf(worst, seen.origin.length())
			finite = finite and NoodleEvents.root_xform.origin.is_finite()
			beat += 0.25
		_check("4a2b3: move is parented to helo", NoodleTracks.tracks[move].parent == helo)
		_check("4a2b3: player rides helo", NoodleEvents.player_track == helo)
		_check("4a2b3: transforms stay finite", finite)
		_near("4a2b3: notes stay put relative to the player", worst, 0.0)
	if _load_fixture("198f3", "ExpertPlus.dat"):
		NoodleEvents.reset()
		NoodleEvents.load_events(_fixture_data("198f3", "ExpertPlus.dat"))
		var n := NoodleEvents.stack.size()
		var finite := true
		var beat := 0.0
		while not NoodleEvents.stack.is_empty() and beat < 2000.0:
			var sec := Map.beat_to_seconds(beat)
			NoodleEvents.dispatch_until(beat, sec)
			NoodleEvents.update(sec)
			for t in NoodleTracks.tracks:
				for p in NoodleTracks.P_COUNT:
					if t.has[p] and not (t.vec[p].is_finite() and is_finite(t.flt[p])):
						finite = false
			beat += 1.0
		_check("198f3 (v2): every event dispatched", NoodleEvents.stack.is_empty() and n > 0, "%d events" % n)
		_check("198f3 (v2): values stay finite", finite)
	NoodleEvents.reset()
	MapData.reset()
	NoodleTracks.reset()


func _fixture_data(folder: String, file: String) -> Dictionary:
	var data: Variant = vr.load_json_file(_fixture_dir(folder) + file)
	return data if data is Dictionary else {}
