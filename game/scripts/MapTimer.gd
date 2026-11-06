extends RefCounted

# BPM segments for the loaded map (specs/013 FR-007, first Map split).
#
# Maps may change BPM mid-song. Every beat<->time conversion in the game goes through here, so
# notes, walls, arcs, light events, the bot and the bench clock agree after a change instead of
# drifting against the audio.
#
# Static state, like Map: it survives a scene change, so reset() is explicit and load_bpm_events()
# starts from it.

static var _beats := PackedFloat32Array([0.0])
static var _values := PackedFloat32Array([60.0])
static var _times := PackedFloat32Array([0.0])

static func reset() -> void:
	_beats = PackedFloat32Array([0.0])
	_values = PackedFloat32Array([60.0])
	_times = PackedFloat32Array([0.0])

static func segment_count() -> int:
	return _beats.size()

static func load_bpm_events(map_data: Dictionary, base_bpm: float, audio_data: Dictionary = {}) -> void:
	reset()
	var points: Array[Vector2] = [Vector2(0.0, base_bpm)]
	for e: Variant in Utils.get_array(map_data, "bpmEvents", []):
		if not (e is Dictionary):
			continue
		@warning_ignore("unsafe_cast")
		var d := e as Dictionary
		var beat := Utils.get_float(d, "b", 0.0)
		var bpm := Utils.get_float(d, "m", 0.0)
		if bpm > 1.0 and beat >= 0.0:
			points.append(Vector2(beat, bpm))
	# v2 keeps BPM changes in the event list: type 100 (older maps use 10). The new BPM is
	# usually the event value; some tools write it as the float value.
	for e: Variant in Utils.get_array(map_data, "_events", []):
		if not (e is Dictionary):
			continue
		@warning_ignore("unsafe_cast")
		var d := e as Dictionary
		var t := int(Utils.get_float(d, "_type", -1))
		if t != 100 and t != 10:
			continue
		var beat := Utils.get_float(d, "_time", 0.0)
		var bpm := Utils.get_float(d, "_floatValue", -1.0)
		if bpm <= 1.0:
			bpm = Utils.get_float(d, "_value", 0.0)
		if bpm > 1.0 and beat >= 0.0:
			points.append(Vector2(beat, bpm))
	# v4 keeps BPM in the audio file: sample ranges plus the beat range they cover, so the
	# tempo is derived rather than stored. Only used when the map itself has no bpmEvents.
	if points.size() == 1:
		var freq := Utils.get_float(audio_data, "songFrequency", 44100.0)
		for seg: Variant in Utils.get_array(audio_data, "bpmData", []):
			if not (seg is Dictionary):
				continue
			@warning_ignore("unsafe_cast")
			var sd := seg as Dictionary
			var sb := Utils.get_float(sd, "sb", 0.0)
			var eb := Utils.get_float(sd, "eb", sb)
			var si := Utils.get_float(sd, "si", 0.0)
			var ei := Utils.get_float(sd, "ei", si)
			var seconds := (ei - si) / maxf(freq, 1.0)
			if seconds > 0.0 and eb > sb:
				points.append(Vector2(sb, (eb - sb) / seconds * 60.0))
	points.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var beats := PackedFloat32Array()
	var values := PackedFloat32Array()
	for point in points:
		if not beats.is_empty() and is_equal_approx(beats[beats.size() - 1], point.x):
			values[values.size() - 1] = point.y
		else:
			beats.append(point.x)
			values.append(point.y)
	_beats = beats
	_values = values
	_times.resize(beats.size())
	_times[0] = 0.0
	for i in range(1, beats.size()):
		_times[i] = _times[i - 1] + (beats[i] - beats[i - 1]) * 60.0 / maxf(values[i - 1], 1.0)

static func bpm_at_beat(beat: float) -> float:
	return _values[segment_index_at_beat(beat)]

static func beat_to_seconds(beat: float) -> float:
	if _beats.is_empty():
		return 0.0
	if beat <= _beats[0]:
		return beat * 60.0 / maxf(_values[0], 1.0)
	var i := segment_index_at_beat(beat)
	return _times[i] + (beat - _beats[i]) * 60.0 / maxf(_values[i], 1.0)

static func seconds_to_beat(seconds: float) -> float:
	if _beats.is_empty():
		return 0.0
	if seconds <= 0.0:
		return seconds * _values[0] / 60.0
	var lo := 0
	var hi := _times.size() - 1
	while lo < hi:
		@warning_ignore("integer_division")
		var mid := (lo + hi + 1) >> 1
		if _times[mid] <= seconds:
			lo = mid
		else:
			hi = mid - 1
	return _beats[lo] + (seconds - _times[lo]) * _values[lo] / 60.0

static func segment_index_at_beat(beat: float) -> int:
	var lo := 0
	var hi := _beats.size() - 1
	while lo < hi:
		@warning_ignore("integer_division")
		var mid := (lo + hi + 1) >> 1
		if _beats[mid] <= beat:
			lo = mid
		else:
			hi = mid - 1
	return lo
