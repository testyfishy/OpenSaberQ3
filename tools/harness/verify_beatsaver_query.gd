extends Node

# UI-4 step 1 gate: BeatSaverQuery owns the query state and its persistence.
#
# Checks the parts a refactor can silently break: the settings keys, the preset bounds, the
# difficulty string round-trip and the sort list that depends on whether a query is present.
#
# Run: godot --headless --path . res://tools/harness/verify_beatsaver_query.tscn

const Query := preload("res://game/ui/BeatSaverPanel/BeatSaverQuery.gd")

var _bad := 0

func _ready() -> void:
	var q := Query.new()

	# Defaults from Settings.
	q.load_from_settings()
	_check(String(q.data["q"]).is_empty(), "q starts empty")
	_check(not String(q.data["order"]).is_empty(), "order has a value")
	_check(int(q.data["duration_index"]) == 0 and int(q.data["nps_index"]) == 0, "preset indexes start at 0")
	_check(float(q.data["min_duration"]) == -1.0 and float(q.data["max_nps"]) == -1.0, "unbounded by default")

	# Relevance needs a query and must never be the starting sort.
	Settings.beatsaver_order = "Relevance"
	q.load_from_settings()
	_check(String(q.data["order"]) != "Relevance", "Relevance is not a startable sort")

	# Out-of-range persisted indexes are clamped into the tables.
	Settings.beatsaver_duration = 99
	Settings.beatsaver_nps = -4
	q.load_from_settings()
	_check(int(q.data["duration_index"]) == Query.DURATION_LABELS.size() - 1, "duration index clamps high")
	_check(int(q.data["nps_index"]) == 0, "nps index clamps low")

	# Pairing a preset index with its bounds.
	q.data["duration_index"] = 2
	q.data["nps_index"] = 3
	q.apply_preset_bounds()
	_check(int(q.data["min_duration"]) == 120 and int(q.data["max_duration"]) == 240, "duration preset 2")
	_check(is_equal_approx(float(q.data["min_nps"]), 7.0) and is_equal_approx(float(q.data["max_nps"]), 10.0), "nps preset 3")

	# Difficulty persistence round-trip; junk entries are ignored.
	_check(q.parse_difficulties("") == [], "empty difficulty text")
	var parsed := q.parse_difficulties("0,4,9")
	_check(parsed == ["Easy", "ExpertPlus"], "difficulty text parses known indexes only")
	q.data["difficulties"] = parsed
	_check(q.difficulties_setting() == "0,4", "difficulty text serialises")

	# Save writes every key the settings schema knows.
	q.data["order"] = "Rating"
	q.save_to_settings()
	_check(Settings.beatsaver_order == "Rating", "saved order")
	_check(Settings.beatsaver_duration == 2, "saved duration index")
	_check(Settings.beatsaver_nps == 3, "saved nps index")
	_check(Settings.beatsaver_difficulties == "0,4", "saved difficulties")

	# Sort list follows the presence of a query.
	q.data["q"] = ""
	_check(q.sort_options().size() == Query.SORT_WITHOUT_QUERY.size(), "no query: no Relevance")
	q.data["q"] = "camellia"
	_check(q.sort_options().has("Relevance"), "query: Relevance offered")

	Settings.restore_defaults()
	print("VERIFYQUERY bad=%d" % _bad)
	get_tree().quit(0 if _bad == 0 else 1)

func _check(condition: bool, what: String) -> void:
	if not condition:
		push_error("VERIFYQUERY " + what)
		_bad += 1
