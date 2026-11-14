extends Node3D
class_name ClashSparks

# Saber clash sparks, pooled. Each clash used to build a new CPUParticles3D with its own sphere mesh
# and material under the track: on the headset one physics tick of about 27 ms per clash (ODDS
# with the bot, 23 hitches in 60 s; none with the bot off), and the first clash of a launch also
# compiled the spark shader (6-39 ms, plus up to 405 ms the next frame, on a PC). The pool is built
# once at startup (BeepSaber_Game draws one burst then) and reused round-robin. The game's 90 ms
# clash cooldown and a burst's 0.34 s life keep at most POOL_SIZE bursts alive at once.

const POOL_SIZE := 6

var _next := 0


## Builds the emitters once: the same settings as the old per-clash ones, one shared mesh and
## material.
func build() -> void:
	if get_child_count() > 0:
		return
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.018
	spark_mesh.height = 0.036
	var spark_material := StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.albedo_color = Color(1.0, 0.92, 0.65)
	spark_material.emission_enabled = true
	spark_material.emission = Color(1.0, 0.8, 0.4)
	spark_material.emission_energy_multiplier = 4.0
	for i in POOL_SIZE:
		var sparks := CPUParticles3D.new()
		sparks.amount = 14
		sparks.lifetime = 0.34
		sparks.one_shot = true
		sparks.explosiveness = 1.0
		sparks.direction = Vector3.UP
		sparks.spread = 180.0
		sparks.gravity = Vector3.ZERO
		sparks.initial_velocity_min = 1.0
		sparks.initial_velocity_max = 2.6
		sparks.scale_amount_min = 0.015
		sparks.scale_amount_max = 0.035
		sparks.color = Color(1.0, 0.9, 0.6)
		sparks.mesh = spark_mesh
		sparks.material_override = spark_material
		sparks.emitting = false
		add_child(sparks)


## One burst at `at` (global position), on the next emitter of the pool.
func burst(at: Vector3) -> void:
	if get_child_count() == 0:
		build()
	var sparks := get_child(_next) as CPUParticles3D
	_next = (_next + 1) % POOL_SIZE
	sparks.global_position = at
	sparks.restart()


# Kept across maps: BeepSaber_Game._clear_track() calls this instead of freeing the pool.
func clear_from_track() -> void:
	for c in get_children():
		(c as CPUParticles3D).emitting = false
