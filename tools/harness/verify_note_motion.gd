extends Node

# Note motion harness (docs/note-motion-report.md): Beat Saber's move phase before the jump (the
# fly-in) for notes, Noodle notes, walls and chain links. Headless.
#
# Every object is run twice from one map clock: as the game spawns it now (MOVE_DURATION_S before
# its jump starts, flying in) and as it spawned before 0.7.37 (at the jump start). From the jump
# start on the two must be drawn in the same place, and before it the flying one must come in at
# 200 m/s from 100 m beyond the jump start and never be hittable. Expected values are literals
# worked out by hand. Each check prints `MOTION ok` / `MOTION FAIL`; the last line is the verdict.
#
# Run: godot --headless --path . res://tools/harness/verify_note_motion.tscn

const MapTimer := preload("res://game/scripts/MapTimer.gd")
const EPS := 0.0005
# 120 Hz physics, as on the headset.
const DT := 1.0 / 120.0

var _fails := 0
var _checks := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("MOTION %s %s%s" % ["ok  " if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _near(label: String, got: float, want: float, eps := EPS) -> void:
	_check(label, absf(got - want) < eps, "got %.5f want %.5f" % [got, want])


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	MapTimer.load_bpm_events({}, 120.0)
	Map.current_info = MapInfo.new("3.0.0", "t", "", "a", "m", 120.0, 0.0, 0.0, "", "", "", 0.0, {}, "", [])
	Map.current_difficulty = DifficultyInfo.new("Expert", 7, "x.dat", 10.0, 0.0, {}, "One")
	Scoreboard.paused = false
	_constants()
	_plain_note()
	_close_jump_not_hittable()
	_noodle_note(false)
	_noodle_note(true)
	_own_jump()
	_plain_wall()
	_noodle_wall()
	_chain_rigid()
	_pool_peak()
	_spawn_pop()
	_legacy()
	NoteMotion.reset()
	Map.current_info = null
	Map.current_difficulty = null
	MapTimer.reset()
	NoodleTracks.reset()
	NoodleFrame.reset()
	var verdict := "MOTION PASS" if _fails == 0 else "MOTION FAIL"
	print("%s (%d checks, %d failed)" % [verdict, _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


# NJS 10 at 120 BPM: half jump 2 beats = 1 s = 10 m.
func _configure() -> void:
	NoteMotion.fly_in_enabled = true
	NoteMotion.configure(10.0, 0.0, 120.0, 7, 1.0)


func _constants() -> void:
	_configure()
	_near("fly-in lasts 0.5 s (kMoveDuration)", NoteMotion.fly_in_seconds(), 0.5)
	_near("fly-in speed is 200 m/s (kMoveDistance 100 / 0.5 s)", NoteMotion.fly_in_speed(), 200.0)
	_near("jump starts 10 m out (NJS 10 x 1 s)", NoteMotion.spawn_distance(), 10.0)
	NoteMotion.fly_in_enabled = false
	_near("switched off: no fly-in", NoteMotion.fly_in_seconds(), 0.0)
	NoteMotion.fly_in_enabled = true


func _cuttable(z: float, speed: float) -> Cuttable:
	var c := Cuttable.new()
	add_child(c)
	c.set_physics_process(false)
	c._is_released = false
	c.speed = speed
	c.transform = Transform3D(Basis.IDENTITY, Vector3(0.3, 1.1, z))
	return c


# A note on beat 4 (2.0 s): jump from 1.0 s at 10 m, created at 0.5 s at 15 m of travel.
func _plain_note() -> void:
	_configure()
	var flying := _cuttable(-15.0, 10.0)
	flying.fly_in(0.5)
	_near("note: created 100 m beyond its jump start (drawn z)", flying.transform.origin.z, -110.0)
	_check("note: flying in after spawn", flying.is_flying())
	_near("note: an arc reads its travel through fly_offset", flying.transform.origin.z - flying.fly_offset(), -15.0)
	var today: Cuttable = null
	var t := 0.5
	var max_diff := 0.0
	var speed_ok := true
	var hit_while_flying := false
	var land_t := -1.0
	var last_drawn := flying.transform.origin.z
	var jump_z := 0.0
	while t < 2.2:
		t += DT
		flying._physics_process(DT)
		if flying.is_flying():
			hit_while_flying = hit_while_flying or flying._collision_enabled
			var step := flying.transform.origin.z - last_drawn
			speed_ok = speed_ok and absf(step - 200.0 * DT) < 0.001
		elif land_t < 0.0:
			land_t = t
			jump_z = flying.transform.origin.z
		last_drawn = flying.transform.origin.z
		# The note as spawned before 0.7.37: on the first tick at or after its jump start, at the
		# map's distance for that time, then ticked like any note.
		if today == null and t >= 1.0 - 0.000001:
			today = _cuttable(-(2.0 - t) * 10.0, 10.0)
		elif today != null:
			today._physics_process(DT)
			max_diff = maxf(max_diff, absf(today.transform.origin.z - flying.transform.origin.z))
	_check("note: comes in at 200 m/s while flying", speed_ok)
	_check("note: the jump starts on the first tick at or after 1.0 s", land_t >= 1.0 - 0.000001 and land_t < 1.0 + DT, "landed at %.4f s" % land_t)
	_near("note: drawn at its travel when the jump starts (continuous)", jump_z, -(2.0 - land_t) * 10.0, 0.001)
	_check("note: never hittable while flying", not hit_while_flying)
	_check("note: drawn where it was drawn before 0.7.37 from the jump start on", max_diff < 0.0005, "max %.6f m" % max_diff)
	flying.queue_free()
	if today != null:
		today.queue_free()


# A quarter-beat jump that starts inside the hit window (2 m out): the travel crosses ENABLE_Z while
# the note still flies in, and it must not be hittable until the jump starts.
func _close_jump_not_hittable() -> void:
	_configure()
	var c := _cuttable(-7.0, 10.0)
	c.fly_in(0.5)
	var enabled_flying := false
	var enabled_after := false
	for i in 120:
		var was_flying := c.is_flying()
		c._physics_process(DT)
		if was_flying and c.is_flying():
			enabled_flying = enabled_flying or c._collision_enabled
		elif not c.is_flying():
			enabled_after = enabled_after or c._collision_enabled
			break
	_check("close jump: travel inside the hit window while flying does not enable the hit", not enabled_flying)
	_check("close jump: hittable on the tick its jump starts", enabled_after)
	c.queue_free()


# Noodle notes: an offset path (rides on the travel) and a definite position (does not).
func _noodle_note(definite: bool) -> void:
	_configure()
	NoodleTracks.reset()
	NoodleTracks.active = true
	NoodleFrame.reset()
	var kind := "definite position" if definite else "offset path"
	var anim := {"animation": {"dissolve": [[0.4, 0], [1, 0.5]]}}
	if definite:
		anim["animation"]["definitePosition"] = [[0, 2, 20, 0], [0, 2, 0, 1]]
	else:
		anim["animation"]["offsetPosition"] = [[0, 0, 0, 0], [1, 3, 0, 0.6], [0, 1, 0, 1]]
	var flying := _cuttable(-15.0, 10.0)
	flying.noodle_spawn(_obj(anim), 1.0)
	flying.fly_in(0.5)
	flying._noodle_pose()
	# Life 0 of the path: offset (0,0,0) on the 10 m jump start, or definite (0, 2, 20) lanes =
	# 12 m forward (Heck +z is away from the player, -z in Godot), pushed by the whole 100 m.
	var want_z := (-12.0 if definite else -10.0) - 100.0
	_near("noodle %s: posed at life 0, 100 m beyond the jump start" % kind, flying.transform.origin.z, want_z, 0.001)
	_check("noodle %s: not hittable while flying" % kind, not flying._n_can_hit)
	_near("noodle %s: dissolve is the path's first point while flying" % kind, flying._n_dissolve, 0.4)
	var today: Cuttable = null
	var t := 0.5
	var max_diff := 0.0
	var life_at_jump := -1.0
	while t < 2.2:
		t += DT
		var was_flying := flying.is_flying()
		flying._noodle_tick(DT)
		if was_flying and not flying.is_flying():
			life_at_jump = 0.5 + (flying._n_base.z / 10.0) / 2.0
		if today == null and t >= 1.0 - 0.000001:
			today = _cuttable(-(2.0 - t) * 10.0, 10.0)
			today.noodle_spawn(_obj(anim), 1.0)
		elif today != null:
			today._noodle_tick(DT)
			max_diff = maxf(max_diff, today.transform.origin.distance_to(flying.transform.origin))
	_check("noodle %s: path life is 0 at the jump start (within a tick)" % kind, life_at_jump >= 0.0 and life_at_jump < DT / 2.0 + 0.000001, "life %.5f" % life_at_jump)
	_check("noodle %s: drawn as before 0.7.37 from the jump start on" % kind, max_diff < 0.0005, "max %.6f m" % max_diff)
	_check("noodle %s: hittable after the jump start" % kind, flying._n_can_hit)
	flying.queue_free()
	if today != null:
		today.queue_free()
	NoodleTracks.reset()
	NoodleFrame.reset()


# Noodle noteJumpMovementSpeed 20: own half jump 1 beat (40 m and 20 m are over 18 m) = 0.5 s =
# 10 m; NoodleTracks gives it spawn_lead -1, so Playing starts its fly-in at beat 4 - 1 - 2 - 1
# (0.5 s at 120 BPM) = beat 0 for a note on beat 4, i.e. 0.5 s before its 1.5 s jump start.
func _own_jump() -> void:
	_configure()
	_near("own NJS 20: half jump 1 beat", NoteMotion.object_half_jump_beats(20.0, false, 0.0), 1.0)
	var playing := GameStatePlaying.new()
	playing._fly_sec = 0.5
	playing._song_sec = 1.0
	# Jump beat = 4 - (-1) lead... = beat - lead - map beats = 4 + 1 - 2 = 3 (1.5 s).
	_near("own jump: fly-in time left from the spawner", playing._fly_rem(4.0 - (-1.0) - 2.0), 0.5)
	var c := _cuttable(-(2.0 - 1.0) * 20.0, 20.0)
	c.fly_in(0.5)
	_near("own jump: created 100 m beyond its own jump start (10 m)", c.transform.origin.z, -110.0)
	var t := 1.0
	while c.is_flying() and t < 3.0:
		t += DT
		c._physics_process(DT)
	_check("own jump: jump starts at its own 1.5 s", t >= 1.5 - 0.000001 and t < 1.5 + DT, "%.4f s" % t)
	_near("own jump: at its own jump distance then", c.transform.origin.z, -(2.0 - t) * 20.0, 0.001)
	c.queue_free()


func _wall(info: ObstacleInfo, song_sec: float) -> Wall:
	var w := (load("res://game/Wall/Wall.tscn") as PackedScene).instantiate() as Wall
	add_child(w)
	w.set_physics_process(false)
	w._is_released = false
	w.spawn(info, Map.seconds_to_beat(song_sec))
	return w


# A 1-beat wall on beat 4 (front reaches the player at 2.0 s), 0.5 m deep at NJS 10... 1 beat =
# 0.5 s = 5 m deep. Jump starts at 1.0 s with the front 10 m out.
func _plain_wall() -> void:
	_configure()
	var info := ObstacleInfo.new_v3({"b": 4.0, "d": 1.0, "x": 1, "y": 0, "w": 1, "h": 5})
	var flying := _wall(info, 0.5)
	flying.fly_in(0.5)
	var front := flying.transform.origin.z + flying._half_depth
	_near("wall: front created 100 m beyond its jump start", front, -110.0, 0.001)
	_check("wall: collision shape off while flying", flying._shape_off)
	var today: Wall = null
	var t := 0.5
	var max_diff := 0.0
	var front_ok := true
	while t < 2.6:
		t += DT
		flying._physics_process(DT)
		if flying.is_flying():
			front_ok = front_ok and flying.transform.origin.z + flying._half_depth <= -10.0 + 0.000001
		if today == null and t >= 1.0 - 0.000001:
			today = _wall(info, t)
		elif today != null:
			today._physics_process(DT)
			max_diff = maxf(max_diff, today.transform.origin.distance_to(flying.transform.origin))
			var a := today._wall_mesh()
			var b := flying._wall_mesh()
			max_diff = maxf(max_diff, a.scale.distance_to(b.scale))
	_check("wall: front never closer than its jump start while flying", front_ok)
	_check("wall: collision shape back on after the jump start", not flying._shape_off)
	_check("wall: drawn and grown as before 0.7.37 from the jump start on", max_diff < 0.0005, "max %.6f" % max_diff)
	flying.queue_free()
	if today != null:
		today.queue_free()


func _noodle_wall() -> void:
	_configure()
	NoodleTracks.reset()
	NoodleTracks.active = true
	NoodleFrame.reset()
	var cd := {"animation": {"offsetPosition": [[0, 0, 0, 0], [2, 1, 0, 1]], "dissolve": [[0.5, 0], [1, 0.3]]}}
	var info := ObstacleInfo.new_v3({"b": 4.0, "d": 1.0, "x": 1, "y": 0, "w": 1, "h": 5, "customData": cd})
	NoodleTracks._resolve(info.noodle)
	var flying := _wall(info, 0.5)
	flying.fly_in(0.5)
	flying._noodle_pose()
	var front := flying.transform.origin.z + flying._half_depth
	_near("noodle wall: front posed 100 m beyond its jump start", front, -110.0, 0.001)
	_check("noodle wall: not posed every tick while flying", not flying._needs_tick_pose())
	var today: Wall = null
	var t := 0.5
	var max_diff := 0.0
	while t < 2.6:
		t += DT
		flying._noodle_tick(DT)
		if today == null and t >= 1.0 - 0.000001:
			today = _wall(info, t)
		elif today != null:
			today._noodle_tick(DT)
			max_diff = maxf(max_diff, today.transform.origin.distance_to(flying.transform.origin))
	_check("noodle wall: drawn as before 0.7.37 from the jump start on", max_diff < 0.0005, "max %.6f m" % max_diff)
	flying.queue_free()
	if today != null:
		today.queue_free()
	NoodleTracks.reset()
	NoodleFrame.reset()


# Chain links fly in with their head: same speed, same time left, so the same push and the chain
# keeps its shape.
func _chain_rigid() -> void:
	_configure()
	var head := _cuttable(-15.0, 10.0)
	var link := _cuttable(-15.8, 10.0)
	head.fly_in(0.5)
	link.fly_in(0.5)
	var same := true
	for i in 70:
		head._physics_process(DT)
		link._physics_process(DT)
		same = same and absf((link.transform.origin.z - head.transform.origin.z) - (-0.8)) < 0.0005
	_check("chain: a link keeps its distance to the head through the fly-in", same)
	head.queue_free()
	link.queue_free()


# Notes on beats 0 and 3.5, half jump 2 beats, 1 beat of tail: live [-2, 1] and [1.5, 4.5], apart.
# With the 0.5 s (1 beat at 120 BPM) fly-in the second is live from 0.5 and they overlap.
func _pool_peak() -> void:
	var notes: Array = [ColorNoteInfo.new_v3({"b": 0.0, "x": 1, "y": 0, "c": 0, "d": 1}),
		ColorNoteInfo.new_v3({"b": 3.5, "x": 1, "y": 0, "c": 0, "d": 1})]
	_check("pool: apart without the fly-in", MapData.peak_live(notes, 2.0, 1.0) == 1)
	_check("pool: overlapping with it", MapData.peak_live(notes, 2.0, 1.0, 0.5) == 2)


# The spawn pop (grow from 10 %, roll, hop) is over by the jump start when the object flies in, and
# by 1/8 of the jump without a fly-in, whatever the NJS (it used to run at NJS / 9 speed and end
# about 0.2 s before the hit). ODDS&ENDS Hard's tempo and offset, NJS 10 to 23, and Note Speed 50 %.
func _spawn_pop() -> void:
	var cases: Array = [[10.0, 1.0], [14.0, 1.0], [17.0, 1.0], [23.0, 1.0], [14.0, 0.5]]
	for c: Array in cases:
		for fly: bool in [true, false]:
			NoteMotion.fly_in_enabled = fly
			NoteMotion.configure(c[0], -1.714, 192.0, 5, c[1])
			for scene_path: String in ["res://game/BeepCube/BeepCube.tscn", "res://game/Bomb/Bomb.tscn"]:
				var obj := (load(scene_path) as PackedScene).instantiate() as Cuttable
				add_child(obj)
				obj.set_physics_process(false)
				var anim := obj.get_node("AnimationPlayer") as AnimationPlayer
				anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
				var mesh := obj.get_node("BeepCubeMesh" if obj is BeepCube else "BombAnimation") as Node3D
				var half := NoteMotion.half_jump_seconds()
				var rest := mesh.transform
				if obj is BeepCube:
					(obj as BeepCube).spawn(ColorNoteInfo.new_v3({"b": 40.0, "x": 1, "y": 1, "c": 0, "d": 0}), 30.0)
				else:
					(obj as Bomb).spawn(BombInfo.new_v3({"b": 40.0, "x": 1, "y": 1}), 30.0)
				# Settle point, from the object's creation.
				var settle := half * 2.0 * Cuttable.SPAWN_SETTLE_JUMP_FRACTION
				if fly:
					obj.fly_in(0.5)
					settle = 0.5
				var t := 0.0
				while t < settle - 0.000001:
					anim.advance(DT)
					t += DT
				anim.advance(0.000001)
				var done := mesh.scale.is_equal_approx(Vector3.ONE) and absf(mesh.rotation.z) < 0.001 and absf(mesh.rotation.y) < 0.001 and mesh.position.length() < 0.001
				_check("spawn pop: %s NJS %d speed %d %% %s settled at %s (%.3f s)" % [
					"note" if obj is BeepCube else "bomb", int(c[0]), roundi(c[1] * 100.0),
					"fly-in" if fly else "no fly-in", "the jump start" if fly else "1/8 of the jump", settle],
					done, "scale %s rot %s pos %s" % [str(mesh.scale), str(mesh.rotation), str(mesh.position)])
				obj.queue_free()
	NoteMotion.fly_in_enabled = true


# Unconfigured motion (harness scenes, tools) keeps the legacy numbers and has no fly-in.
func _legacy() -> void:
	NoteMotion.reset()
	_near("unconfigured: no fly-in", NoteMotion.fly_in_seconds(), 0.0)
	_near("unconfigured: legacy spawn distance", NoteMotion.spawn_distance(), 16.0)
	var playing := GameStatePlaying.new()
	_near("unconfigured: spawner computes no fly-in", playing._fly_rem(10.0), 0.0)


func _obj(cd: Dictionary) -> NoodleObject:
	var o := NoodleObject.from_custom_data(cd)
	NoodleTracks._resolve(o)
	return o
