extends RefCounted
class_name SongModifiers

# Per-song modifiers (0.7.38): Note Speed, Strict cuts and No Fail are chosen on the song panel of
# the main menu and remembered per song, keyed like the high scores (MapInfo.get_key()). A song
# with no saved choice uses the Settings keys (note_speed_percent, strict_cuts, no_fail) as its
# default. Making a song easier than its default lowers the score, the way Beat Saber's modifier
# multipliers do (docs/note-motion-report.md, "Per-song modifiers"):
#
#   score multiplier = 1 + sum of the penalties below, never under MIN_MULTIPLIER
#   modified score   = floor(points x multiplier)  (Beat Saber ScoreModel.GetModifiedScoreFor...)
#
# Accuracy and rank still come from the unmodified points.

const FILEPATH := "user://song_modifiers.json"
# Tests point this elsewhere.
static var file_path := FILEPATH

# Each SPEED_STEP_PERCENT below the map's speed costs SPEED_PENALTY_PER_STEP: 85 % = -0.30, Beat
# Saber's Slower Song (85 % speed, -0.30).
const SPEED_CHOICES: Array[int] = [100, 90, 80, 70, 60, 50]
const SPEED_STEP_PERCENT := 5
const SPEED_PENALTY_PER_STEP := 0.10
const STRICT_OFF_PENALTY := 0.15
# Only when energy actually ran out during the song (Beat Saber since 1.13.2).
const NO_FAIL_PENALTY := 0.50
const MIN_MULTIPLIER := 0.10

# The modifiers of the song being played (set by activate() when a map is loaded).
static var note_speed_percent := 100
static var strict_cuts := true
static var no_fail := true

static var _table: Dictionary = {}
static var _loaded := false


## The defaults for a song with no saved choice: the Settings keys.
static func defaults() -> Dictionary:
	return {
		"note_speed_percent": Settings.note_speed_percent,
		"strict_cuts": Settings.strict_cuts,
		"no_fail": Settings.no_fail,
	}


## The choices for `map_info`: its saved ones, or the defaults.
static func get_for(map_info: MapInfo) -> Dictionary:
	_load()
	var mods := defaults()
	if map_info == null:
		return mods
	var saved: Variant = _table.get(map_info.get_key())
	if saved is Dictionary:
		var d := saved as Dictionary
		if d.has("note_speed_percent"):
			mods["note_speed_percent"] = clamp_speed(int(d["note_speed_percent"]))
		if d.has("strict_cuts"):
			mods["strict_cuts"] = bool(d["strict_cuts"])
		if d.has("no_fail"):
			mods["no_fail"] = bool(d["no_fail"])
	return mods


## Remembers the choices for `map_info` and writes the file.
static func set_for(map_info: MapInfo, mods: Dictionary) -> void:
	if map_info == null:
		return
	_load()
	_table[map_info.get_key()] = {
		"note_speed_percent": clamp_speed(int(mods.get("note_speed_percent", 100))),
		"strict_cuts": bool(mods.get("strict_cuts", true)),
		"no_fail": bool(mods.get("no_fail", true)),
	}
	_save()


## Makes `map_info`'s choices the active ones (Map.load_beatmap, before the motion is configured).
static func activate(map_info: MapInfo) -> void:
	var mods := get_for(map_info)
	note_speed_percent = int(mods["note_speed_percent"])
	strict_cuts = bool(mods["strict_cuts"])
	no_fail = bool(mods["no_fail"])


static func clamp_speed(percent: int) -> int:
	return clampi(percent, SPEED_CHOICES[-1], SPEED_CHOICES[0])


## The score multiplier for these choices; `energy_emptied` is whether energy reached zero during
## the song (No Fail costs nothing otherwise).
static func multiplier(speed_percent: int, strict: bool, no_fail_on: bool, energy_emptied: bool) -> float:
	var m := 1.0
	var steps := float(100 - clamp_speed(speed_percent)) / float(SPEED_STEP_PERCENT)
	m -= steps * SPEED_PENALTY_PER_STEP
	if not strict:
		m -= STRICT_OFF_PENALTY
	if no_fail_on and energy_emptied:
		m -= NO_FAIL_PENALTY
	return maxf(m, MIN_MULTIPLIER)


## The multiplier of the song being played right now.
static func current_multiplier() -> float:
	return multiplier(note_speed_percent, strict_cuts, no_fail, Scoreboard.energy_emptied())


static func modified_score(points: int, mult: float) -> int:
	# Rounded to 1/1000 first so x0.70 x 1000 is 700, not 699 from float error.
	return floori(float(points) * snappedf(mult, 0.001) + 0.0001)


## "x0.70" style.
static func multiplier_text(mult: float) -> String:
	return "x%.2f" % mult


## The modifiers that cost points, for the results screen and the stored record.
static func describe(speed_percent: int, strict: bool, no_fail_on: bool, energy_emptied: bool) -> String:
	var parts := PackedStringArray()
	if speed_percent < 100:
		parts.append("Note Speed %d%%" % speed_percent)
	if not strict:
		parts.append("Strict cuts off")
	if no_fail_on and energy_emptied:
		parts.append("No Fail used")
	if parts.is_empty():
		return ""
	return "%s: score %s" % [", ".join(parts), multiplier_text(multiplier(speed_percent, strict, no_fail_on, energy_emptied))]


## The results screen's modifiers line ("" when nothing lowered the score). Its font has no
## percent sign, so the speed is written "80/100"; it is one line so it stays above the accuracy
## ring, which already shows the (unmodified) accuracy the rank comes from.
static func results_text(speed_percent: int, strict: bool, no_fail_on: bool, energy_emptied: bool) -> String:
	var parts := PackedStringArray()
	if speed_percent < 100:
		parts.append("Note Speed %d/100" % speed_percent)
	if not strict:
		parts.append("Strict cuts off")
	if no_fail_on and energy_emptied:
		parts.append("No Fail used")
	if parts.is_empty():
		return ""
	return "%s: score %s" % [", ".join(parts),
		multiplier_text(multiplier(speed_percent, strict, no_fail_on, energy_emptied))]


## What a stored high-score record carries about the modifiers it was set with.
static func record_fields(points: int, energy_emptied: bool) -> Dictionary:
	return {
		"raw_score": points,
		"multiplier": snappedf(multiplier(note_speed_percent, strict_cuts, no_fail, energy_emptied), 0.001),
		"modifiers": {
			"note_speed_percent": note_speed_percent,
			"strict_cuts": strict_cuts,
			"no_fail": no_fail,
			"no_fail_used": no_fail and energy_emptied,
		},
	}


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_table = {}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_table = parsed


static func _save() -> void:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_warning("SongModifiers: cannot write %s" % file_path)
		return
	file.store_string(JSON.stringify(_table, "  ", true))


## Tests: forget the loaded table (the next read reloads the file).
static func forget_loaded() -> void:
	_loaded = false
