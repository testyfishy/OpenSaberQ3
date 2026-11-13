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
		transform.origin.z += speed * delta
		z = transform.origin.z
	else:
		z = _noodle_tick(delta)
	
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
	_n_base.z += speed * delta
	var life := 0.5 + (_n_base.z / speed) / (2.0 * _n_half_sec)
	NoodleAnim.evaluate(noodle, life)
	transform = NoodleAnim.compose(_n_base, _n_rot, _n_scale)
	_n_can_hit = not fake and NoodleAnim.out_interactable >= 1.0
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
	return _n_base.z

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
