extends Node

# AudioAnalyser test (spec FR-040/FR-041). Uses the real GlobalReferences instance: enable, check
# the label and bus effect, play a hit, disable, check both are gone.

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

	Settings.audio_analyser = false
	for i in 3:
		await get_tree().process_frame
	_check(analyser.get("_label") == null, "label removed")
	_check(AudioServer.get_bus_effect_count(bus) == before, "spectrum effect removed")

	print("ANALYSERTEST ", "PASS" if _bad == 0 else "FAIL")
	get_tree().quit(0 if _bad == 0 else 1)

func _check(condition: bool, what: String) -> void:
	if not condition:
		push_error("ANALYSERTEST " + what)
		_bad += 1
