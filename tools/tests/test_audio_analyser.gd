extends Node

# AudioAnalyser test (spec FR-040/FR-041). Uses the real GlobalReferences instance: enable, check
# the label and bus effect, play a hit, toggle off/on, swap the camera, then disable and check
# everything is gone. Also proves the bar formatting without needing an audio device.

var _bad := 0
var _camera: Camera3D

func _ready() -> void:
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.current = true
	for i in 2:
		await get_tree().process_frame

	var analyser: Node = GlobalReferences.audio_analyser
	var bus := AudioServer.get_bus_index(&"SFX")
	var before := AudioServer.get_bus_effect_count(bus)

	# Formatting is separate from the audio device.
	_check(analyser.call("_bar_for_db", 0.0) == "########", "0 dB is a full bar")
	_check(analyser.call("_bar_for_db", -60.0) == "", "-60 dB is an empty bar")
	_check((analyser.call("_bar_for_db", -30.0) as String).length() == 4, "-30 dB is a half bar")

	Settings.audio_analyser = true
	for i in 3:
		await get_tree().process_frame
	var label: Variant = analyser.get("_label")
	_check(label != null, "label created")
	if label != null:
		_check((label as Node).get_parent() == _camera, "label attached to the camera")
	_check(AudioServer.get_bus_effect_count(bus) == before + 1, "spectrum effect added")

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 44100
	wav.stereo = true
	var data := PackedByteArray()
	data.resize(44100 * 4)
	wav.data = data
	GlobalReferences.hit_audio.reset()
	GlobalReferences.hit_audio.play(wav, Vector3(0.6, 0, -1.0), -3.0, 1.0)
	_check(absf(GlobalReferences.hit_audio.last_gain_db + 3.0) < 0.01, "last hit gain recorded")
	_check(GlobalReferences.hit_audio.last_pan_x > 0.0, "right-side hit has positive pan")
	await get_tree().create_timer(0.15).timeout
	if label != null and is_instance_valid(label):
		_check((label as Label3D).text.contains("last hit"), "label text updated")
		_check((label as Label3D).text.contains("-3.0"), "label shows the hit gain")

	# Off and on again must restore exactly one effect (the effect is added by _enable, not by
	# the bus index being unset).
	Settings.audio_analyser = false
	for i in 3:
		await get_tree().process_frame
	_check(AudioServer.get_bus_effect_count(bus) == before, "effect removed on disable")
	Settings.audio_analyser = true
	for i in 3:
		await get_tree().process_frame
	_check(AudioServer.get_bus_effect_count(bus) == before + 1, "effect restored after off/on")
	_check(analyser.get("_effect") != null, "effect instance after off/on")

	# A scene change frees the camera and the label; the analyser must re-attach to the new camera.
	_camera.queue_free()
	await get_tree().process_frame
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.current = true
	for i in 4:
		await get_tree().process_frame
	var new_label: Variant = analyser.get("_label")
	_check(new_label != null and (new_label as Node).get_parent() == _camera, "label re-attached after camera swap")

	Settings.audio_analyser = false
	for i in 3:
		await get_tree().process_frame
	_check(analyser.get("_label") == null, "label removed at the end")
	_check(AudioServer.get_bus_effect_count(bus) == before, "effect removed at the end")

	print("ANALYSERTEST ", "PASS" if _bad == 0 else "FAIL")
	get_tree().quit(0 if _bad == 0 else 1)

func _check(condition: bool, what: String) -> void:
	if not condition:
		push_error("ANALYSERTEST " + what)
		_bad += 1
