extends PooledNode3D
class_name Cuttable

const Cost := preload("res://game/scripts/CostProbe.gd")

# Notes are spawned several beats ahead with their collision shapes disabled and
# only become hittable when they get close (see _physics_process). Enabling a
# shape is a physics-server write, and the original code repeats that write on
# every tick for the whole approach. `SETTING_ENABLE_ONCE` writes it once per
# approach instead. It defaults to OFF so the baseline capture stays comparable;
# BenchmarkRunner can flip it per run, which is how the cost gets measured
# rather than assumed.
const SETTING_ENABLE_ONCE := &"gameplay/notes/enable_collision_once"
const ENABLE_Z := -3.0

const HitResolver := preload("res://game/scripts/HitResolver.gd")

# The BoxShape3D resources in BeepCube.tscn / ChainLink.tscn are shared by every
# instance of the scene, and spawn() mutates them per node (0.8 vs 0.5 tall for
# dots; an extended hitbox for distant chain links). So the last node spawned
# dictates the hitbox of every live node of that type. This flag gives each
# instance its own copy; default OFF so the baseline is unchanged.
const SETTING_ISOLATE_SHAPES := &"gameplay/notes/isolate_collision_shapes"

var speed: float
var beat: float

# specs/028 FR-011: closest blade-to-box distance seen while the miss probe is on. INF means no
# blade came near; BeepCube.on_miss logs it only when the debug setting enables the probe.
var blade_min_dist := INF

func track_blade_distance(d: float) -> void:
	if d < blade_min_dist:
		blade_min_dist = d

# used to release the cube once both of it's cut pieces have died off
# Note: serves no purpose for bombs
var _piece_death_count := 0

# Noodle Extensions animation (game/noodle/NoodleAnim.gd). `noodle` is null for an object
# without tracks or an animation block, and then nothing below is touched per tick.
var noodle: NoodleObject = null
var _n_half_sec := 1.0
var _n_base := Vector3.ZERO
var _n_rot := Quaternion.IDENTITY
var _n_scale := Vector3.ONE
# False while the animation makes the object non-interactable: not hittable, not missable.
var _n_can_hit := true
# A decorative (fake) object: drawn and animated, never hittable or missable (it uses the
# non-interactable path below), so it never reaches the scoreboard.
var fake := false
var _n_shown := true
# The last Noodle dissolve / dissolveArrow handed to the subclass (1 = fully drawn). Pooled
# objects reset both to 1 on every spawn so a value never carries into the next object.
var _n_dissolve := 1.0
var _n_dissolve_arrow := 1.0
# On NoodleFrame's list for this frame, and posed for the current travel (see _noodle_frame).
var _n_ticked := false
var _n_posed := false

# Beat Saber's move phase before the jump (NoteMotion.MOVE_*). The travel is integrated exactly as
# always, from an earlier spawn; only the drawn z is pushed out, by (200 / speed - 1) metres per
# metre of travel left before the jump start, so the object comes in at 200 m/s and is drawn at
# its travel position from the jump start on. While it flies in it cannot be hit or missed.
var _flying := false
var _fly_z := 0.0       # travel z at the jump start
var _fly_travel := 0.0  # travel z of an un-animated object while it flies in
var _fly_k := 0.0       # 200 / speed - 1
var _fly_drawn := 0.0   # drawn z minus travel z, last applied

func is_flying() -> bool:
	return _flying

# The spawn pop of notes and bombs (the scenes' "Spawn" animation: the mesh grows from 10 %, rolls in
# and hops). It used to play at NJS / 9 speed, written for the old 16 m approach; on a 0.7 s jump
# it was still growing and turning about 0.2 s before the hit. Beat Saber draws a note full size
# from its creation and has it at its "middle" rotation (cut direction plus a small random turn) by
# 1/8 of the jump (NoteJump: Lerp(start, middle, sin(t * 4 pi)) for t < 0.125), so the pop now ends
# by then: at the jump start when the object flies in, else SPAWN_SETTLE_JUMP_FRACTION into the jump.
const SPAWN_SETTLE_JUMP_FRACTION := 0.125
const SPAWN_MIN_FLY_S := 0.1
var _spawn_anim: AnimationPlayer = null
var _spawn_anim_len := 0.8

## Plays the spawn pop timed to settle SPAWN_SETTLE_JUMP_FRACTION into a jump of `half_sec` x 2
## that starts now; fly_in() retimes it to end at the jump start.
func play_spawn_anim(anim: AnimationPlayer, half_sec: float) -> void:
	_spawn_anim = anim
	var a := anim.get_animation(&"Spawn")
	_spawn_anim_len = a.length if a != null else 0.8
	anim.speed_scale = _spawn_anim_len / maxf(SPAWN_SETTLE_JUMP_FRACTION * 2.0 * half_sec, 0.01)
	anim.play(&"Spawn")

## Drawn z minus travel z while flying in (0 otherwise): an arc built on this note uses its travel.
func fly_offset() -> float:
	return _fly_drawn if _flying else 0.0

## Seconds until this object's jump starts while it flies in, else 0 (an arc flies in with its
## head note, Arc.fly_in).
func fly_seconds_left() -> float:
	if not _flying or speed <= 0.0:
		return 0.0
	var travel := _n_base.z if noodle != null else _fly_travel
	return maxf(_fly_z - travel, 0.0) / speed

## Called by the spawner right after spawn() for an object whose jump starts `rem_sec` from now:
## it flies in until then. A rem_sec of 0 or less leaves it as spawned.
func fly_in(rem_sec: float) -> void:
	if rem_sec <= 0.0 or speed <= 0.0:
		_flying = false
		return
	_flying = true
	if _spawn_anim != null and rem_sec >= SPAWN_MIN_FLY_S:
		_spawn_anim.speed_scale = _spawn_anim_len / rem_sec
	var left := speed * rem_sec
	_fly_k = NoteMotion.fly_in_speed() / speed - 1.0
	if noodle == null:
		_fly_travel = transform.origin.z
		_fly_z = _fly_travel + left
		_fly_drawn = -_fly_k * left
		transform.origin.z = _fly_travel + _fly_drawn
	else:
		_fly_z = _n_base.z + left
		# spawn() posed it without the fly-in; the frame pass poses it again with it.
		_n_posed = false

var _collision_enabled := false
var _enable_once := -1  # -1 = not read yet, 0 = legacy, 1 = enable once

# Hit-test registration (specs/006-swing-hit-sweep FR-001). -1 = detection mode
# not read yet, 0 = ray fan (nothing registers), 1 = analytic resolver.
var _hit_mode := -1
var _hit_registered := false

# overridden by bombs and cubes
@warning_ignore("unused_parameter")
func set_collision_disabled(value: bool) -> void:
	return

# Single funnel for the collision-shape enable flag, so the tracked state and
# the engine state cannot drift apart.
#  - legacy mode (default): always delegates. The engine sees exactly the same
#    writes as before this change, so a baseline capture is unaffected.
#  - enable-once mode: skips writes that would not change anything.
func set_collision_enabled(value: bool) -> void:
	if _enable_once_mode() and _collision_enabled == value:
		return
	_collision_enabled = value
	if value:
		_register_hit()
	else:
		_unregister_hit()
	if _analytic_hits():
		# FR-008: under the resolver, nothing in the physics reads a cuttable's
		# shapes any more (the saber's own Area3D only looks for walls), so they
		# stay disabled for their whole life: no per-approach physics-server
		# write and no broadphase entry to update every tick.
		return
	if Cost.enabled:
		Cost.shape_reenable += 1
	set_collision_disabled(not value)

func _enable_once_mode() -> bool:
	if _enable_once < 0:
		_enable_once = 1 if bool(ProjectSettings.get_setting(SETTING_ENABLE_ONCE, false)) else 0
	return _enable_once == 1

# --- analytic hit registration (specs/006-swing-hit-sweep FR-001, FR-006) -----
# Hooked onto the collision-enable transition rather than given its own window,
# so the set of notes the resolver knows about is exactly the set the ray fan
# could hit: a disabled CollisionShape3D is not in the physics space.
func is_hit_registered() -> bool:
	return _hit_registered

func _analytic_hits() -> bool:
	if _hit_mode < 0:
		_hit_mode = 1 if HitResolver.is_analytic() else 0
	return _hit_mode == 1

func _register_hit() -> void:
	if _hit_registered: return
	if not _analytic_hits(): return
	_hit_registered = true
	# One walk of our own children, once per approach. Every Area3D under a
	# cuttable is a hitbox and its collision_layer bits decide which saber may
	# hit it (a cube's big box is on its own note layer, its small box on the
	# opposite one), so the layer is captured with the shape.
	for area in get_children():
		if not area is Area3D: continue
		var bits := (area as Area3D).collision_layer
		for child in area.get_children():
			if not child is CollisionShape3D: continue
			var shape_node := child as CollisionShape3D
			if shape_node.shape == null: continue
			HitResolver.add(self, bits, shape_node)

func _unregister_hit() -> void:
	if not _hit_registered: return
	_hit_registered = false
	HitResolver.remove(self)

# A pooled note goes back to the pool while still alive, so a released instance
# must never keep its hit entry: the next spawn of this node would otherwise
# inherit a registration pointing at the old note's geometry.
func release() -> void:
	_unregister_hit()
	_flying = false
	super()

# overriden by bombs and cubes.
# Returns the hit data the sabre needs for its hit sound; null when the cuttable
# has none (chain links). See HitInfo.gd.
@warning_ignore("unused_parameter")
func cut(saber_type: int, cut_speed: Vector3, cut_plane: Plane, controller: BeepSaberController) -> HitInfo:
	return null

# this too
func on_miss() -> void:
	return

func _on_cut_piece_died():
	_piece_death_count += 1
	if _piece_death_count >= 2:
		release()

func _physics_process(delta: float) -> void:
	if Scoreboard.paused or not visible or not Map.current_info: return
	var probe := Cost.enabled
	var t0 := Time.get_ticks_usec() if probe else 0
	# Local z, not global: notes are children of the track, which sits at the origin with no
	# rotation or scale, so the two are the same number - but reading `global_transform`
	# walks up the tree and touches the transform cache once per access, and this runs twice
	# per live note per tick. With 8 notes live at 120 Hz that is ~2 000 extra transform
	# reads a second, on the exact path that gets slower as the map gets denser.
	var z: float
	if noodle == null:
		if _flying:
			_fly_travel += speed * delta
			var left := _fly_z - _fly_travel
			if left > 0.0:
				_fly_drawn = -_fly_k * left
				transform.origin.z = _fly_travel + _fly_drawn
				return
			# The jump starts this tick: from here on exactly the un-animated travel.
			_flying = false
			transform.origin.z = _fly_travel
		else:
			transform.origin.z += speed * delta
		z = transform.origin.z
	else:
		# The animated pose is only drawn once per frame (NoodleFrame), but from the hit window on
		# (and while collision is on) sabers and the miss check need it every tick.
		z = _noodle_travel(delta)
		if z > ENABLE_Z or _collision_enabled:
			_noodle_pose()
	
	# enable collisions when cuttable gets close enough to player
	# (this is also the hit window: see _register_hit)
	if z > ENABLE_Z:
		set_collision_enabled(_n_can_hit)
	
	# remove children that go to far
	if z > Constants.MISS_Z:
		if _n_can_hit:
			on_miss()
		else:
			_noodle_vanish()
	
	if probe:
		Cost.cuttable_usec += Time.get_ticks_usec() - t0

## The half jump (seconds) an object's lifetime runs over: its own when it has a Noodle jump.
static func _noodle_half_sec(obj: NoodleObject) -> float:
	if obj != null and obj.half_sec > 0.0:
		return obj.half_sec
	return NoteMotion.half_jump_seconds()

## Called at the end of a spawn. `info_noodle` is the object's Noodle data (or null); the
## transform the spawn wrote is the un-animated pose the animation starts from.
func noodle_spawn(info_noodle: NoodleObject, half_sec: float) -> void:
	_flying = false
	_n_can_hit = not fake
	_n_shown = true
	if _n_dissolve != 1.0 or _n_dissolve_arrow != 1.0:
		_n_dissolve = 1.0
		_n_dissolve_arrow = 1.0
		_noodle_set_dissolve(1.0, 1.0)
	if info_noodle == null or not info_noodle.animated or not NoodleTracks.active:
		noodle = null
		return
	noodle = info_noodle
	_n_half_sec = maxf(half_sec, 0.001)
	_n_base = transform.origin
	# From the node's properties, not the basis: a static Noodle scale of 0 leaves a basis with
	# no rotation to decompose.
	_n_rot = Quaternion.from_euler(rotation)
	_n_scale = scale
	_noodle_tick(0.0)

# One animated tick. The object's travel is integrated exactly as an un-animated one (so it is
# as smooth), and its lifetime follows from how far it has come: 0.5 at the hit plane, and the
# half jump either side. Returns the travel z, which decides the hit window and the miss.
func _noodle_tick(delta: float) -> float:
	var z := _noodle_travel(delta)
	_noodle_pose()
	return z

# The travel, integrated exactly as an un-animated object's. Returns the travel z.
func _noodle_travel(delta: float) -> float:
	_n_base.z += speed * delta
	_n_posed = false
	if not _n_ticked:
		_n_ticked = true
		NoodleFrame.cubes.append(self)
	return _n_base.z

# Once per drawn frame for a Noodle object that ticked (NoodleFrame.flush): its pose, unless the
# tick already worked it out.
func _noodle_frame() -> void:
	if not _n_ticked:
		return
	_n_ticked = false
	if noodle == null or is_released() or _n_posed:
		return
	_noodle_pose()

# The animated pose for the current travel and song time: transform, hittable, dissolve, shown.
func _noodle_pose() -> void:
	_n_posed = true
	var life := 0.5 + (_n_base.z / speed) / (2.0 * _n_half_sec)
	var left := 0.0
	if _flying:
		left = _fly_z - _n_base.z
		if left > 0.0:
			# Heck evaluates a note in its move phase at a negative lifetime, which point
			# definitions read as their first point: the pose of the jump start.
			life = maxf(life, 0.0)
		else:
			_flying = false
	NoodleAnim.evaluate(noodle, life)
	if _flying:
		# A definite position does not follow the travel, so it is pushed by the whole 200 m/s
		# lead; an offset rides on the travel, which already covers speed x the time left.
		_fly_drawn = -left * (_fly_k + (1.0 if NoodleAnim.out_has_definite else 0.0))
		transform = NoodleAnim.compose(_n_base, _n_rot, _n_scale, _fly_drawn)
	else:
		transform = NoodleAnim.compose(_n_base, _n_rot, _n_scale)
	_n_can_hit = not fake and not _flying and NoodleAnim.out_interactable >= 1.0
	if not _n_can_hit and _collision_enabled:
		set_collision_enabled(false)
	# Dissolve is a fade in the object's shader; at 0 the object is not drawn at all.
	var d := clampf(NoodleAnim.out_dissolve, 0.0, 1.0)
	var da := clampf(NoodleAnim.out_dissolve_arrow, 0.0, 1.0)
	if d != _n_dissolve or da != _n_dissolve_arrow:
		_n_dissolve = d
		_n_dissolve_arrow = da
		_noodle_set_dissolve(d, da)
	var shown := d > 0.0
	if shown != _n_shown:
		_n_shown = shown
		_noodle_set_shown(shown)

# Hides or shows the object's meshes (dissolve 0). Overridden by notes and bombs.
@warning_ignore("unused_parameter")
func _noodle_set_shown(shown: bool) -> void:
	return

# Hands the object's dissolve (0..1) and arrow dissolve to its shader. Called only when a value
# changes, and with (1, 1) on a spawn that follows a dissolved life. Overridden by notes and bombs.
@warning_ignore("unused_parameter")
func _noodle_set_dissolve(dissolve: float, dissolve_arrow: float) -> void:
	return

# Leaves without a miss: a non-interactable object that reached the end of its travel.
func _noodle_vanish() -> void:
	release()

## specs/027 FR-019: the visual cut angle in the object's own frame. Noodle x/y rotation and 360
## lane yaw change the Euler decomposition of z, so subtracting `global_rotation.z` splits the
## pieces along the wrong plane. Project the world plane normal through the inverse rotation
## instead. Scale is stripped (orthonormalized); `fallback` is the old Euler-z result and is used
## when the basis is degenerate (a zero Noodle scale) or the cut normal lies along the object's z.
static func local_cut_angle(xform: Basis, plane_normal: Vector3, fallback: float) -> float:
	var rotation := xform.orthonormalized()
	for axis: Vector3 in [rotation.x, rotation.y, rotation.z]:
		if not axis.is_finite() or axis.length() < 0.0001:
			return fallback
	var local := rotation.transposed() * plane_normal
	var planar := Vector2(local.x, local.y)
	if planar.length() < 0.0001:
		return fallback
	return planar.angle()
