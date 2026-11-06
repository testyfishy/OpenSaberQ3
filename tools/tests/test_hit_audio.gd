extends Node

# HitAudio unit test (specs/016 Part 6, FR-031..FR-034, FR-036).
#
# Run: godot --headless --path . res://tools/tests/test_hit_audio.tscn

const HitAudioScript := preload("res://game/scripts/HitAudio.gd")

var _bad := 0

func _ready() -> void:
	var pool = HitAudioScript.new()
	pool.name = "HitAudioTest"
	add_child(pool)
	await get_tree().process_frame

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 44100
	wav.stereo = true
	var data := PackedByteArray()
	data.resize(44100 * 4)  # one second of silence
	wav.data = data

	# Fill the pool and check every voice landed on its own position.
	for i in pool.VOICES:
		var id: int = pool.play(wav, Vector3(i, 0, 0), 0.0, 1.0)
		_check(id == i, "voice %d allocated in order (got %d)" % [i, id])
		_check(pool.voice_active(i), "voice %d active" % i)
		_check(pool.voice_position(i).is_equal_approx(Vector3(i, 0, 0)), "voice %d position" % i)

	# The 17th steals the oldest (voice 0) and takes its position.
	var stolen: int = pool.play(wav, Vector3(99, 0, 0), 0.0, 1.0)
	_check(stolen == 0, "17th hit steals voice 0 (got %d)" % stolen)
	_check(pool.steal_count == 1, "steal counted")
	_check(pool.voice_position(0).is_equal_approx(Vector3(99, 0, 0)), "stolen voice moved")

	# FR-034: four voices started inside the window are each at base - 10*log10(4).
	pool.reset()
	for i in 4:
		pool.play(wav, Vector3(i, 0, 0), 0.0, 1.0)
	var want := -10.0 * log(4.0) / log(10.0)
	for i in 4:
		_check(absf(pool.voice_gain_db(i) - want) < 0.01,
			"window gain voice %d = %.3f dB (want %.3f)" % [i, pool.voice_gain_db(i), want])

	# Reset stops everything and clears the counters.
	pool.reset()
	for i in pool.VOICES:
		_check(not pool.voice_active(i), "voice %d released by reset" % i)
	_check(pool.steal_count == 0, "steal count reset")

	# Probe: the recorded x keeps the side of the head.
	pool.begin_probe()
	pool.play(wav, Vector3(0.8, 0, -1.0), 0.0, 1.0)
	pool.play(wav, Vector3(-0.9, 0, -1.0), 0.0, 1.0)
	var hits: Array = pool.take_probe()
	_check(hits.size() == 2, "probe recorded two hits")
	if hits.size() == 2:
		_check(float(hits[0]["x"]) > 0.0, "right-side hit has positive x")
		_check(float(hits[1]["x"]) < 0.0, "left-side hit has negative x")

	pool.queue_free()
	print("HITAUDIOTEST ", "PASS" if _bad == 0 else "FAIL")
	get_tree().quit(0 if _bad == 0 else 1)

func _check(condition: bool, what: String) -> void:
	if not condition:
		push_error("HITAUDIOTEST " + what)
		_bad += 1
