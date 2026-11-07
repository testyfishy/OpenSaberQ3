extends RefCounted
class_name MapData

# The spawned-object stacks and their loaders (specs/013 FR-007, final Map split).
#
# Map keeps the metadata and the format dispatch; MapData owns the six stacks and the twelve
# loader threads that fill them. Every load starts from reset(), which clears the stacks and joins
# any thread a previous load left behind, so a second map cannot see the first map's notes.

static var note_stack: Array[ColorNoteInfo]
static var bomb_stack: Array[BombInfo]
static var obstacle_stack: Array[ObstacleInfo]
static var arc_stack: Array[ArcInfo]
static var chain_stack: Array[ChainInfo]
static var event_stack: Array[EventInfo]

# Large maps take a long time to parse. Each per-type loader splits the array in half and parses
# the two halves concurrently; the thread_1 worker is joined inside the loader, the thread_0
# workers are started by load_v2()/load_v3() and joined before the map returns.
static var _note_thread_0 := Thread.new()
static var _note_thread_1 := Thread.new()
static var _bomb_thread_0 := Thread.new()
static var _bomb_thread_1 := Thread.new()
static var _obstacle_thread_0 := Thread.new()
static var _obstacle_thread_1 := Thread.new()
static var _arc_thread_0 := Thread.new()
static var _arc_thread_1 := Thread.new()
static var _chain_thread_0 := Thread.new()
static var _chain_thread_1 := Thread.new()
static var _event_thread_0 := Thread.new()
static var _event_thread_1 := Thread.new()

static func reset() -> void:
	# Join first: a thread that somehow outlived a load must finish before its stack is cleared.
	# (load_v2/load_v3 are synchronous, so in practice this is a safety net.)
	var threads: Array[Thread] = [
		_note_thread_0, _note_thread_1, _bomb_thread_0, _bomb_thread_1,
		_obstacle_thread_0, _obstacle_thread_1, _arc_thread_0, _arc_thread_1,
		_chain_thread_0, _chain_thread_1, _event_thread_0, _event_thread_1,
	]
	for thread: Thread in threads:
		# wait_to_finish() on a thread that never started is an error.
		if thread.is_started():
			thread.wait_to_finish()
	note_stack.clear()
	bomb_stack.clear()
	obstacle_stack.clear()
	arc_stack.clear()
	chain_stack.clear()
	event_stack.clear()

static func load_v2(map_data: Dictionary) -> void:
	Utils.custom_thread_call(_note_thread_0, load_note_stack_v2, [Utils.get_array(map_data, "_notes", [])])
	Utils.custom_thread_call(_obstacle_thread_0, load_obstacle_stack_v2, [Utils.get_array(map_data, "_obstacles", [])])
	Utils.custom_thread_call(_event_thread_0, load_event_stack_v2, [Utils.get_array(map_data, "_events", [])])
	Utils.custom_thread_call(_arc_thread_0, load_arc_stack_v2, [Utils.get_array(map_data, "_sliders", [])])
	chain_stack.clear()
	Utils.custom_thread_wait_to_finish(_note_thread_0)
	Utils.custom_thread_wait_to_finish(_obstacle_thread_0)
	Utils.custom_thread_wait_to_finish(_event_thread_0)
	Utils.custom_thread_wait_to_finish(_arc_thread_0)

static func load_v3(map_data: Dictionary) -> void:
	Utils.custom_thread_call(_note_thread_0, load_note_stack_v3, [Utils.get_array(map_data, "colorNotes", [])])
	Utils.custom_thread_call(_bomb_thread_0, load_bomb_stack_v3, [Utils.get_array(map_data, "bombNotes", [])])
	Utils.custom_thread_call(_obstacle_thread_0, load_obstacle_stack_v3, [Utils.get_array(map_data, "obstacles", [])])
	Utils.custom_thread_call(_arc_thread_0, load_arc_stack_v3, [Utils.get_array(map_data, "sliders", [])])
	Utils.custom_thread_call(_chain_thread_0, load_chain_stack_v3, [Utils.get_array(map_data, "burstSliders", [])])
	var event_list := Utils.get_array(map_data, "basicBeatmapEvents", [])
	# FR-029: v3 keeps boost in its own array. Convert to the v2 type 5 event so one code path in
	# event_driver handles both formats.
	for b: Variant in Utils.get_array(map_data, "colorBoostBeatmapEvents", []):
		if not (b is Dictionary):
			continue
		@warning_ignore("unsafe_cast")
		var bd := b as Dictionary
		event_list.append({"b": Utils.get_float(bd, "b", 0.0), "et": 5.0, "i": Utils.get_float(bd, "i", 0.0), "f": -1.0})
	event_list.sort_custom(func(x: Variant, y: Variant) -> bool:
		return Utils.get_float(x as Dictionary, "b", 0.0) < Utils.get_float(y as Dictionary, "b", 0.0))
	Utils.custom_thread_call(_event_thread_0, load_event_stack_v3, [event_list])
	Utils.custom_thread_wait_to_finish(_note_thread_0)
	Utils.custom_thread_wait_to_finish(_bomb_thread_0)
	Utils.custom_thread_wait_to_finish(_obstacle_thread_0)
	Utils.custom_thread_wait_to_finish(_arc_thread_0)
	Utils.custom_thread_wait_to_finish(_chain_thread_0)
	Utils.custom_thread_wait_to_finish(_event_thread_0)

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
			if MapSupport.is_fake_v2(note_dict):
				# FR-026: decorative note from Noodle/Chroma. Hidden and unscored, not a ghost:
				# its real position depends on animation we do not implement.
				MapSupport.fakes_filtered += 1
				i += 1
				continue
			if note_type == 3 and Settings.bombs_enabled:
				bomb_array.append(BombInfo.new_v2(note_dict))
			elif note_type == 0 or note_type == 1:
				note_array.append(ColorNoteInfo.new_v2(note_dict))
			i += 1
		return [note_array, bomb_array]
	var midpoint := note_data.size() >> 1
	#_note_thread_1.start(load_range.bind(0, midpoint))
	Utils.custom_thread_call(_note_thread_1, load_range, [0, midpoint])
	var total_second_half : Array[Array] = load_range.bind(midpoint, note_data.size()).call()
	#var total_first_half : Array[Array] = _note_thread_1.wait_to_finish()
	var total_first_half : Array[Array] = Utils.custom_thread_wait_to_finish(_note_thread_1)
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
	#_obstacle_thread_1.start(load_range.bind(0, midpoint))
	Utils.custom_thread_call(_obstacle_thread_1, load_range, [0, midpoint])
	load_range.bind(midpoint, obstacle_data.size()).call()
	#_obstacle_thread_1.wait_to_finish()
	Utils.custom_thread_wait_to_finish(_obstacle_thread_1)

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
	#_arc_thread_1.start(load_range.bind(0, midpoint))
	Utils.custom_thread_call(_arc_thread_1, load_range, [0, midpoint])
	load_range.bind(midpoint, arc_data.size()).call()
	#_arc_thread_1.wait_to_finish()
	Utils.custom_thread_wait_to_finish(_arc_thread_1)
	

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
	#_event_thread_1.start(load_range.bind(0, midpoint))
	Utils.custom_thread_call(_event_thread_1, load_range, [0, midpoint])
	load_range.bind(midpoint, event_data.size()).call()
	#_event_thread_1.wait_to_finish()
	Utils.custom_thread_wait_to_finish(_event_thread_1)

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
	#_note_thread_1.start(load_range.bind(0, midpoint))
	Utils.custom_thread_call(_note_thread_1, load_range, [0, midpoint])
	load_range.bind(midpoint, note_data.size()).call()
	#_note_thread_1.wait_to_finish()
	Utils.custom_thread_wait_to_finish(_note_thread_1)

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
	#_bomb_thread_1.start(load_range.bind(0, midpoint))
	Utils.custom_thread_call(_bomb_thread_1, load_range, [0, midpoint])
	load_range.bind(midpoint, bomb_data.size()).call()
	#_bomb_thread_1.wait_to_finish()
	Utils.custom_thread_wait_to_finish(_bomb_thread_1)

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
	#_obstacle_thread_1.start(load_range.bind(0, midpoint))
	Utils.custom_thread_call(_obstacle_thread_1, load_range, [0, midpoint])
	load_range.bind(midpoint, obstacle_data.size()).call()
	#_obstacle_thread_1.wait_to_finish()
	Utils.custom_thread_wait_to_finish(_obstacle_thread_1)

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
	#_arc_thread_1.start(load_range.bind(0, midpoint))
	Utils.custom_thread_call(_arc_thread_1, load_range, [0, midpoint])
	load_range.bind(midpoint, arc_data.size()).call()
	#_arc_thread_1.wait_to_finish()
	Utils.custom_thread_wait_to_finish(_arc_thread_1)

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
	#_chain_thread_1.start(load_range.bind(0, midpoint))
	Utils.custom_thread_call(_chain_thread_1, load_range, [0, midpoint])
	load_range.bind(midpoint, chain_data.size()).call()
	#_chain_thread_1.wait_to_finish()
	Utils.custom_thread_wait_to_finish(_chain_thread_1)

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
	#_event_thread_1.start(load_range.bind(0, midpoint))
	Utils.custom_thread_call(_event_thread_1, load_range, [0, midpoint])
	load_range.bind(midpoint, event_data.size()).call()
	#_event_thread_1.wait_to_finish()
	Utils.custom_thread_wait_to_finish(_event_thread_1)


# --- v4 -> v3 expansion --------------------------------------------------------------------
# v4 stores each object's geometry once in a `...Data` collection and references it by index,
# so several objects can share one definition. The game needs a concrete object per note, so
# the index is resolved here and the result written in the v3 field names.
static func v4_to_v3(map_data: Dictionary, lightshow_data: Dictionary) -> void:
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




## specs/027 FR-010/FR-017/FR-018: turn v3/v4 light colour box groups into the basic events the
## driver already understands. Filters, distributions and strobe are ignored (the group colour and
## brightness are applied at the event beat). `i` is the transition type: 0 instant, 1 transition
## (fade to the colour) and 2 extend, where the previous event keeps running.
static func expand_box_group_colors(map_data: Dictionary, lightshow_data: Dictionary) -> void:
	var groups: Array = []
	groups.append_array(Utils.get_array(map_data, "lightColorEventBoxGroups", []))
	groups.append_array(Utils.get_array(lightshow_data, "lightColorEventBoxGroups", []))
	if groups.is_empty():
		return
	var events: Array = Utils.get_array(map_data, "basicBeatmapEvents", [])
	events = events.duplicate()
	# Group ids are defined by the environment, not the map, and a custom environment can use ids
	# the room does not have. Fold them onto the five room types instead of leaving the map dark;
	# the mapping is an approximation (FR-018).
	var folded_ids := {}
	for group in groups:
		if not (group is Dictionary):
			continue
		var raw_group := Utils.get_float(group as Dictionary, "g", 0.0)
		if raw_group < 0.0 or absf(raw_group - roundf(raw_group)) > 0.001:
			continue
		var group_id := int(roundf(raw_group))
		var light_type := group_id % 5
		if group_id > 4:
			folded_ids[group_id] = light_type
		var group_beat := Utils.get_float(group as Dictionary, "b", 0.0)
		for box in Utils.get_array(group as Dictionary, "e", []):
			if not (box is Dictionary):
				continue
			for ev in Utils.get_array(box as Dictionary, "e", []):
				if not (ev is Dictionary):
					continue
				var transition := int(Utils.get_float(ev as Dictionary, "i", 0.0))
				if transition == 2:
					# Extend: hold whatever the previous group event started.
					continue
				var beat := group_beat + Utils.get_float(ev as Dictionary, "b", 0.0)
				var brightness := Utils.get_float(ev as Dictionary, "s", 1.0)
				var color: Variant = (ev as Dictionary).get("c", null)
				# v3/v4 use a colour index: 0 = left/red, 1 = right/blue, 2 = white. Brightness 0
				# is "off"; there is no basic fade-to-black, so the off is instant.
				if color is float or color is int:
					var value := 1
					if brightness <= 0.0:
						value = 0
					else:
						# i=1 uses the basic fade-to-colour values; i=0 the instant on values.
						match int(color):
							0: value = 8 if transition == 1 else 5
							1: value = 4 if transition == 1 else 1
							_: value = 12 if transition == 1 else 9
					events.append({
						"b": beat,
						"et": light_type,
						"i": value,
						"f": brightness,
					})
					continue
				# Older/custom payloads may carry a literal RGB colour.
				var color_dict := {}
				if color is Array and (color as Array).size() >= 3:
					color_dict = {"r": float((color as Array)[0]), "g": float((color as Array)[1]),
						"b": float((color as Array)[2])}
				elif color is Dictionary:
					color_dict = color
				if color_dict.is_empty():
					continue
				events.append({
					"b": beat,
					"et": light_type,
					"i": 0 if brightness <= 0.0 else (4 if transition == 1 else 1),
					"f": brightness,
					"customData": {"color": color_dict},
				})
	if not folded_ids.is_empty():
		vr.log_info("box groups folded onto room lights: %s" % str(folded_ids))
	map_data["basicBeatmapEvents"] = events
