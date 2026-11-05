extends Node3D
class_name DefaultSaber

# Hit-feedback audio. Design and every number here: specs/002-hit-audio-research/research.md
# (§3 mapping, §5 mechanism). Summary:
#
#   * one AudioStreamPlayer3D per saber carrying an AudioStreamPolyphonic, so
#     overlapping hits get a voice each instead of cutting each other off;
#   * per-voice sample, gain and pitch come from the cut data the note returned
#     (HitInfo), which is why `hit()` takes the info rather than just a time;
#   * all voices are mixed first and then panned/attenuated at this node's
#     current transform, so the sound is always at the saber tip.
#
# The player's `pitch_scale`/`volume_db` are node-wide and shared by every voice,
# and `max_polyphony` cannot give a voice its own pitch — that is why neither is
# used here.

const POLYPHONY := 8

# Audio verification counters (FR: prove hit audio really plays). Benchmark-only; reset and
# read by BenchmarkRunner, which writes them into the run's meta file. Zero effect in play.
static var probe_enabled := false
static var probe_calls := 0
static var probe_invalid := 0
static var probe_soft := 0
static var probe_hard := 0
static var probe_accent := 0
static var probe_dull := 0

# Sample pools. Generated procedurally by tools/audio/gen_hitsounds.py, so there
# is no licensing obligation attached (ATTRIBUTION.md).
#   soft: pre-darkened (the soft layer *is* the low-pass; a polyphonic voice has
#         no per-voice DSP and the node's filter would hit every voice)
#   dull: wrong-saber / bomb set
const SOFT: Array[AudioStream] = [
	preload("res://game/data/hits/soft_01.wav"),
	preload("res://game/data/hits/soft_02.wav"),
	preload("res://game/data/hits/soft_03.wav"),
]
const HARD: Array[AudioStream] = [
	preload("res://game/data/hits/hard_01.wav"),
	preload("res://game/data/hits/hard_02.wav"),
	preload("res://game/data/hits/hard_03.wav"),
]
const ACCENT: Array[AudioStream] = [
	preload("res://game/data/hits/accent_01.wav"),
]
const DULL: Array[AudioStream] = [
	preload("res://game/data/hits/dull_01.wav"),
	preload("res://game/data/hits/dull_02.wav"),
]

# Gain budget (FR-012): the three gesture terms span at most -8 dB, the jitter
# +/-0.5 dB is counted inside the clamp, and the total span is exactly 9 dB.
# Split into terms and clamped once, rather than summed wide and clamped after
# (which would flatten every slow off-centre hit onto the same floor).
const SPEED_GAIN_MIN_DB := -6.0     # at SPEED_REF_MIN m/s
const SPEED_GAIN_MAX_DB := 0.0      # at SPEED_REF_MAX m/s
const SPEED_REF_MIN := 1.0
const SPEED_REF_MAX := 8.0
const DIST_GAIN_MIN_DB := -1.5      # centrality 0
const TRAVEL_GAIN_MIN_DB := -0.5    # travel 0
const JITTER_DB := 0.5
const GAIN_MIN_DB := -8.5
const GAIN_MAX_DB := 0.5

# Layer thresholds.
# The "thump" set: same files, re-derived with a low-shelf boost, a 2.5 kHz cut and soft
# clipping (tools/audio/make_thump_set.py). Selectable in settings, so the old sound is not lost.
const THUMP_SOFT: Array[AudioStream] = [
preload("res://game/data/hits_thump/soft_01.wav"),
preload("res://game/data/hits_thump/soft_02.wav"),
preload("res://game/data/hits_thump/soft_03.wav"),
]
const THUMP_HARD: Array[AudioStream] = [
preload("res://game/data/hits_thump/hard_01.wav"),
preload("res://game/data/hits_thump/hard_02.wav"),
preload("res://game/data/hits_thump/hard_03.wav"),
]
const THUMP_ACCENT: Array[AudioStream] = [
preload("res://game/data/hits_thump/accent_01.wav"),
]
const THUMP_DULL: Array[AudioStream] = [
preload("res://game/data/hits_thump/dull_01.wav"),
preload("res://game/data/hits_thump/dull_02.wav"),
]

# Active pools. Swapped as a set, never between _pick() and playback, so a live voice keeps the
# stream it started with.
var _soft: Array[AudioStream] = SOFT
var _hard: Array[AudioStream] = HARD
var _accent: Array[AudioStream] = ACCENT
var _dull: Array[AudioStream] = DULL

const LAYER_SOFT_MAX_SPEED := 3.0   # below this -> soft layer
const LAYER_HARD_MAX_SPEED := 7.0   # above this -> hard + accent
const ANGLE_SOFT_THRESHOLD := 0.5   # glancing cut sounds dull whatever the speed
const BEAT_ACCENT_MIN := 0.2        # far off the beat: drop the accent layer

# Pitch is jitter only: no pitch->score mapping ships anywhere credible, and
# key data does not exist in this map format (research.md §3, "key-lock").
const PITCH_JITTER_ST := 1.0        # FR-012 ceiling is +/-2 st
# Bench-only: when true, _fire() returns immediately. Used to test whether audio voice
# churn is what makes a long run slower, without changing anything else.
static var audio_disabled := false
const BAD_CUT_GAIN_DB := -3.0       # wrong saber / bomb, on the dull set
const CHAIN_TAP_GAIN_DB := -4.0     # no hit data at all: a light tap

var is_extended := false

@onready var _anim := $AnimationPlayer as AnimationPlayer
@onready var light_mesh := $LightSaber_Mesh as MeshInstance3D
@onready var _mat := light_mesh.material_override as ShaderMaterial
@onready var tip := $tip as Marker3D
@onready var tail := $tail as SaberTail
@onready var hitsound := $hitsound as AudioStreamPlayer3D

# Emissive glow (FR-046, 007 rule 3): a camera-facing quad strip, billboarded about the
# blade axis in its own shader, instead of the 2.4x additive capsule shell it replaced. Its
# height is driven by the same Show/Hide animations as the blade, so a retracting saber
# shortens its glow. The colour comes from the light globals, not from this node, because a
# map light event tints the light once at the source (007 rule 6).
@onready var _halo := $LightSaber_Mesh/Halo as MeshInstance3D
@onready var _halo_mat := _halo.material_override as ShaderMaterial

# Mirrored copy, as a `next_pass` on the blade material (FR-047). The pass reads the colour
# from an instance uniform, so one shared material serves both blades.
const MIRROR_SHADER := preload("res://game/shaders/mirror_pass.gdshader")
static var _mirror_material: ShaderMaterial

# The polyphonic playback, obtained once from the player. Every later hit is a
# `play_stream` on this object; the player itself is never played again, because
# a second play()/stop() creates a new playback and silences every live voice.
var _voices: AudioStreamPlaybackPolyphonic = null

# Fixed ring of voice ids, oldest at `_voice_next`. Used to steal the oldest
# still-playing voice when the pool is full, instead of relying on engine order.
var _voice_ids := PackedInt32Array()
var _voice_next := 0

# Last variant played per pool, so round-robin never repeats immediately.
var _last_variant := {}

# Pending delayed hit sounds: `{remaining: float, info: HitInfo}`. A hit whose
# note is a little in the future plays its sound when that beat arrives; this
# used to be an `await get_tree().create_timer(...)`, i.e. a SceneTreeTimer plus
# a coroutine per hit (FR-033: per-hit allocation on the gameplay path). A
# SceneTreeTimer only fires on a process frame anyway, so polling here has the
# same timing. The info travels with the delay so the sound keeps the gesture
# data it was struck with.
var _pending_hits: Array[Dictionary] = []

func _ready() -> void:
	_apply_hit_sound_set(Settings.hit_sound)
	Settings.changed.connect(_on_setting_changed)
	set_process(false)
	quickhide()
	set_halo_enabled(Settings.saber_halo)
	_set_mirror_pass(Settings.mirror_reflections)
	# Exactly one play() for the lifetime of this node, then cache the playback.
	if hitsound.stream is AudioStreamPolyphonic:
		hitsound.play()
		_voices = hitsound.get_stream_playback() as AudioStreamPlaybackPolyphonic

func _process(delta: float) -> void:
	if _pending_hits.is_empty():
		set_process(false)
		return
	var i := 0
	while i < _pending_hits.size():
		_pending_hits[i]["remaining"] -= delta
		if _pending_hits[i]["remaining"] <= 0.0:
			var info: HitInfo = _pending_hits[i]["info"]
			_pending_hits.remove_at(i)
			_fire(info, 0.0)
		else:
			i += 1

func set_color(color: Color) -> void:
	_mat.set_shader_parameter(&"color", color)
	tail.set_color(color)
	# The mirrored pass is a second pass on this same mesh, so its colour travels as an
	# instance uniform: one shared mirror material serves both blades (007 rule 2).
	light_mesh.set_instance_shader_parameter(&"mirror_color", color)

# 0 = left blade, 1 = right: which light global the glow strip reads, so the strip follows
# the light that is applied once at the source rather than carrying its own tint.
func set_side(side: int) -> void:
	_halo_mat.set_shader_parameter(&"side", side)

func set_mirror_enabled(value: bool) -> void:
	_set_mirror_pass(value)

# `next_pass = null` when off, not a hidden uniform test: a pass that is not attached costs
# no draw call at all.
func _set_mirror_pass(enabled: bool) -> void:
	if _mat == null:
		return
	if enabled:
		if _mirror_material == null:
			_mirror_material = ShaderMaterial.new()
			_mirror_material.shader = MIRROR_SHADER
			_mirror_material.render_priority = -1
		if _mat.next_pass != _mirror_material:
			_mat.next_pass = _mirror_material
	elif _mat.next_pass != null:
		_mat.next_pass = null

func set_thickness(value: float) -> void:
	light_mesh.scale.x = value
	light_mesh.scale.z = value

# FR-046 / FR-049: the halo is a setting, so it must be switchable at runtime.
func set_halo_enabled(value: bool) -> void:
	_halo.visible = value

func set_trail(enabled: bool = true) -> void:
	tail.visible = enabled

func _show() -> void:
	_anim.play(&"Show")
	is_extended = true
	
func _hide() -> void:
	_anim.play(&"Hide")
	is_extended = false
	
func quickhide() -> void:
	_anim.play(&"QuickHide")
	is_extended = false

# `info` is null when the cuttable has no hit data (chain links).
func hit(time_offset: float, info: HitInfo = null) -> void:
	if time_offset > 0.2 or time_offset < -0.05:
		_fire(info, 0.0)
	else:
		if time_offset <= 0.0:
			# Already late: skip into the sample instead of starting it late.
			_fire(info, maxf(0.0, -time_offset))
		else:
			_pending_hits.append({"remaining": time_offset, "info": info})
			set_process(true)

# Gain -> layer -> pitch -> voices. One function so the mapping stays readable
# and the pending-hit path and the immediate path cannot drift apart.
func _fire(info: HitInfo, from_offset: float) -> void:
	if audio_disabled:
		return
	var gain_db := 0.0
	var pool: Array = _hard
	var pool_key := &"hard"
	var accent := false
	
	if info == null:
		# Chain link: no scoring data, keep the old "a cut happened" cue.
		pool = _soft
		pool_key = &"soft"
		gain_db = CHAIN_TAP_GAIN_DB
	elif info.kind == HitInfo.Kind.BAD:
		# A different, duller set: the sound should tell you it was wrong.
		pool = _dull
		pool_key = &"dull"
		gain_db = BAD_CUT_GAIN_DB
	else:
		var speed_gain := remap(
			clampf(info.speed_len, SPEED_REF_MIN, SPEED_REF_MAX),
			SPEED_REF_MIN, SPEED_REF_MAX, SPEED_GAIN_MIN_DB, SPEED_GAIN_MAX_DB)
		var centrality_gain := remap(clampf(info.dist_acc, 0.0, 1.0), 0.0, 1.0, DIST_GAIN_MIN_DB, 0.0)
		var travel_trim := remap(clampf(info.travel, 0.0, 1.0), 0.0, 1.0, TRAVEL_GAIN_MIN_DB, 0.0)
		gain_db = clampf(
			speed_gain + centrality_gain + travel_trim + randf_range(-JITTER_DB, JITTER_DB),
			GAIN_MIN_DB, GAIN_MAX_DB)
		
		if info.angle_acc < ANGLE_SOFT_THRESHOLD or info.speed_len < LAYER_SOFT_MAX_SPEED:
			pool = _soft
			pool_key = &"soft"
		elif info.speed_len <= LAYER_HARD_MAX_SPEED:
			pool = _hard
			pool_key = &"hard"
		else:
			pool = _hard
			pool_key = &"hard"
			# Far off the beat, the accent would only smear the timing.
			accent = info.beat_acc >= BEAT_ACCENT_MIN
	
	var semitones := randf_range(-PITCH_JITTER_ST, PITCH_JITTER_ST)
	_play(_pick(pool, pool_key), gain_db, semitones, from_offset)
	if probe_enabled:
		match pool_key:
			&"soft": probe_soft += 1
			&"dull": probe_dull += 1
			&"hard": probe_hard += 1
		if accent:
			probe_accent += 1
	if accent:
		# The accent stacks on top of the hard layer, so it must sit below it or the pair
		# breaches the 9 dB total budget. -4 dB is a tuning start (G4).
		_play(_pick(_accent, &"accent"), gain_db - 4.0, semitones, from_offset)

# Round-robin with no immediate repeat (research.md §3 row 13).
func _pick(pool: Array, key: StringName) -> AudioStream:
	var n := pool.size()
	if n == 0:
		return null
	var idx := randi() % n
	var last: int = _last_variant.get(key, -1)
	if n > 1 and idx == last:
		idx = (idx + 1 + randi() % (n - 1)) % n
	_last_variant[key] = idx
	return pool[idx] as AudioStream

func _play(sample: AudioStream, gain_db: float, semitones: float, from_offset: float) -> void:
	if sample == null:
		return
	# Pause, a tree re-entry or a saber swap can stop the parent player, and the
	# cached playback would then be dead without any error. Re-arm before each
	# hit rather than assuming the _ready() play() still holds.
	if not hitsound.playing:
		hitsound.play()
		_voices = hitsound.get_stream_playback() as AudioStreamPlaybackPolyphonic
	if _voices == null:
		return
	
	var ratio := pow(2.0, semitones / 12.0)
	# Godot marks a stopped stream inactive only on the NEXT audio mix, so stopping a
	# voice and immediately calling play_stream would still return INVALID_ID and the
	# newest hit would be the one dropped. The stream is therefore configured with
	# POLYPHONY + 2 slots (see the .tscn): we cap ourselves at POLYPHONY, so after a
	# steal there is always a spare slot to play into without a retry.
	if _active_voice_count() >= POLYPHONY:
		_steal_oldest()
	# p_bus is only honoured on the Web PLAYBACK_TYPE_SAMPLE path; on native the voice
	# is mixed by the player and routed by the node's own `bus` property, which is SFX.
	var id := _voices.play_stream(sample, from_offset, gain_db, ratio, 0, &"SFX")
	if probe_enabled:
		probe_calls += 1
	if id == AudioStreamPlaybackPolyphonic.INVALID_ID:
		if probe_enabled:
			probe_invalid += 1
		return
	_remember(id)

# Voices still actually playing. A stolen voice lingers here until the next mix, so
# this is deliberately the same check the steal path uses.
func _active_voice_count() -> int:
	if _voices == null:
		return 0
	var count := 0
	for id in _voice_ids:
		if id != AudioStreamPlaybackPolyphonic.INVALID_ID and _voices.is_stream_playing(id):
			count += 1
	return count

func _remember(id: int) -> void:
	if _voice_ids.size() < POLYPHONY:
		_voice_ids.append(id)
		_voice_next = _voice_ids.size() % POLYPHONY
	else:
		_voice_ids[_voice_next] = id
		_voice_next = (_voice_next + 1) % POLYPHONY

# Oldest-first steal. Dead ids are skipped on the way past, so the ring cleans
# itself up without a separate sweep.
func _steal_oldest() -> bool:
	var n := _voice_ids.size()
	for k in n:
		var idx := (_voice_next + k) % n
		var id := _voice_ids[idx]
		if id == AudioStreamPlaybackPolyphonic.INVALID_ID:
			continue
		if _voices != null and _voices.is_stream_playing(id):
			_voices.stop_stream(id)
			return true
	return false


func _on_setting_changed(key: StringName) -> void:
	if key == &"hit_sound":
		_apply_hit_sound_set(Settings.hit_sound)

func _apply_hit_sound_set(index: int) -> void:
	if index == 1:
		_soft = THUMP_SOFT
		_hard = THUMP_HARD
		_accent = THUMP_ACCENT
		_dull = THUMP_DULL
	else:
		_soft = SOFT
		_hard = HARD
		_accent = ACCENT
		_dull = DULL
	# The sets have different variant counts; restart the round-robin so it cannot index past
	# the end of the new pool.
	_last_variant.clear()
