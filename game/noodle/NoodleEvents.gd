extends RefCounted
class_name NoodleEvents

# Heck / Noodle Extensions custom events: AnimateTrack, AssignPathAnimation, AssignTrackParent
# and AssignPlayerToTrack. Parsed once at load into a stack sorted by beat (spawn order, like
# MapData's stacks), dispatched by GameStatePlaying when the song reaches them, and evaluated
# lazily: a track's running animations are stepped only when something reads the track (sync(),
# track_xform()), at most once per tick, so a map with thousands of tracks and long animations
# pays only for the tracks its live objects, parents and player actually use. The values read
# are the same as stepping every animation every tick (see sync() for why).
#
# Timing follows Heck's CoroutineEventManager: an event's duration is in beats, converted to
# seconds with the BPM at the event's own beat; its start is the event's time, not the frame it
# was dispatched in; `repeat` plays it again that many times back to back; a duration of 0, a
# single-point definition, or an event already entirely in the past sets the final value at
# once. Starting an animation of a property that is already animating stops the old one.
#
# Every other custom event type (Chroma, Vivify, fog...) is counted in `ignored` and otherwise
# skipped, so MapSupport can name what a map uses that this build does not do.

enum { ANIMATE_TRACK, ASSIGN_PATH_ANIMATION, ASSIGN_TRACK_PARENT, ASSIGN_PLAYER_TO_TRACK }

const TYPES := {
	"AnimateTrack": ANIMATE_TRACK,
	"AssignPathAnimation": ASSIGN_PATH_ANIMATION,
	"AssignTrackParent": ASSIGN_TRACK_PARENT,
	"AssignPlayerToTrack": ASSIGN_PLAYER_TO_TRACK,
}


class Event extends RefCounted:
	var beat := 0.0
	var order := 0
	var type := ANIMATE_TRACK
	var tracks := PackedInt32Array()
	# Parallel arrays: property index and its points (null = set the property to null).
	var props := PackedInt32Array()
	var points: Array[NoodlePoints] = []
	var duration := 0.0
	var easing := NoodleEasing.LINEAR
	var repeat := 0
	var parent := -1


class Anim extends RefCounted:
	var track: NoodleTrack
	var prop := 0
	var points: NoodlePoints
	var start := 0.0
	var duration := 1.0
	var easing := NoodleEasing.LINEAR
	var repeat := 0


# Spawn-order stack: the next event is at the back.
static var stack: Array[Event] = []
# Running animations live on their track (NoodleTrack.tw / ptw, one per property). Path
# transitions reuse Anim: `points` is unused, the track's path_blend is driven instead.
# Every track that ever had one (each once), for the catch-up before time goes backwards.
static var _busy: Array[NoodleTrack] = []
# How many animations are running (value and path), for the bench probe.
static var _live := 0
# The update() count and the song time of the last update(): what a read brings a track to.
static var _tick := 0
static var _now := -INF
# The track the player is assigned to (-1 for none) and the transform the game's track root
# takes so the world is drawn relative to that player (see update()).
static var player_track := -1
static var root_xform := Transform3D.IDENTITY
# Custom event type -> count, for every type this build does not act on.
static var ignored := {}
# How many event properties used point features that are not evaluated (bases, modifiers), and
# how many AssignPlayerToTrack events targeted something other than the player's root.
static var unsupported_points := 0
static var unsupported_targets := 0
# Event properties that were read but are not applied (time) or not known at all
# (Chroma `color`...), name -> count.
static var unapplied := {}
const EVENT_KEYS := ["track", "duration", "easing", "repeat"]


static func reset() -> void:
	stack.clear()
	_busy.clear()
	_live = 0
	_tick += 1
	_now = -INF
	player_track = -1
	root_xform = Transform3D.IDENTITY
	ignored = {}
	unsupported_points = 0
	unsupported_targets = 0
	unapplied = {}


## Parses the map's custom events (v3 `customData.customEvents` {b, t, d}; v2
## `_customData._customEvents` {_time, _type, _data}). Main thread: creates tracks.
static func load_events(map_data: Dictionary) -> void:
	var raw: Array = []
	var cd3: Variant = map_data.get("customData", null)
	if cd3 is Dictionary and (cd3 as Dictionary).get("customEvents", null) is Array:
		for e: Variant in (cd3 as Dictionary)["customEvents"] as Array:
			if e is Dictionary:
				raw.append([e, false])
	var cd2: Variant = map_data.get("_customData", null)
	if cd2 is Dictionary and (cd2 as Dictionary).get("_customEvents", null) is Array:
		for e: Variant in (cd2 as Dictionary)["_customEvents"] as Array:
			if e is Dictionary:
				raw.append([e, true])
	var events: Array[Event] = []
	for pair: Array in raw:
		var ev := _parse(pair[0] as Dictionary, bool(pair[1]))
		if ev != null:
			ev.order = events.size()
			events.append(ev)
	# Sort by beat, keeping file order within a beat: several events on one beat can target the
	# same property, and the last one in the file must win. sort_custom is not stable, so the
	# file index breaks ties.
	events.sort_custom(func(a: Event, b: Event) -> bool:
		return a.beat < b.beat or (a.beat == b.beat and a.order < b.order))
	events.reverse()
	stack = events
	if not stack.is_empty():
		NoodleTracks.active = true


static func _parse(e: Dictionary, v2: bool) -> Event:
	var type_name: Variant = e.get("_type", null) if v2 else e.get("t", null)
	if not (type_name is String):
		return null
	if not TYPES.has(type_name):
		ignored[type_name] = int(ignored.get(type_name, 0)) + 1
		return null
	var d: Variant = e.get("_data", null) if v2 else e.get("d", null)
	if not (d is Dictionary):
		return null
	var data := d as Dictionary
	var ev := Event.new()
	ev.type = int(TYPES[type_name])
	ev.beat = float(e.get("_time", 0.0) if v2 else e.get("b", 0.0))
	var k := "_" if v2 else ""
	ev.duration = maxf(float(_num(data.get(k + "duration", 0.0))), 0.0)
	ev.easing = NoodleEasing.from_name(data.get(k + "easing", "easeLinear"))
	ev.repeat = maxi(int(_num(data.get(k + "repeat", 0))), 0)
	match ev.type:
		ANIMATE_TRACK, ASSIGN_PATH_ANIMATION:
			for track_name in NoodleTracks.names_from(data.get(k + "track", null)):
				ev.tracks.append(NoodleTracks.index_of(track_name))
			var names: Dictionary = NoodleTracks.V2_NAMES if v2 else NoodleTracks.V3_NAMES
			for key: Variant in data:
				if not names.has(key):
					if not EVENT_KEYS.has(String(key).trim_prefix("_")):
						unapplied[key] = int(unapplied.get(key, 0)) + 1
					continue
				var p := int(names[key])
				if p == NoodleTracks.P_TIME:
					unapplied[key] = int(unapplied.get(key, 0)) + 1
				if ev.type == ASSIGN_PATH_ANIMATION and p > NoodleTracks.P_DEFINITE_POSITION:
					continue  # not a path property
				if ev.type == ANIMATE_TRACK and p == NoodleTracks.P_DEFINITE_POSITION:
					continue  # path-only
				var value: Variant = data[key]
				var pts: NoodlePoints = null
				if value != null:
					pts = NoodlePoints.from_value(value, NoodleTracks.KINDS[p], NoodleTracks.named)
					if pts == null:
						continue  # malformed: skip, as Heck would fail to read it
					if pts.unsupported != "":
						unsupported_points += 1
						continue
				ev.props.append(p)
				ev.points.append(pts)
			if ev.tracks.is_empty():
				return null
		ASSIGN_TRACK_PARENT:
			var parent_name: Variant = data.get(k + "parentTrack", null)
			if not (parent_name is String) or parent_name == "":
				return null
			ev.parent = NoodleTracks.index_of(parent_name)
			for track_name in NoodleTracks.names_from(data.get(k + "childrenTracks", null)):
				var child := NoodleTracks.index_of(track_name)
				if child != ev.parent:
					ev.tracks.append(child)
		ASSIGN_PLAYER_TO_TRACK:
			var target: Variant = data.get(k + "target", "Root")
			if target is String and target != "Root":
				# Head and hand targets would move the player's own body parts; not done here.
				unsupported_targets += 1
				return null
			var names := NoodleTracks.names_from(data.get(k + "track", null))
			if names.is_empty():
				return null
			ev.tracks.append(NoodleTracks.index_of(names[0]))
	return ev


static func _num(v: Variant) -> float:
	return float(v) if v is float or v is int else 0.0


## Starts every event whose beat has been reached. Called once per tick before update().
static func dispatch_until(current_beat: float, song_sec: float) -> void:
	while not stack.is_empty() and stack[-1].beat <= current_beat:
		dispatch(stack.pop_back(), song_sec)


static func dispatch(ev: Event, song_sec: float) -> void:
	if song_sec < _now:
		_catch_up(song_sec)
	var start := Map.beat_to_seconds(ev.beat)
	var duration := 60.0 * ev.duration / maxf(Map.bpm_at_beat(ev.beat), 1.0)
	var no_duration := duration <= 0.0 or start + duration * float(ev.repeat + 1) < song_sec
	match ev.type:
		ANIMATE_TRACK:
			for ti in ev.tracks:
				var track := NoodleTracks.tracks[ti]
				# Bring the track's other animations to the last update first: a read before the
				# next update sees them there and this one at `song_sec`, as when every animation
				# was stepped every tick.
				sync(track)
				for j in ev.props.size():
					var p := ev.props[j]
					var pts := ev.points[j]
					_stop(track, p, false)
					if pts == null:
						track.clear_value(p)
					elif no_duration or pts.count() <= 1:
						track.set_from_points(p, pts, 1.0)
					else:
						var tw := Anim.new()
						tw.track = track
						tw.prop = p
						tw.points = pts
						tw.start = start
						tw.duration = duration
						tw.easing = ev.easing
						tw.repeat = ev.repeat
						_start(track, p, tw, false)
						_step_value(tw, song_sec)
				track.synced = _tick
		ASSIGN_PATH_ANIMATION:
			for ti in ev.tracks:
				var track := NoodleTracks.tracks[ti]
				sync(track)
				track.has_path = true
				for j in ev.props.size():
					var p := ev.props[j]
					var pts := ev.points[j]
					_stop(track, p, true)
					track.path_prev[p] = track.path_cur[p]
					track.set_path(p, pts)
					track.path_blend[p] = 0.0
					if pts == null or no_duration:
						track.path_prev[p] = null
						track.path_blend[p] = 1.0
					else:
						var tw := Anim.new()
						tw.track = track
						tw.prop = p
						tw.start = start
						tw.duration = duration
						tw.easing = ev.easing
						_start(track, p, tw, true)
						_step_path(tw, song_sec)
				track.synced = _tick
		ASSIGN_TRACK_PARENT:
			_mark_transform(NoodleTracks.tracks[ev.parent])
			for ti in ev.tracks:
				NoodleTracks.tracks[ti].parent = ev.parent
		ASSIGN_PLAYER_TO_TRACK:
			player_track = ev.tracks[0]
			_mark_transform(NoodleTracks.tracks[player_track])


static func _mark_transform(t: NoodleTrack) -> void:
	t.is_transform = true


static func _start(track: NoodleTrack, p: int, tw: Anim, path: bool) -> void:
	if track.tw.is_empty():
		track.tw.resize(NoodleTracks.P_COUNT)
		track.ptw.resize(NoodleTracks.P_COUNT)
	if path:
		track.ptw[p] = tw
	else:
		track.tw[p] = tw
	track.tw_count += 1
	_live += 1
	if not track.busy:
		track.busy = true
		_busy.append(track)


# Stops the running animation of property `p` (Heck: a new animation of a property stops the
# old one). O(1): there is at most one per track and property.
static func _stop(track: NoodleTrack, p: int, path: bool) -> void:
	if track.tw_count == 0:
		return
	var list := track.ptw if path else track.tw
	if list[p] != null:
		list[p] = null
		track.tw_count -= 1
		_live -= 1


## Brings `track`'s running animations to the song time of the last update(), once per tick.
## Every reader of track values calls this first (NoodleAnim.evaluate, track_xform).
##
## Why stepping late gives the same values: an animation's value depends only on the time it is
## stepped at and on its start, which each used-up repeat advances by one duration. While time
## only moves forward, one step at the latest time uses up the same repeats (the test is
## monotonic in time) and so reaches the same start by the same additions as stepping at every
## tick on the way, and elapsed time is then taken from that start either way. A finished animation leaves its end value whenever it is
## stepped. A new animation of the same property replaces the old one's value entirely, so the
## old one's unobserved steps never mattered. Time going backwards (a seek, an audio stall
## snap) is the one case where the ticks in between matter; _catch_up() steps everything at the
## old time first, as every tick would have.
static func sync(track: NoodleTrack) -> void:
	if track.tw_count == 0 or track.synced == _tick:
		return
	track.synced = _tick
	_step_track(track, _now)


static func _step_track(track: NoodleTrack, song_sec: float) -> void:
	for p in NoodleTracks.P_COUNT:
		var tw: Anim = track.tw[p]
		if tw != null and _step_value(tw, song_sec):
			track.tw[p] = null
			track.tw_count -= 1
			_live -= 1
		tw = track.ptw[p]
		if tw != null and _step_path(tw, song_sec):
			track.ptw[p] = null
			track.tw_count -= 1
			_live -= 1


# Time is about to go back from `_now` to `song_sec`: step every running animation at `_now`
# first (what the ticks before this one did when every animation was stepped every tick).
static func _catch_up(song_sec: float) -> void:
	for t in _busy:
		if t.tw_count > 0:
			_step_track(t, _now)
		t.synced = _tick
	_now = song_sec


# Writes the tween's value for `song_sec`; true when it has finished (no repeats left).
static func _step_value(tw: Anim, song_sec: float) -> bool:
	var elapsed := song_sec - tw.start
	while elapsed >= tw.duration and tw.repeat > 0:
		tw.repeat -= 1
		tw.start += tw.duration
		# From the advanced start, not `elapsed - duration`: a late step and a step every tick
		# then do the same arithmetic (see sync()).
		elapsed = song_sec - tw.start
	var u := clampf(elapsed / tw.duration, 0.0, 1.0)
	tw.track.set_from_points(tw.prop, tw.points, NoodleEasing.ease(u, tw.easing))
	return elapsed >= tw.duration


static func _step_path(tw: Anim, song_sec: float) -> bool:
	var elapsed := song_sec - tw.start
	var u := clampf(elapsed / tw.duration, 0.0, 1.0)
	tw.track.path_blend[tw.prop] = NoodleEasing.ease(u, tw.easing)
	if elapsed >= tw.duration:
		tw.track.path_prev[tw.prop] = null
		tw.track.path_blend[tw.prop] = 1.0
		return true
	return false


## Moves the song time the tracks are read at to `song_sec` and refreshes the player's track
## (the world is drawn relative to it). Running animations are stepped when read, not here.
## Allocation-free: tweens are created at dispatch, not here.
static func update(song_sec: float) -> void:
	if song_sec < _now:
		_catch_up(song_sec)
	_tick += 1
	_now = song_sec
	root_xform = Transform3D.IDENTITY
	if player_track >= 0:
		root_xform = track_xform(NoodleTracks.tracks[player_track]).affine_inverse()


## Running animations (value and path), for the bench probe.
static func live_tweens() -> int:
	return _live


## The transform track `t` applies to its children (parents and the player's track): its own
## `local` with its parents' chained on, as of the last update(). Computed when read, once per
## tick per track.
static func track_xform(t: NoodleTrack) -> Transform3D:
	if t.xform_tick == _tick:
		return t.xform
	# Chain parents (a parent track can itself be a child of another), always from the local
	# transforms. Depth-limited so a cycle in a broken map cannot hang the game.
	var list := NoodleTracks.tracks
	var world := _local_of(t)
	var up := t.parent
	var depth := 0
	while up >= 0 and depth < 8:
		world = _local_of(list[up]) * world
		up = list[up].parent
		depth += 1
	t.xform = world
	t.xform_tick = _tick
	return world


static func _local_of(t: NoodleTrack) -> Transform3D:
	if t.local_tick != _tick:
		sync(t)
		t.local = _local_xform(t, NoodleTracks.is_v2)
		t.local_tick = _tick
	return t.local


## The transform a parent or player track applies. v3 (TransformController): localPosition or
## position in metres, localRotation or rotation, scale. v2 (ParentObject / PlayerTrack): the
## offset properties, `_position` in lane units (x 0.6) turned by `_rotation`, then
## `_localRotation`.
static func _local_xform(t: NoodleTrack, v2: bool) -> Transform3D:
	var P := NoodleTracks
	var pos := Vector3.ZERO
	var rot := Quaternion.IDENTITY
	if v2:
		var world := t.quat[P.P_OFFSET_WORLD_ROTATION] if t.has[P.P_OFFSET_WORLD_ROTATION] else Quaternion.IDENTITY
		if t.has[P.P_OFFSET_POSITION]:
			pos = world * (t.vec[P.P_OFFSET_POSITION] * Constants.LANE_DISTANCE)
		rot = world
		if t.has[P.P_LOCAL_ROTATION]:
			rot = world * t.quat[P.P_LOCAL_ROTATION]
	else:
		if t.has[P.P_LOCAL_POSITION]:
			pos = t.vec[P.P_LOCAL_POSITION]
		elif t.has[P.P_POSITION]:
			pos = t.vec[P.P_POSITION]
		if t.has[P.P_LOCAL_ROTATION]:
			rot = t.quat[P.P_LOCAL_ROTATION]
		elif t.has[P.P_ROTATION]:
			rot = t.quat[P.P_ROTATION]
	var basis := Basis(rot)
	if t.has[P.P_SCALE]:
		basis = basis * Basis.from_scale(t.vec[P.P_SCALE])
	return Transform3D(basis, pos)
