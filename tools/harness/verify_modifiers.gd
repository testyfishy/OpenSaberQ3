extends Node

# Per-song modifiers harness (SongModifiers, docs/note-motion-report.md "Per-song modifiers").
# Headless. Expected values are literals worked out by hand. Each check prints `MODS2 ok` /
# `MODS2 FAIL`; the last line is the verdict (check.ps1 matches "MODIFIERS PASS").
#
# Run: godot --headless --path . res://tools/harness/verify_modifiers.tscn

const MapTimer := preload("res://game/scripts/MapTimer.gd")
const TEST_MODS := "user://song_modifiers_harness.json"
const TEST_SCORES := "user://highscores_harness.json"

var _fails := 0
var _checks := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("MODS2 %s %s%s" % ["ok  " if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _near(label: String, got: float, want: float) -> void:
	_check(label, absf(got - want) < 0.0005, "got %.4f want %.4f" % [got, want])


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var M := SongModifiers
	# Multiplier arithmetic: 1 + penalties, never under 0.10.
	_near("map speed, strict, No Fail unused: x1.00", M.multiplier(100, true, true, false), 1.0)
	_near("90 %: x0.80", M.multiplier(90, true, false, false), 0.8)
	_near("85 % (Beat Saber's Slower Song): x0.70", M.multiplier(85, true, false, false), 0.7)
	_near("50 %: 1 - 1.00 floors at x0.10", M.multiplier(50, true, false, false), 0.1)
	_near("strict cuts off: x0.85", M.multiplier(100, false, false, false), 0.85)
	_near("90 % and strict off: x0.65", M.multiplier(90, false, false, false), 0.65)
	_near("No Fail on, energy never ran out: no penalty", M.multiplier(100, true, true, false), 1.0)
	_near("No Fail on, energy ran out: x0.50", M.multiplier(100, true, true, true), 0.5)
	_near("No Fail off: never a No Fail penalty", M.multiplier(100, true, false, true), 1.0)
	_near("80 %, strict off, No Fail used: floors at x0.10", M.multiplier(80, false, true, true), 0.1)
	_check("modified score floor(1000 x 0.70) = 700", M.modified_score(1000, 0.7) == 700, str(M.modified_score(1000, 0.7)))
	_check("modified score floor(12345 x 0.85) = 10493", M.modified_score(12345, 0.85) == 10493, str(M.modified_score(12345, 0.85)))
	_check("x1.00 leaves the score", M.modified_score(98765, 1.0) == 98765)

	# Results text.
	_check("results text, nothing lowered: empty", M.describe(100, true, true, false) == "")
	var text := M.describe(80, false, true, true)
	_check("results text names each modifier and the multiplier",
		text == "Note Speed 80%, Strict cuts off, No Fail used: score x0.10", text)
	var rt := M.results_text(80, false, true, true)
	_check("results screen line: the modifiers and the score multiplier",
		rt == "Note Speed 80/100, Strict cuts off, No Fail used: score x0.10", rt)
	_check("results screen, nothing lowered: no lines", M.results_text(100, true, true, false) == "")
	_check("results text for 90 %", M.describe(90, true, true, false) == "Note Speed 90%: score x0.80", M.describe(90, true, true, false))

	# Per-song persistence round trip, in a file of its own.
	var real_path := ProjectSettings.globalize_path(SongModifiers.FILEPATH)
	var real_before := FileAccess.get_file_as_string(real_path) if FileAccess.file_exists(real_path) else "<none>"
	SongModifiers.file_path = TEST_MODS
	_check("the harness writes its own file, not the player's", SongModifiers.file_path == TEST_MODS)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_MODS))
	M.forget_loaded()
	var a := MapInfo.new("3.0.0", "Song A", "", "Artist", "Mapper", 120.0, 0.0, 0.0, "", "", "", 0.0, {}, "", [])
	var b := MapInfo.new("3.0.0", "Song B", "", "Artist", "Mapper", 120.0, 0.0, 0.0, "", "", "", 0.0, {}, "", [])
	var d := M.get_for(a)
	_check("an unsaved song uses the Settings defaults",
		int(d["note_speed_percent"]) == Settings.note_speed_percent and bool(d["strict_cuts"]) == Settings.strict_cuts
		and bool(d["no_fail"]) == Settings.no_fail, str(d))
	M.set_for(a, {"note_speed_percent": 70, "strict_cuts": false, "no_fail": false})
	M.forget_loaded()
	var back := M.get_for(a)
	_check("saved choices come back after a reload",
		int(back["note_speed_percent"]) == 70 and not bool(back["strict_cuts"]) and not bool(back["no_fail"]), str(back))
	_check("another song keeps the defaults", int(M.get_for(b)["note_speed_percent"]) == Settings.note_speed_percent)
	M.activate(a)
	_check("activate() makes the song's choices current",
		M.note_speed_percent == 70 and not M.strict_cuts and not M.no_fail)
	M.set_for(a, {"note_speed_percent": 42})
	_check("an out-of-range speed is clamped", int(M.get_for(a)["note_speed_percent"]) == 50)

	# No Fail penalty only after energy ran out during the song.
	SongModifiers.note_speed_percent = 100
	SongModifiers.strict_cuts = true
	SongModifiers.no_fail = true
	Scoreboard.restart()
	_near("No Fail, full energy: x1.00", M.current_multiplier(), 1.0)
	Scoreboard.drain(1.0)
	_check("energy ran out", Scoreboard.energy_emptied())
	_near("No Fail, after energy ran out: x0.50", M.current_multiplier(), 0.5)
	Scoreboard.restart()
	_check("a new song starts with no penalty", not Scoreboard.energy_emptied())

	# The stored record: modified score plus what it was set with; an old record is unmodified.
	var table := HighscoreTable.new()
	table.file_path = TEST_SCORES
	table.clear_table()
	SongModifiers.note_speed_percent = 85
	var rec := table.add_highscore(a, 7, "P", M.modified_score(1000, M.multiplier(85, true, true, false)), "id",
		M.record_fields(1000, false))
	_check("stored record keeps the modified score and the raw one",
		int(rec.get("score", 0)) == 700 and int(rec.get("raw_score", 0)) == 1000, str(rec))
	_check("stored record names its modifiers",
		is_equal_approx(float(rec.get("multiplier", 0.0)), 0.7) and int(rec["modifiers"]["note_speed_percent"]) == 85
		and bool(rec["modifiers"]["no_fail"]) and not bool(rec["modifiers"]["no_fail_used"]), str(rec.get("modifiers")))
	var moved := table.move_record(a, 7, rec, "Q", "id2")
	_check("moving a record to another profile keeps its modifiers", moved.has("modifiers") and int(moved.get("raw_score", 0)) == 1000)
	var old := {"score": 5, "player_name": "Old", "epoch_time": 1, "user_id": ""}
	_check("a record from before 0.7.38 reads as unmodified", float(old.get("multiplier", 1.0)) == 1.0)
	table.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SCORES))

	# Note Speed keeps the map's spawn distance and jump start (ODDS&ENDS Hard: NJS 14, offset
	# -1.714, 192 BPM: half jump 2.286 beats = 0.714 s = 10.0 m).
	MapTimer.load_bpm_events({}, 192.0)
	NoteMotion.configure(14.0, -1.714, 192.0, 5, 1.0)
	var full_dist := NoteMotion.spawn_distance()
	var full_half := NoteMotion.half_jump_seconds()
	NoteMotion.configure(14.0, -1.714, 192.0, 5, 0.5)
	_near("50 %: same spawn distance (10.0 m)", NoteMotion.spawn_distance(), full_dist)
	_near("50 %: NJS 7", NoteMotion.njs(), 7.0)
	_near("50 %: the note is seen twice as long (1.429 s)", NoteMotion.half_jump_seconds(), full_half * 2.0)
	_near("50 %: the fly-in is still 0.5 s from 100 m beyond", NoteMotion.fly_in_seconds(), 0.5)
	_near("50 %: an object at the map's NJS with its own offset stretches too",
		NoteMotion.object_half_jump_beats(0.0, true, -1.714), NoteMotion.spawn_beats())
	_near("50 %: an object with its own NJS keeps its jump",
		NoteMotion.object_half_jump_beats(20.0, false, 0.0), NoteMotion.half_jump_beats(20.0, -1.714, 192.0))
	NoteMotion.reset()
	MapTimer.reset()

	# One place: the Settings panel no longer has these rows.
	var rows: Array = load("res://game/settings_Panel.gd").TAB_ROWS[0]
	_check("Settings > Gameplay has no Note Speed / Strict / No Fail rows",
		not rows.has("NoteSpeedRow") and not rows.has("strict_cuts") and not rows.has("no_fail"), str(rows))

	SongModifiers.file_path = SongModifiers.FILEPATH
	var real_after := FileAccess.get_file_as_string(real_path) if FileAccess.file_exists(real_path) else "<none>"
	_check("the player's song_modifiers.json is untouched", real_after == real_before)
	M.forget_loaded()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_MODS))
	var verdict := "MODIFIERS PASS" if _fails == 0 else "MODIFIERS FAIL"
	print("%s (%d checks, %d failed)" % [verdict, _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
