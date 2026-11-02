extends SceneTree

## Unit tests for the BeatSaver browser's pure logic (URL building, parsing, client-side filters
## and the paging cursor). No network, no scene tree, no autoloads:
##
##   godot --headless --path . --script res://tools/tests/beatsaver_browser_test.gd

const Api := preload("res://game/ui/BeatSaverPanel/BeatSaverApi.gd")

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_test_url_builder()
	_test_parsing()
	_test_client_filters()
	_test_cursor()
	_test_helpers()
	_test_settings_keys()
	if _failures == 0:
		print("beatsaver browser test: OK (%d checks)" % _checks)
	else:
		print("beatsaver browser test: %d of %d checks FAILED" % [_failures, _checks])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


func _test_url_builder() -> void:
	var plain := Api.build_search_url({}, 0)
	_check(plain.begins_with("https://api.beatsaver.com/search/text/0?"), "base path: " + plain)
	_check(plain.contains("order=Latest"), "default order present: " + plain)
	_check(plain.contains("pageSize=20"), "page size present: " + plain)
	_check(not plain.contains("q="), "no empty q: " + plain)
	_check(not plain.contains("minDuration"), "no zero minDuration: " + plain)
	_check(not plain.contains("minNps"), "no zero minNps: " + plain)
	_check(not plain.contains("curated"), "no curated by default: " + plain)

	var blank_relevance := Api.build_search_url({"order": "Relevance"}, 0)
	_check(blank_relevance.contains("order=Latest"), "blank q drops Relevance: " + blank_relevance)
	_check(not blank_relevance.contains("Relevance"), "Relevance never sent blank: " + blank_relevance)

	var with_query := Api.build_search_url({"order": "Relevance", "q": "camellia"}, 2)
	_check(with_query.contains("q=camellia"), "query encoded: " + with_query)
	_check(with_query.contains("order=Relevance"), "Relevance with query: " + with_query)
	_check(with_query.contains("/search/text/2?"), "page index in path: " + with_query)

	var bogus := Api.build_search_url({"order": "Cheapest"}, 0)
	_check(bogus.contains("order=Latest"), "unknown enum replaced (server 500 otherwise): " + bogus)
	_check(not bogus.contains("Cheapest"), "unknown enum never sent: " + bogus)

	var encoded := Api.build_search_url({"q": "a b|c"}, 0)
	_check(encoded.contains("q=a%20b%7Cc"), "q is uri encoded: " + encoded)

	var filtered := Api.build_search_url({
		"ranked": true,
		"curated": true,
		"verified": true,
		"min_duration": 120,
		"max_duration": 240,
		"min_nps": 4.0,
		"max_nps": 7.0,
	}, 1)
	for expected in ["leaderboard=Ranked", "curated=true", "verified=true", "minDuration=120", "maxDuration=240", "minNps=4", "maxNps=7"]:
		_check(filtered.contains(expected), "filter param %s in %s" % [expected, filtered])
	_check(not filtered.contains("playable_only"), "client-only filter never reaches the URL")
	_check(not filtered.contains("difficulty"), "no difficulty in the URL (not a server parameter)")


func _test_parsing() -> void:
	var json := """
	{
	  "docs": [
	    {
	      "id": "557f4",
	      "name": "Zhoni - DIGITAL SUICIDE WORLD",
	      "description": "a map [with] brackets",
	      "metadata": {"bpm": 90.0, "duration": 192, "songName": "Digital Suicide World",
	                   "songAuthorName": "Zhoni", "levelAuthorName": "ComplexNumbers"},
	      "uploader": {"id": 32693, "name": "ComplexNumbers", "verifiedMapper": true},
	      "stats": {"upvotes": 45, "downvotes": 5, "score": 0.9123},
	      "curator": {"id": 1, "name": "staff"},
	      "blRanked": true,
	      "tags": ["challenge", "speed"],
	      "versions": [{
	        "hash": "abc",
	        "coverURL": "https://cfcdn.beatsaver.com/abc.jpg",
	        "previewURL": "https://cfcdn.beatsaver.com/abc.mp3",
	        "downloadURL": "https://r2cdn.beatsaver.com/abc.zip",
	        "diffs": [
	          {"characteristic": "Standard", "difficulty": "ExpertPlus", "nps": 6.4, "seconds": 150.5,
	           "stars": 7.25, "ne": true},
	          {"characteristic": "OneSaber", "difficulty": "ExpertPlus", "nps": 5.0, "seconds": 150.5}
	        ]
	      }]
	    },
	    {"id": "empty"}
	  ],
	  "info": {"total": 586, "pages": 30}
	}
	"""
	var parsed := Api.parse_search(json.to_utf8_buffer())
	_check(parsed.ok, "search response parses")
	_check(parsed.docs.size() == 2, "two docs")
	_check(parsed.total == 586, "total read from info")

	var map = parsed.docs[0]
	_check(map.id == "557f4", "id")
	_check(map.mapper == "ComplexNumbers", "mapper is levelAuthorName")
	_check(map.uploader_id == 32693, "uploader id")
	_check(map.uploader_verified, "verified mapper flag")
	_check(map.duration == 192, "duration comes from metadata.duration")
	_check(map.bpm == 90.0, "bpm")
	_check(map.curated, "curator present means curated")
	_check(map.bl_ranked, "blRanked")
	_check(map.cover_url.ends_with("abc.jpg"), "cover url")
	_check(map.diffs.size() == 2, "two diffs")
	_check(map.standard_diffs().size() == 1, "one Standard diff")

	var empty = parsed.docs[1]
	_check(empty.duration == 0 and empty.diffs.is_empty(), "sparse doc does not crash")
	_check(empty.mapper.is_empty(), "sparse doc has no mapper")

	var redirect := Api.parse_search("{\"redirect\":\"557f4\"}".to_utf8_buffer())
	_check(redirect.ok and redirect.redirect == "557f4", "redirect is read at the top level")
	_check(redirect.docs.is_empty(), "redirect has no docs")

	var broken := Api.parse_search("<html>nope</html>".to_utf8_buffer())
	_check(not broken.ok and not broken.error.is_empty(), "non-JSON is an error, not a crash")


func _test_client_filters() -> void:
	var noodle: Variant = _make_map("noodle", [_make_diff("ExpertPlus", "Standard", true, false, false)])
	var clean: Variant = _make_map("clean", [_make_diff("ExpertPlus", "Standard", false, false, false)])
	var one_saber_only: Variant = _make_map("1s", [_make_diff("ExpertPlus", "OneSaber", false, false, false)])

	var playable := {"playable_only": true}
	_check(not Api.passes_client_filters(noodle, playable), "playable only drops Noodle maps")
	_check(Api.passes_client_filters(clean, playable), "playable only keeps clean maps")

	var expert_plus := {"difficulties": ["ExpertPlus"]}
	_check(Api.passes_client_filters(clean, expert_plus), "difficulty filter passes Standard Expert+")
	_check(not Api.passes_client_filters(one_saber_only, expert_plus), "difficulty filter is Standard only")

	_check(Api.passes_client_filters(noodle, {}), "no filters means everything passes")

	_check(noodle.required_mods() == ["Noodle"], "requirement badge for Noodle")
	_check(one_saber_only.extra_characteristics() == ["OneSaber"], "characteristic tag source")


func _test_cursor() -> void:
	# Three server pages, 20 / 20 / 2 maps, where every fourth map is rejected by the filter.
	var pages: Array = []
	var next_id := 0
	for page_index in 3:
		var docs: Array = []
		var count := 20 if page_index < 2 else 2
		for i in count:
			var is_noodle := (next_id % 4) == 3
			docs.append(_make_map("m%d" % next_id, [_make_diff("ExpertPlus", "Standard", is_noodle, false, false)]))
			next_id += 1
		pages.append(docs)

	var query := {"playable_only": true}
	var page1 := _collect_page(pages, 0, 0, query)
	_check(page1["rows"].size() == 20, "page 1 is full (%d)" % page1["rows"].size())
	_check(int(page1["cursor_page"]) == 1, "page 1 consumed one full server page and started the next")
	_check(int(page1["cursor_doc"]) == 6, "page 1 stopped mid server page 1 (doc 6), got %d" % int(page1["cursor_doc"]))
	_check(int(page1["rejected"]) == 6, "6 maps rejected, got %d" % int(page1["rejected"]))
	_check(not bool(page1["exhausted"]), "more results remain after page 1")

	var page2 := _collect_page(pages, int(page1["cursor_page"]), int(page1["cursor_doc"]), query)
	_check(page2["rows"].size() == 12, "page 2 is short and honest (%d)" % page2["rows"].size())
	_check(bool(page2["exhausted"]), "page 2 runs out of server pages")

	# Back to page 1 must produce the same maps.
	var replay := _collect_page(pages, 0, 0, query)
	var same := true
	for i in page1["rows"].size():
		if page1["rows"][i].id != replay["rows"][i].id:
			same = false
	_check(same, "replaying the start cursor returns the same page (Back is exact)")

	# An empty page is end-of-results, not an error.
	var end := _collect_page(pages, 9, 0, query)
	_check(end["rows"].is_empty() and bool(end["exhausted"]), "past the end is empty + exhausted")


## Mirrors the panel's fetch loop over a fixed set of server pages.
func _collect_page(pages: Array, start_page: int, start_doc: int, query: Dictionary) -> Dictionary:
	var rows: Array = []
	var rejected := 0
	var cursor_page := start_page
	var cursor_doc := start_doc
	var served := 0
	var exhausted := false
	while rows.size() < 20 and served < 4 and not exhausted:
		served += 1
		var docs: Array = pages[cursor_page] if cursor_page >= 0 and cursor_page < pages.size() else []
		if docs.is_empty():
			exhausted = true
			break
		var result := Api.consume_docs(docs, cursor_doc, query, 20 - rows.size())
		rows.append_array(result["rows"])
		rejected += int(result["rejected"])
		cursor_doc = int(result["doc"])
		if bool(result["done_with_page"]):
			cursor_page += 1
			cursor_doc = 0
	return {
		"rows": rows,
		"rejected": rejected,
		"cursor_page": cursor_page,
		"cursor_doc": cursor_doc,
		"exhausted": exhausted,
	}


func _test_helpers() -> void:
	_check(Api.format_duration(192) == "3:12", "m:ss formatting")
	_check(Api.format_duration(0) == "-", "unknown duration")
	_check(Api.total_pages(586) == 30, "pages computed from total, not info.pages")
	_check(Api.total_pages(0) == 1, "zero total still has a page")
	_check(Api.vote_percent(_make_map("v", [])) == "-", "no votes and no score is a dash")

	var voted: Variant = _make_map("v", [])
	voted.upvotes = 45
	voted.downvotes = 5
	_check(Api.vote_percent(voted) == "90%", "vote percentage from counts")

	var scored: Variant = _make_map("s", [])
	scored.score = 0.9123
	_check(Api.vote_percent(scored) == "91%", "falls back to stats.score")

	var map_with_length = Api.parse_map(("""
	{"metadata": {"duration": 192},
	 "versions": [{"diffs": [{"characteristic": "Standard", "difficulty": "Expert", "length": 399.0, "seconds": 136.7}]}]}
	""").to_utf8_buffer())
	_check(map_with_length.duration == 192, "beats are never used as a duration")
	_check(map_with_length.diffs[0].seconds == 136.7, "per-diff seconds kept separately")


## Guards against Settings.gd and the panel drifting apart on the persisted key names.
func _test_settings_keys() -> void:
	var text := FileAccess.get_file_as_string("res://game/Settings.gd")
	var keys := [
		"beatsaver_order", "beatsaver_curated", "beatsaver_verified", "beatsaver_ranked",
		"beatsaver_playable_only", "beatsaver_duration", "beatsaver_nps", "beatsaver_difficulties",
	]
	for key: String in keys:
		_check(text.contains(key + " ="), "Settings.gd declares a default for " + key)


func _make_map(id: String, diffs: Array) -> Variant:
	var map = Api.make_map_record()
	map.id = id
	map.diffs = diffs
	return map


func _make_diff(difficulty: String, characteristic: String, ne: bool, me: bool, vivify: bool) -> Variant:
	var diff = Api.make_diff_record()
	diff.difficulty = difficulty
	diff.characteristic = characteristic
	diff.ne = ne
	diff.me = me
	diff.vivify = vivify
	return diff
