extends RefCounted
class_name NoteMotion

# The one place a note's motion is defined.
#
# Since 0.7.26 this is Beat Saber's model: every object travels at the difficulty's note jump
# speed (NJS, metres per second) and appears a "half jump duration" before its beat. Both come
# from the map, so a fast map comes at the player fast and a slow one slowly, as its mapper
# intended:
#
#   NJS            Info.dat `_noteJumpMovementSpeed`; when the map leaves it at 0, the game's own
#                  default for that difficulty (10 up to Hard, 12 Expert, 16 Expert+).
#   half jump      4 beats, halved until the distance it covers is under 18 m, then shifted by
#                  the map's `_noteJumpStartBeatOffset`, never less than a quarter of a beat.
#   spawn distance NJS x the half jump's length in seconds.
#
# Before that, the game ignored both values: every object moved 4 metres per beat and appeared
# 4 beats ahead, whatever the map said. That model is still what an unconfigured NoteMotion does
# (see `configured`), so the harness scenes and tools that spawn objects without loading a map
# keep the numbers they were written against.
#
# Distances are worked out in seconds, not beats, so a tempo change in the middle of a map does
# not bend them: an object's z is always (time until its beat) x NJS.

const LEGACY_METRES_PER_BEAT := 4.0
const LEGACY_SPAWN_BEATS := 4.0
const MAX_HALF_JUMP_DISTANCE_M := 17.999
const MIN_HALF_JUMP_BEATS := 0.25

static var configured := false
static var _njs := 0.0
static var _half_jump_beats := LEGACY_SPAWN_BEATS
static var _base_bpm := 120.0


static func reset() -> void:
	configured = false
	_njs = 0.0
	_half_jump_beats = LEGACY_SPAWN_BEATS


## Called when a map is loaded. `difficulty_rank` is Beat Saber's 1/3/5/7/9.
static func configure(njs: float, start_beat_offset: float, base_bpm: float, difficulty_rank: int = 5) -> void:
	_base_bpm = maxf(base_bpm, 1.0)
	_njs = njs if njs > 0.0 else default_njs(difficulty_rank)
	_half_jump_beats = half_jump_beats(_njs, start_beat_offset, _base_bpm)
	configured = true


static func default_njs(difficulty_rank: int) -> float:
	if difficulty_rank >= 9:
		return 16.0
	if difficulty_rank >= 7:
		return 12.0
	return 10.0


static func half_jump_beats(njs: float, start_beat_offset: float, bpm: float) -> float:
	var seconds_per_beat := 60.0 / maxf(bpm, 1.0)
	var beats := 4.0
	while njs * seconds_per_beat * beats > MAX_HALF_JUMP_DISTANCE_M:
		beats *= 0.5
	return maxf(beats + start_beat_offset, MIN_HALF_JUMP_BEATS)


## The map's note jump speed in metres per second (0 when no map has configured it).
static func njs() -> float:
	return _njs


## Forward speed of an object whose beat is `beat`, in metres per second. `object_njs` is a
## per-object override (Noodle Extensions `noteJumpMovementSpeed`); 0 means "the map's".
static func speed_at(beat: float, object_njs: float = 0.0) -> float:
	if object_njs > 0.0:
		return object_njs
	if not configured:
		return LEGACY_METRES_PER_BEAT * Map.bpm_at_beat(beat) / 60.0
	return _njs


## How far an object is from the hit plane: the distance covered between `from_beat` and
## `to_beat`, in metres (negative when `to_beat` is earlier).
static func distance_between(from_beat: float, to_beat: float, object_njs: float = 0.0) -> float:
	if not configured and object_njs <= 0.0:
		return (to_beat - from_beat) * LEGACY_METRES_PER_BEAT
	var speed := object_njs if object_njs > 0.0 else _njs
	return (Map.beat_to_seconds(to_beat) - Map.beat_to_seconds(from_beat)) * speed


## How many beats ahead of the song an object is spawned.
static func spawn_beats() -> float:
	return _half_jump_beats if configured else LEGACY_SPAWN_BEATS


## How far away an object is when it is spawned, in metres.
static func spawn_distance() -> float:
	if not configured:
		return LEGACY_SPAWN_BEATS * LEGACY_METRES_PER_BEAT
	return _njs * (60.0 / _base_bpm) * _half_jump_beats
