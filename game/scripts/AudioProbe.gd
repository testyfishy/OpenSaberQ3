extends Node

# Bench-only audio probe (part 6 instrument).
#
# Taps two points on the mixer and writes 16-bit stereo WAVs for offline analysis:
#   <prefix>.wav      - Master, after music, SFX and the hit limiter (what the player hears)
#   <prefix>_sfx.wav  - SFX only, so hit levels can be measured without the music masking them
#
# A headset microphone would add the room, the speakers and AGC to the measurement; these taps are
# the signal the game actually produces.
#
# Created by BenchmarkRunner only when the flag has `[bench] audio_probe=<seconds>`.

const MAX_SECONDS := 60.0
const TRACK_BUSES := [&"Master", &"SFX"]

var _tracks: Array = []
var _rate := 44100
var _limit_frames := 0
var _recording := false

func start(prefix: String, seconds: float) -> bool:
	if _recording:
		return false
	_rate = int(AudioServer.get_mix_rate())
	_limit_frames = int(clampf(seconds, 0.5, MAX_SECONDS) * _rate)
	for bus_name: StringName in TRACK_BUSES:
		var bus := AudioServer.get_bus_index(bus_name)
		if bus < 0:
			vr.log_error("AUDIOPROBE: no %s bus" % bus_name)
			continue
		var capture := AudioEffectCapture.new()
		capture.buffer_length = 1.0
		var effect_index := AudioServer.get_bus_effect_count(bus)
		AudioServer.add_bus_effect(bus, capture)
		var suffix := "" if bus_name == &"Master" else "_" + String(bus_name).to_lower()
		# Packed arrays are value types: keep the buffer in the dictionary and write it back after
		# each read. An `as`-cast resize would resize a copy and leave the stored buffer empty.
		var buffer := PackedByteArray()
		buffer.resize(_limit_frames * 4)
		_tracks.append({
			"bus": bus,
			"effect": effect_index,
			"capture": capture,
			"path": prefix + suffix + ".wav",
			"frames": 0,
			"data": buffer,
		})
	if _tracks.is_empty():
		return false
	_recording = true
	set_process(true)
	vr.log_info("AUDIOPROBE: recording %.1fs to %s (%d Hz)" % [seconds, prefix, _rate])
	return true

func stop() -> Array[String]:
	var written: Array[String] = []
	if not _recording:
		return written
	_recording = false
	set_process(false)
	for track: Dictionary in _tracks:
		var capture: AudioEffectCapture = track["capture"]
		AudioServer.remove_bus_effect(int(track["bus"]), int(track["effect"]))
		var data: PackedByteArray = track["data"]
		data.resize(int(track["frames"]) * 4)
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = _rate
		wav.stereo = true
		wav.data = data
		var path: String = track["path"]
		var err := wav.save_to_wav(path)
		if err == OK:
			written.append(path)
			vr.log_info("AUDIOPROBE: wrote %s (%d frames)" % [path, int(track["frames"])])
		else:
			vr.log_error("AUDIOPROBE: cannot write %s (%s)" % [path, error_string(err)])
	_tracks.clear()
	return written

func _process(_delta: float) -> void:
	if not _recording:
		return
	for track: Dictionary in _tracks:
		var capture: AudioEffectCapture = track["capture"]
		var available := capture.get_frames_available()
		if available <= 0:
			continue
		var frames := capture.get_buffer(available)
		var data: PackedByteArray = track["data"]
		var count: int = track["frames"]
		for frame in frames:
			if count >= _limit_frames:
				break
			var offset := count * 4
			data.encode_s16(offset, int(clampf(frame.x, -1.0, 1.0) * 32767.0))
			data.encode_s16(offset + 2, int(clampf(frame.y, -1.0, 1.0) * 32767.0))
			count += 1
		track["frames"] = count
		track["data"] = data
		if count >= _limit_frames:
			stop()
			return
