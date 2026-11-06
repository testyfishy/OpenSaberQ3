extends Node
class_name AudioAnalyser

# In-game audio analyser (spec FR-040/FR-041, user request 2026-11-06). Off by default.
#
# Shows the last hit's gain and pan side, plus a three-band view of the SFX bus. The spectrum comes
# from an AudioEffectSpectrumAnalyzer on the SFX bus, which is the signal the hits are mixed from.
# While off it adds no effect, no label and no per-hit work.

const UPDATE_S := 0.1
const BANDS := [[150.0, 800.0], [800.0, 2000.0], [2000.0, 6000.0]]

var _label: Label3D
var _effect: AudioEffectSpectrumAnalyzer
var _bus := -1
var _effect_index := -1
var _enabled := false
var _timer := 0.0

func _ready() -> void:
	Settings.changed.connect(_on_setting_changed)
	_enabled = Settings.audio_analyser
	if _enabled:
		_enable()
	else:
		set_process(false)

func _on_setting_changed(key: StringName) -> void:
	if key != &"audio_analyser":
		return
	if Settings.audio_analyser:
		_enable()
	else:
		_disable()

func _enable() -> void:
	if _enabled and is_instance_valid(_label):
		return
	_enabled = true
	if _bus < 0:
		_bus = AudioServer.get_bus_index(&"SFX")
	# Check the effect, not the bus: `_disable()` leaves `_bus` set, so a second enable after an
	# off/on must still add its effect.
	if _effect == null and _bus >= 0:
		_effect = AudioEffectSpectrumAnalyzer.new()
		_effect.buffer_length = 0.1
		_effect_index = AudioServer.get_bus_effect_count(_bus)
		AudioServer.add_bus_effect(_bus, _effect)
	if GlobalReferences.hit_audio != null:
		GlobalReferences.hit_audio.analyser_enabled = true
	_attach_label()
	set_process(true)

func _attach_label() -> void:
	if is_instance_valid(_label):
		return
	_label = null
	var camera := get_viewport().get_camera_3d() as Camera3D
	if camera == null:
		return
	_label = Label3D.new()
	_label.name = "AudioAnalyserLabel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 28
	_label.outline_size = 8
	_label.modulate = Color(1, 1, 1, 0.9)
	_label.position = Vector3(0, -0.26, -0.9)
	_label.text = "AUDIO  waiting for a hit"
	camera.add_child(_label)

func _disable() -> void:
	_enabled = false
	set_process(false)
	if is_instance_valid(_label):
		_label.queue_free()
	_label = null
	# Remove by identity: another effect could have been added to the bus since ours.
	if _bus >= 0 and _effect != null:
		for i in AudioServer.get_bus_effect_count(_bus):
			if AudioServer.get_bus_effect(_bus, i) == _effect:
				AudioServer.remove_bus_effect(_bus, i)
				break
	_effect = null
	_effect_index = -1
	if GlobalReferences.hit_audio != null:
		GlobalReferences.hit_audio.analyser_enabled = false

func _process(delta: float) -> void:
	if not _enabled:
		return
	if not is_instance_valid(_label):
		# The camera does not exist yet when the setting is restored at launch, and a scene change
		# frees the camera together with the label.
		_label = null
		_attach_label()
		if not is_instance_valid(_label):
			return
	_timer += delta
	if _timer < UPDATE_S:
		return
	_timer = 0.0
	var bars := PackedStringArray(["", "", ""])
	var instance := AudioServer.get_bus_effect_instance(_bus, _effect_index) as AudioEffectSpectrumAnalyzerInstance
	if instance != null:
		for i in BANDS.size():
			var band: Array = BANDS[i]
			var magnitude := instance.get_magnitude_for_frequency_range(band[0], band[1]).length()
			bars[i] = _bar_for_db(linear_to_db(maxf(magnitude, 0.000001)))
	var gain := 0.0
	var pan := 0.0
	if GlobalReferences.hit_audio != null:
		gain = GlobalReferences.hit_audio.last_gain_db
		pan = GlobalReferences.hit_audio.last_pan_x
	var side := "L" if pan < 0.0 else "R"
	_label.text = "AUDIO  last hit %+.1f dB  pan %s %.2f\nLOW %s\nMID %s\nHIGH %s" % [
		gain, side, absf(pan), bars[0], bars[1], bars[2]]

# One bar string for a dB value: 8 chars at 0 dB, none at -60 dB. Split out so the headless test
# can prove the formatting without an audio device.
func _bar_for_db(db: float) -> String:
	var filled := clampi(int(remap(db, -60.0, 0.0, 0.0, 8.0)), 0, 8)
	return "#".repeat(filled)
