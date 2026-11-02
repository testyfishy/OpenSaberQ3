# extend the RayCast node and add additional RayCasts that help detect
# collisions with objects while swinging at high velocities.
extends RayCast3D
class_name SwingableRayCast

signal area_collided(area: Area3D)

const Cost := preload("res://game/scripts/CostProbe.gd")

# Project-setting override, default 0 = "keep the exported value". Benchmark
# runs set it (see BenchmarkRunner) so the ray fan can be widened or narrowed
# for an A/B without editing a scene, i.e. without rebuilding the scene cache.
const SETTING_RAYS := &"gameplay/swing_hit/num_collision_raycasts"

@export var num_collision_raycasts: int = 8

const DEBUG := false
const DEBUG_TRAIL_SEGMENTS := 5

# this constant is used to prevent unnecessary raycast collision computations
# when the ray's 'cast_to' vector length is below this threshold. it seems like
# Godot's physics engine never picks up on collisions when the vector's length
# is below this threshold. this vlaue was imperically found by logging the
# minimum length when using the node in-game.
const MIN_SWEPT_LENGTH_THRESHOLD := 0.035

var core_ray_collision_count := 0
var aux_ray_collision_count := 0
var adjust_segments := true

var _prev_ray_positions: Array[Vector3] = []
var _rays: Array[RayCast3D]
var _debug_curr_balls: Array[MeshInstance3D] = []
var _debug_raycast_trail := LinkedList.new()
@onready var _sw := StopwatchFactory.create(name, 10, true)

func _ready() -> void:
	await get_tree().physics_frame
	
	# Benchmark override (0 = unset, keep the exported value). Clamped to 1..32:
	# the fan divides by (count - 1), so 0 would be a division by zero.
	var configured := int(ProjectSettings.get_setting(SETTING_RAYS, 0))
	if configured > 0:
		num_collision_raycasts = clampi(configured, 1, 32)
	
	# use discrete RayCasts for continuous collision detection between _physics_process()
	for _i in range(num_collision_raycasts):
		var new_ray := RayCast3D.new()
		# inherit properties of parent
		new_ray.collision_mask = collision_mask
		new_ray.collide_with_areas = collide_with_areas
		new_ray.collide_with_bodies = collide_with_bodies
		new_ray.enabled = enabled
		add_child(new_ray)
		_prev_ray_positions.append(Vector3())
		_rays.append(new_ray)
		
		if DEBUG:
			var new_ball := $debug_ball.duplicate() as MeshInstance3D
			new_ball.visible = true
			add_child(new_ball)
			_debug_curr_balls.append(new_ball)
	
	# no longer need original instance
	remove_child($debug_ball)

# override so that we can update child segments too
func _set_collision_mask_value(bit: int, value: bool) -> void:
	#collision_mask = 0x0
	#collision_mask = collision_mask | (int(value) << bit)
	set_collision_mask_value(bit, value)
	for ray in _rays:
		#ray.collision_mask = 0x0
		ray.set_collision_mask_value(bit,value)

func reset_counters() -> void:
	core_ray_collision_count = 0
	aux_ray_collision_count = 0

func set_raycasts_enabled(value: bool) -> void:
	enabled = value

func _update_element_positions() -> void:
	# generate new locations for ray casters
	var saber_base := transform.origin
	var saber_tip := saber_base + target_position
	# A single cast has no "step": put it on the tip, which is where the blade
	# does most of its cutting. Dividing by (count - 1) used to yield `inf`.
	var count := maxi(num_collision_raycasts, 1)
	var step_dist := (saber_tip - saber_base) / float(maxi(count - 1, 1))
	
	var next_local_pos := transform.origin
	if count == 1:
		next_local_pos += step_dist
	for i in range(count):
		var next_global_pos := global_transform * (next_local_pos)
			
		# update ray's newest location for next physics frame processing
		var ray : RayCast3D = _rays[i]
		ray.global_transform.origin = next_global_pos
		if DEBUG:
			_debug_curr_balls[i].global_transform.origin = next_global_pos
			
		next_local_pos += step_dist

func _physics_process(_delta: float) -> void:
	if not enabled: return
	_sw.start()
	var probe := Cost.enabled
	var t0 := Time.get_ticks_usec() if probe else 0
	# see if 'core' ray is colliding with anything
	var coll := get_collider()
	if coll is Area3D:
		core_ray_collision_count += 1
		area_collided.emit(coll)
	
	# ---------------------
	
	# update positions of segmented ray casts and check for collisions on them
	if adjust_segments:
		_update_element_positions()
	
	for i in range(_rays.size()):
		var ray: RayCast3D = _rays[i]
			
		# cast a ray to the newest location and check for collisions
		ray.target_position = ray.to_local(_prev_ray_positions[i])
		if ray.target_position.length() > MIN_SWEPT_LENGTH_THRESHOLD:
			ray.force_raycast_update()
			coll = ray.get_collider()
			if coll is Area3D:
				aux_ray_collision_count += 1
				area_collided.emit(coll)
		
		_prev_ray_positions[i] = ray.global_transform.origin
		
	if DEBUG:
		var old_slice := _debug_raycast_trail.pop_back() as Array[RayCast3D]

		# update oldest slide with newest ray casts
		for i in range(_rays.size()):
			old_slice[i].global_transform = _rays[i].global_transform
			old_slice[i].target_position = _rays[i].target_position

		_debug_raycast_trail.push_front(old_slice)
	if probe:
		Cost.swing_usec += Time.get_ticks_usec() - t0
	_sw.stop()

func _on_SwingableRayCast_tree_entered() -> void:
	if DEBUG:
		var root := get_tree().get_root()
		var scene_root := root.get_child(root.get_child_count() - 1)
		for _t in range(DEBUG_TRAIL_SEGMENTS):
			var trail_slice: Array[RayCast3D] = []
			for _i in range(num_collision_raycasts):
				var new_ray := RayCast3D.new()
				new_ray.enabled = true
				new_ray.collision_mask = collision_mask
				scene_root.add_child(new_ray)
				trail_slice.append(new_ray)
			_debug_raycast_trail.push_front(trail_slice)
