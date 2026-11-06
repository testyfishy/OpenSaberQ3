extends Node

# Bench-only audio probe (part 6 instrument).
#
# Taps the Master bus after music, SFX and the hit limiter, and writes a 16-bit stereo WAV for
# offline analysis with tools/perf/audio_probe.py. This is the signal the player is meant to hear;
# a headset microphone would add the room, the speakers and AGC to the measurement.
#
# Created by BenchmarkRunner only when the flag has `[bench] audio_probe=<seconds>`.

const MAX_SECONDS := 60.0

var _capture: AudioEffectCapture
var _bus := 0
var _effect_index := -1
var _rate := 44100
var _path := ""
var _data := PackedByteArray()
var _frames := 0
var _limit_frames := 0
var _recording := false

func start(path: String, seconds: float) -> bool:
	if _recording:
		return false
	_bus = AudioServer.get_bus_index(&"Master")
	if _bus < 0:
		vr.log_error("AUDIOPROBE: no Master bus")
		return false
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 1.0
	_effect_index = AudioServer.get_bus_effect_count(_bus)
	AudioServer.add_bus_effect(_bus, _capture)
	_rate = int(AudioServer.get_mix_rate())
	_path = path
	_limit_frames = int(clampf(seconds, 0.5, MAX_SECONDS) * _rate)
	_frames = 0
	_data = PackedByteArray()
	_data.resize(_limit_frames * 4)
	_recording = true
	set_process(true)
	vr.log_info("AUDIOPROBE: recording %.1fs to %s (%d Hz)" % [seconds, path, _rate])
	return true

func stop() -> String:
	if not _recording:
		return ""
	_recording = false
	set_process(false)
	if _capture != null:
		AudioServer.remove_bus_effect(_bus, _effect_index)
		_capture = null
		_effect_index = -1
	_data.resize(_frames * 4)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = _rate
	wav.stereo = true
	wav.data = _data
	var err := wav.save_to_wav(_path)
	if err != OK:
		vr.log_error("AUDIOPROBE: cannot write %s (%s)" % [_path, error_string(err)])
		return ""
	vr.log_info("AUDIOPROBE: wrote %s (%d frames)" % [_path, _frames])
	return _path

func _process(_delta: float) -> void:
	if not _recording or _capture == null:
		return
	var available := _capture.get_frames_available()
	if available <= 0:
		return
	var frames := _capture.get_buffer(available)
	for frame in frames:
		if _frames >= _limit_frames:
			break
		var offset := _frames * 4
		_data.encode_s16(offset, int(clampf(frame.x, -1.0, 1.0) * 32767.0))
		_data.encode_s16(offset + 2, int(clampf(frame.y, -1.0, 1.0) * 32767.0))
		_frames += 1
	if _frames >= _limit_frames:
		stop()
