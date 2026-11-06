extends RefCounted
class_name Map

const MapTimer := preload("res://game/scripts/MapTimer.gd")

# this would have basically been impossible to figure out without constantly
# referencing the beat saber modding group wiki.
# https://bsmg.wiki/mapping/map-format.html

static var current_info: MapInfo
# Bench-only: when true, _process_map spawns nothing, so a run measures the floor.
static var spawn_disabled := false
static var current_difficulty: DifficultyInfo

static var note_stack: Array[ColorNoteInfo]
static var bomb_stack: Array[BombInfo]
static var obstacle_stack: Array[ObstacleInfo]
static var arc_stack: Array[ArcInfo]
static var chain_stack: Array[ChainInfo]
static var event_stack: Array[EventInfo]

static var color_left: Color
static var color_right: Color

# --- BPM segments (FR-025) ---------------------------------------------------------------
# The segments live in MapTimer (specs/013 FR-007). These wrappers keep the call sites on the
# Map facade; the tempo state is deliberately not duplicated here.
static func bpm_at_beat(beat: float) -> float:
	return MapTimer.bpm_at_beat(beat)

static func beat_to_seconds(beat: float) -> float:
	return MapTimer.beat_to_seconds(beat)

static func seconds_to_beat(seconds: float) -> float:
	return MapTimer.seconds_to_beat(seconds)


# some simple multithreading, since larger maps can take a very long time to
# load.  one particulary notable outlier is the beatmap of shrek, which took
# around 48 milliseconds to load before even on a 7800x3d, and now takes around
# 29 milliseconds.  takes just over half as long as before, very worth the
# nightmare code i've written.
#
# long story short, each beatmap-element loading func splits into two threads:
# one for parsing the top half of the array of dicts, and one for parsing the
# bottom half.  these run concurrently, not quite halfing the time, but
# getting pretty close to halfing it.
static var note_thread_0 := Thread.new()
static var note_thread_1 := Thread.new()
static var bomb_thread_0 := Thread.new()
static var bomb_thread_1 := Thread.new()
static var obstacle_thread_0 := Thread.new()
static var obstacle_thread_1 := Thread.new()
static var arc_thread_0 := Thread.new()
static var arc_thread_1 := Thread.new()
static var chain_thread_0 := Thread.new()
static var chain_thread_1 := Thread.new()
static var event_thread_0 := Thread.new()
static var event_thread_1 := Thread.new()

# --- Map colours (FR-027/FR-028) ---------------------------------------------------------
# Notes, the room's lights and the walls each take a colour from the track, in order:
# map environment colours -> map note colours -> the environment's default scheme -> the
# player's settings. "Classic" skips the environment scheme and reproduces the old look.
# FR-030: map features this build cannot fully render. Surfaced in the pause menu and logged,
# instead of a map silently playing half its design.
static var unsupported_features := PackedStringArray()
# Diagnostics: how many decorative entries were filtered and how many tempo segments exist.
static var fakes_filtered := 0
static var bpm_segments := 1

# --- Palette (FR-025/FR-028) --------------------------------------------------------------
# The colour rules live in MapPalette (specs/013 FR-007); this wrapper keeps the loader and
# the game on the Map facade.
static func set_colors_from_custom_data() -> void:
	MapPalette.set_colors_from_custom_data(current_info, current_difficulty)


static func _is_fake_v3(entry: Dictionary) -> bool:
	var cd := Utils.get_dict(entry, "customData", {})
	return Utils.get_bool(cd, "fake", false)

static func _is_fake_v2(entry: Dictionary) -> bool:
	var cd := Utils.get_dict(entry, "_customData", {})
	return Utils.get_bool(cd, "_fake", false)

static func _detect_unsupported(map_data: Dictionary) -> void:
	var found := PackedStringArray()
	if not Utils.get_array(map_data, "lightColorEventBoxGroups", []).is_empty() \
			or not Utils.get_array(map_data, "lightRotationEventBoxGroups", []).is_empty() \
			or not Utils.get_array(map_data, "lightTranslationEventBoxGroups", []).is_empty():
		found.append("box-group lighting")
	if not Utils.get_array(map_data, "rotationEvents", []).is_empty():
		found.append("360 rotation")
	for e: Variant in Utils.get_array(map_data, "_events", []):
		if e is Dictionary:
			var t := int(Utils.get_float(e as Dictionary, "_type", -1))
			if t == 14 or t == 15:
				found.append("lane rotation")
				break
	var cd := Utils.get_dict(map_data, "customData", Utils.get_dict(map_data, "_customData", {}))
	for key: String in ["customEvents", "_customEvents", "environment", "_environment", "materials"]:
		if cd.has(key):
			found.append("Chroma/Noodle animation")
			break
	# Noodle keeps decorative notes in their own arrays; we never load them, which is the
	# right outcome but has to show up in the diagnostic or the filter looks inert.
	var cd_all := Utils.get_dict(map_data, "customData", {})
	for key: String in ["fakeColorNotes", "fakeBombNotes", "fakeObstacles"]:
		fakes_filtered += Utils.get_array(cd_all, key, []).size()
	if current_info != null and current_info.custom_data.has("_assetBundle"):
		found.append("custom Unity assets")
	unsupported_features = found
	if not found.is_empty():
		vr.log_warning("MAP unsupported features: %s" % ", ".join(found))

static func load_map_info(load_path: String) -> MapInfo:
	var info_dict := {}
	if FileAccess.file_exists(load_path + "Info.dat"):
		info_dict = vr.load_json_file(load_path + "Info.dat")
	elif FileAccess.file_exists(load_path + "info.dat"):
		info_dict = vr.load_json_file(load_path + "info.dat")
	if (info_dict.is_empty()):
		vr.log_error("Invalid info.dat found in " + load_path)
		return null
	
	if info_dict.has("_version"):
		return MapInfo.new_v2(info_dict, load_path)
	elif info_dict.has("version"):
		var version := Utils.get_str(info_dict, "version", "")
		if version.begins_with("3.") or version.begins_with("4."):
			return MapInfo.new_v3(info_dict, load_path)
		vr.log_warning("%s is an unsupported beatmap version: %s" % [load_path, version])
		return null
	else:
		vr.log_warning("%s is an unknown beatmap version" % load_path)
		return null

# speed for the speed gods.  please forgive me for this.
# - steve hocktail
static func load_note_stack_v2(note_data: Array) -> void:
	var load_range := func(start: int, end: int) -> Array[Array]:
		var note_array: Array[ColorNoteInfo] = []
		var bomb_array: Array[BombInfo] = []
		var i := start
		while i < end:
			if not note_data[i] is Dictionary: continue
			@warning_ignore("unsafe_cast")
			var note_dict := note_data[i] as Dictionary
			var note_type := int(Utils.get_float(note_dict, "_type", -1.0))
			if _is_fake_v2(note_dict):
				# FR-026: decorative note from Noodle/Chroma. Hidden and unscored, not a ghost:
				# its real position depends on animation we do not implement.
				fakes_filtered += 1
				i += 1
				continue
			if note_type == 3 and Settings.bombs_enabled:
				bomb_array.append(BombInfo.new_v2(note_dict))
			elif note_type == 0 or note_type == 1:
				note_array.append(ColorNoteInfo.new_v2(note_dict))
			i += 1
		return [note_array, bomb_array]
	var midpoint := note_data.size() >> 1
	#note_thread_1.start(load_range.bind(0, midpoint))
	Utils.custom_thread_call(note_thread_1, load_range, [0, midpoint])
	var total_second_half : Array[Array] = load_range.bind(midpoint, note_data.size()).call()
	#var total_first_half : Array[Array] = note_thread_1.wait_to_finish()
	var total_first_half : Array[Array] = Utils.custom_thread_wait_to_finish(note_thread_1)
	note_stack = total_first_half[0] + total_second_half[0]
	bomb_stack = total_first_half[1] + total_second_half[1]
	note_stack.reverse()
	bomb_stack.reverse()

static func load_obstacle_stack_v2(obstacle_data: Array) -> void:
	var last_index := obstacle_data.size() - 1
	var load_range := func(start: int, end: int) -> void:
		var i := start
		while i < end:
			if obstacle_data[i] is Dictionary:
				@warning_ignore("unsafe_cast")
				obstacle_stack[last_index - i] = ObstacleInfo.new_v2(obstacle_data[i] as Dictionary)
			i += 1
	var midpoint := obstacle_data.size() >> 1
	obstacle_stack.resize(obstacle_data.size())
	#obstacle_thread_1.start(load_range.bind(0, midpoint))
	Utils.custom_thread_call(obstacle_thread_1, load_range, [0, midpoint])
	load_range.bind(midpoint, obstacle_data.size()).call()
	#obstacle_thread_1.wait_to_finish()
	Utils.custom_thread_wait_to_finish(obstacle_thread_1)

static func load_arc_stack_v2(arc_data: Array) -> void:
	var last_index := arc_data.size() - 1
	var load_range := func(start: int, end: int) -> void:
		var i := start
		while i < end:
			if arc_data[i] is Dictionary:
				@warning_ignore("unsafe_cast")
				arc_stack[last_index - i] = ArcInfo.new_v2(arc_data[i] as Dictionary)
			i += 1
	var midpoint := arc_data.size() >> 1
	arc_stack.resize(arc_data.size())
	#arc_thread_1.start(load_range.bind(0, midpoint))
	Utils.custom_thread_call(arc_thread_1, load_range, [0, midpoint])
	load_range.bind(midpoint, arc_data.size()).call()
	#arc_thread_1.wait_to_finish()
	Utils.custom_thread_wait_to_finish(arc_thread_1)
	

static func load_event_stack_v2(event_data: Array) -> void:
	var last_index := event_data.size() - 1
	var load_range := func(start: int, end: int) -> void:
		var i := start
		while i < end:
			if event_data[i] is Dictionary:
				@warning_ignore("unsafe_cast")
				event_stack[last_index - i] = EventInfo.new_v2(event_data[i] as Dictionary)
			i += 1
	var midpoint := event_data.size() >> 1
	event_stack.resize(event_data.size())
	#event_thread_1.start(load_range.bind(0, midpoint))
	Utils.custom_thread_call(event_thread_1, load_range, [0, midpoint])
	load_range.bind(midpoint, event_data.size()).call()
	#event_thread_1.wait_to_finish()
	Utils.custom_thread_wait_to_finish(event_thread_1)

static func load_note_stack_v3(note_data: Array) -> void:
	var last_index := note_data.size() - 1
	var load_range := func(start: int, end: int) -> void:
		var i := start
		while i < end:
			if note_data[i] is Dictionary:
				@warning_ignore("unsafe_cast")
				note_stack[last_index - i] = ColorNoteInfo.new_v3(note_data[i] as Dictionary)
			i += 1
	var midpoint := note_data.size() >> 1
	note_stack.resize(note_data.size())
	#note_thread_1.start(load_range.bind(0, midpoint))
	Utils.custom_thread_call(note_thread_1, load_range, [0, midpoint])
	load_range.bind(midpoint, note_data.size()).call()
	#note_thread_1.wait_to_finish()
	Utils.custom_thread_wait_to_finish(note_thread_1)

static func load_bomb_stack_v3(bomb_data: Array) -> void:
	if not Settings.bombs_enabled:
		bomb_stack.clear()
		return
	var last_index := bomb_data.size() - 1
	var load_range := func(start: int, end: int) -> void:
		var i := start
		while i < end:
			if bomb_data[i] is Dictionary:
				@warning_ignore("unsafe_cast")
				bomb_stack[last_index - i] = BombInfo.new_v3(bomb_data[i] as Dictionary)
			i += 1
	var midpoint := bomb_data.size() >> 1
	bomb_stack.resize(bomb_data.size())
	#bomb_thread_1.start(load_range.bind(0, midpoint))
	Utils.custom_thread_call(bomb_thread_1, load_range, [0, midpoint])
	load_range.bind(midpoint, bomb_data.size()).call()
	#bomb_thread_1.wait_to_finish()
	Utils.custom_thread_wait_to_finish(bomb_thread_1)

static func load_obstacle_stack_v3(obstacle_data: Array) -> void:
	var last_index := obstacle_data.size() - 1
	var load_range := func(start: int, end: int) -> void:
		var i := start
		while i < end:
			if obstacle_data[i] is Dictionary:
				@warning_ignore("unsafe_cast")
				obstacle_stack[last_index - i] = ObstacleInfo.new_v3(obstacle_data[i] as Dictionary)
			i += 1
	var midpoint := obstacle_data.size() >> 1
	obstacle_stack.resize(obstacle_data.size())
	#obstacle_thread_1.start(load_range.bind(0, midpoint))
	Utils.custom_thread_call(obstacle_thread_1, load_range, [0, midpoint])
	load_range.bind(midpoint, obstacle_data.size()).call()
	#obstacle_thread_1.wait_to_finish()
	Utils.custom_thread_wait_to_finish(obstacle_thread_1)

static func load_arc_stack_v3(arc_data: Array) -> void:
	var last_index := arc_data.size() - 1
	var load_range := func(start: int, end: int) -> void:
		var i := start
		while i < end:
			if arc_data[i] is Dictionary:
				@warning_ignore("unsafe_cast")
				arc_stack[last_index - i] = ArcInfo.new_v3(arc_data[i] as Dictionary)
			i += 1
	var midpoint := arc_data.size() >> 1
	arc_stack.resize(arc_data.size())
	#arc_thread_1.start(load_range.bind(0, midpoint))
	Utils.custom_thread_call(arc_thread_1, load_range, [0, midpoint])
	load_range.bind(midpoint, arc_data.size()).call()
	#arc_thread_1.wait_to_finish()
	Utils.custom_thread_wait_to_finish(arc_thread_1)

static func load_chain_stack_v3(chain_data: Array) -> void:
	var last_index := chain_data.size() - 1
	var load_range := func(start: int, end: int) -> void:
		var i := start
		while i < end:
			if chain_data[i] is Dictionary:
				@warning_ignore("unsafe_cast")
				chain_stack[last_index - i] = ChainInfo.new_v3(chain_data[i] as Dictionary)
			i += 1
	var midpoint := chain_data.size() >> 1
	chain_stack.resize(chain_data.size())
	#chain_thread_1.start(load_range.bind(0, midpoint))
	Utils.custom_thread_call(chain_thread_1, load_range, [0, midpoint])
	load_range.bind(midpoint, chain_data.size()).call()
	#chain_thread_1.wait_to_finish()
	Utils.custom_thread_wait_to_finish(chain_thread_1)

static func load_event_stack_v3(event_data: Array) -> void:
	var last_index := event_data.size() - 1
	var load_range := func(start: int, end: int) -> void:
		var i := start
		while i < end:
			if event_data[i] is Dictionary:
				@warning_ignore("unsafe_cast")
				event_stack[last_index - i] = EventInfo.new_v3(event_data[i] as Dictionary)
			i += 1
	var midpoint := event_data.size() >> 1
	event_stack.resize(event_data.size())
	#event_thread_1.start(load_range.bind(0, midpoint))
	Utils.custom_thread_call(event_thread_1, load_range, [0, midpoint])
	load_range.bind(midpoint, event_data.size()).call()
	#event_thread_1.wait_to_finish()
	Utils.custom_thread_wait_to_finish(event_thread_1)

# --- v4 -> v3 expansion --------------------------------------------------------------------
# v4 stores each object's geometry once in a `...Data` collection and references it by index,
# so several objects can share one definition. The game needs a concrete object per note, so
# the index is resolved here and the result written in the v3 field names.
static func _v4_to_v3(map_data: Dictionary, lightshow_data: Dictionary) -> void:
	var note_data := Utils.get_array(map_data, "colorNotesData", [])
	var bomb_data := Utils.get_array(map_data, "bombNotesData", [])
	var obstacle_data := Utils.get_array(map_data, "obstaclesData", [])
	var arc_data := Utils.get_array(map_data, "arcsData", [])
	var chain_data := Utils.get_array(map_data, "chainsData", [])
	var event_data := Utils.get_array(lightshow_data, "basicEventsData", [])

	map_data["colorNotes"] = _v4_expand_notes(Utils.get_array(map_data, "colorNotes", []), note_data)
	map_data["bombNotes"] = _v4_expand_bombs(Utils.get_array(map_data, "bombNotes", []), bomb_data)
	map_data["obstacles"] = _v4_expand_obstacles(Utils.get_array(map_data, "obstacles", []), obstacle_data)
	map_data["sliders"] = _v4_expand_arcs(
		Utils.get_array(map_data, "arcs", []), note_data, arc_data)
	map_data["burstSliders"] = _v4_expand_chains(
		Utils.get_array(map_data, "chains", []), note_data, chain_data)
	map_data["basicBeatmapEvents"] = _v4_expand_events(
		Utils.get_array(lightshow_data, "basicEvents", []), event_data)


static func _v4_at(entry: Dictionary, data: Array, key: String, default: int = -1) -> Dictionary:
	var idx := int(Utils.get_float(entry, key, float(default)))
	if idx < 0 or idx >= data.size() or not (data[idx] is Dictionary):
		return {}
	@warning_ignore("unsafe_cast")
	return data[idx] as Dictionary


static func _v4_expand_notes(list: Array, data: Array) -> Array:
	var out: Array = []
	for e: Variant in list:
		if not (e is Dictionary):
			continue
		@warning_ignore("unsafe_cast")
		var entry := e as Dictionary
		var d := _v4_at(entry, data, "i")
		if d.is_empty():
			continue
		out.append({
			"b": Utils.get_float(entry, "b", 0.0),
			"x": Utils.get_float(d, "x", 0.0),
			"y": Utils.get_float(d, "y", 0.0),
			"c": Utils.get_float(d, "c", -1.0),
			"d": Utils.get_float(d, "d", 0.0),
			"a": Utils.get_float(d, "a", 0.0),
			"customData": entry.get("customData", d.get("customData", {})),
		})
	return out


static func _v4_expand_bombs(list: Array, data: Array) -> Array:
	var out: Array = []
	for e: Variant in list:
		if not (e is Dictionary):
			continue
		@warning_ignore("unsafe_cast")
		var entry := e as Dictionary
		var d := _v4_at(entry, data, "i")
		if d.is_empty():
			continue
		out.append({
			"b": Utils.get_float(entry, "b", 0.0),
			"x": Utils.get_float(d, "x", 0.0),
			"y": Utils.get_float(d, "y", 0.0),
		})
	return out


static func _v4_expand_obstacles(list: Array, data: Array) -> Array:
	var out: Array = []
	for e: Variant in list:
		if not (e is Dictionary):
			continue
		@warning_ignore("unsafe_cast")
		var entry := e as Dictionary
		var d := _v4_at(entry, data, "i")
		if d.is_empty():
			continue
		out.append({
			"b": Utils.get_float(entry, "b", 0.0),
			"d": Utils.get_float(d, "d", 0.0),
			"x": Utils.get_float(d, "x", 0.0),
			"y": Utils.get_float(d, "y", 0.0),
			"w": Utils.get_float(d, "w", 0.0),
			"h": Utils.get_float(d, "h", 0.0),
		})
	return out


static func _v4_expand_arcs(list: Array, note_data: Array, arc_data: Array) -> Array:
	var out: Array = []
	for e: Variant in list:
		if not (e is Dictionary):
			continue
		@warning_ignore("unsafe_cast")
		var entry := e as Dictionary
		var head := _v4_at(entry, note_data, "hi")
		var tail := _v4_at(entry, note_data, "ti")
		var meta := _v4_at(entry, arc_data, "ai")
		if head.is_empty() or tail.is_empty():
			continue
		out.append({
			"c": Utils.get_float(head, "c", 0.0),
			"b": Utils.get_float(entry, "hb", 0.0),
			"x": Utils.get_float(head, "x", 0.0),
			"y": Utils.get_float(head, "y", 0.0),
			"d": Utils.get_float(head, "d", 0.0),
			"mu": Utils.get_float(meta, "m", 1.0),
			"tb": Utils.get_float(entry, "tb", 0.0),
			"tx": Utils.get_float(tail, "x", 0.0),
			"ty": Utils.get_float(tail, "y", 0.0),
			"tc": Utils.get_float(tail, "d", 0.0),
			"tmu": Utils.get_float(meta, "tm", 1.0),
			"m": Utils.get_float(meta, "a", 0.0),
		})
	return out


static func _v4_expand_chains(list: Array, note_data: Array, chain_data: Array) -> Array:
	var out: Array = []
	for e: Variant in list:
		if not (e is Dictionary):
			continue
		@warning_ignore("unsafe_cast")
		var entry := e as Dictionary
		var head := _v4_at(entry, note_data, "i")
		var meta := _v4_at(entry, chain_data, "ci")
		if head.is_empty() or meta.is_empty():
			continue
		out.append({
			"c": Utils.get_float(head, "c", 0.0),
			"b": Utils.get_float(entry, "hb", 0.0),
			"x": Utils.get_float(head, "x", 0.0),
			"y": Utils.get_float(head, "y", 0.0),
			"d": Utils.get_float(head, "d", 0.0),
			"tb": Utils.get_float(entry, "tb", 0.0),
			"tx": Utils.get_float(meta, "tx", 0.0),
			"ty": Utils.get_float(meta, "ty", 0.0),
			"sc": Utils.get_float(meta, "c", 0.0),
			"s": Utils.get_float(meta, "s", 1.0),
		})
	return out


static func _v4_expand_events(list: Array, data: Array) -> Array:
	var out: Array = []
	for e: Variant in list:
		if not (e is Dictionary):
			continue
		@warning_ignore("unsafe_cast")
		var entry := e as Dictionary
		var d := _v4_at(entry, data, "i")
		out.append({
			"b": Utils.get_float(entry, "b", 0.0),
			"et": Utils.get_float(d, "t", 0.0),
			"i": Utils.get_float(d, "i", 0.0),
			"f": Utils.get_float(d, "f", -1.0),
		})
	return out


static func load_beatmap(info: MapInfo, difficulty: DifficultyInfo, map_data: Dictionary, lightshow_data: Dictionary = {}, audio_data: Dictionary = {}) -> bool:
	# v4 splits the beatmap and the lightshow into two files and references shared geometry
	# through index arrays. Expand it into the flat v3 shape once, up front, so every object
	# type keeps a single parser (the v3 loaders below) instead of gaining a second one.
	fakes_filtered = 0
	if Utils.get_str(map_data, "version", "").begins_with("4."):
		_v4_to_v3(map_data, lightshow_data)
		map_data["version"] = "3.0.0"
	# Ensures the map_data dict has a version (some maps include the version only on info but not in the data)
	if !map_data.has("_version") and !map_data.has("version"):
		if info.version.begins_with("2.") or info.version.begins_with("1."):
			map_data["_version"] = info.version
		else:
			map_data["version"] = info.version
	MapTimer.load_bpm_events(map_data, info.beats_per_minute, audio_data)
	bpm_segments = MapTimer.segment_count()
	_detect_unsupported(map_data)
	vr.log_info("MAP data: bpm_segments=%d fakes_filtered=%d unsupported=%s" % [bpm_segments, fakes_filtered, str(unsupported_features)])
	
	if map_data.has("_version"):
		#note_thread_0.start(load_note_stack_v2.bind(Utils.get_array(map_data, "_notes", [])))
		Utils.custom_thread_call(note_thread_0, load_note_stack_v2, [Utils.get_array(map_data, "_notes", [])])
		#obstacle_thread_0.start(load_obstacle_stack_v2.bind(Utils.get_array(map_data, "_obstacles", [])))
		Utils.custom_thread_call(obstacle_thread_0, load_obstacle_stack_v2, [Utils.get_array(map_data, "_obstacles", [])])
		#event_thread_0.start(load_event_stack_v2.bind(Utils.get_array(map_data, "_events", [])))
		Utils.custom_thread_call(event_thread_0, load_event_stack_v2, [Utils.get_array(map_data, "_events", [])])
		#arc_thread_0.start(load_arc_stack_v2.bind(Utils.get_array(map_data, "_sliders", [])))
		Utils.custom_thread_call(arc_thread_0, load_arc_stack_v2, [Utils.get_array(map_data, "_sliders", [])])
		chain_stack.clear()
		current_info = info
		current_difficulty = difficulty
		Map.set_colors_from_custom_data()
		#note_thread_0.wait_to_finish()
		Utils.custom_thread_wait_to_finish(note_thread_0)
		#obstacle_thread_0.wait_to_finish()
		Utils.custom_thread_wait_to_finish(obstacle_thread_0)
		#event_thread_0.wait_to_finish()
		Utils.custom_thread_wait_to_finish(event_thread_0)
		#arc_thread_0.wait_to_finish()
		Utils.custom_thread_wait_to_finish(arc_thread_0)
		return true
	elif map_data.has("version"):
		var version := Utils.get_str(map_data, "version", "")
		if version.begins_with("3."):
			#note_thread_0.start(load_note_stack_v3.bind(Utils.get_array(map_data, "colorNotes", [])))
			Utils.custom_thread_call(note_thread_0, load_note_stack_v3, [Utils.get_array(map_data, "colorNotes", [])])
			#bomb_thread_0.start(load_bomb_stack_v3.bind(Utils.get_array(map_data, "bombNotes", [])))
			Utils.custom_thread_call(bomb_thread_0, load_bomb_stack_v3, [Utils.get_array(map_data, "bombNotes", [])])
			#obstacle_thread_0.start(load_obstacle_stack_v3.bind(Utils.get_array(map_data, "obstacles", [])))
			Utils.custom_thread_call(obstacle_thread_0, load_obstacle_stack_v3, [Utils.get_array(map_data, "obstacles", [])])
			#arc_thread_0.start(load_arc_stack_v3.bind(Utils.get_array(map_data, "sliders", [])))
			Utils.custom_thread_call(arc_thread_0, load_arc_stack_v3, [Utils.get_array(map_data, "sliders", [])])
			#chain_thread_0.start(load_chain_stack_v3.bind(Utils.get_array(map_data, "burstSliders", [])))
			Utils.custom_thread_call(chain_thread_0, load_chain_stack_v3, [Utils.get_array(map_data, "burstSliders", [])])
			#event_thread_0.start(load_event_stack_v3.bind(Utils.get_array(map_data, "basicBeatmapEvents", [])))
			var event_list := Utils.get_array(map_data, "basicBeatmapEvents", [])
			# FR-029: v3 keeps boost in its own array. Convert to the v2 type 5 event so one
			# code path in event_driver handles both formats.
			for b: Variant in Utils.get_array(map_data, "colorBoostBeatmapEvents", []):
				if not (b is Dictionary):
					continue
				@warning_ignore("unsafe_cast")
				var bd := b as Dictionary
				event_list.append({"b": Utils.get_float(bd, "b", 0.0), "et": 5.0, "i": Utils.get_float(bd, "i", 0.0), "f": -1.0})
			event_list.sort_custom(func(x: Variant, y: Variant) -> bool:
				return Utils.get_float(x as Dictionary, "b", 0.0) < Utils.get_float(y as Dictionary, "b", 0.0))
			Utils.custom_thread_call(event_thread_0, load_event_stack_v3, [event_list])
			current_info = info
			current_difficulty = difficulty
			Map.set_colors_from_custom_data()
			#note_thread_0.wait_to_finish()
			Utils.custom_thread_wait_to_finish(note_thread_0)
			#bomb_thread_0.wait_to_finish()
			Utils.custom_thread_wait_to_finish(bomb_thread_0)
			#obstacle_thread_0.wait_to_finish()
			Utils.custom_thread_wait_to_finish(obstacle_thread_0)
			#arc_thread_0.wait_to_finish()
			Utils.custom_thread_wait_to_finish(arc_thread_0)
			#chain_thread_0.wait_to_finish()
			Utils.custom_thread_wait_to_finish(chain_thread_0)
			#event_thread_0.wait_to_finish()
			Utils.custom_thread_wait_to_finish(event_thread_0)
			return true
	vr.log_warning("selected map is an unsupported version")
	return false

