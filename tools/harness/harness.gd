extends RefCounted
class_name Harness

# Deterministic replay (v0.4 gate FR-001/FR-011/FR-012).
#
# In replay mode the game stops reading the audio clock: song time is frame_index / fps and the
# global RNG is seeded. Everything that decides gameplay (spawns, cuts, misses, score) is written
# to a canonical log, so two runs can be diffed byte for byte. The seam is inert unless replay
# mode is enabled - normal play still uses the audio clock.

static var replay := false
static var fps := 72.0
static var frame := 0
static var max_frames := 1440
static var lines := PackedStringArray()

static func begin(rate: float, frames: int = 1440) -> void:
	replay = true
	fps = maxf(rate, 1.0)
	max_frames = maxi(frames, 1)
	frame = 0
	lines.clear()
	# Bot miss patterns are deterministic already; this pins debris jitter, pitch jitter and any
	# other global RNG the run touches.
	seed(1234567)
	print("HARNESS replay begin fps=%.1f max_frames=%d" % [fps, max_frames])

static func song_time() -> float:
	return float(frame) / fps

static func tick() -> void:
	if replay:
		frame += 1

static func log_spawn(note: ColorNoteInfo) -> void:
	if not replay:
		return
	lines.append("SPAWN f=%d b=%.6f x=%d y=%d c=%d d=%d" % [
		frame, note.beat, note.line_index, note.line_layer, note.color, note.cut_direction])

static func log_cut(beat: float, good: bool, angle: float, dist: float, travel: float, beat_acc: float) -> void:
	if not replay:
		return
	lines.append("CUT f=%d b=%.6f good=%s a=%d d=%d t=%d ba=%d score=%d combo=%d mult=%d" % [
		frame, beat, str(good), _q(angle), _q(dist), _q(travel), _q(beat_acc),
		Scoreboard.points, Scoreboard.combo, Scoreboard.multiplier])

static func log_miss(beat: float) -> void:
	if not replay:
		return
	lines.append("MISS f=%d b=%.6f combo=%d" % [frame, beat, Scoreboard.combo])

static func finish(path: String) -> void:
	if not replay:
		return
	lines.append("TOTAL frames=%d score=%d combo_max=%d right=%.0f wrong=%.0f" % [
		frame, Scoreboard.points, Scoreboard.combo, Scoreboard.right_notes, Scoreboard.wrong_notes])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("harness: cannot write %s" % path)
		return
	for line in lines:
		f.store_line(line)
	f.close()
	replay = false
	print("HARNESS replay wrote %s lines=%d frames=%d" % [ProjectSettings.globalize_path(path), lines.size(), frame])

static func _q(value: float) -> int:
	return int(round(value * 1000.0))
