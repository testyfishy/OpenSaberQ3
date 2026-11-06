extends RefCounted
class_name BeatLeaderApi

## Thin, testable layer over https://api.beatleader.xyz (specs/020 FR-004, FR-010).
##
## The read path is two documented calls:
##   1. GET /leaderboard/{hash}/{difficulty}/{mode}  -> the board (its `id`, song, difficulty)
##   2. GET /leaderboard/{id}?page=1&count=N&sortBy=rank&order=desc -> `scores`
## Reads need no auth. Score submission is a different, account/replay-gated path and is out of
## scope. Every failure is a distinct status so the panel can say what actually happened.
##
## `sortBy=rank&order=desc` returns ranks 1..N: the API's `asc` sorts the rank number upward
## (worst first), which is the opposite of what "top scores" means.

const BASE_URL := "https://api.beatleader.xyz"
const USER_AGENT := "OpenSaberQ3/0.6 (in-VR BeatLeader leaderboard)"
const TOP_COUNT := 10

const STATUS_OK := "ok"
const STATUS_NO_HASH := "no_hash"
const STATUS_UNSUPPORTED := "unsupported"
const STATUS_NOT_FOUND := "not_found"
const STATUS_NO_SCORES := "no_scores"
const STATUS_OFFLINE := "offline"

## Local characteristics (Info.dat) -> BeatLeader mode names. A map from another characteristic
## has no leaderboard this panel can show; saying so is better than asking the wrong board.
const MODES := {
	"Standard": "Standard",
	"OneSaber": "OneSaber",
	"NoArrows": "NoArrows",
	"90Degree": "90Degree",
	"NinetyDegree": "90Degree",
	"360Degree": "360Degree",
	"ThreeSixtyDegree": "360Degree",
	"Lightshow": "Lightshow",
	"Lawless": "Lawless",
}

static func mode_for_characteristic(characteristic: String) -> String:
	return String(MODES.get(characteristic, ""))


## The level hash is case-insensitive on BeatLeader; the local sidecar is already lower-case.
static func board_url(hash: String, difficulty: String, mode: String) -> String:
	return "%s/leaderboard/%s/%s/%s" % [BASE_URL, hash.strip_edges().to_lower(), difficulty, mode]


static func scores_url(board_id: String, count: int = TOP_COUNT) -> String:
	return "%s/leaderboard/%s?page=1&count=%d&sortBy=rank&order=desc" % [BASE_URL, board_id, count]


## Parses the board response. `ok=false` + `error` describes a shape problem, not a network state.
static func parse_board(body: PackedByteArray) -> Dictionary:
	return parse_board_value(_parse_json(body))


## Entry point for the panel: the JSON parse itself runs in the panel's (instance) context.
## Observed in the Android export: the API's static path returned null for a valid body; the cause
## is unconfirmed. The tests keep using `parse_board(body)`.
static func parse_board_value(parsed: Variant) -> Dictionary:
	if not (parsed is Dictionary):
		return {"ok": false, "error": "invalid_json"}
	var d := parsed as Dictionary
	var id := _str(d, "id", "")
	if id.is_empty():
		return {"ok": false, "error": "no_board_id"}
	var song := _dict(d, "song", {})
	var diff := _dict(d, "difficulty", {})
	return {
		"ok": true,
		"id": id,
		"song_name": _str(song, "name", ""),
		"song_author": _str(song, "author", ""),
		"difficulty": _str(diff, "difficultyName", ""),
		"mode": _str(diff, "modeName", ""),
	}


## Parses the scores response into display-ready rows (rank order is the API's).
static func parse_scores(body: PackedByteArray) -> Dictionary:
	return parse_scores_value(_parse_json(body))


static func parse_scores_value(parsed: Variant) -> Dictionary:
	if not (parsed is Dictionary):
		return {"ok": false, "error": "invalid_json"}
	var rows: Array[Dictionary] = []
	for entry: Variant in _array(parsed as Dictionary, "scores", []):
		if not (entry is Dictionary):
			continue
		var d := entry as Dictionary
		var player := _dict(d, "player", {})
		rows.append({
			"rank": int(_num(d, "rank", 0.0)),
			"player": _str(player, "name", "Unknown"),
			"score": int(_num(d, "modifiedScore", _num(d, "baseScore", 0.0))),
			"accuracy": _num(d, "accuracy", 0.0),
			"pp": _num(d, "pp", 0.0),
			"modifiers": format_modifiers(_str(d, "modifiers", "")),
		})
	return {"ok": true, "scores": rows}


## Empty modifiers read as "-" so a column is never ambiguous whitespace.
static func format_modifiers(modifiers: String) -> String:
	var m := modifiers.strip_edges()
	return m if not m.is_empty() else "-"


## 0.9813 -> "98.13%"; a value already above 1 is treated as a percentage by the API's own
## convention (some boards return 0-100), so both shapes read correctly.
static func format_accuracy(accuracy: float) -> String:
	var pct := accuracy * 100.0 if accuracy <= 1.5 else accuracy
	return "%.2f%%" % pct


static func format_pp(pp: float) -> String:
	return "%.2f" % pp if pp > 0.0 else "-"


static func label(characteristic: String) -> String:
	var mode := mode_for_characteristic(characteristic)
	return mode if not mode.is_empty() else characteristic


static func _parse_json(body: PackedByteArray) -> Variant:
	var text := body.get_string_from_utf8()
	if text.begins_with("\ufeff"):
		text = text.substr(1)
	# JSON.parse_string matches the proven BeatSaver path. Observed in the Android export: this
	# and JSON.new().parse() returned null for a valid body. Cause unconfirmed.
	return JSON.parse_string(text)


static func _str(d: Dictionary, key: String, default: String) -> String:
	var v: Variant = d.get(key)
	return v as String if v is String else default


static func _num(d: Dictionary, key: String, default: float) -> float:
	var v: Variant = d.get(key)
	return float(v) if (v is float or v is int) else default


static func _dict(d: Dictionary, key: String, default: Dictionary) -> Dictionary:
	var v: Variant = d.get(key)
	@warning_ignore("unsafe_cast")
	return v as Dictionary if v is Dictionary else default


static func _array(d: Dictionary, key: String, default: Array) -> Array:
	var v: Variant = d.get(key)
	@warning_ignore("unsafe_cast")
	return v as Array if v is Array else default
