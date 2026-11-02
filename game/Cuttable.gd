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

# used to release the cube once both of it's cut pieces have died off
# Note: serves no purpose for bombs
var _piece_death_count := 0

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
	if Scoreboard.paused or not is_visible_in_tree() or not Map.current_info: return
	var probe := Cost.enabled
	var t0 := Time.get_ticks_usec() if probe else 0
	transform.origin.z += speed * delta
	
	# enable collisions when cuttable gets close enough to player
	# (this is also the hit window: see _register_hit)
	if global_transform.origin.z > ENABLE_Z:
		set_collision_enabled(true)
	
	# remove children that go to far
	if global_transform.origin.z > Constants.MISS_Z:
		on_miss()
	
	if probe:
		Cost.cuttable_usec += Time.get_ticks_usec() - t0
