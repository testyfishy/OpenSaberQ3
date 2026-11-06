# Deterministic autoplay workload for benchmark runs (spec FR-006 / FR-014 / FR-026).
#
# ── Why ──────────────────────────────────────────────────────────────────────
# Frame-time measurement used to need a person in the headset, so no two runs
# played the same notes, at the same speed, in the same order. This node replaces
# the player with a fixed workload: a head sway of known amplitude, and both
# sabers driven through the map's notes in the notes' required cut directions at
# a known arc length and speed.
#
# ── Inertness ────────────────────────────────────────────────────────────────
# Created by BenchmarkRunner only when the flag file has `[bot] enabled=true`,
# which itself only exists in benchmark mode, so a normal launch never loads,
# instantiates or ticks this script.
#
# ── The three things that make it work ───────────────────────────────────────
# 1. Saber pose. LightSaber.gd:90-92 rewrites `position` and `rotation_degrees`
#    every physics tick from `offset_pos + extra_offset_pos` and
#    `offset_rot + extra_offset_rot`, so `extra_offset_*` is the only writable
#    lever. We compute the transform the blade MUST have in world space (it
#    points at the note on its hit beat) and convert it into the controller's
#    local space, which is exactly what those two vectors encode.
# 2. Real hit path. This never calls note.cut(). SwingableRayCast samples the
#    saber node's transform (SwingableRayCast.gd:70-87) and casts 8 swept rays
#    per physics tick (SwingableRayCast.gd:103-115), so moving the saber moves
#    the rays and the game's own area_collided -> LightSaber._handle_area_collided
#    -> note.cut() path does the cutting.
# 3. Ordering. This node runs at process_priority -50, before LightSaber (0):
#    Godot processes lower priorities first, so the offsets are already written
#    when LightSaber copies them into position/rotation, and before its child
#    SwingableRayCast samples the result.
#
# ── Clock ────────────────────────────────────────────────────────────────────
# Swings are scheduled on the song clock, not on wall clock: hit time is
# `beat * 60 / bpm` seconds of playback, the same relation Playing.gd:47 uses to
# spawn notes, and the same clock Cube movement is driven by (Cuttable.gd:30-32
# advances z by BEAT_DISTANCE*BPM/60 per physics tick). The clock is advanced by
# the physics delta and eased towards
# `get_playback_position() + AudioServer.get_time_since_last_mix()` so a dropped
# frame produces a real swept gap instead of the swing being resampled. It never
# runs backwards. Using the raw playback position directly is worse: it only
# steps once per audio mix buffer, and on the ticks where it does not move the
# saber would not move either, so `cut_speed` (LightSaber.gd:134) would be zero
# and the game would score a bad cut the bot never made.
#
# ── Geometry ────────────────────────────────────────────────────────────────
# Everything is derived from the XROrigin3D body frame and the map's track
# space, never from tracked controller poses, so an unworn headset lying on a
# table still swings correctly (the blades visually detach from the real hands -
# a documented fidelity note, not a behaviour change).
#
# For a note whose hit point is P and whose required swing direction is d
# (Constants.ROTATION_UNIT_VECTORS[cut_direction] in track XY, the direction
# BeepCube.cut scores as a perfect angle):  pick a blade direction r that is
# perpendicular to d and points from the shoulder towards P, place the hilt at
# P - r*reach so P sits inside the blade segment, and rotate the blade about the
# hilt around axis (r x d) by a cosine-eased angle. At the middle of the window
# the blade points exactly at P while moving along d, so the cut angle is ~1.0.
# Tip travel is SWING_ARC_M, and the tip's peak speed is
# SWING_ARC_M*PI/(2*window) ~= 4 m/s for the default window.
extends Node

# --- workload shape ---------------------------------------------------------
const SWING_ARC_M := 0.6          # blade tip travel per swing
const SWING_WINDOW_S := 0.2356    # 2*arc*... => 4.0 m/s peak tip speed
const MIN_WINDOW_S := 0.05        # dense notes get a shorter, faster arc
const SWING_BLEND_S := 0.15       # move between two swing poses, never teleport
const MIN_REACH_M := 0.35         # hilt distance from the note
const MIN_BLADE_LEN_M := 0.2      # blade retracted (Show animation) => no swing
const FALLBACK_BLADE_LEN_M := 1.26
const TAIL_S := 0.05              # keep a note active this long past its window
const NEAR_HIT_S := 0.06          # window for the blade/note distance check

const SWAY_YAW_DEG := 15.0
const SWAY_YAW_HZ := 0.2
const SWAY_PITCH_DEG := 5.0
const SWAY_PITCH_HZ := 0.13
const SWAY_LEAN_M := 0.10
const SWAY_LEAN_HZ := 0.11

# Shoulder points in XROrigin3D space (left, right). The note grid is 0.8-2.0 m
# up in track space, so a shoulder at 1.35 m gives a natural reach.
const SHOULDER_LOCAL := [Vector3(-0.25, 1.35, 0.0), Vector3(0.25, 1.35, 0.0)]

# --- song clock -------------------------------------------------------------
const CLOCK_RESYNC_S := 0.030
const CLOCK_EASE := 0.25

class HandState:
	var pose := Transform3D.IDENTITY      # world transform we last asked for
	var expected_local := Transform3D.IDENTITY
	var have_expected := false
	var goal_id := 0                      # 0 = rest, -1 = following a swing
	var from := Transform3D.IDENTITY
	var from_t := 0.0
	var active_note := {}                 # note currently being swung at
	var near_min := INF                   # closest blade/note approach, this note

var _game: Node3D
var _miss_percent := 0.0
var _sway_enabled := true

var _xr_origin: XROrigin3D
var _track: Node3D
var _song: AudioStreamPlayer
var _base_origin := Transform3D.IDENTITY       # XROrigin3D pose before sway
var _sabers: Array[LightSaber] = []
var _controllers: Array[BeepSaberController] = []
var _swingcasts: Array[RayCast3D] = []

var _queues: Array[Array] = [[], []]            # per hand, beat order
var _heads: Array[int] = [0, 0]
var _notes_queued := 0
var _skipped := 0
var _swings := 0
var _state: Array[HandState] = [HandState.new(), HandState.new()]

var _song_time := 0.0
var _clock_target := -1.0
var _clock_resyncs := 0
var _pose_error_max := 0.0
var _blade_near_max := 0.0

func _init(game: Node3D, miss_percent: float, sway: bool) -> void:
	_game = game
	_miss_percent = clampf(miss_percent, 0.0, 100.0)
	_sway_enabled = sway
	# Runs before LightSaber._physics_process (0) and before its child
	# SwingableRayCast, so the offsets are in place when both read them.
	process_priority = -50

func _ready() -> void:
	@warning_ignore("unsafe_property_access")
	_xr_origin = _game.xr_origin
	@warning_ignore("unsafe_property_access")
	_track = _game.track
	@warning_ignore("unsafe_property_access")
	_song = _game.song_player
	@warning_ignore("unsafe_property_access")
	_sabers.append(_game.left_saber as LightSaber)
	@warning_ignore("unsafe_property_access")
	_sabers.append(_game.right_saber as LightSaber)
	@warning_ignore("unsafe_property_access")
	_controllers.append(_game.left_controller as BeepSaberController)
	@warning_ignore("unsafe_property_access")
	_controllers.append(_game.right_controller as BeepSaberController)
	
	if _xr_origin == null or _track == null or _song == null:
		vr.log_error("BOT: main scene is missing xr_origin/track/song_player")
		_queues = [[], []]
		return
	
	for saber in _sabers:
		_swingcasts.append(saber.get_node_or_null("SwingableRayCast") as RayCast3D)
	
	_base_origin = _xr_origin.transform
	_song_time = _song.get_playback_position()
	_queue_notes()
	_state[0].pose = _rest_pose(0)
	_state[1].pose = _rest_pose(1)
	vr.log_info("BOT: %d notes queued (%d skipped by miss_percent=%.1f), sway=%s" % [
		_notes_queued, _skipped, _miss_percent, str(_sway_enabled)])

func _physics_process(delta: float) -> void:
	if _xr_origin == null or _track == null or _song == null:
		return
	_advance_clock(delta)
	if _sway_enabled:
		_apply_sway()
	for hand in 2:
		_tick_hand(hand)

# ── clock ────────────────────────────────────────────────────────────────────
func _advance_clock(delta: float) -> void:
	var prev := _song_time
	_song_time += delta
	if not Harness.replay and _song != null and _song.playing:
		var target := _song.get_playback_position() + clampf(
			AudioServer.get_time_since_last_mix(), 0.0, 0.1)
		# Only resync off a clock that is actually moving: a frozen audio clock
		# (headless dummy driver, stalled stream) must not pin the bot in place.
		if absf(target - _clock_target) > 0.0005:
			_clock_target = target
			var drift := target - _song_time
			if absf(drift) > CLOCK_RESYNC_S:
				_clock_resyncs += 1
				_song_time += drift * CLOCK_EASE
	if _song_time < prev:
		_song_time = prev

# ── sway ─────────────────────────────────────────────────────────────────────
func _apply_sway() -> void:
	var t := _song_time
	var yaw := deg_to_rad(SWAY_YAW_DEG) * sin(TAU * SWAY_YAW_HZ * t)
	var pitch := deg_to_rad(SWAY_PITCH_DEG) * sin(TAU * SWAY_PITCH_HZ * t)
	var lean := SWAY_LEAN_M * sin(TAU * SWAY_LEAN_HZ * t)
	_xr_origin.transform = Transform3D(
		_base_origin.basis * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch),
		_base_origin.origin + _base_origin.basis.x * lean)

# ── note queue ───────────────────────────────────────────────────────────────
# Snapshot of MapData.note_stack taken before the first physics tick: Playing.gd:58
# pops from it only once the song has started, and note_stack is reverse-ordered
# (next note at index -1), so reversing the copy gives beat order.
func _queue_notes() -> void:
	if Map.current_info == null:
		return
	if Map.current_info.beats_per_minute <= 0.0:
		return
	var stack: Array = MapData.note_stack.duplicate()
	stack.reverse()
	var track_xf := _track.global_transform
	var last_t: Array[float] = [-INF, -INF]
	var id := 0
	for entry in stack:
		var note := entry as ColorNoteInfo
		if note == null:
			continue
		var hand := 0 if note.color == 0 else 1
		var t := Map.beat_to_seconds(note.beat)
		# Dense notes get a shorter window so consecutive swings never overlap;
		# the arc stays 0.6 m, so the peak speed rises above 4 m/s (as it does
		# for a real player) instead of notes being dropped.
		var window := SWING_WINDOW_S
		var gap: float = t - last_t[hand]
		if gap > 0.0 and gap * 0.9 < window:
			window = maxf(MIN_WINDOW_S, gap * 0.9)
		last_t[hand] = t
		
		var unit := Constants.ROTATION_UNIT_VECTORS[clampi(note.cut_direction, 0, 8)]
		var skip := _should_skip(id)
		if skip:
			_skipped += 1
		_queues[hand].append({
			"id": id,
			"t": t,
			"w": window,
			"p": track_xf * Vector3(
				Constants.LANE_DISTANCE * float(note.line_index) + Constants.LANE_ZERO_X,
				Constants.LANE_DISTANCE * float(note.line_layer) + Constants.LAYER_ZERO_Y,
				0.0),
			"d": (track_xf.basis * Vector3(unit.x, unit.y, 0.0)).normalized(),
			"skip": skip,
		})
		id += 1
	_notes_queued = id

# Deterministic miss pass: exactly miss_percent out of every 100 notes, spread
# evenly over the map (Bresenham), no RNG, same notes on every run.
func _should_skip(index: int) -> bool:
	var p := _miss_percent / 100.0
	if p <= 0.0:
		return false
	if p >= 1.0:
		return true
	return floori(float(index + 1) * p) > floori(float(index) * p)

# ── per hand ─────────────────────────────────────────────────────────────────
func _tick_hand(hand: int) -> void:
	var saber := _sabers[hand]
	var queue: Array = _queues[hand]
	var st := _state[hand]
	
	_check_last_write(hand, st)
	
	# Drop finished notes.
	var i := _heads[hand]
	while i < queue.size() and float(queue[i]["t"]) + float(queue[i]["w"]) * 0.5 + TAIL_S < _song_time:
		i += 1
	_heads[hand] = i
	
	var note := {}
	var approaching := {}
	if i < queue.size():
		var candidate: Dictionary = queue[i]
		if not bool(candidate["skip"]):
			var half := float(candidate["w"]) * 0.5
			if _song_time >= float(candidate["t"]) - half:
				note = candidate
			elif _song_time >= float(candidate["t"]) - half - _blend_time(candidate):
				approaching = candidate
	
	var blade := _blade_length(hand)
	if not note.is_empty() and blade < MIN_BLADE_LEN_M:
		note = {}   # saber still retracted by the Show animation
		approaching = {}
	
	if not note.is_empty():
		var t_hit := float(note["t"])
		var half := float(note["w"]) * 0.5
		var u := clampf((_song_time - (t_hit - half)) / float(note["w"]), 0.0, 1.0)
		if st.active_note.is_empty() or int(st.active_note["id"]) != int(note["id"]):
			_fold_near(st)
			st.active_note = note
			_swings += 1
		st.goal_id = -1
		st.pose = _swing_pose(hand, note, u, blade)
		if absf(_song_time - t_hit) <= NEAR_HIT_S:
			st.near_min = minf(st.near_min, _blade_distance(hand, note, blade))
	elif not approaching.is_empty():
		var id := int(approaching["id"])
		if st.goal_id != id:
			st.goal_id = id
			st.from = st.pose
			st.from_t = _song_time
		var k := clampf((_song_time - st.from_t) / _blend_time(approaching), 0.0, 1.0)
		st.pose = st.from.interpolate_with(_swing_pose(hand, approaching, 0.0, blade), _smooth(k))
		if not st.active_note.is_empty():
			_fold_near(st)
			st.active_note = {}
	else:
		if st.goal_id != 0:
			st.goal_id = 0
			st.from = st.pose
			st.from_t = _song_time
		var k := clampf((_song_time - st.from_t) / SWING_BLEND_S, 0.0, 1.0)
		st.pose = st.from.interpolate_with(_rest_pose(hand), _smooth(k))
		if not st.active_note.is_empty():
			_fold_near(st)
			st.active_note = {}
	
	_write_pose(hand, st, saber)

func _blend_time(note: Dictionary) -> float:
	# Never longer than half the swing window, so the blend always finishes
	# before the arc starts and the pose stays continuous.
	return minf(SWING_BLEND_S, float(note["w"]) * 0.5)

static func _smooth(k: float) -> float:
	return k * k * (3.0 - 2.0 * k)

# ── geometry ─────────────────────────────────────────────────────────────────
func _swing_pose(hand: int, note: Dictionary, u: float, blade: float) -> Transform3D:
	var p: Vector3 = note["p"]
	var d: Vector3 = note["d"]
	var shoulder: Vector3 = _xr_origin.global_transform * SHOULDER_LOCAL[hand]
	var to_note := p - shoulder
	
	# Blade direction at mid-swing: from the shoulder towards the note, made
	# perpendicular to the swing direction so the rotation below is a pure arc.
	var r := to_note - d * to_note.dot(d)
	if r.length() < 0.15:
		r = Vector3(0.0, 0.0, -1.0)
		r -= d * r.dot(d)
		if r.length() < 0.15:
			r = Vector3(0.0, 1.0, 0.0)
			r -= d * r.dot(d)
	r = r.normalized()
	
	var reach := clampf(to_note.length(), MIN_REACH_M, maxf(MIN_REACH_M, blade * 0.9))
	var hilt := p - r * reach
	var axis_raw := r.cross(d)
	if axis_raw.length() < 0.1:
		axis_raw = Vector3(0.0, 0.0, -1.0).cross(d)
	var axis := axis_raw.normalized()
	
	# Tip arc of SWING_ARC_M, cosine eased so the peak speed is at the hit.
	var theta := SWING_ARC_M / maxf(blade, 0.3)
	var phi := -0.5 * theta * cos(PI * u)
	var y_axis := (r * cos(phi) + d * sin(phi)).normalized()
	var z_axis := axis.cross(y_axis).normalized()
	return Transform3D(Basis(axis, y_axis, z_axis), hilt)

func _rest_pose(hand: int) -> Transform3D:
	var saber := _sabers[hand]
	var ctrl := _controllers[hand]
	var ctf := ctrl.global_transform
	# The saber's resting local transform: offset_pos / offset_rot applied in the
	# node's default YXZ euler order (the same order rotation_degrees uses).
	var rot := saber.offset_rot * (PI / 180.0)
	var rest_basis := Basis(Vector3.UP, rot.y) * Basis(Vector3.RIGHT, rot.x) * Basis(Vector3.BACK, rot.z)
	return Transform3D(ctf.basis.orthonormalized(), ctf.origin) * Transform3D(rest_basis, saber.offset_pos)

func _blade_length(hand: int) -> float:
	var rc := _swingcasts[hand]
	if rc == null:
		return FALLBACK_BLADE_LEN_M
	return rc.target_position.length()

# Distance from the note's hit point to the saber's real blade segment, using
# the transform the saber node actually has right now (written by LightSaber on
# the previous tick). This is the end-to-end check that the offsets really moved
# the geometry the raycasts sample.
func _blade_distance(hand: int, note: Dictionary, blade: float) -> float:
	var xf := _sabers[hand].global_transform
	var a := xf.origin
	var b := xf * Vector3(0.0, maxf(blade, 0.01), 0.0)
	var p: Vector3 = note["p"]
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.000001:
		return a.distance_to(p)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return (a + ab * t).distance_to(p)

func _fold_near(st: HandState) -> void:
	if st.near_min < INF:
		_blade_near_max = maxf(_blade_near_max, st.near_min)
	st.near_min = INF

# ── write the pose into the two offset vectors LightSaber owns ───────────────
func _write_pose(hand: int, st: HandState, saber: LightSaber) -> void:
	var ctrl := _controllers[hand]
	var ctf := ctrl.global_transform
	var base := Transform3D(ctf.basis.orthonormalized(), ctf.origin)
	var local := base.affine_inverse() * st.pose
	saber.extra_offset_pos = local.origin - saber.offset_pos
	saber.extra_offset_rot = local.basis.get_euler(saber.rotation_order) * (180.0 / PI) - saber.offset_rot
	st.expected_local = local
	st.have_expected = true

# Read back what LightSaber made of the offsets on the previous tick: anything
# else writing the saber transform would show up here.
func _check_last_write(hand: int, st: HandState) -> void:
	if not st.have_expected:
		return
	var saber := _sabers[hand]
	var err := saber.transform.origin.distance_to(st.expected_local.origin)
	if err > _pose_error_max:
		_pose_error_max = err

# ── reporting ────────────────────────────────────────────────────────────────
func get_stats() -> Dictionary:
	for hand in 2:
		_fold_near(_state[hand])
	return {
		"bot_enabled": "true",
		"bot_notes_queued": _notes_queued,
		"bot_swings": _swings,
		"bot_skipped": _skipped,
		"bot_miss_percent": "%.1f" % _miss_percent,
		"bot_sway": str(_sway_enabled),
		"bot_clock_resyncs": _clock_resyncs,
		"bot_pose_error_max_mm": "%.2f" % (_pose_error_max * 1000.0),
		"bot_blade_near_max_mm": "%.1f" % (_blade_near_max * 1000.0),
		"bot_score_points": str(Scoreboard.points),
		"bot_score_right_notes": "%.2f" % Scoreboard.right_notes,
		"bot_score_wrong_notes": "%.2f" % Scoreboard.wrong_notes,
		"bot_score_full_combo": str(Scoreboard.full_combo),
	}
