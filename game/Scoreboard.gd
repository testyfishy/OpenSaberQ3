extends Node

# Scoring, on the standard Beat Saber model (owner decision, 0.7.23).
#
#   A note is worth up to 115 points:
#     70  swing before the cut   (full marks for 100 degrees of swing into the note)
#     30  follow-through after   (full marks for 60 degrees of swing out of it)
#     15  accuracy               (how close the cut passed to the centre of the note)
#   A chain link is worth a flat 20.
#   Multiplier: x1, x2 after 2 hits, x4 after 4 more, x8 after 8 more. A miss, a wrong-colour
#   cut or a bomb drops it one step (x8 -> x4) and restarts the count toward the next step.
#   Accuracy is points / the most that could have been scored so far, where "the most" uses the
#   multiplier a perfect run would have had on each note. That is the percentage BeatLeader and
#   ScoreSaber show, so scores mean the same thing here as there.
#
# What this replaced: 50 timing + 50 angle + 50 centre, doubled by a "travel" bonus, a multiplier
# of 1 + combo/10, and an accuracy figure that compared the running TOTAL with 80 - so after a
# cut or two every hit read as 100 %.
#
# A cut is scored in two steps because the follow-through has not happened yet when the blade
# meets the note: note_cut() settles the combo and the multiplier and hands back a ticket, and
# finish_cut() adds the points once the saber has measured the swing out (see LightSaber).

signal score_changed()
# Energy reached zero. The game decides what that means (nothing, with No Fail on).
signal failed()
signal points_awarded(position: Vector3, amount: String)

# Spike attribution (FR-033): one branch when off, one integer add when on.
const Cost := preload("res://game/scripts/CostProbe.gd")

const NOTE_MAX := 115
const PRE_SWING_MAX := 70
const POST_SWING_MAX := 30
const ACCURACY_MAX := 15
const LINK_POINTS := 20
# Full pre-swing / follow-through marks, in degrees of blade rotation.
const PRE_SWING_FULL_DEG := 100.0
const POST_SWING_FULL_DEG := 60.0
# Distance from the note's centre at which the accuracy part reaches zero.
const ACCURACY_ZERO_M := 0.3
# Hits needed to climb from each multiplier to the next.
const MULTIPLIER_STEPS := {1: 2, 2: 4, 4: 8}
const MULTIPLIER_MAX := 8

# What kind of note was cut. Arcs and chains change which swing a note is judged on:
#   an arc's head has to be held into the arc, so its follow-through is given;
#   an arc's tail arrives along the arc, so its swing in is given;
#   a chain's head is followed by the links, so it has no follow-through and tops out at 85.
const FREE_PRE_SWING := 1
const FREE_POST_SWING := 2
const NO_POST_SWING := 4

# Energy, as in Beat Saber: starts half full, a good cut adds 1 %, a bad cut costs 10 %, a miss or
# a bomb 15 %, and standing in a wall drains 130 % a second.
const ENERGY_START := 0.5
const ENERGY_GOOD_CUT := 0.01
const ENERGY_BAD_CUT := 0.10
const ENERGY_MISS := 0.15
const ENERGY_WALL_PER_SEC := 1.3

var points: int
var combo: int
var multiplier: int
var full_combo: bool
var paused: bool
# The most that could have been scored on everything judged so far.
var max_points: int
# Notes and links hit / missed or mis-cut. Counts, kept for the bot and replay logs.
var right_notes: float
var wrong_notes: float

var energy := ENERGY_START
var _failed := false
var _progress := 0
# The multiplier ladder of a run with no mistakes, used for max_points.
var _ideal_multiplier := 1
var _ideal_progress := 0
var _pending: Dictionary = {}


func restart() -> void:
	points = 0
	multiplier = 1
	combo = 0
	right_notes = 0.0
	wrong_notes = 0.0
	full_combo = true
	max_points = 0
	_progress = 0
	_ideal_multiplier = 1
	_ideal_progress = 0
	_pending = {}
	energy = ENERGY_START
	_failed = false
	score_changed.emit()


func _change_energy(amount: float) -> void:
	energy = clampf(energy + amount, 0.0, 1.0)
	if energy <= 0.0 and not _failed:
		_failed = true
		failed.emit()


## Energy lost over time, for standing in a wall.
func drain(amount: float) -> void:
	_change_energy(-amount)
	score_changed.emit()


## Share of the possible score actually scored, 0..1. 1.0 before anything has been judged.
func accuracy() -> float:
	return float(points) / float(max_points) if max_points > 0 else 1.0


# One more hit on the ladder; returns the multiplier that hit is scored at. The hit that
# completes a step already counts at the higher multiplier.
static func _climb(current: int, progress: int) -> Vector2i:
	if current >= MULTIPLIER_MAX:
		return Vector2i(MULTIPLIER_MAX, 0)
	progress += 1
	if progress >= int(MULTIPLIER_STEPS[current]):
		return Vector2i(current * 2, 0)
	return Vector2i(current, progress)


func _hit() -> void:
	combo += 1
	var step := _climb(multiplier, _progress)
	multiplier = step.x
	_progress = step.y


# Adds `value` (a note's 115 or a link's 20) to the best possible score.
func _count_possible(value: int) -> void:
	if value <= 0:
		return
	var step := _climb(_ideal_multiplier, _ideal_progress)
	_ideal_multiplier = step.x
	_ideal_progress = step.y
	max_points += value * _ideal_multiplier


## A note was cut with the right saber. `pre_swing` is 0..1 of a full swing in,
## `center_distance` the cut's distance from the note centre in metres. `swing_counts` is false
## for a cut that went against the note's arrow: it still hits, but only the accuracy part scores.
## The points are not added yet - take the ticket with take_pending() and pass it to finish_cut().
func note_cut(position: Vector3, pre_swing: float, center_distance: float, swing_counts: bool = true, kind: int = 0) -> void:
	if Cost.enabled: Cost.cuts += 1
	_hit()
	_count_possible(NOTE_MAX - POST_SWING_MAX if (kind & NO_POST_SWING) != 0 else NOTE_MAX)
	right_notes += 1.0
	_change_energy(ENERGY_GOOD_CUT)
	if (kind & FREE_PRE_SWING) != 0:
		pre_swing = 1.0
	var pre := roundi(PRE_SWING_MAX * clampf(pre_swing, 0.0, 1.0)) if swing_counts else 0
	var acc := roundi(ACCURACY_MAX * (1.0 - clampf(absf(center_distance) / ACCURACY_ZERO_M, 0.0, 1.0)))
	# A second cut in the same tick must not lose the first one's ticket.
	if not _pending.is_empty():
		finish_cut(_pending, 0.0)
	_pending = {"position": position, "base": pre + acc, "multiplier": multiplier, "swing_counts": swing_counts,
		"kind": kind}
	score_changed.emit()


## The ticket for the note_cut() that just happened, or an empty dictionary.
func take_pending() -> Dictionary:
	var ticket := _pending
	_pending = {}
	return ticket


## Adds a cut's points. `post_swing` is 0..1 of a full follow-through.
func finish_cut(ticket: Dictionary, post_swing: float) -> void:
	if ticket.is_empty():
		return
	var kind := int(ticket.get("kind", 0))
	if (kind & FREE_POST_SWING) != 0:
		post_swing = 1.0
	var post := roundi(POST_SWING_MAX * clampf(post_swing, 0.0, 1.0)) if bool(ticket.get("swing_counts", true)) else 0
	if (kind & NO_POST_SWING) != 0:
		post = 0
	var amount := int(ticket["base"]) + post
	points += amount * int(ticket["multiplier"])
	points_awarded.emit(ticket["position"], str(amount))
	score_changed.emit()


func chain_link_cut(position: Vector3) -> void:
	if Cost.enabled: Cost.cuts += 1
	_hit()
	_count_possible(LINK_POINTS)
	right_notes += 1.0
	_change_energy(ENERGY_GOOD_CUT * 0.2)
	points += LINK_POINTS * multiplier
	points_awarded.emit(position, str(LINK_POINTS))
	score_changed.emit()


## A miss. `possible` is what the missed object was worth (115 for a note, 20 for a link, 0 for
## anything that was never worth points, such as hitting a bomb).
func reset_combo(possible: int = NOTE_MAX, energy_loss: float = ENERGY_MISS) -> void:
	_count_possible(possible)
	_change_energy(-energy_loss)
	@warning_ignore("integer_division")
	multiplier = maxi(1, multiplier / 2)
	_progress = 0
	combo = 0
	wrong_notes += 1.0
	full_combo = false
	score_changed.emit()


## A cut with the wrong saber, or a bomb. See reset_combo for `possible`.
func bad_cut(position: Vector3, possible: int = NOTE_MAX, energy_loss: float = ENERGY_BAD_CUT) -> void:
	reset_combo(possible, energy_loss)
	points_awarded.emit(position, "x")
