extends RefCounted
class_name NoodleEvents

# Heck / Noodle Extensions custom events: AnimateTrack, AssignPathAnimation, AssignTrackParent
# and AssignPlayerToTrack. Parsed once at load and sorted by beat. Parent and player events are
# dispatched by GameStatePlaying when the song reaches them. Everything that sets a track's own
# values (AnimateTrack, AssignPathAnimation) is lazy: the song reaching an event's beat only
# records when it did (one write per distinct beat, however many events share it), and the
# track applies its due events and steps its running animations when something reads it
# (sync(), track_xform()), at most once per tick. A map with thousands of tracks, events and
# long animations pays only for the tracks its live objects, parents and player actually use.
# The values read are the same as dispatching and stepping everything every tick (see sync()).
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
	# Index of this event's beat in the distinct beats (NoodleEvents._beats).
	var slot := 0


class Anim extends RefCounted:
	var track: NoodleTrack
	var prop := 0
	var points: NoodlePoints
	var start := 0.0
	var duration := 1.0
	var easing := NoodleEasing.LINEAR
	var repeat := 0
	# The update() count when its event was reached: an animation is stepped at a read only once
	# an update() has passed since then (until then it holds the value at its dispatch time).
	var born := 0


# Every parsed event, in beat order (file order within a beat).
static var all_events: Array[Event] = []
# Parent and player events, dispatched as the song reaches them: spawn-order stack, the next
# event at the back.
static var stack: Array[Event] = []
# The distinct beats of all events (ascending), the song time and update() count of the tick
# that reached each, how many events lie at or before each, and how many have been reached.
static var _beats := PackedFloat64Array()
static var _beat_sec := PackedFloat64Array()
static var _beat_tick := PackedInt64Array()
static var _beat_events := PackedInt32Array()
static var _due := 0
# The tracks with events of their own (NoodleTrack.events), cleared on reset.
static var _event_tracks: Array[NoodleTrack] = []
# Each time the song time went backwards: the time it went back from, how many distinct beats had
# been reached, and the update() count then. A track replays the ones it has not seen when it is
# next read (NoodleTrack.jumps_done), so a jump costs nothing up front.
static var _jump_sec := PackedFloat64Array()
static var _jump_due := PackedInt32Array()
static var _jump_tick := PackedInt64Array()
# Running animations live on their track (NoodleTrack.tw / ptw, one per property). Path
# transitions reuse Anim: `points` is unused, the track's path_blend is driven instead.
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
	for t in _event_tracks:
		t.events.clear()
		t.next_ev = 0
	_event_tracks.clear()
	all_events.clear()
	stack.clear()
	_beats.clear()
	_beat_sec.clear()
	_beat_tick.clear()
	_beat_events.clear()
	_due = 0
	_jump_sec.clear()
	_jump_due.clear()
	_jump_tick.clear()
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
	all_events = events
	var globals: Array[Event] = []
	for i in events.size():
		var ev := events[i]
		if _beats.is_empty() or ev.beat != _beats[_beats.size() - 1]:
			_beats.append(ev.beat)
			_beat_events.append(0)
		ev.slot = _beats.size() - 1
		_beat_events[ev.slot] = i + 1
		if ev.type == ANIMATE_TRACK or ev.type == ASSIGN_PATH_ANIMATION:
			for ti in ev.tracks:
				var t := NoodleTracks.tracks[ti]
				if t.events.is_empty():
					_event_tracks.append(t)
				t.events.append(ev)
		else:
			globals.append(ev)
	_beat_sec.resize(_beats.size())
	_beat_tick.resize(_beats.size())
	globals.reverse()
	stack = globals
	# Parent and player assignments at beat 0 or before set fields only, so they are applied here
	# at load rather than in the song's first tick (1e6ff has 835 at beat 0, part of a 66 ms
	# first frame on the headset). Objects spawned in that first tick now see their parents from
	# their first frame instead of one frame later.
	while not stack.is_empty() and stack[-1].beat <= 0.0:
		dispatch(stack.pop_back(), 0.0)
	if not all_events.is_empty():
		NoodleTracks.active = true


## How many events the song has reached so far (all kinds).
static func events_due() -> int:
	return _beat_events[_due - 1] if _due > 0 else 0


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


## Marks every event whose beat has been reached and dispatches the parent and player events
## among them. Called once per tick before update(). The track events are applied when their
## track is read (sync()), at the time recorded here.
static func dispatch_until(current_beat: float, song_sec: float) -> void:
	if song_sec < _now:
		_catch_up(song_sec)
	while _due < _beats.size() and _beats[_due] <= current_beat:
		_beat_sec[_due] = song_sec
		_beat_tick[_due] = _tick
		_due += 1
	while not stack.is_empty() and stack[-1].beat <= current_beat:
		dispatch(stack.pop_back(), song_sec)


## Applies one event now, at `song_sec` (parent and player events, and tools).
static func dispatch(ev: Event, song_sec: float) -> void:
	if song_sec < _now:
		_catch_up(song_sec)
	match ev.type:
		ANIMATE_TRACK, ASSIGN_PATH_ANIMATION:
			for ti in ev.tracks:
				var track := NoodleTracks.tracks[ti]
				_apply_pending(track)
				_apply(ev, track, song_sec, _tick)
		ASSIGN_TRACK_PARENT:
			_mark_transform(NoodleTracks.tracks[ev.parent])
			for ti in ev.tracks:
				var child := NoodleTracks.tracks[ti]
				child.parent = ev.parent
				child.touch()
		ASSIGN_PLAYER_TO_TRACK:
			player_track = ev.tracks[0]
			_mark_transform(NoodleTracks.tracks[player_track])


# Applies the track's events the song has reached and that are not applied yet, each at the
# song time of the tick that reached it.
static func _apply_pending(track: NoodleTrack, due: int = -1) -> void:
	if due < 0:
		due = _due
	var list := track.events
	while track.next_ev < list.size():
		var ev: Event = list[track.next_ev]
		if ev.slot >= due:
			return
		_apply(ev, track, _beat_sec[ev.slot], int(_beat_tick[ev.slot]))
		track.next_ev += 1


# What dispatching `ev` at `song_sec` does to one of its tracks. `born`: the update() count when
# the event was reached.
static func _apply(ev: Event, track: NoodleTrack, song_sec: float, born: int) -> void:
	var start := Map.beat_to_seconds(ev.beat)
	var duration := 60.0 * ev.duration / maxf(Map.bpm_at_beat(ev.beat), 1.0)
	var no_duration := duration <= 0.0 or start + duration * float(ev.repeat + 1) < song_sec
	if ev.type == ANIMATE_TRACK:
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
				tw.born = born
				_start(track, p, tw, false)
				_step_value(tw, song_sec)
	else:
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
				tw.born = born
				_start(track, p, tw, true)
				_step_path(tw, song_sec)


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
##
## Events are applied late the same way: an event changes only its own properties of its own
## track, so applying it at the read, at the song time of the tick that reached it, gives what
## dispatching it then did. Its animation was stepped by every update() after that tick, so it is
## stepped at the read unless no update() has passed since (`born`); the others likewise.
static func sync(track: NoodleTrack) -> void:
	if track.jumps_done < _jump_sec.size():
		_replay_jumps(track)
	if track.next_ev < track.events.size() and (track.events[track.next_ev] as Event).slot < _due:
		_apply_pending(track)
	if track.synced == _tick:
		return
	track.synced = _tick
	if track.tw_count > 0:
		_step_track(track, _now)


# Steps the track's animations at `song_sec`, except those whose event was reached at or after
# update() count `fresh` (they hold their dispatch-time value until an update() passes).
static func _step_track(track: NoodleTrack, song_sec: float, fresh: int = -1) -> void:
	if fresh < 0:
		fresh = _tick
	for p in NoodleTracks.P_COUNT:
		var tw: Anim = track.tw[p]
		if tw != null and tw.born < fresh and _step_value(tw, song_sec):
			track.tw[p] = null
			track.tw_count -= 1
			_live -= 1
		tw = track.ptw[p]
		if tw != null and tw.born < fresh and _step_path(tw, song_sec):
			track.ptw[p] = null
			track.tw_count -= 1
			_live -= 1


# Time is about to go back from `_now` to `song_sec`. Every track must first be brought to `_now`
# (what the ticks before this one did when everything was dispatched and stepped every tick):
# recorded here, and done per track when it is next read (_replay_jumps), so a jump back (a song
# restart, an audio stall snap) does not apply every pending event of the map in one tick.
static func _catch_up(song_sec: float) -> void:
	_jump_sec.append(_now)
	_jump_due.append(_due)
	_jump_tick.append(_tick)
	_now = song_sec


static func _replay_jumps(track: NoodleTrack) -> void:
	for j in range(track.jumps_done, _jump_sec.size()):
		_apply_pending(track, _jump_due[j])
		if track.tw_count > 0:
			_step_track(track, _jump_sec[j], int(_jump_tick[j]))
	track.jumps_done = _jump_sec.size()
	# A jump in this very tick, before its update(): the track now holds what every tick before
	# gave it, which is what a read sees until that update().
	if _jump_tick[_jump_tick.size() - 1] == _tick:
		track.synced = _tick


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
## tick per track, as its parent's chained transform times its own local one, so a parent chain
## shared by many tracks (1e6ff: tunnels of tracks four or five deep, one wall each) is built once
## per tick, not once per child. This multiplies in a different order than chaining every local
## from the child up (0.7.33 and before), which can change the last bits of the result (accepted
## by the owner; verify_noodle compares these transforms with a tolerance).
static func track_xform(t: NoodleTrack) -> Transform3D:
	if t.xform_tick == _tick:
		return t.xform
	# Marked first: a cycle in a broken map then reads the previous value instead of recursing.
	t.xform_tick = _tick
	var world := _local_of(t)
	if t.parent >= 0:
		world = track_xform(NoodleTracks.tracks[t.parent]) * world
	t.xform = world
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
