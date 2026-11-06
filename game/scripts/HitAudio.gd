extends Node
class_name HitAudio

# Positioned hit voices (specs/016 Part 6, FR-031..FR-034).
#
# One fixed pool of 3D players on the SFX bus. Every hit is placed at the cube's world position,
# so the sound comes from the thing you cut rather than from your hand. Voices are allocated from
# a preallocated array (no per-hit nodes), the oldest is stolen when the pool is full, and hits
# that start within 30 ms of each other are attenuated by 1/sqrt(n).
#
# Distance attenuation is disabled: the old per-saber player mixed at the saber and this one must
# not get quieter because the cube happens to be a metre away (FR-033). Panning is kept so a hit
# on the left of the head is heard on the left.

const VOICES := 16
const WINDOW_USEC := 30000
const PANNING_STRENGTH := 0.85
# Music ducking (FR-035). A per-frame envelope cannot do a 3 ms attack; at 120 Hz it is one frame
# (8 ms), which is the documented gap. The hold keeps the duck through a dense phrase; the release
# is 3 dB over 120 ms.
const DUCK_DB := -3.0
const DUCK_HOLD_USEC := 80000
const DUCK_RELEASE_DB_PER_SEC := 25.0

var steal_count := 0

var _players: Array[AudioStreamPlayer3D] = []
var _base_db := PackedFloat32Array()
var _started_usec := PackedInt64Array()
var _active := PackedByteArray()
var _probe_enabled := false
var _probe_origin := 0
var _probe_hits: Array = []
var last_gain_db := 0.0
var last_pan_x := 0.0
var analyser_enabled := false
var _ducking := false
var _duck_until := 0
var _duck_current := 0.0
var _music_base_db := 0.0
var duck_min_db := 0.0
var duck_frames := 0

func _ready() -> void:
	# Voices pause with the game (and with a paused tree), so a paused song cannot keep hits
	# echoing into the menu.
	# The ducker must release even if the tree is paused; stop_all() handles the voices.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var player := AudioStreamPlayer3D.new()
		player.name = "HitVoice%d" % i
		player.bus = &"SFX"
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		player.panning_strength = PANNING_STRENGTH
		add_child(player)
		_players.append(player)
		_base_db.append(0.0)
		_started_usec.append(0)
		_active.append(0)
	_ducking = Settings.audio_ducking
	_music_base_db = linear_to_db(maxf(Settings.audio_music, 0.0001))
	Settings.changed.connect(_on_setting_changed)
	_apply_music()
	set_process(false)

# Returns the voice index, or -1 when the sample is missing / the pool cannot start.
func play(sample: AudioStream, pos: Vector3, gain_db: float, ratio: float, offset := 0.0) -> int:
	if sample == null:
		return -1
	var index := _free_index()
	if index < 0:
		index = _steal_oldest()
		if index < 0:
			return -1
		steal_count += 1
		if _probe_enabled:
			vr.log_info("HITAUDIO: stole voice %d (total %d)" % [index, steal_count])
	var player := _players[index]
	player.stream = sample
	player.global_position = pos
	player.pitch_scale = ratio
	player.volume_db = gain_db
	player.play(offset)
	_base_db[index] = gain_db
	_started_usec[index] = Time.get_ticks_usec()
	_active[index] = 1
	last_gain_db = gain_db
	if analyser_enabled:
		var camera := get_viewport().get_camera_3d() as Camera3D
		last_pan_x = (camera.global_transform.affine_inverse() * pos).x if camera != null else pos.x
	_apply_window_gain()
	if _ducking:
		_duck_until = Time.get_ticks_usec() + DUCK_HOLD_USEC
		set_process(true)
	if _probe_enabled:
		_record_hit(pos)
	return index

# FR-036: called on pause, game end and a return to the menu. No voice survives a state
# change and the music must never stay ducked. Probe state is left alone for the bench.
func stop_all() -> void:
	for i in VOICES:
		_players[i].stop()
		_players[i].stream = null
		_active[i] = 0
		_base_db[i] = 0.0
		_started_usec[i] = 0
	_release_duck()

func reset() -> void:
	stop_all()
	steal_count = 0
	_probe_enabled = false
	_probe_hits.clear()

# --- music ducking (FR-035) -------------------------------------------------------------------

func _on_setting_changed(key: StringName) -> void:
	if key == &"audio_music":
		_music_base_db = linear_to_db(maxf(Settings.audio_music, 0.0001))
		if _duck_current == 0.0:
			_apply_music()
	elif key == &"audio_ducking":
		_ducking = Settings.audio_ducking
		if not _ducking:
			_release_duck()

func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if now < _duck_until:
		_duck_current = DUCK_DB
	else:
		_duck_current = minf(0.0, _duck_current + DUCK_RELEASE_DB_PER_SEC * delta)
		if _duck_current >= 0.0:
			_duck_current = 0.0
			_apply_music()
			set_process(false)
			return
	_apply_music()

func _apply_music() -> void:
	var bus := AudioServer.get_bus_index(&"Music")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, _music_base_db + _duck_current)
	if _probe_enabled and _duck_current < 0.0:
		duck_min_db = minf(duck_min_db, _duck_current)
		duck_frames += 1

func _release_duck() -> void:
	_duck_until = 0
	_duck_current = 0.0
	_apply_music()
	set_process(false)

# --- benchmarking hooks -----------------------------------------------------------------------

func begin_probe() -> void:
	_probe_enabled = true
	_probe_origin = Time.get_ticks_usec()
	_probe_hits.clear()
	duck_min_db = 0.0
	duck_frames = 0

# Each entry: usec since begin_probe, and the hit's x in the camera's frame (panning is relative
# to the head, so world x is not enough).
func take_probe() -> Array:
	_probe_enabled = false
	var out := _probe_hits.duplicate(true)
	_probe_hits.clear()
	return out

func _record_hit(pos: Vector3) -> void:
	var x := pos.x
	var camera := get_viewport().get_camera_3d() as Camera3D
	if camera != null:
		x = (camera.global_transform.affine_inverse() * pos).x
	_probe_hits.append({"usec": Time.get_ticks_usec() - _probe_origin, "x": x})

# --- voice bookkeeping -------------------------------------------------------------------------

func _free_index() -> int:
	var now := Time.get_ticks_usec()
	for i in VOICES:
		# A voice that stopped (or that a paused/driver-stalled player left marked) is free.
		# Hit samples are under 1 s, so the 4 s cutoff can never truncate a real hit.
		if _active[i] == 1 and (not _players[i].playing or now - _started_usec[i] > 4000000):
			_active[i] = 0
		if _active[i] == 0:
			return i
	return -1

func _steal_oldest() -> int:
	var oldest := -1
	var oldest_start := 0
	for i in VOICES:
		if _active[i] == 0:
			continue
		if oldest < 0 or _started_usec[i] < oldest_start:
			oldest = i
			oldest_start = _started_usec[i]
	if oldest >= 0:
		_players[oldest].stop()
		_active[oldest] = 0
	return oldest

# FR-034: every voice that starts inside the 30 ms window is set to base - 10*log10(n). Recomputed
# only when a new hit arrives; voices are never raised when the window empties.
func _apply_window_gain() -> void:
	var now := Time.get_ticks_usec()
	var n := 0
	for i in VOICES:
		if _active[i] == 1 and now - _started_usec[i] <= WINDOW_USEC:
			n += 1
	if n <= 1:
		return
	var attenuation := 10.0 * log(float(n)) / log(10.0)
	for i in VOICES:
		if _active[i] == 1 and now - _started_usec[i] <= WINDOW_USEC:
			_players[i].volume_db = _base_db[i] - attenuation

# Test accessors: the unit test needs the positions and gains without reaching into children.
func voice_position(index: int) -> Vector3:
	return _players[index].global_position

func voice_gain_db(index: int) -> float:
	return _players[index].volume_db

func voice_active(index: int) -> bool:
	return _active[index] == 1
