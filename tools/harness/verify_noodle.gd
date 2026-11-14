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
	_lazy_matches_eager()
	_evaluators_match()
	_apply()
	await _apply_nodes()
	_jumps()
	_support()
	await _zero_scale()
	await _dissolve()
	_v4_custom_data()
	_head_links()
	_static_rotation()
	await _fakes()
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


# A track brought up to date for reading: running animations are stepped when read (lazy), and
# its transform is computed when read.
func _tr(track_name: String) -> NoodleTrack:
	var t := NoodleTracks.tracks[NoodleTracks.find(track_name)]
	NoodleEvents.sync(t)
	NoodleEvents.track_xform(t)
	return t


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
	_check("v3: finished tweens are dropped", E.live_tweens() == 0)
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
				_check("4a2b3: the elevator has risen", NoodleEvents.track_xform(NoodleTracks.tracks[helo]).origin.y > 50.0, "y=%.1f" % NoodleEvents.track_xform(NoodleTracks.tracks[helo]).origin.y)
			var parent := NoodleTracks.tracks[move].parent
			if parent >= 0:
				var seen := NoodleEvents.root_xform * NoodleEvents.track_xform(NoodleTracks.tracks[parent])
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
				NoodleEvents.sync(t)
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


# --- step 4: applying animation to objects --------------------------------------------------
func _obj(cd: Dictionary) -> NoodleObject:
	var o := NoodleObject.from_custom_data(cd)
	NoodleTracks._resolve(o)
	return o


func _apply() -> void:
	var T := NoodleTracks
	var A := NoodleAnim
	var P := NoodlePoints
	# Object animation blocks and the interactable flags, both spellings.
	var v3 := NoodleObject.from_custom_data({"animation": {"offsetPosition": [[0, 0, 0, 0], [2, 0, 0, 1]], "definitePosition": [0, 0, 1], "time": [0.5]}})
	_check("v3 animation block read", v3 != null and v3.animated and v3.anim_mask == ((1 << T.P_OFFSET_POSITION) | (1 << T.P_DEFINITE_POSITION)))
	var v2 := NoodleObject.from_custom_data({"_animation": {"_position": [[0, 0, 0, 0], [2, 0, 0, 1]], "_dissolve": [[0, 0], [1, 1]], "_rotation": [0, 90, 0]}})
	_check("v2 _animation block read", v2 != null and v2.anim_mask == ((1 << T.P_OFFSET_POSITION) | (1 << T.P_DISSOLVE) | (1 << T.P_OFFSET_WORLD_ROTATION)))
	_check("v3 uninteractable", NoodleObject.from_custom_data({"uninteractable": true}).uninteractable)
	_check("v2 _interactable false", NoodleObject.from_custom_data({"_interactable": false}).uninteractable)
	_check("_interactable true is nothing", NoodleObject.from_custom_data({"_interactable": true}) == null)

	T.reset()
	var a := T.get_track(T.index_of("a"))
	var b := T.get_track(T.index_of("b"))
	a.set_vec(T.P_OFFSET_POSITION, Vector3(1, 0, 0))
	b.set_vec(T.P_OFFSET_POSITION, Vector3(0, 1, 0))
	var ab := _obj({"track": ["a", "b"]})
	A.evaluate(ab, 0.5)
	_near3("offsets of several tracks add", A.out_offset, Vector3(1, 1, 0))
	_near3("offset is in lanes", A.compose(Vector3(0, 1, -5), Quaternion.IDENTITY, Vector3.ONE).origin, Vector3(0.6, 1.6, -5))
	# The object's own path replaces its tracks' path for that property; track values still add.
	a.set_path(T.P_OFFSET_POSITION, P.parse([[0, 0, 0, 0], [0, 0, 10, 1]], P.KIND_POSITION))
	var own := _obj({"track": "a", "animation": {"offsetPosition": [[0, 0, 0, 0], [2, 0, 0, 1]]}})
	A.evaluate(own, 0.5)
	_near3("own path replaces the track path", A.out_offset, Vector3(2, 0, 0))
	var only_a := _obj({"track": "a"})
	A.evaluate(only_a, 0.5)
	_near3("track path plus track value", A.out_offset, Vector3(1, 0, -5))
	a.set_path(T.P_OFFSET_POSITION, null)
	# definitePosition keeps x/y, drops the travel, still takes offsetPosition.
	var def := _obj({"track": "a", "animation": {"definitePosition": [[0, 0, 0, 0], [0, 0, 20, 1]]}})
	A.evaluate(def, 0.5)
	_near3("definitePosition", A.compose(Vector3(0.3, 1.0, -5), Quaternion.IDENTITY, Vector3.ONE).origin, Vector3(0.9, 1.0, -6))
	# World rotation turns the position about the player; local rotations multiply.
	var w := T.get_track(T.index_of("w"))
	w.set_quat(T.P_OFFSET_WORLD_ROTATION, P.euler_to_quat(0, 90, 0))
	var wo := _obj({"track": "w"})
	A.evaluate(wo, 0.5)
	var wx := A.compose(Vector3(0, 0, -10), Quaternion.IDENTITY, Vector3.ONE)
	_near3("offsetWorldRotation turns the position", wx.origin, Vector3(10, 0, 0))
	_near3("offsetWorldRotation turns the object", wx.basis * Vector3(0, 0, -1), Vector3(1, 0, 0))
	var l := T.get_track(T.index_of("l"))
	l.set_quat(T.P_LOCAL_ROTATION, P.euler_to_quat(0, 45, 0))
	var lo := _obj({"track": "l", "animation": {"localRotation": [0, 45, 0]}})
	A.evaluate(lo, 0.5)
	var lx := A.compose(Vector3(0, 0, -10), Quaternion.IDENTITY, Vector3.ONE)
	_near3("track and path localRotation multiply", lx.basis * Vector3(0, 0, -1), Vector3(1, 0, 0))
	_near3("localRotation leaves the position", lx.origin, Vector3(0, 0, -10))
	# Scale multiplies across tracks, path and the static scale.
	var s1 := T.get_track(T.index_of("s1"))
	var s2 := T.get_track(T.index_of("s2"))
	s1.set_vec(T.P_SCALE, Vector3(2, 2, 2))
	s2.set_vec(T.P_SCALE, Vector3(1, 3, 1))
	var so := _obj({"track": ["s1", "s2"], "animation": {"scale": [[1, 1, 1, 0], [1, 1, 3, 1]]}})
	A.evaluate(so, 0.5)
	_near3("scale multiplies", A.out_scale, Vector3(2, 6, 4))
	_near3("scale times the static scale", A.compose(Vector3.ZERO, Quaternion.IDENTITY, Vector3(0.5, 0.5, 0.5)).basis.get_scale(), Vector3(1, 3, 2))
	# Dissolve and interactable multiply; the static flag wins.
	a.set_float(T.P_DISSOLVE, 0.5)
	var dz := _obj({"track": "a", "animation": {"dissolve": [[1, 0], [0, 1]]}})
	A.evaluate(dz, 0.5)
	_near("dissolve multiplies", A.out_dissolve, 0.25)
	_near("interactable defaults to 1", A.out_interactable, 1.0)
	var un := _obj({"track": "a", "uninteractable": true})
	A.evaluate(un, 0.5)
	_near("uninteractable object", A.out_interactable, 0.0)
	a.set_float(T.P_INTERACTABLE, 0.0)
	A.evaluate(only_a, 0.5)
	_near("interactable from the track", A.out_interactable, 0.0)
	# A track parent applies on top.
	var par := T.get_track(T.index_of("par"))
	var child := T.get_track(T.index_of("child"))
	child.parent = T.find("par")
	par.is_transform = true
	par.set_vec(T.P_LOCAL_POSITION, Vector3(0, 10, 0))
	var po := _obj({"track": "child"})
	A.evaluate(po, 0.5)
	_near3("parent transform applies", A.compose(Vector3(0, 0, -5), Quaternion.IDENTITY, Vector3.ONE).origin, Vector3(0, 10, -5))
	# Allocation-free per tick: no new objects after thousands of evaluations.
	var before := Performance.get_monitor(Performance.OBJECT_COUNT)
	var sink := Vector3.ZERO
	for i in 3000:
		A.evaluate(so, float(i) / 3000.0)
		sink += A.compose(Vector3(0, 0, -5), Quaternion.IDENTITY, Vector3.ONE).origin
		A.evaluate(lo, 0.25)
		A.evaluate(def, 0.75)
	var after := Performance.get_monitor(Performance.OBJECT_COUNT)
	_check("per-tick evaluation allocates no objects", after == before and sink.is_finite(), "%d -> %d" % [before, after])
	T.reset()


# Real nodes: a note-type Cuttable and a wall, driven through their own tick functions.
func _apply_nodes() -> void:
	var T := NoodleTracks
	T.reset()
	T.active = true
	var c := Cuttable.new()
	add_child(c)
	c.set_physics_process(false)
	c.speed = 10.0
	c.transform = Transform3D(Basis.IDENTITY, Vector3(0.3, 1.1, -10))
	var obj := _obj({"track": "x", "animation": {"interactable": [0], "offsetPosition": [[0, 0, 0, 0], [0, 2, 0, 1]]}})
	c.noodle_spawn(obj, 1.0)
	_near3("spawn pose: lifetime 0, no offset", c.transform.origin, Vector3(0.3, 1.1, -10))
	c._noodle_tick(0.5)
	# 0.5 s at 10 m/s: z = -5, lifetime 0.25, offset 0.5 lane up.
	_near3("travel and path after half a second", c.transform.origin, Vector3(0.3, 1.4, -5))
	_check("non-interactable note is not hittable", not c._n_can_hit)
	c._noodle_tick(0.5)
	_near("lifetime 0.5 at the hit plane", c.transform.origin.z, 0.0)
	var plain := Cuttable.new()
	add_child(plain)
	plain.set_physics_process(false)
	plain.noodle_spawn(null, 1.0)
	_check("plain object takes no Noodle path", plain.noodle == null and plain._n_can_hit)
	c.queue_free()
	plain.queue_free()

	var wall := (load("res://game/Wall/Wall.tscn") as PackedScene).instantiate() as Wall
	add_child(wall)
	wall.set_physics_process(false)
	MapTimer.load_bpm_events({}, 120.0)
	var info := ObstacleInfo.new_v3({"b": 4.0, "d": 1.0, "x": 1, "y": 0, "w": 1, "h": 5,
		"customData": {"track": "x", "uninteractable": true, "animation": {"offsetPosition": [[0, 0, 0, 0], [0, 5, 0, 1]]}}})
	T._resolve(info.noodle)
	wall.speed = 10.0
	wall._half_depth = 0.5
	wall.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.5, -10.5))
	wall._noodle_spawn(info, 1.0)
	_check("animated wall takes the Noodle path", wall.noodle != null)
	var centre := wall._noodle_tick(0.5)
	# Front at -5 after 0.5 s; lifetime (-0.5 + 1) / (2 + 0.5) = 0.2, offset 1 lane up.
	_near("wall travel (centre)", centre, -5.5)
	_near3("wall pose", wall.transform.origin, Vector3(0, 2.1, -5.5))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("uninteractable wall has no collision", wall._wall_shape().disabled)
	var plain_info := ObstacleInfo.new_v3({"b": 4.0, "d": 1.0, "x": 1, "y": 0, "w": 1, "h": 5})
	wall._noodle_spawn(plain_info, 1.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("a respawned plain wall is solid and unscaled", wall.noodle == null and not wall._wall_shape().disabled and wall.scale == Vector3.ONE)
	wall.queue_free()
	MapTimer.reset()
	T.reset()


# --- step 5: per-object jump -------------------------------------------------------------------
# Map: NJS 10 at 120 BPM (0.5 s a beat). Half jump: 4 beats would cover 20 m (> 18), so 2 beats.
func _jumps() -> void:
	MapTimer.load_bpm_events({}, 120.0)
	NoteMotion.configure(10.0, 0.0, 120.0, 7, 1.0)
	_near("map half jump", NoteMotion.spawn_beats(), 2.0)
	_near("map half jump in seconds", NoteMotion.half_jump_seconds(), 1.0)
	# Own NJS 20: 4 beats = 40 m, 2 = 20 m, 1 = 10 m -> 1 beat.
	_near("own NJS shortens the jump", NoteMotion.object_half_jump_beats(20.0, false, 0.0), 1.0)
	_near("own offset lengthens it", NoteMotion.object_half_jump_beats(0.0, true, 1.0), 3.0)
	_near("both", NoteMotion.object_half_jump_beats(20.0, true, 0.5), 1.5)
	_near("never under a quarter beat", NoteMotion.object_half_jump_beats(20.0, true, -5.0), 0.25)

	# Parsed in both spellings, for every object type.
	var n3 := ColorNoteInfo.new_v3({"b": 10.5, "x": 1, "y": 0, "c": 0, "d": 1, "customData": {"noteJumpStartBeatOffset": 1.0, "disableNoteGravity": true}})
	var n2 := ColorNoteInfo.new_v2({"_time": 11.0, "_lineIndex": 1, "_lineLayer": 0, "_type": 1, "_cutDirection": 1, "_customData": {"_noteJumpMovementSpeed": 20.0, "_disableNoteGravity": true}})
	var plain := ColorNoteInfo.new_v3({"b": 10.0, "x": 1, "y": 0, "c": 0, "d": 1})
	_check("v3 note jump offset read", n3.noodle != null and n3.noodle.has_jump_offset and is_equal_approx(n3.noodle.jump_offset, 1.0) and n3.noodle.disable_gravity)
	_check("v2 note jump speed read", n2.noodle != null and is_equal_approx(n2.noodle.njs, 20.0) and n2.noodle.disable_gravity and is_equal_approx(n2.custom_njs, 20.0))
	_check("jump data alone does not animate", not n3.noodle.animated and not n2.noodle.animated)
	var b3 := BombInfo.new_v3({"b": 9.0, "x": 0, "y": 0, "customData": {"noteJumpMovementSpeed": 20.0, "noteJumpStartBeatOffset": 0.5}})
	var b2 := BombInfo.new_v2({"_time": 9.0, "_lineIndex": 0, "_lineLayer": 0, "_type": 3, "_customData": {"_noteJumpStartBeatOffset": 1.0}})
	_check("bombs read NJS and offset (v3, v2)", is_equal_approx(b3.noodle.njs, 20.0) and is_equal_approx(b3.noodle.jump_offset, 0.5) and b2.noodle.has_jump_offset)
	var w3 := ObstacleInfo.new_v3({"b": 9.0, "d": 1.0, "x": 0, "y": 0, "w": 1, "h": 5, "customData": {"noteJumpMovementSpeed": 20.0}})
	var w2 := ObstacleInfo.new_v2({"_time": 9.0, "_duration": 1.0, "_lineIndex": 0, "_type": 0, "_width": 1, "_customData": {"_noteJumpStartBeatOffset": -1.0}})
	_check("walls read NJS and offset (v3, v2)", is_equal_approx(w3.noodle.njs, 20.0) and w2.noodle.has_jump_offset and is_equal_approx(w2.noodle.jump_offset, -1.0))

	# Leads and spawn order. Stacks are spawn order reversed (the next object at the back).
	NoodleTracks.reset()
	MapData.reset()
	MapData.note_stack = [n2, n3, plain]
	MapData.bomb_stack = [b3, b2]
	MapData.obstacle_stack = [w2]
	NoodleTracks.apply_jumps()
	_near("longer own jump spawns earlier", n3.spawn_lead, 1.0)
	_near("shorter own jump spawns later", n2.spawn_lead, -1.0)
	_near("plain note keeps the map lead", plain.spawn_lead, 0.0)
	_near("own half jump in seconds", n3.noodle.half_sec, 1.5)
	_near("bomb with both", b3.spawn_lead, -0.5)
	_near("wall with a negative offset", w2.spawn_lead, -1.0)
	# Spawn beats: n3 10.5 - 1 = 9.5, plain 10, n2 11 + 1 = 12 -> order n3, plain, n2.
	_check("note stack re-sorted by spawn beat", MapData.note_stack[-1] == n3 and MapData.note_stack[-2] == plain and MapData.note_stack[0] == n2)
	# Bombs: b3 at 9.5, b2 at 9 - 1 = 8 -> b2 first.
	_check("bomb stack re-sorted", MapData.bomb_stack[-1] == b2)
	MapData.reset()
	NoodleTracks.reset()
	NoteMotion.reset()
	MapTimer.reset()


# --- step 6: what is reported as missing -------------------------------------------------------
func _support() -> void:
	MapTimer.load_bpm_events({}, 120.0)
	# v3: everything this build plays, nothing reported.
	MapSupport.reset()
	var played := {"version": "3.2.0", "customData": {"customEvents": [
		{"b": 0, "t": "AnimateTrack", "d": {"track": "a", "duration": 1, "offsetPosition": [0, 1, 0], "dissolve": [1]}},
		{"b": 0, "t": "AssignPathAnimation", "d": {"track": "a", "definitePosition": [0, 0, 1]}},
		{"b": 0, "t": "AssignTrackParent", "d": {"childrenTracks": ["a"], "parentTrack": "p"}},
		{"b": 0, "t": "AssignPlayerToTrack", "d": {"track": "p"}},
	]}}
	MapSupport.detect_unsupported(played, null)
	NoodleTracks.begin_load(played)
	Map._finish_noodle(played)
	_check("v3: played features are not reported", MapSupport.unsupported_features.is_empty(), str(MapSupport.unsupported_features))
	# v3: Vivify, Chroma components, bases, head target, time and colour animation are reported.
	MapSupport.reset()
	var missing := {"version": "3.2.0", "customData": {"environment": [], "customEvents": [
		{"b": 0, "t": "InstantiatePrefab", "d": {}},
		{"b": 0, "t": "AnimateComponent", "d": {}},
		{"b": 0, "t": "SomethingNew", "d": {}},
		{"b": 0, "t": "AnimateTrack", "d": {"track": "a", "offsetPosition": [[0, 0, 0, 0, "baseHeadPosition"]], "time": [[0, 0], [1, 1]], "color": [1, 0, 0, 1]}},
		{"b": 0, "t": "AssignPlayerToTrack", "d": {"track": "a", "target": "Head"}},
	]}}
	MapSupport.detect_unsupported(missing, null)
	NoodleTracks.begin_load(missing)
	Map._finish_noodle(missing)
	var f := MapSupport.unsupported_features
	_check("v3: Chroma environment reported", f.has("Chroma environment"), str(f))
	_check("v3: Vivify events reported", f.has("Vivify events"))
	_check("v3: Chroma component events reported", f.has("Chroma component/fog events"))
	_check("v3: unknown event types named", f.has("custom events SomethingNew"))
	_check("v3: point bases reported", f.has("Heck point bases/modifiers"))
	_check("v3: head target reported", f.has("player head/hand tracks"))
	_check("v3: time and colour animation reported", f.has("track time animation") and f.has("Chroma colour animation"))
	_check("no blanket 'Chroma/Noodle animation' any more", not f.has("Chroma/Noodle animation"))
	# v2 spelling.
	MapSupport.reset()
	var v2 := {"_version": "2.2.0", "_customData": {"_customEvents": [
		{"_time": 0, "_type": "AnimateTrack", "_data": {"_track": "a", "_position": [0, 1, 0], "_dissolveArrow": [0], "_color": [1, 1, 1, 1]}},
		{"_time": 0, "_type": "AssignFogTrack", "_data": {"_track": "a"}},
	]}}
	MapSupport.detect_unsupported(v2, null)
	NoodleTracks.begin_load(v2)
	Map._finish_noodle(v2)
	f = MapSupport.unsupported_features
	_check("v2: colour reported", f.has("Chroma colour animation"), str(f))
	_check("v2: _dissolveArrow is played, not reported", not f.has("arrow dissolve"), str(f))
	_check("v2: fog track reported", f.has("Chroma component/fog events"))
	_check("v2: _position is played, not reported", not f.has("animated position"))
	MapSupport.reset()
	NoodleTracks.reset()
	NoodleEvents.reset()
	MapTimer.reset()


# Scale 0 hides an object in many Noodle maps: it must not leave a singular transform.
func _zero_scale() -> void:
	var T := NoodleTracks
	T.reset()
	T.active = true
	var hidden := T.get_track(T.index_of("hide"))
	hidden.set_vec(T.P_SCALE, Vector3.ZERO)
	var c := Cuttable.new()
	add_child(c)
	c.set_physics_process(false)
	c.speed = 10.0
	c.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1, -10))
	c.rotation = Vector3(0, 0, PI / 2.0)
	c.scale = Vector3.ZERO
	c.noodle_spawn(_obj({"track": "hide"}), 1.0)
	_check("static and animated scale 0: invertible note", absf(c.transform.basis.determinant()) > 0.0 and c.transform.affine_inverse().origin.is_finite())
	_check("static rotation kept through a static scale 0", c._n_rot.is_equal_approx(Quaternion.from_euler(Vector3(0, 0, PI / 2.0))))
	c.queue_free()
	var wall := (load("res://game/Wall/Wall.tscn") as PackedScene).instantiate() as Wall
	add_child(wall)
	wall.set_physics_process(false)
	MapTimer.load_bpm_events({}, 120.0)
	var info := ObstacleInfo.new_v3({"b": 4.0, "d": 1.0, "x": 1, "y": 0, "w": 1, "h": 5, "customData": {"track": "hide"}})
	T._resolve(info.noodle)
	wall.speed = 10.0
	wall._half_depth = 0.5
	wall.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.5, -10.5))
	wall._noodle_spawn(info, 1.0)
	wall._noodle_tick(0.1)
	wall._update_inside_fade()
	_check("animated scale 0: invertible wall", absf(wall.transform.basis.determinant()) > 0.0 and wall.transform.affine_inverse().origin.is_finite())
	wall.queue_free()
	await get_tree().physics_frame
	MapTimer.reset()
	T.reset()


# Dissolve is a fade: the value reaches each object's own shader, resets when a pooled object is
# reused, defaults to 1, and never touches the shared materials.
func _dissolve() -> void:
	var T := NoodleTracks
	var A := NoodleAnim
	T.reset()
	T.active = true
	# Evaluation: dissolveArrow defaults to 1 and multiplies like dissolve.
	var none := _obj({"track": "plainx"})
	A.evaluate(none, 0.5)
	_near("dissolve defaults to 1", A.out_dissolve, 1.0)
	_near("dissolveArrow defaults to 1", A.out_dissolve_arrow, 1.0)
	T.get_track(T.index_of("arr")).set_float(T.P_DISSOLVE_ARROW, 0.5)
	var arr := _obj({"track": "arr", "animation": {"dissolveArrow": [[1, 0], [0, 1]]}})
	A.evaluate(arr, 0.5)
	_near("dissolveArrow multiplies", A.out_dissolve_arrow, 0.25)
	_near("dissolveArrow leaves dissolve alone", A.out_dissolve, 1.0)

	var fade := {"track": "f", "animation": {"dissolve": [[0, 0], [1, 1]], "dissolveArrow": [0.5]}}
	var note := (load("res://game/BeepCube/BeepCube.tscn") as PackedScene).instantiate() as BeepCube
	var other := (load("res://game/BeepCube/BeepCube.tscn") as PackedScene).instantiate() as BeepCube
	add_child(note)
	add_child(other)
	note.set_physics_process(false)
	other.set_physics_process(false)
	var param := func(mi: GeometryInstance3D, key: StringName) -> float:
		var v: Variant = mi.get_instance_shader_parameter(key)
		return 1.0 if v == null else float(v)
	_check("a fresh note is at dissolve 1", note._n_dissolve == 1.0 and note._n_dissolve_arrow == 1.0
		and param.call(note.mi, &"note_dissolve") == 1.0 and param.call(note.mi, &"note_dissolve_arrow") == 1.0)
	note.speed = 10.0
	note.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1, -10))
	note.mi.visible = true
	note.noodle_spawn(_obj(fade), 1.0)
	_check("dissolve 0 at lifetime 0: note not drawn", not note.mi.visible)
	note._noodle_tick(0.5)
	_near("note dissolve reaches the shader", param.call(note.mi, &"note_dissolve"), 0.25)
	_near("note dissolveArrow reaches the shader", param.call(note.mi, &"note_dissolve_arrow"), 0.5)
	_check("a partly dissolved note is drawn", note.mi.visible)
	_check("another note keeps dissolve 1", param.call(other.mi, &"note_dissolve") == 1.0 and other._n_dissolve == 1.0)
	_check("the shared note material is not written", note._mat.get_shader_parameter(&"note_dissolve") == null
		and note.mi.material_override == other.mi.material_override)
	note.mi.visible = true
	note.noodle_spawn(null, 1.0)
	_check("a reused note is back at dissolve 1", note._n_dissolve == 1.0 and param.call(note.mi, &"note_dissolve") == 1.0
		and param.call(note.mi, &"note_dissolve_arrow") == 1.0)
	note.queue_free()
	other.queue_free()

	var bomb := (load("res://game/Bomb/Bomb.tscn") as PackedScene).instantiate() as Bomb
	add_child(bomb)
	bomb.set_physics_process(false)
	var body := bomb.get_node(^"BombAnimation/Mesh/Icosphere") as MeshInstance3D
	var rim := bomb.get_node(^"BombAnimation/Mesh/Icosphere2") as MeshInstance3D
	var body_mat := body.material_override
	var rim_mat := rim.material_override
	bomb.speed = 10.0
	bomb.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1, -10))
	bomb.noodle_spawn(_obj(fade), 1.0)
	bomb._noodle_tick(0.5)
	_near("bomb dissolve reaches the shader", param.call(body, &"bomb_dissolve"), 0.25)
	_check("a dissolving bomb uses the dissolve shaders", body.material_override is ShaderMaterial and rim.material_override is ShaderMaterial)
	bomb.noodle_spawn(null, 1.0)
	_check("a reused bomb gets its own materials back", body.material_override == body_mat and rim.material_override == rim_mat and bomb._n_dissolve == 1.0)
	bomb.queue_free()

	var wall := (load("res://game/Wall/Wall.tscn") as PackedScene).instantiate() as Wall
	add_child(wall)
	wall.set_physics_process(false)
	MapTimer.load_bpm_events({}, 120.0)
	var info := ObstacleInfo.new_v3({"b": 4.0, "d": 1.0, "x": 1, "y": 0, "w": 1, "h": 5,
		"customData": {"track": "f", "animation": {"dissolve": [[0, 0], [1, 1]]}}})
	T._resolve(info.noodle)
	var mesh := wall._wall_mesh()
	_check("a fresh wall is at dissolve 1", wall._n_dissolve == 1.0 and param.call(mesh, &"dissolve") == 1.0)
	wall.speed = 10.0
	wall._half_depth = 0.5
	wall.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.5, -10.5))
	wall._noodle_spawn(info, 1.0)
	_check("dissolve 0: wall not drawn", not mesh.visible)
	wall._noodle_tick(0.5)
	# Lifetime (-0.5 + 1) / 2.5 = 0.2.
	_near("wall dissolve reaches the shader", param.call(mesh, &"dissolve"), 0.2)
	_check("a partly dissolved wall is drawn", mesh.visible)
	var plain_info := ObstacleInfo.new_v3({"b": 4.0, "d": 1.0, "x": 1, "y": 0, "w": 1, "h": 5})
	wall._noodle_spawn(plain_info, 1.0)
	_check("a reused wall is back at dissolve 1", wall._n_dissolve == 1.0 and param.call(mesh, &"dissolve") == 1.0)
	# Through the real spawn(): its tail must not show a wall that spawned at dissolve 0.
	var gone := ObstacleInfo.new_v3({"b": 4.0, "d": 1.0, "x": 1, "y": 0, "w": 1, "h": 5,
		"customData": {"track": "f", "animation": {"dissolve": [0]}}})
	T._resolve(gone.noodle)
	wall.spawn(gone, 0.0)
	_check("spawn() at dissolve 0: wall not drawn", not mesh.visible and wall.noodle != null)
	wall.spawn(plain_info, 0.0)
	_check("spawn() of a plain wall: drawn at dissolve 1", mesh.visible and wall._n_dissolve == 1.0)
	wall.queue_free()
	await get_tree().physics_frame
	MapTimer.reset()
	T.reset()


# v4 maps: the expansion to v3 keeps bomb and wall customData, as it does for notes.
func _v4_custom_data() -> void:
	var bombs := MapData._v4_expand_bombs([{"b": 2.0, "i": 0.0, "customData": {"track": "vb"}}], [{"x": 1, "y": 0}])
	_check("v4 bomb keeps customData", bombs.size() == 1 and (bombs[0]["customData"] as Dictionary).get("track") == "vb")
	var walls := MapData._v4_expand_obstacles([{"b": 2.0, "i": 0.0, "customData": {"track": "vw"}}], [{"d": 1, "x": 0, "y": 0, "w": 1, "h": 5}])
	_check("v4 wall keeps customData", walls.size() == 1 and (walls[0]["customData"] as Dictionary).get("track") == "vw")
	var shared := MapData._v4_expand_bombs([{"b": 2.0, "i": 0.0}], [{"x": 1, "y": 0, "customData": {"track": "vd"}}])
	_check("v4 bomb falls back to its data entry's customData", (shared[0]["customData"] as Dictionary).get("track") == "vd")
	var b3 := BombInfo.new_v3(bombs[0])
	var w3 := ObstacleInfo.new_v3(walls[0])
	_check("v4 bomb and wall join their tracks", b3.noodle != null and w3.noodle != null and w3.noodle.track_names[0] == "vw")


# Arcs and chains find a head note that spawned in a different frame (its own jump offset):
# the link is made at load by beat, colour and grid position.
func _head_links() -> void:
	MapData.reset()
	NoodleTracks.reset()
	var head := ColorNoteInfo.new_v3({"b": 4.0, "x": 1.0, "y": 0.0, "c": 0.0, "d": 1.0})
	var tail := ColorNoteInfo.new_v3({"b": 5.0, "x": 2.0, "y": 0.0, "c": 0.0, "d": 1.0})
	var twin := ColorNoteInfo.new_v3({"b": 4.0, "x": 1.0, "y": 0.0, "c": 1.0, "d": 1.0})
	var stray := ColorNoteInfo.new_v3({"b": 7.0, "x": 0.0, "y": 0.0, "c": 0.0, "d": 1.0})
	MapData.note_stack.assign([stray, tail, twin, head])
	var arc := ArcInfo.new_v3({"c": 0.0, "b": 4.0, "x": 1.0, "y": 0.0, "d": 1.0, "tb": 5.0, "tx": 2.0, "ty": 0.0, "tc": 0.0})
	var lone := ArcInfo.new_v3({"c": 0.0, "b": 9.0, "x": 3.0, "y": 2.0, "d": 1.0, "tb": 9.5, "tx": 3.0, "ty": 1.0, "tc": 0.0})
	MapData.arc_stack.assign([lone, arc])
	var chain := ChainInfo.new_v3({"c": 1.0, "b": 4.0, "x": 1.0, "y": 0.0, "d": 1.0, "tb": 4.5, "tx": 1.0, "ty": 2.0, "sc": 4.0, "s": 1.0})
	MapData.chain_stack.assign([chain])
	NoodleTracks.link_heads()
	_check("heads linked", NoodleTracks.heads_linked)
	_check("arc head linked by beat, colour and position", arc.head_info == head)
	_check("arc tail linked", arc.tail_linked and tail.arc_tail_link and not head.arc_tail_link)
	_check("chain head linked to the note of its own colour", chain.head_info == twin)
	_check("an arc with no such note stays unlinked", lone.head_info == null and not lone.tail_linked)
	_check("an unspawned head has no cube", GameStatePlaying.linked_head(head) == null)
	var cube := (load("res://game/BeepCube/BeepCube.tscn") as PackedScene).instantiate() as BeepCube
	add_child(cube)
	cube.set_physics_process(false)
	cube.beat = 4.0
	cube._is_released = false
	head.spawned = cube
	_check("a head spawned in an earlier frame is found", GameStatePlaying.linked_head(head) == cube)
	cube._is_released = true
	_check("a head back in the pool is not used", GameStatePlaying.linked_head(head) == null)
	cube._is_released = false
	cube.beat = 6.0
	_check("a pooled cube reused for another note is not used", GameStatePlaying.linked_head(head) == null)
	cube.queue_free()
	MapData.reset()
	NoodleTracks.reset()
	_check("reset clears the link flag", not NoodleTracks.heads_linked)


# Static Noodle rotation converted from Beat Saber's left-handed frame, against hand-computed
# axes. In Beat Saber +z is away from the player and +x is right; in Godot away is -z.
#  - localRotation [90, 0, 0]: Unity turns up (+y) to away (+z), so Godot up -> (0, 0, -1).
#  - worldRotation [0, 90, 0]: Unity turns right (+x) to toward the player (-z), Godot (0, 0, 1).
#  - both, cut direction 0: up -> away -> right, Godot (1, 0, 0).
func _static_rotation() -> void:
	var local := ColorNoteInfo.new_v3({"b": 1.0, "x": 1.0, "y": 0.0, "c": 0.0, "d": 1.0, "customData": {"localRotation": [90, 0, 0]}})
	_check("static localRotation read", local.has_custom_rotation and local.custom_world == Quaternion.IDENTITY)
	_near3("localRotation x 90: up turns away from the player", Basis(local.custom_local) * Vector3.UP, Vector3(0, 0, -1))
	var world := ColorNoteInfo.new_v3({"b": 1.0, "x": 1.0, "y": 0.0, "c": 0.0, "d": 1.0, "customData": {"worldRotation": [0, 90, 0]}})
	_near3("worldRotation y 90: right turns toward the player", Basis(world.custom_world) * Vector3.RIGHT, Vector3(0, 0, 1))
	var v2 := ColorNoteInfo.new_v2({"_time": 1.0, "_lineIndex": 1.0, "_lineLayer": 0.0, "_type": 0.0, "_cutDirection": 1.0, "_customData": {"_rotation": 90.0}})
	_near3("v2 _rotation as one number is a y turn", Basis(v2.custom_world) * Vector3.RIGHT, Vector3(0, 0, 1))
	var wall := ObstacleInfo.new_v3({"b": 1.0, "d": 1.0, "x": 0.0, "y": 0.0, "w": 1.0, "h": 5.0, "customData": {"localRotation": [0, 0, 30]}})
	_near3("wall z turn keeps its sign", Basis(wall.custom_local) * Vector3.RIGHT, Vector3(cos(PI / 6.0), sin(PI / 6.0), 0))
	# Through BeepCube.spawn(): world * cut direction * local.
	Map.current_difficulty = DifficultyInfo.new("ExpertPlus", 9, "x.dat", 16.0, 0.0, {}, "One")
	var both := ColorNoteInfo.new_v3({"b": 1.0, "x": 1.0, "y": 0.0, "c": 0.0, "d": 1.0, "customData": {"worldRotation": [0, 90, 0], "localRotation": [90, 0, 0]}})
	var cube := (load("res://game/BeepCube/BeepCube.tscn") as PackedScene).instantiate() as BeepCube
	add_child(cube)
	cube.set_physics_process(false)
	var d := 0
	while d < Constants.CUBE_ROTATIONS.size() and absf(Constants.CUBE_ROTATIONS[d]) > 0.0001:
		d += 1
	both.cut_direction = d
	cube.rotation = Vector3(0.7, 0.3, 0)  # a pooled cube's old turn must not survive
	cube.spawn(both, 0.0)
	_near3("spawned note: up -> away -> right", cube.transform.basis.orthonormalized() * Vector3.UP, Vector3(1, 0, 0))
	var plain := ColorNoteInfo.new_v3({"b": 1.0, "x": 1.0, "y": 0.0, "c": 0.0, "d": float(d)})
	cube.spawn(plain, 0.0)
	_near3("a plain note respawned in that cube is upright", cube.transform.basis.orthonormalized() * Vector3.UP, Vector3.UP)
	# Cut direction 3 turns +90 about z. Local x 90 must apply outside it (Heck: world * local *
	# cut): up -> (-1, 0, 0) by the cut, which the x turn leaves alone. The other order would
	# give (0, 0, -1).
	var turned := ColorNoteInfo.new_v3({"b": 1.0, "x": 1.0, "y": 0.0, "c": 0.0, "d": 3.0, "customData": {"localRotation": [90, 0, 0]}})
	cube.spawn(turned, 0.0)
	_near3("local rotation applies outside the cut direction", cube.transform.basis.orthonormalized() * Vector3.UP, Vector3(-1, 0, 0))
	cube.queue_free()
	Map.current_difficulty = null


# Fake (decorative) objects are loaded, drawn and animated, and never hittable or missable.
func _fakes() -> void:
	var T := NoodleTracks
	MapSupport.reset()
	MapData.reset()
	T.reset()
	# v2: `_fake` notes and bombs stay in the stacks, marked.
	var v2 := {"_version": "2.2.0", "_notes": [
		{"_time": 1.0, "_lineIndex": 1.0, "_lineLayer": 0.0, "_type": 0.0, "_cutDirection": 1.0},
		{"_time": 2.0, "_lineIndex": 1.0, "_lineLayer": 0.0, "_type": 1.0, "_cutDirection": 1.0, "_customData": {"_fake": true}},
		{"_time": 3.0, "_lineIndex": 2.0, "_lineLayer": 0.0, "_type": 3.0, "_customData": {"_fake": true}},
	], "_obstacles": [{"_time": 4.0, "_lineIndex": 0.0, "_type": 0.0, "_duration": 1.0, "_width": 1.0, "_customData": {"_fake": true}}]}
	MapData.load_v2(v2)
	var fake_notes := 0
	for n in MapData.note_stack:
		if n.fake:
			fake_notes += 1
	_check("v2: fake note loaded and marked", MapData.note_stack.size() == 2 and fake_notes == 1)
	_check("v2: fake bomb loaded and marked", MapData.bomb_stack.size() == 1 and MapData.bomb_stack[0].fake)
	_check("v2: fake wall kept and marked", MapData.obstacle_stack.size() == 1 and MapData.obstacle_stack[0].fake)
	_check("v2: fakes counted", MapSupport.fake_objects == 3, str(MapSupport.fake_objects))
	# v3: the customData arrays are merged into the stacks in beat order.
	MapSupport.reset()
	MapData.reset()
	var v3 := {"version": "3.2.0", "colorNotes": [{"b": 1.0, "x": 1.0, "y": 0.0, "c": 0.0, "d": 1.0}, {"b": 3.0, "x": 1.0, "y": 0.0, "c": 0.0, "d": 1.0}],
		"customData": {"fakeColorNotes": [{"b": 2.0, "x": 0.0, "y": 2.0, "c": 1.0, "d": 8.0}],
			"fakeBombNotes": [{"b": 2.5, "x": 3.0, "y": 0.0}],
			"fakeObstacles": [{"b": 0.5, "d": 1.0, "x": 0.0, "y": 0.0, "w": 1.0, "h": 5.0}]}}
	MapSupport.detect_unsupported(v3, null)
	MapData.load_v3(v3)
	var beats := PackedFloat32Array()
	for n in MapData.note_stack:
		beats.append(n.beat)
	_check("v3: fake notes merged in beat order (stack reversed)", beats == PackedFloat32Array([3.0, 2.0, 1.0]) and MapData.note_stack[1].fake and not MapData.note_stack[0].fake, str(beats))
	_check("v3: fake bomb and wall loaded", MapData.bomb_stack.size() == 1 and MapData.bomb_stack[0].fake and MapData.obstacle_stack.size() == 1 and MapData.obstacle_stack[0].fake)
	_check("v3: fakes counted", MapSupport.fake_objects == 3)
	MapSupport.reset()
	MapData.reset()
	var plain := {"version": "3.2.0", "colorNotes": [{"b": 3.0, "x": 1.0, "y": 0.0, "c": 0.0, "d": 1.0}, {"b": 1.0, "x": 1.0, "y": 0.0, "c": 0.0, "d": 1.0}]}
	MapData.load_v3(plain)
	_check("v3 without fakes: stack order untouched", MapData.note_stack[0].beat == 1.0 and MapData.note_stack[1].beat == 3.0)
	MapData.reset()

	# Runtime: never hittable, never missed.
	Map.current_difficulty = DifficultyInfo.new("ExpertPlus", 9, "x.dat", 16.0, 0.0, {}, "One")
	var info := ColorNoteInfo.new_v3({"b": 1.0, "x": 1.0, "y": 0.0, "c": 0.0, "d": 1.0, "customData": {"fake": true}})
	_check("v3 per-object fake flag read", info.fake)
	var cube := (load("res://game/BeepCube/BeepCube.tscn") as PackedScene).instantiate() as BeepCube
	add_child(cube)
	cube.set_physics_process(false)
	cube.spawn(info, 0.0)
	_check("fake note is drawn but not interactable", cube.mi.visible and cube.fake and not cube._n_can_hit)
	var anim := _obj({"track": "fk", "animation": {"interactable": [1], "offsetPosition": [[0, 0, 0, 0], [0, 1, 0, 1]]}})
	T.active = true
	cube.speed = 10.0
	cube.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1, -10))
	cube.noodle_spawn(anim, 1.0)
	cube._noodle_tick(0.5)
	_check("fake animated note stays not interactable", cube.noodle != null and not cube._n_can_hit)
	cube.spawn(ColorNoteInfo.new_v3({"b": 1.0, "x": 1.0, "y": 0.0, "c": 0.0, "d": 1.0}), 0.0)
	_check("a real note reusing the cube is interactable", not cube.fake and cube._n_can_hit)
	cube.queue_free()
	var bomb := (load("res://game/Bomb/Bomb.tscn") as PackedScene).instantiate() as Bomb
	add_child(bomb)
	bomb.set_physics_process(false)
	var bi := BombInfo.new_v3({"b": 1.0, "x": 1.0, "y": 0.0, "customData": {"fake": true}})
	bomb.spawn(bi, 0.0)
	_check("fake bomb is drawn but not interactable", bi.fake and bomb.visible and not bomb._n_can_hit)
	bomb.queue_free()
	var wall := (load("res://game/Wall/Wall.tscn") as PackedScene).instantiate() as Wall
	add_child(wall)
	wall.set_physics_process(false)
	MapTimer.load_bpm_events({}, 120.0)
	var wi := ObstacleInfo.new_v3({"b": 4.0, "d": 1.0, "x": 1.0, "y": 0.0, "w": 1.0, "h": 5.0, "customData": {"fake": true}})
	wall.spawn(wi, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("fake wall is drawn with no collision", wall.visible and wall._wall_mesh().visible and wall._wall_shape().disabled)
	wall.spawn(ObstacleInfo.new_v3({"b": 4.0, "d": 1.0, "x": 1.0, "y": 0.0, "w": 1.0, "h": 5.0}), 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("a real wall reusing it is solid", not wall._wall_shape().disabled)
	wall.queue_free()
	await get_tree().physics_frame
	Map.current_difficulty = null
	MapTimer.reset()
	MapSupport.reset()
	T.reset()


# Lazy evaluation reads the same values as stepping everything every tick. Each fixture is run
# twice over the same uneven ticks (with two jumps back in time): once through the 0.7.30 eager
# reference (noodle_eager_ref.gd), once through NoodleEvents. At every third tick a few random
# tracks are read (most tracks stay unread for long stretches, as in the game) and every value,
# path, transform and the player's root are recorded; the two records must be identical.
const EagerRef := preload("res://tools/harness/noodle_eager_ref.gd")
const LIFE := 0.37


func _lazy_matches_eager() -> void:
	var runs: Array = [["synthetic", "", _lazy_synthetic_map()]]
	runs.append_array([["1e6ff", "ExpertPlusLawless.dat"], ["4a2b3", "HardStandard.dat"], ["198f3", "ExpertPlus.dat"], ["23f6b", "ExpertPlusStandard.dat"], ["352d8", _first_dat("352d8")]])
	for fx: Array in runs:
		var synthetic: Dictionary = fx[2] if fx.size() > 2 else {}
		var eager := _record_run(fx[0], fx[1], true, synthetic)
		if eager.is_empty():
			continue
		var lazy := _record_run(fx[0], fx[1], false, synthetic)
		var diffs := 0
		var worst := 0.0
		if lazy.size() == eager.size():
			for i in eager.size():
				if lazy[i] != eager[i]:
					diffs += 1
					worst = maxf(worst, absf(lazy[i] - eager[i]))
		_check("%s: lazy reads equal eager stepping" % fx[0], lazy.size() == eager.size() and diffs == 0,
			"%d values, %d differ, worst %.6f, sizes %d/%d" % [eager.size(), diffs, worst, eager.size(), lazy.size()])
	NoodleEvents.reset()
	EagerRef.reset()
	MapData.reset()
	NoodleTracks.reset()


func _record_run(folder: String, file: String, eager: bool, synthetic: Dictionary = {}) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if not synthetic.is_empty():
		MapData.reset()
		_events_setup(synthetic)
	elif not _load_fixture(folder, file):
		return out
	var events: Array[NoodleEvents.Event] = NoodleEvents.stack.duplicate()
	NoodleEvents.reset()
	EagerRef.reset()
	NoodleEvents.stack = events.duplicate()
	var tracks := NoodleTracks.tracks
	# To the last event or the last object, whichever is first (some maps park end markers far
	# past the song), plus 64 beats so the last animations finish.
	var end_beat := events[0].beat if not events.is_empty() else 0.0
	var last_object := 0.0
	for stack: Array in [MapData.note_stack, MapData.obstacle_stack]:
		if not stack.is_empty() and stack[0] != null:
			last_object = maxf(last_object, stack[0].beat)
	if synthetic.is_empty():
		end_beat = minf(end_beat, last_object)
	end_beat += 64.0
	# The synthetic map has few tracks: one read per sample leaves each unread across several
	# repeats.
	var reads := 1 if not synthetic.is_empty() else 6
	var steps := RandomNumberGenerator.new()
	steps.seed = 7
	var pick := RandomNumberGenerator.new()
	pick.seed = 11
	var beat := 0.0
	var tick := 0
	var t0 := Time.get_ticks_msec()
	while beat < end_beat:
		var sec := Map.beat_to_seconds(beat)
		if eager:
			while not NoodleEvents.stack.is_empty() and NoodleEvents.stack[-1].beat <= beat:
				EagerRef.dispatch(NoodleEvents.stack.pop_back(), sec)
			EagerRef.update(sec)
		else:
			NoodleEvents.dispatch_until(beat, sec)
			NoodleEvents.update(sec)
		if tick % 3 == 0 and not tracks.is_empty():
			var root := EagerRef.root_xform if eager else NoodleEvents.root_xform
			_append_xform(out, root)
			for k in reads:
				_record_track(out, tracks[pick.randi_range(0, tracks.size() - 1)], eager)
		# Every track right after each jump back (what a missed catch-up would get wrong) and
		# now and then.
		if tick == 701 or tick == 1901 or tick % 500 == 250:
			for t in tracks:
				_record_track(out, t, eager)
		tick += 1
		# Mostly game-like ticks, sometimes long gaps; twice the time jumps back 3 beats.
		if tick == 700 or tick == 1900:
			beat -= 3.0
		else:
			beat += [0.03, 0.05, 0.12, 0.4][steps.randi_range(0, 3)]
	print("NOODLE %s %s: %d ticks in %d ms" % [folder, "eager" if eager else "lazy", tick, Time.get_ticks_msec() - t0])
	return out


func _record_track(out: PackedFloat64Array, t: NoodleTrack, eager: bool) -> void:
	if not eager:
		NoodleEvents.sync(t)
	out.append(t.vmask)
	out.append(t.pmask)
	for p in NoodleTracks.P_COUNT:
		out.append(t.has[p])
		if t.has[p]:
			match NoodleTracks.KINDS[p]:
				NoodlePoints.KIND_FLOAT:
					out.append(t.flt[p])
				NoodlePoints.KIND_ROTATION:
					var q := t.quat[p]
					out.append_array([q.x, q.y, q.z, q.w])
				_:
					var v := t.vec[p]
					out.append_array([v.x, v.y, v.z])
		out.append(t.path_blend[p])
		out.append(1.0 if t.path_prev[p] != null else 0.0)
		if t.path_cur[p] != null:
			match NoodleTracks.KINDS[p]:
				NoodlePoints.KIND_FLOAT:
					out.append(t.path_float(p, LIFE))
				NoodlePoints.KIND_ROTATION:
					var q := t.path_quat(p, LIFE)
					out.append_array([q.x, q.y, q.z, q.w])
				_:
					var v := t.path_vec(p, LIFE)
					out.append_array([v.x, v.y, v.z])
	out.append(t.parent)
	if t.is_transform:
		_append_xform(out, t.xform if eager else NoodleEvents.track_xform(t))


func _append_xform(out: PackedFloat64Array, x: Transform3D) -> void:
	for c in 3:
		var col := x.basis[c]
		out.append_array([col.x, col.y, col.z])
	out.append_array([x.origin.x, x.origin.y, x.origin.z])


# The inlined point evaluators give the 0.7.30 values bit for bit: every property path and
# animation block of real fixtures, at many times, including the ends, exact point times and
# outside 0..1.
func _evaluators_match() -> void:
	for fx: Array in [["1e6ff", "ExpertPlusLawless.dat"], ["4a2b3", "HardStandard.dat"], ["198f3", "ExpertPlus.dat"], ["23f6b", "ExpertPlusStandard.dat"]]:
		if not _load_fixture(fx[0], fx[1]):
			continue
		var all: Array[NoodlePoints] = []
		for stack: Array in [MapData.note_stack, MapData.bomb_stack, MapData.obstacle_stack]:
			for info: Variant in stack:
				if info != null and info.noodle != null:
					for pts: NoodlePoints in info.noodle.anim:
						if pts != null:
							all.append(pts)
		for ev in NoodleEvents.stack:
			for pts in ev.points:
				if pts != null:
					all.append(pts)
		var values := 0
		var diffs := 0
		for pts in all:
			var times := PackedFloat32Array([-0.5, 0.0, 1.0, 1.5])
			for k in 41:
				times.append(float(k) / 40.0)
			times.append_array(pts.times)
			for t in times:
				values += 1
				match pts.kind:
					NoodlePoints.KIND_FLOAT:
						if pts.eval_float(t) != EagerRef.eval_float(pts, t):
							diffs += 1
					NoodlePoints.KIND_ROTATION:
						if pts.eval_quat(t) != EagerRef.eval_quat(pts, t):
							diffs += 1
					_:
						if pts.eval_vec3(t) != EagerRef.eval_vec3(pts, t):
							diffs += 1
		_check("%s: inlined evaluators equal 0.7.30" % fx[0], diffs == 0 and values > 0, "%d point lists, %d values, %d differ" % [all.size(), values, diffs])
	MapData.reset()
	NoodleTracks.reset()
	NoodleEvents.reset()


# What the fixtures do not cover: repeats wrapping while their track is unread, a value cleared
# with null, two animations of one property on the same beat, a path blend interrupted by
# another, events with no duration, and a repeating parent the player rides.
func _lazy_synthetic_map() -> Dictionary:
	return {"version": "3.2.0", "customData": {"customEvents": [
		{"b": 2.0, "t": "AnimateTrack", "d": {"track": "r1", "duration": 1.3, "repeat": 5, "easing": "easeInOutQuad", "dissolve": [[0, 0], [1, 1]]}},
		{"b": 5.0, "t": "AnimateTrack", "d": {"track": "r2", "duration": 0.7, "repeat": 7, "offsetPosition": [[0, 0, 0, 0], [1, 2, 3, 0.4], [0, 1, 0, 1]]}},
		{"b": 1.0, "t": "AnimateTrack", "d": {"track": "r3", "duration": 2.1, "repeat": 3, "localRotation": [[0, 0, 0, 0], [90, 45, 10, 1]]}},
		{"b": 10.0, "t": "AnimateTrack", "d": {"track": "c", "duration": 20.0, "offsetPosition": [[0, 0, 0, 0], [5, 0, 0, 1]]}},
		{"b": 15.0, "t": "AnimateTrack", "d": {"track": "c", "offsetPosition": null}},
		{"b": 18.0, "t": "AnimateTrack", "d": {"track": "c", "duration": 0.0, "offsetPosition": [[0, 0, 0, 0], [2, 2, 2, 1]]}},
		{"b": 30.0, "t": "AnimateTrack", "d": {"track": "ow", "duration": 8.0, "scale": [[1, 1, 1, 0], [3, 3, 3, 1]]}},
		{"b": 30.0, "t": "AnimateTrack", "d": {"track": "ow", "duration": 4.0, "scale": [[2, 2, 2, 0], [0.5, 1, 2, 1]]}},
		{"b": 40.0, "t": "AssignPathAnimation", "d": {"track": "pa", "duration": 6.0, "offsetPosition": [[0, 0, 0, 0], [0, 4, 0, 1]]}},
		{"b": 43.0, "t": "AssignPathAnimation", "d": {"track": "pa", "duration": 4.0, "easing": "easeOutCubic", "offsetPosition": [[1, 0, 0, 0], [0, 0, 2, 1]], "dissolve": [[0, 0], [1, 1]]}},
		{"b": 60.0, "t": "AssignPathAnimation", "d": {"track": "pa", "offsetPosition": [[0, 0, 0, 0], [3, 3, 3, 1]]}},
		{"b": 0.0, "t": "AssignTrackParent", "d": {"childrenTracks": ["c", "r2"], "parentTrack": "par"}},
		{"b": 50.0, "t": "AnimateTrack", "d": {"track": "par", "duration": 3.0, "repeat": 2, "position": [[0, 0, 0, 0], [0, 5, 0, 1]], "rotation": [[0, 0, 0, 0], [0, 90, 0, 1]]}},
		{"b": 0.0, "t": "AssignPlayerToTrack", "d": {"track": "par"}},
		{"b": 120.0, "t": "AnimateTrack", "d": {"track": ["r1", "r3"], "duration": 1.0, "repeat": 2, "scale": [[1, 1, 1, 0], [2, 1, 1, 1]]}},
	]}}
