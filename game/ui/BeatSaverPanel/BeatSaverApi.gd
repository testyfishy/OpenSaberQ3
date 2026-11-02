extends RefCounted
class_name BeatSaverApi

## Thin, testable layer over https://api.beatsaver.com.
##
## The contract is `specs/003-beatsaver-api-research/beatsaver-api-reference.md`; every parameter
## name, enum and field below is taken from it and not re-derived here. This script has no
## dependencies on autoloads so it can be unit tested with `--script` (see
## `tools/tests/beatsaver_browser_test.gd`).
##
## Callers reach the record types through the factory/parse functions at the bottom (`parse_search`,
## `parse_map`, `make_map_record`) rather than through the inner class names, so the file also
## compiles in a `--script` run where the editor's global class cache has not been built.

const BASE_URL := "https://api.beatsaver.com"
const PAGE_SIZE := 20
const USER_AGENT := "OpenSaberQ3/0.2 (in-VR BeatSaver browser)"

## `order` enum (reference 3.1). An unknown value returns HTTP 500, so it is validated here.
const ORDERS: Array[String] = ["Latest", "Relevance", "Rating", "Curated"]
const DEFAULT_ORDER := "Latest"

## Difficulty enum order used by the pills, the chip set and the client-side filter (FR-005).
const DIFFICULTIES: Array[String] = ["Easy", "Normal", "Hard", "Expert", "ExpertPlus"]
const DIFFICULTY_SHORT: Array[String] = ["E", "N", "H", "Ex", "Ex+"]
const STANDARD := "Standard"


## JSON field accessors. Null fields are omitted from the API, so every field is optional.
class JsonBase extends RefCounted:
	const STANDARD := "Standard"

	static func str_of(d: Dictionary, key: String, default: String = "") -> String:
		var v: Variant = d.get(key)
		if v is String:
			@warning_ignore("unsafe_cast")
			return v as String
		return default

	static func num_of(d: Dictionary, key: String, default: float = 0.0) -> float:
		var v: Variant = d.get(key)
		if v is float or v is int:
			return float(v)
		return default

	static func bool_of(d: Dictionary, key: String) -> bool:
		var v: Variant = d.get(key)
		if v is bool:
			@warning_ignore("unsafe_cast")
			return v as bool
		return false

	static func dict_of(d: Dictionary, key: String) -> Dictionary:
		var v: Variant = d.get(key)
		if v is Dictionary:
			@warning_ignore("unsafe_cast")
			return v as Dictionary
		return {}

	static func arr_of(d: Dictionary, key: String) -> Array:
		var v: Variant = d.get(key)
		if v is Array:
			@warning_ignore("unsafe_cast")
			return v as Array
		return []


class DiffRecord extends JsonBase:
	var characteristic := ""
	var difficulty := ""
	var nps := 0.0
	var seconds := 0.0
	## ScoreSaber stars, -1 when the difficulty is not ScoreSaber ranked.
	var stars := -1.0
	## BeatLeader stars, -1 when not BeatLeader ranked.
	var bl_stars := -1.0
	## Requirement flags (reference 4.3): `ne` = Noodle Extensions, `me` = Mapping Extensions.
	var ne := false
	var me := false
	var chroma := false
	var vivify := false

	static func from_dict(d: Dictionary) -> DiffRecord:
		var r := DiffRecord.new()
		r.characteristic = JsonBase.str_of(d, "characteristic", "")
		r.difficulty = JsonBase.str_of(d, "difficulty", "")
		r.nps = JsonBase.num_of(d, "nps", 0.0)
		r.seconds = JsonBase.num_of(d, "seconds", 0.0)
		r.stars = JsonBase.num_of(d, "stars", -1.0)
		r.bl_stars = JsonBase.num_of(d, "blStars", -1.0)
		r.ne = JsonBase.bool_of(d, "ne")
		r.me = JsonBase.bool_of(d, "me")
		r.chroma = JsonBase.bool_of(d, "chroma")
		r.vivify = JsonBase.bool_of(d, "vivify")
		return r


class MapRecord extends JsonBase:
	var id := ""
	var name := ""
	var song_name := ""
	var song_author := ""
	## Display author: `metadata.levelAuthorName`, falling back to the uploader account name.
	var mapper := ""
	var uploader_name := ""
	var uploader_id := -1
	var uploader_verified := false
	var bpm := 0.0
	## `metadata.duration` - whole song in seconds. Never `diffs[].length` (that is beats).
	var duration := 0
	var upvotes := -1
	var downvotes := -1
	var score := -1.0
	var cover_url := ""
	var preview_url := ""
	var download_url := ""
	var hash := ""
	var description := ""
	var curated := false
	var ranked := false
	var bl_ranked := false
	var automapper := false
	var tags: Array = []
	var diffs: Array = []

	static func from_dict(d: Dictionary) -> MapRecord:
		var r := MapRecord.new()
		r.id = JsonBase.str_of(d, "id", "")
		r.name = JsonBase.str_of(d, "name", "")
		r.description = JsonBase.str_of(d, "description", "")

		var md := JsonBase.dict_of(d, "metadata")
		r.song_name = JsonBase.str_of(md, "songName", "")
		r.song_author = JsonBase.str_of(md, "songAuthorName", "")
		r.bpm = JsonBase.num_of(md, "bpm", 0.0)
		r.duration = int(JsonBase.num_of(md, "duration", 0.0))

		var up := JsonBase.dict_of(d, "uploader")
		r.uploader_name = JsonBase.str_of(up, "name", "")
		r.uploader_id = int(JsonBase.num_of(up, "id", -1.0))
		r.uploader_verified = JsonBase.bool_of(up, "verifiedMapper")
		r.mapper = JsonBase.str_of(md, "levelAuthorName", r.uploader_name)
		if r.mapper.is_empty():
			r.mapper = r.uploader_name

		var st := JsonBase.dict_of(d, "stats")
		r.upvotes = int(JsonBase.num_of(st, "upvotes", -1.0))
		r.downvotes = int(JsonBase.num_of(st, "downvotes", -1.0))
		r.score = JsonBase.num_of(st, "score", -1.0)

		r.curated = not JsonBase.dict_of(d, "curator").is_empty()
		r.ranked = JsonBase.bool_of(d, "ranked")
		r.bl_ranked = JsonBase.bool_of(d, "blRanked")
		r.automapper = JsonBase.bool_of(d, "automapper")

		var tags_v: Variant = d.get("tags")
		if tags_v is Array:
			@warning_ignore("unsafe_cast")
			r.tags = tags_v as Array

		var versions := JsonBase.arr_of(d, "versions")
		if versions.size() > 0 and versions[0] is Dictionary:
			@warning_ignore("unsafe_cast")
			var v: Dictionary = versions[0] as Dictionary
			r.hash = JsonBase.str_of(v, "hash", "")
			r.cover_url = JsonBase.str_of(v, "coverURL", "")
			r.preview_url = JsonBase.str_of(v, "previewURL", "")
			r.download_url = JsonBase.str_of(v, "downloadURL", "")
			for dv: Variant in JsonBase.arr_of(v, "diffs"):
				if dv is Dictionary:
					@warning_ignore("unsafe_cast")
					r.diffs.append(DiffRecord.from_dict(dv as Dictionary))
		return r

	## Diffs that belong to the Standard characteristic - the only ones the pills light up for
	## and the only ones the difficulty filter looks at (FR-005).
	func standard_diffs() -> Array:
		var out: Array = []
		for d: Variant in diffs:
			var diff: DiffRecord = d
			if diff.characteristic == STANDARD:
				out.append(diff)
		return out

	func difficulty_present(difficulty_name: String, standard_only: bool) -> bool:
		for d: Variant in diffs:
			var diff: DiffRecord = d
			if diff.difficulty != difficulty_name:
				continue
			if standard_only and diff.characteristic != STANDARD:
				continue
			return true
		return false

	## Characteristics other than Standard that the map carries, e.g. ["OneSaber"].
	func extra_characteristics() -> Array:
		var out: Array = []
		for d: Variant in diffs:
			var diff: DiffRecord = d
			if diff.characteristic == STANDARD:
				continue
			if not out.has(diff.characteristic):
				out.append(diff.characteristic)
		return out

	## Requirement badges for the map as a whole (any difficulty needing the mod blocks play).
	func required_mods() -> Array:
		var out: Array = []
		for d: Variant in diffs:
			var diff: DiffRecord = d
			if diff.ne and not out.has("Noodle"):
				out.append("Noodle")
			if diff.me and not out.has("MapsExt"):
				out.append("MapsExt")
			if diff.vivify and not out.has("Vivify"):
				out.append("Vivify")
			if diff.chroma and not out.has("Chroma"):
				out.append("Chroma")
		return out


class SearchResult extends JsonBase:
	var ok := false
	var error := ""
	## Set when the server answered `{"redirect": "<id>"}` for a pasted map key (FR-014).
	var redirect := ""
	var docs: Array = []
	var total := 0

	static func from_body(body: PackedByteArray) -> SearchResult:
		var r := SearchResult.new()
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not parsed is Dictionary:
			r.error = "BeatSaver sent something that is not JSON"
			return r
		@warning_ignore("unsafe_cast")
		var d := parsed as Dictionary

		var redirect_v: Variant = d.get("redirect")
		if redirect_v is String and not (redirect_v as String).is_empty():
			r.redirect = redirect_v
			r.ok = true
			return r

		var docs_v: Variant = d.get("docs")
		if not docs_v is Array:
			r.error = "BeatSaver response had no map list"
			return r
		@warning_ignore("unsafe_cast")
		for item: Variant in docs_v as Array:
			if item is Dictionary:
				@warning_ignore("unsafe_cast")
				r.docs.append(MapRecord.from_dict(item as Dictionary))
		r.total = int(JsonBase.num_of(JsonBase.dict_of(d, "info"), "total", float(r.docs.size())))
		r.ok = true
		return r


# --- Factories, so no caller needs the inner class names ----------------------------------------

static func make_map_record() -> MapRecord:
	return MapRecord.new()


static func make_diff_record() -> DiffRecord:
	return DiffRecord.new()


## Parses a `/search/text/{page}` body.
static func parse_search(body: PackedByteArray) -> SearchResult:
	return SearchResult.from_body(body)


## Parses a single-map body (`/maps/id/{id}`), used for the map-key redirect (FR-014).
static func parse_map(body: PackedByteArray) -> MapRecord:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		return null
	@warning_ignore("unsafe_cast")
	return MapRecord.from_dict(parsed as Dictionary)


# --- URL building (FR-002, FR-003) -------------------------------------------------------------

## Builds `/search/text/{page}`. Only parameters that the reference verifies are emitted, and a
## parameter is omitted rather than sent as 0/empty so the server keeps its own default.
static func build_search_url(query: Dictionary, page: int) -> String:
	var text := String(query.get("q", "")).strip_edges()
	var order := String(query.get("order", DEFAULT_ORDER))
	if not ORDERS.has(order):
		# An unknown enum is an HTTP 500 on the server side; never send one.
		order = DEFAULT_ORDER
	if order == "Relevance" and text.is_empty():
		# Blank query + Relevance is a silent Latest (or a 500 depending on the entry point).
		order = DEFAULT_ORDER

	var parts := PackedStringArray()
	if not text.is_empty():
		parts.append("q=" + text.uri_encode())
	parts.append("order=" + order)

	if bool(query.get("curated", false)):
		parts.append("curated=true")
	if bool(query.get("verified", false)):
		parts.append("verified=true")
	if bool(query.get("ranked", false)):
		# BeatSaver's "Ranked" is an OR of the ScoreSaber and BeatLeader mirrors (reference 6).
		parts.append("leaderboard=Ranked")

	var min_duration := int(query.get("min_duration", -1))
	var max_duration := int(query.get("max_duration", -1))
	if min_duration > 0:
		parts.append("minDuration=%d" % min_duration)
	if max_duration > 0:
		parts.append("maxDuration=%d" % max_duration)

	var min_nps := float(query.get("min_nps", -1.0))
	var max_nps := float(query.get("max_nps", -1.0))
	if min_nps > 0.0:
		parts.append("minNps=" + _num_text(min_nps))
	if max_nps > 0.0:
		parts.append("maxNps=" + _num_text(max_nps))

	parts.append("pageSize=%d" % PAGE_SIZE)
	return "%s/search/text/%d?%s" % [BASE_URL, maxi(0, page), "&".join(parts)]


static func map_url(map_id: String) -> String:
	return "%s/maps/id/%s" % [BASE_URL, map_id.uri_encode()]


static func total_pages(total: int) -> int:
	# `info.pages` is hard-coded to /20 on the server, so it is never trusted (FR-008).
	if total <= 0:
		return 1
	return maxi(1, ceili(float(total) / float(PAGE_SIZE)))


# --- Client-side filtering (FR-005, FR-006) ----------------------------------------------------

## Both filters below are client-side by necessity: the reference has no difficulty query
## parameter, and the server honours only one `X=false` mod filter per request (verified
## 2026-11-01 - combining `noodle=false&me=false` returns the `me` result set).
static func passes_client_filters(map: MapRecord, query: Dictionary) -> bool:
	if bool(query.get("playable_only", false)):
		for d: Variant in map.diffs:
			var diff: DiffRecord = d
			if diff.ne or diff.me or diff.vivify:
				return false
	var wanted: Array = query.get("difficulties", [])
	if wanted.size() > 0:
		var matched := false
		for d: Variant in map.standard_diffs():
			if wanted.has((d as DiffRecord).difficulty):
				matched = true
				break
		if not matched:
			return false
	return true


## Consumes one server page's docs from `cursor_doc` onwards, appending maps that pass the
## client-side filters until `budget` rows are collected. Pure, so the paging maths is unit
## tested. Returns {rows, rejected, doc, done_with_page, exhausted}.
static func consume_docs(docs: Array, cursor_doc: int, query: Dictionary, budget: int) -> Dictionary:
	var rows: Array = []
	var rejected := 0
	var i := maxi(0, cursor_doc)
	var page_size := docs.size()
	while i < page_size and rows.size() < budget:
		var item: Variant = docs[i]
		i += 1
		if not item is MapRecord:
			continue
		@warning_ignore("unsafe_cast")
		var map := item as MapRecord
		if passes_client_filters(map, query):
			rows.append(map)
		else:
			rejected += 1
	return {
		"rows": rows,
		"rejected": rejected,
		"doc": i,
		"done_with_page": i >= page_size,
		"exhausted": page_size == 0,
	}


# --- Presentation helpers ----------------------------------------------------------------------

static func format_duration(total_seconds: int) -> String:
	if total_seconds <= 0:
		return "-"
	return "%d:%02d" % [floori(float(total_seconds) / 60.0), total_seconds % 60]


## Up/down percentage from the vote counts, falling back to `stats.score`, then "-" (FR-004).
static func vote_percent(map: MapRecord) -> String:
	var votes := map.upvotes + map.downvotes
	if map.upvotes >= 0 and map.downvotes >= 0 and votes > 0:
		return "%d%%" % roundi(100.0 * float(map.upvotes) / float(votes))
	if map.score >= 0.0:
		return "%d%%" % roundi(map.score * 100.0)
	return "-"


static func short_difficulty(difficulty_name: String) -> String:
	var index := DIFFICULTIES.find(difficulty_name)
	if index < 0:
		return difficulty_name
	return DIFFICULTY_SHORT[index]


static func _num_text(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%d" % roundi(value)
	return "%.1f" % value
