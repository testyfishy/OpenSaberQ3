extends SceneTree

# Throwaway local check (not shipped): does the polyphonic lifecycle behave?
# Run: godot --headless --path . --script res://tools/audio/hit_test.gd

var _saber: Node3D

func _initialize() -> void:
	var scene := load("res://game/sabers/default/default_saber.tscn") as PackedScene
	_saber = scene.instantiate() as Node3D
	root.add_child(_saber)
	# _ready() (and therefore @onready + the one play()) is deferred to the first
	# frame in a --script SceneTree.
	await process_frame
	var player := _saber.get_node("hitsound") as AudioStreamPlayer3D
	print("0. sample formats: ", _formats())
	print("1. stream=", player.stream, " playing=", player.playing, " _voices=", _saber._voices)

	var info := HitInfo.new()
	info.speed_len = 5.0
	info.angle_acc = 0.8
	info.dist_acc = 0.9
	info.travel = 0.8
	info.beat_acc = 0.9

	_saber.hit(0.0, info)
	print("2. after good hit ids=", _saber._voice_ids, " playing=", player.playing)

	_saber.hit(0.0, info)
	print("3. after 2nd hit ids=", _saber._voice_ids, " same playback=", player.get_stream_playback() == _saber._voices)

	var fast := HitInfo.new()
	fast.speed_len = 9.0
	fast.angle_acc = 0.9
	fast.dist_acc = 1.0
	fast.travel = 1.0
	fast.beat_acc = 0.9
	_saber.hit(0.0, fast)
	print("4. accent ids=", _saber._voice_ids)

	var bad := HitInfo.new()
	bad.kind = HitInfo.Kind.BAD
	bad.is_correct_saber = false
	_saber.hit(0.0, bad)
	print("5. bad ids=", _saber._voice_ids)

	_saber.hit(0.0, null)
	print("6. chain-link (null info) ids=", _saber._voice_ids)

	# Future beat: must queue, keep its info, then fire on drain.
	var future := HitInfo.new()
	future.speed_len = 2.0
	_saber.hit(0.030, future)
	print("7. pending=", _saber._pending_hits)
	_saber._process(0.040)
	print("8. after drain pending=", _saber._pending_hits, " ids=", _saber._voice_ids)

	# Overrun the pool: 12 more hits at once must steal, never exceed 8 slots.
	for i in 12:
		_saber.hit(0.0, info)
	print("9. after 12 more: ring size=", _saber._voice_ids.size(), " next=", _saber._voice_next, " playing=", player.playing)

	# A player swap (pause/stop) must be re-armed, not silenced.
	player.stop()
	print("10. after stop playing=", player.playing, " stale playback valid=", _saber._voices != null)
	_saber.hit(0.0, info)
	print("11. re-armed playing=", player.playing, " ids=", _saber._voice_ids)

	# The particle saber overrides _process but no longer hit(); same voices, and
	# the pending queue must drain through super._process.
	var pscene := load("res://game/sabers/particles/particles_saber.tscn") as PackedScene
	var psaber := pscene.instantiate() as Node3D
	root.add_child(psaber)
	await process_frame
	psaber.hit(0.0, info)
	psaber.hit(0.0, info)
	print("12. particle saber ids=", psaber._voice_ids)
	psaber.hit(0.030, future)
	psaber._process(0.040)
	print("13. particle pending=", psaber._pending_hits, " ids=", psaber._voice_ids)

	var sfx := AudioServer.get_bus_index(&"SFX")
	print("14. SFX bus effect=", AudioServer.get_bus_effect(sfx, 0), " count=", AudioServer.get_bus_effect_count(sfx))

	quit()

# 16_BITS (1) means uncompressed PCM: no decoder on the hit path.
func _formats() -> String:
	var out := []
	for pool in _saber.HARD + _saber.SOFT + _saber.ACCENT + _saber.DULL:
		var w := pool as AudioStreamWAV
		out.append("%s f=%d %dms" % [w.resource_path.get_file(), w.format, int(1000.0 * w.data.size() / (2.0 * w.mix_rate))])
	return ", ".join(out)
