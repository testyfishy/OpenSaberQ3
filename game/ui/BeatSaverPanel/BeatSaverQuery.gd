extends RefCounted

# The BeatSaver browser's query state and its persistence (UI-4 step 1).
#
# Pure data: no nodes, no HTTP, no UI. The panel owns the debounce timer and calls
# `save_to_settings()`; `BeatSaverApi` owns URL building. Keeping this here means the filter
# tables, the preset bounds and the settings keys are one unit, and a test can load/save them
# without a scene.

const API := preload("res://game/ui/BeatSaverPanel/BeatSaverApi.gd")

const DURATION_LABELS: Array[String] = ["Any length", "<2 min", "2-4 min", "4+ min"]
const DURATION_MIN: Array[int] = [-1, -1, 120, 241]
const DURATION_MAX: Array[int] = [-1, 119, 240, -1]
const NPS_LABELS: Array[String] = ["Any NPS", "Slow <4", "4-7 NPS", "7-10 NPS", "10+ NPS"]
const NPS_MIN: Array[float] = [-1.0, -1.0, 4.0, 7.0, 10.0]
const NPS_MAX: Array[float] = [-1.0, 4.0, 7.0, 10.0, -1.0]
const SORT_WITH_QUERY: Array[String] = ["Latest", "Rating", "Curated", "Relevance"]
const SORT_WITHOUT_QUERY: Array[String] = ["Latest", "Rating", "Curated"]

var data: Dictionary = {}

# The shape `BeatSaverApi.build_search_url()` consumes. `q` is deliberately not persisted.
func load_from_settings() -> void:
	var order := String(Settings.beatsaver_order)
	if not API.ORDERS.has(order) or order == "Relevance":
		# Relevance needs a query; never start in it (FR-003).
		order = API.DEFAULT_ORDER
	data = {
		"q": "",
		"order": order,
		"curated": bool(Settings.beatsaver_curated),
		"verified": bool(Settings.beatsaver_verified),
		"ranked": bool(Settings.beatsaver_ranked),
		"playable_only": bool(Settings.beatsaver_playable_only),
		"duration_index": clampi(int(Settings.beatsaver_duration), 0, DURATION_LABELS.size() - 1),
		"nps_index": clampi(int(Settings.beatsaver_nps), 0, NPS_LABELS.size() - 1),
		"difficulties": parse_difficulties(String(Settings.beatsaver_difficulties)),
		"min_duration": -1,
		"max_duration": -1,
		"min_nps": -1.0,
		"max_nps": -1.0,
	}
	apply_preset_bounds()

# The min/max bounds are derived from the two preset indexes, so they can never disagree with the
# label the player sees.
func apply_preset_bounds() -> void:
	var duration_index: int = clampi(int(data.get("duration_index", 0)), 0, DURATION_LABELS.size() - 1)
	var nps_index: int = clampi(int(data.get("nps_index", 0)), 0, NPS_LABELS.size() - 1)
	data["min_duration"] = DURATION_MIN[duration_index]
	data["max_duration"] = DURATION_MAX[duration_index]
	data["min_nps"] = NPS_MIN[nps_index]
	data["max_nps"] = NPS_MAX[nps_index]

func parse_difficulties(text: String) -> Array:
	var out: Array = []
	if text.strip_edges().is_empty():
		return out
	for part in text.split(",", false):
		var index := int(part)
		if index >= 0 and index < API.DIFFICULTIES.size():
			out.append(API.DIFFICULTIES[index])
	return out

func difficulties_setting() -> String:
	var picked: Array = data.get("difficulties", [])
	var parts: PackedStringArray = PackedStringArray()
	for i in API.DIFFICULTIES.size():
		if picked.has(API.DIFFICULTIES[i]):
			parts.append(str(i))
	return ",".join(parts)

# Writes the persisted part of the query into Settings. The caller owns coalescing the file write.
func save_to_settings() -> void:
	Settings.beatsaver_order = String(data.get("order", API.DEFAULT_ORDER))
	Settings.beatsaver_curated = bool(data.get("curated", false))
	Settings.beatsaver_verified = bool(data.get("verified", false))
	Settings.beatsaver_ranked = bool(data.get("ranked", false))
	Settings.beatsaver_playable_only = bool(data.get("playable_only", false))
	Settings.beatsaver_duration = int(data.get("duration_index", 0))
	Settings.beatsaver_nps = int(data.get("nps_index", 0))
	Settings.beatsaver_difficulties = difficulties_setting()

func sort_options() -> Array:
	if String(data.get("q", "")).strip_edges().is_empty():
		return SORT_WITHOUT_QUERY
	return SORT_WITH_QUERY
