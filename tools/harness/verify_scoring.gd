extends Node

# Scoring harness (standard model, 0.7.23). Headless.
#
# Part 1 drives the Scoreboard directly: point values, the multiplier ladder, what a miss, a
# bomb and a wrong-way cut do, and the accuracy percentage.
# Part 2 swings a real LightSaber by rotating its controller node and checks that the swing in
# and the follow-through are measured in degrees, as the model defines them.
#
# Run: godot --headless --path . res://tools/harness/verify_scoring.tscn
# Prints one SCORING line per check and `SCORING PASS` / `SCORING FAIL`.

const SABER_SCENE := preload("res://game/LightSaber.tscn")
const ControllerScript := preload("res://game/scripts/BeepSaberController.gd")

var _fails := 0
var _controller: BeepSaberController
var _saber: LightSaber
# Degrees per physics tick, and how many ticks are left of the current swing.
var _spin_deg := 0.0
var _spin_ticks := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
	print("SCORING %s %s%s" % ["ok  " if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _ready() -> void:
	_run.call_deferred()


func _physics_process(_dt: float) -> void:
	if _spin_ticks > 0 and _controller != null:
		# About an axis square to the blade, so the blade sweeps exactly the angle asked for.
		_controller.global_rotate(_saber.global_transform.basis.x.normalized(), deg_to_rad(_spin_deg))
		_spin_ticks -= 1


func _perfect_note() -> void:
	Scoreboard.note_cut(Vector3.ZERO, 1.0, 0.0)
	Scoreboard.finish_cut(Scoreboard.take_pending(), 1.0)


func _run() -> void:
	_scoreboard()
	await _swing()
	Scoreboard.restart()
	print("SCORING ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _scoreboard() -> void:
	# --- a perfect run: the ladder and the totals -------------------------------------------
	Scoreboard.restart()
	_check("nothing judged yet reads as 100 %", is_equal_approx(Scoreboard.accuracy(), 1.0))
	var ladder: Array[int] = []
	for i in 20:
		_perfect_note()
		ladder.append(Scoreboard.multiplier)
	var want_ladder: Array[int] = [1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 4, 4, 4, 8, 8, 8, 8, 8, 8, 8]
	_check("multiplier ladder: x1, x2 after 2 hits, x4 after 4 more, x8 after 8 more", ladder == want_ladder, str(ladder))
	var want := 115 * (1 + 4 * 2 + 8 * 4 + 7 * 8)
	_check("20 perfect notes score 115 each on that ladder", Scoreboard.points == want, "%d, want %d" % [Scoreboard.points, want])
	_check("a perfect run is 100 % and a full combo",
		Scoreboard.max_points == want and is_equal_approx(Scoreboard.accuracy(), 1.0) and Scoreboard.full_combo)

	# --- a miss -----------------------------------------------------------------------------
	var before := Scoreboard.points
	var max_before := Scoreboard.max_points
	Scoreboard.reset_combo()
	_check("a miss drops x8 to x4 and ends the combo", Scoreboard.multiplier == 4 and Scoreboard.combo == 0 and not Scoreboard.full_combo)
	_check("a missed note still counts toward the best possible score",
		Scoreboard.points == before and Scoreboard.max_points == max_before + 115 * 8)
	_check("accuracy falls below 100 % after a miss", Scoreboard.accuracy() < 1.0)
	for i in 7:
		_perfect_note()
	_check("seven hits later it is still x4", Scoreboard.multiplier == 4)
	_perfect_note()
	_check("the eighth hit is back at x8", Scoreboard.multiplier == 8)

	# --- a bomb -----------------------------------------------------------------------------
	max_before = Scoreboard.max_points
	Scoreboard.bad_cut(Vector3.ZERO, 0)
	_check("a bomb drops the multiplier but adds nothing to the best possible score",
		Scoreboard.multiplier == 4 and Scoreboard.max_points == max_before)

	# --- the three parts of a note ------------------------------------------------------------
	Scoreboard.restart()
	Scoreboard.note_cut(Vector3.ZERO, 0.5, 0.0)
	Scoreboard.finish_cut(Scoreboard.take_pending(), 0.5)
	_check("half a swing in and half a follow-through: 35 + 15 + 15", Scoreboard.points == 65, str(Scoreboard.points))
	Scoreboard.restart()
	Scoreboard.note_cut(Vector3.ZERO, 1.0, 0.15)
	Scoreboard.finish_cut(Scoreboard.take_pending(), 1.0)
	_check("15 cm off centre keeps half the accuracy part: 70 + 30 + 8", Scoreboard.points == 108, str(Scoreboard.points))
	Scoreboard.restart()
	Scoreboard.note_cut(Vector3.ZERO, 1.0, 0.0, false)
	Scoreboard.finish_cut(Scoreboard.take_pending(), 1.0)
	_check("a cut against the arrow hits but earns the accuracy part only", Scoreboard.points == 15 and Scoreboard.combo == 1, str(Scoreboard.points))
	_check("... and still counts as a 115-point note", Scoreboard.max_points == 115)

	# --- chain links --------------------------------------------------------------------------
	Scoreboard.restart()
	Scoreboard.chain_link_cut(Vector3.ZERO)
	Scoreboard.chain_link_cut(Vector3.ZERO)
	_check("chain links are 20 each and climb the ladder", Scoreboard.points == 20 + 40 and Scoreboard.max_points == 60, str(Scoreboard.points))


func _swing_and_wait(total_deg: float, per_tick_deg: float) -> void:
	_spin_deg = per_tick_deg
	_spin_ticks = int(round(absf(total_deg / per_tick_deg)))
	while _spin_ticks > 0:
		await get_tree().physics_frame
	await get_tree().physics_frame


func _rest(ticks: int) -> void:
	for i in ticks:
		await get_tree().physics_frame


func _swing() -> void:
	var player := AudioStreamPlayer.new()
	add_child(player)
	_controller = ControllerScript.new() as BeepSaberController
	_controller.tracker = &"left_hand"
	add_child(_controller)
	_saber = SABER_SCENE.instantiate() as LightSaber
	_controller.add_child(_saber)
	_saber.song_player_ref = player
	await _rest(4)
	_saber._show()
	# The Show animation extends the blade over a second.
	await _rest(200)
	_check("premise: the blade is out", _saber.is_extended())
	_check("a blade at rest has no swing", is_zero_approx(_saber.pre_swing_ratio()))

	await _swing_and_wait(120.0, 4.0)
	_check("120 degrees of swing is a full pre-swing", _saber.pre_swing_ratio() > 0.99, "%.2f" % _saber.pre_swing_ratio())

	await _rest(12)
	await _swing_and_wait(50.0, 2.5)
	var half := _saber.pre_swing_ratio()
	_check("50 degrees of swing is half a pre-swing", absf(half - 0.5) < 0.04, "%.2f" % half)

	await _rest(12)
	await _swing_and_wait(60.0, 3.0)
	await _swing_and_wait(20.0, -2.0)
	var back := _saber.pre_swing_ratio()
	_check("only the swing since the last reversal counts (20 degrees back)", absf(back - 0.2) < 0.04, "%.2f" % back)

	# Follow-through: cut in the middle of a swing, carry on for 30 degrees, then stop.
	await _rest(12)
	_saber.finish_swings()
	Scoreboard.restart()
	await _swing_and_wait(100.0, 4.0)
	var pre := _saber.pre_swing_ratio()
	Scoreboard.note_cut(Vector3.ZERO, pre, 0.0)
	_saber._follow.append({"ticket": Scoreboard.take_pending(), "axis": _saber._swing_axis(), "angle": 0.0, "age": 0.0})
	_check("the points wait for the follow-through", Scoreboard.points == 0)
	await _swing_and_wait(30.0, 3.0)
	await _rest(70)
	_check("30 degrees of follow-through is half of it: 70 + 15 + 15", Scoreboard.points == 100, str(Scoreboard.points))

	# A full follow-through settles as soon as it reaches 60 degrees.
	await _rest(12)
	_saber.finish_swings()
	Scoreboard.restart()
	await _swing_and_wait(100.0, 4.0)
	Scoreboard.note_cut(Vector3.ZERO, _saber.pre_swing_ratio(), 0.0)
	_saber._follow.append({"ticket": Scoreboard.take_pending(), "axis": _saber._swing_axis(), "angle": 0.0, "age": 0.0})
	await _swing_and_wait(64.0, 4.0)
	_check("a 60 degree follow-through completes the note: 115", Scoreboard.points == 115, str(Scoreboard.points))

	# Pausing or ending the song settles what is still being measured.
	await _rest(12)
	_saber.finish_swings()
	Scoreboard.restart()
	await _swing_and_wait(100.0, 4.0)
	Scoreboard.note_cut(Vector3.ZERO, 1.0, 0.0)
	_saber._follow.append({"ticket": Scoreboard.take_pending(), "axis": _saber._swing_axis(), "angle": 0.0, "age": 0.0})
	_saber.finish_swings()
	_check("ending the song settles a cut still in flight", Scoreboard.points == 85, str(Scoreboard.points))
