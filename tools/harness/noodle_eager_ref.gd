extends RefCounted

# Reference for verify_noodle: the custom event animation as it was before lazy evaluation
# (0.7.30 NoodleEvents), stepping every running animation and every transform track every tick.
# The lazy NoodleEvents must read the same values at any time; verify_noodle runs both over real
# fixture maps and compares. Uses NoodleEvents' parsed events and its pure helpers
# (_local_xform), and writes into the same NoodleTrack fields the game reads.

static var tweens: Array[NoodleEvents.Anim] = []
static var path_tweens: Array[NoodleEvents.Anim] = []
static var transform_tracks: Array[NoodleTrack] = []
static var player_track := -1
static var root_xform := Transform3D.IDENTITY


static func reset() -> void:
	tweens.clear()
	path_tweens.clear()
	transform_tracks.clear()
	player_track = -1
	root_xform = Transform3D.IDENTITY


static func dispatch(ev: NoodleEvents.Event, song_sec: float) -> void:
	var start := Map.beat_to_seconds(ev.beat)
	var duration := 60.0 * ev.duration / maxf(Map.bpm_at_beat(ev.beat), 1.0)
	var no_duration := duration <= 0.0 or start + duration * float(ev.repeat + 1) < song_sec
	match ev.type:
		NoodleEvents.ANIMATE_TRACK:
			for ti in ev.tracks:
				var track := NoodleTracks.tracks[ti]
				for j in ev.props.size():
					var p := ev.props[j]
					var pts := ev.points[j]
					_stop(tweens, track, p)
					if pts == null:
						track.clear_value(p)
					elif no_duration or pts.count() <= 1:
						track.set_from_points(p, pts, 1.0)
					else:
						var tw := NoodleEvents.Anim.new()
						tw.track = track
						tw.prop = p
						tw.points = pts
						tw.start = start
						tw.duration = duration
						tw.easing = ev.easing
						tw.repeat = ev.repeat
						tweens.append(tw)
						NoodleEvents._step_value(tw, song_sec)
		NoodleEvents.ASSIGN_PATH_ANIMATION:
			for ti in ev.tracks:
				var track := NoodleTracks.tracks[ti]
				track.has_path = true
				for j in ev.props.size():
					var p := ev.props[j]
					var pts := ev.points[j]
					_stop(path_tweens, track, p)
					track.path_prev[p] = track.path_cur[p]
					track.set_path(p, pts)
					track.path_blend[p] = 0.0
					if pts == null or no_duration:
						track.path_prev[p] = null
						track.path_blend[p] = 1.0
					else:
						var tw := NoodleEvents.Anim.new()
						tw.track = track
						tw.prop = p
						tw.start = start
						tw.duration = duration
						tw.easing = ev.easing
						path_tweens.append(tw)
						NoodleEvents._step_path(tw, song_sec)
		NoodleEvents.ASSIGN_TRACK_PARENT:
			_mark(NoodleTracks.tracks[ev.parent])
			for ti in ev.tracks:
				NoodleTracks.tracks[ti].parent = ev.parent
		NoodleEvents.ASSIGN_PLAYER_TO_TRACK:
			player_track = ev.tracks[0]
			_mark(NoodleTracks.tracks[player_track])


static func _mark(t: NoodleTrack) -> void:
	if not t.is_transform:
		t.is_transform = true
		transform_tracks.append(t)


static func _stop(list: Array[NoodleEvents.Anim], track: NoodleTrack, p: int) -> void:
	for i in range(list.size() - 1, -1, -1):
		if list[i].track == track and list[i].prop == p:
			list.remove_at(i)


static func update(song_sec: float) -> void:
	for i in range(tweens.size() - 1, -1, -1):
		if NoodleEvents._step_value(tweens[i], song_sec):
			tweens.remove_at(i)
	for i in range(path_tweens.size() - 1, -1, -1):
		if NoodleEvents._step_path(path_tweens[i], song_sec):
			path_tweens.remove_at(i)
	var list := NoodleTracks.tracks
	for t in transform_tracks:
		t.local = NoodleEvents._local_xform(t, NoodleTracks.is_v2)
	for t in transform_tracks:
		var world := t.local
		var up := t.parent
		var depth := 0
		while up >= 0 and depth < 8:
			world = list[up].local * world
			up = list[up].parent
			depth += 1
		t.xform = world
	root_xform = Transform3D.IDENTITY
	if player_track >= 0:
		root_xform = list[player_track].xform.affine_inverse()
