extends Node

# "Animated" maps in the song list: the classification from Info.dat (LibraryView.classify) and
# the three-way map filter. Headless. Each check prints `MODS ok` / `MODS FAIL`; the last line
# is the verdict (check.ps1 matches it).
#
# Run: godot --headless --path . res://tools/harness/verify_library_mods.tscn

var _fails := 0
var _checks := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("MODS %s %s%s" % ["ok  " if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _ready() -> void:
	_classification()
	_filter()
	print("MODS checks=%d failed=%d" % [_checks, _fails])
	print("MODS ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _v2(diffs: Array) -> MapInfo:
	return MapInfo.new_v2({"_version": "2.1.0", "_songName": "S", "_difficultyBeatmapSets": [
		{"_beatmapCharacteristicName": "Standard", "_difficultyBeatmaps": diffs}]}, "res://none/")


func _v4(diffs: Array) -> MapInfo:
	return MapInfo.new_v3({"version": "4.0.1", "song": {"title": "S"}, "difficultyBeatmaps": diffs}, "res://none/")


func _classification() -> void:
	var L := LibraryView
	# v2: one Noodle difficulty among standard ones makes the song Animated.
	var mixed := _v2([
		{"_difficulty": "Hard", "_beatmapFilename": "Hard.dat"},
		{"_difficulty": "Expert", "_beatmapFilename": "Expert.dat", "_customData": {"_difficultyLabel": "Plain"}},
		{"_difficulty": "ExpertPlus", "_beatmapFilename": "EP.dat", "_customData": {"_requirements": ["Noodle Extensions"], "_suggestions": ["Chroma"]}},
	])
	_check("v2: one Noodle difficulty among standard ones is Animated", L.is_animated(mixed))
	_check("v2: names Noodle and the suggested Chroma", L.mod_names(mixed) == "Noodle, Chroma", L.mod_names(mixed))
	var chroma := _v2([{"_difficulty": "Expert", "_customData": {"_requirements": ["Chroma"]}}])
	_check("v2: Chroma only is not Animated", not L.is_animated(chroma) and L.mod_names(chroma) == "Chroma", L.mod_names(chroma))
	var bare := _v2([{"_difficulty": "Expert", "_beatmapFilename": "Expert.dat"}])
	_check("v2: no customData is standard", not L.is_animated(bare) and L.mod_names(bare) == "" and bare.mod_flags == 0)
	var suggested := _v2([{"_difficulty": "Expert", "_customData": {"_suggestions": ["Noodle Extensions"]}}])
	_check("v2: Noodle only suggested is not Animated", not L.is_animated(suggested) and L.mod_names(suggested) == "Noodle")
	var messy := _v2([{"_difficulty": "Expert", "_customData": {"_requirements": [" noodle extensions ", 3, null, "Mapping Extensions"]}}])
	_check("v2: names are matched without case or spaces; junk ignored", L.is_animated(messy) and L.mod_names(messy) == "Noodle, Mapping Extensions", L.mod_names(messy))
	var not_list := _v2([{"_difficulty": "Expert", "_customData": {"_requirements": "Noodle Extensions"}}])
	_check("v2: a requirements value that is not a list is ignored", not L.is_animated(not_list))
	# v4 (and v3) Info: customData.requirements / suggestions per difficulty.
	var v4 := _v4([
		{"characteristic": "Standard", "difficulty": "Easy", "beatmapDataFilename": "E.dat"},
		{"characteristic": "Standard", "difficulty": "Expert", "beatmapDataFilename": "X.dat", "customData": {"requirements": ["Noodle Extensions", "Vivify"]}},
	])
	_check("v4: Noodle requirement is Animated", L.is_animated(v4))
	_check("v4: Vivify is named", L.mod_names(v4) == "Noodle, Vivify", L.mod_names(v4))
	var v4_chroma := _v4([{"characteristic": "Standard", "difficulty": "Expert", "customData": {"suggestions": ["Chroma"]}}])
	_check("v4: Chroma suggestion only is standard", not L.is_animated(v4_chroma) and L.mod_names(v4_chroma) == "Chroma")
	var v4_bare := _v4([{"characteristic": "Standard", "difficulty": "Expert"}])
	_check("v4: no customData is standard", not L.is_animated(v4_bare) and L.mod_names(v4_bare) == "")
	# Worked out once per map: a later change to the difficulty data is not re-read.
	mixed.difficulty_beatmaps[2].custom_data.clear()
	_check("classification is cached on the map", L.is_animated(mixed) and mixed.mod_flags & L.MOD_NOODLE)


func _filter() -> void:
	var L := LibraryView
	var a := _v2([{"_difficulty": "Expert", "_customData": {"_requirements": ["Noodle Extensions"]}}])
	var s1 := _v2([{"_difficulty": "Expert"}])
	var s2 := _v2([{"_difficulty": "Expert", "_customData": {"_requirements": ["Chroma"]}}])
	var maps: Array = [s1, a, s2]
	_check("filter All maps keeps everything, in order", L.filter_mods(maps, L.MODS_ALL) == maps)
	_check("filter Standard only", L.filter_mods(maps, L.MODS_STANDARD) == [s1, s2])
	_check("filter Animated only", L.filter_mods(maps, L.MODS_ANIMATED) == [a])
	_check("an unknown filter value shows everything", L.filter_mods(maps, "bogus") == maps)
	_check("Animated only with no animated map is empty", L.filter_mods([s1, s2], L.MODS_ANIMATED).is_empty())
	_check("the filter cycles All -> Standard -> Animated", L.MOD_FILTERS == [L.MODS_ALL, L.MODS_STANDARD, L.MODS_ANIMATED])
	_check("labels", L.MOD_FILTER_LABELS[L.MODS_ALL] == "All maps" and L.MOD_FILTER_LABELS[L.MODS_STANDARD] == "Standard only" and L.MOD_FILTER_LABELS[L.MODS_ANIMATED] == "Animated only")
	_check("the setting defaults to All maps", Settings.default_values.get("library_mod_filter", "") == L.MODS_ALL)
