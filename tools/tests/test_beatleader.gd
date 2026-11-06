extends Node3D

# BeatLeader read path test (specs/020 FR-004, FR-010, SC-003).
#
# Fixtures are trimmed from the live Phoenix ExpertPlus/Standard response; the test proves the
# parser, the URL/mode mapping and the distinct states, without touching the network.
#
# Run: godot --headless --path . res://tools/tests/test_beatleader.tscn

const Api := preload("res://game/ui/BeatLeaderPanel/BeatLeaderApi.gd")
const FIXTURE := "res://tools/fixtures/beatleader_phoenix.json"
const PHOENIX := "bf2c367d29b133b66dc27f6f8e20467d0ec3301f"

var _bad := 0

func _ready() -> void:
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	_check(fixture is Dictionary, "fixture parses")
	if fixture is Dictionary:
		_test_board(fixture as Dictionary)
		_test_scores(fixture as Dictionary)
	_test_urls()
	_test_modes()
	_test_formats()
	_test_characteristic()
	print("BEATLEADERTEST ", "PASS" if _bad == 0 else "FAIL")
	get_tree().quit(0 if _bad == 0 else 1)

func _test_board(f: Dictionary) -> void:
	var body := JSON.stringify(f["board"]).to_utf8_buffer()
	var board := Api.parse_board(body)
	_check(bool(board.get("ok", false)), "board parses")
	_check(str(board.get("id", "")) == "3269391", "board id")
	_check(str(board.get("song_name", "")) == "The Phoenix", "song name")
	_check(str(board.get("song_author", "")) == "Fall Out Boy", "song author")
	_check(str(board.get("difficulty", "")) == "ExpertPlus", "difficulty name")
	_check(str(board.get("mode", "")) == "Standard", "mode name")
	_check(not bool(Api.parse_board("{oops".to_utf8_buffer()).get("ok", true)), "bad JSON board rejected")
	_check(not bool(Api.parse_board("{}".to_utf8_buffer()).get("ok", true)), "board without id rejected")

func _test_scores(f: Dictionary) -> void:
	var body := JSON.stringify(f["scores"]).to_utf8_buffer()
	var parsed := Api.parse_scores(body)
	_check(bool(parsed.get("ok", false)), "scores parse")
	var rows: Array = parsed.get("scores", [])
	_check(rows.size() == 5, "five rows (%d)" % rows.size())
	if rows.size() >= 5:
		_check(int(rows[0]["rank"]) == 1, "first row is rank 1")
		_check(str(rows[0]["player"]) == "OlbmaPhlee", "first player")
		_check(int(rows[0]["score"]) == 1247685, "first score")
		_check(str(rows[0]["modifiers"]) == "SF", "modifiers kept")
		_check(str(rows[1]["modifiers"]) == "-", "empty modifiers read as '-'")
		_check(str(rows[4]["player"]) == "Reddek", "rank order kept")
	var empty := Api.parse_scores(JSON.stringify(f["empty_scores"]).to_utf8_buffer())
	_check(bool(empty.get("ok", false)), "empty board parses")
	_check((empty.get("scores", []) as Array).is_empty(), "empty board has no rows")
	_check(not bool(Api.parse_scores("nope".to_utf8_buffer()).get("ok", true)), "bad JSON scores rejected")

func _test_urls() -> void:
	_check(
		Api.board_url(PHOENIX.to_upper(), "ExpertPlus", "Standard")
			== "%s/leaderboard/%s/ExpertPlus/Standard" % [Api.BASE_URL, PHOENIX],
		"board URL lower-cases the hash")
	_check(
		Api.scores_url("3269391", 10)
			== "%s/leaderboard/3269391?page=1&count=10&sortBy=rank&order=desc" % Api.BASE_URL,
		"scores URL asks for rank 1..N")

func _test_modes() -> void:
	for local: String in ["Standard", "OneSaber", "NoArrows", "90Degree", "360Degree", "Lightshow", "Lawless"]:
		_check(Api.mode_for_characteristic(local) == local, "mode %s maps" % local)
	_check(Api.mode_for_characteristic("NinetyDegree") == "90Degree", "NinetyDegree alias")
	_check(Api.mode_for_characteristic("ThreeSixtyDegree") == "360Degree", "ThreeSixtyDegree alias")
	_check(Api.mode_for_characteristic("SomethingElse") == "", "unknown characteristic is unsupported")
	var statuses := [
		Api.STATUS_OK, Api.STATUS_NO_HASH, Api.STATUS_UNSUPPORTED,
		Api.STATUS_NOT_FOUND, Api.STATUS_NO_SCORES, Api.STATUS_OFFLINE
	]
	var unique := {}
	for s: String in statuses:
		unique[s] = true
	_check(unique.size() == statuses.size(), "each state is distinct")

func _test_formats() -> void:
	_check(Api.format_accuracy(0.9813) == "98.13%", "fraction accuracy")
	_check(Api.format_accuracy(98.13) == "98.13%", "percent accuracy")
	_check(Api.format_pp(0.0) == "-", "unranked pp")
	_check(Api.format_pp(662.7754) == "662.78", "pp rounding")
	_check(Api.format_modifiers("") == "-", "empty modifiers")
	_check(Api.format_modifiers(" NF ") == "NF", "modifier trim")

func _test_characteristic() -> void:
	var info := {
		"_version": "2.1.0",
		"_songName": "Test",
		"_songSubName": "",
		"_songAuthorName": "Artist",
		"_levelAuthorName": "Mapper",
		"_beatsPerMinute": 120.0,
		"_difficultyBeatmapSets": [
			{
				"_beatmapCharacteristicName": "OneSaber",
				"_difficultyBeatmaps": [
					{"_difficulty": "ExpertPlus", "_difficultyRank": 9, "_beatmapFilename": "ExpertPlus.dat"},
				],
			},
		],
	}
	var parsed := MapInfo.new_v2(info, "user://nope/")
	_check(parsed.difficulty_beatmaps.size() == 1, "one difficulty")
	if parsed.difficulty_beatmaps.size() == 1:
		_check(parsed.difficulty_beatmaps[0].characteristic == "OneSaber", "v2 characteristic kept")

func _check(condition: bool, what: String) -> void:
	if not condition:
		printerr("BEATLEADERTEST FAIL: " + what)
		_bad += 1
