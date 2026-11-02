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
	if Cost.enabled:
		Cost.shape_reenable += 1
	set_collision_disabled(not value)

func _enable_once_mode() -> bool:
	if _enable_once < 0:
		_enable_once = 1 if bool(ProjectSettings.get_setting(SETTING_ENABLE_ONCE, false)) else 0
	return _enable_once == 1

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
	if global_transform.origin.z > ENABLE_Z:
		set_collision_enabled(true)
	
	# remove children that go to far
	if global_transform.origin.z > Constants.MISS_Z:
		on_miss()
	
	if probe:
		Cost.cuttable_usec += Time.get_ticks_usec() - t0
