extends MultiMeshInstance3D
class_name DebrisField

# Cut debris (spec FR-013). One draw call, one shared BoxMesh, and no per-shard CPU work:
# a cut writes ten instance records (transform, colour, custom data) and the vertex shader in
# debris_shard.gdshader flies them. Nothing is instantiated, freed or collided with.
#
# The pool is a ring: a burst that arrives when the pool is full overwrites the oldest shards,
# which is the right failure mode on a dense map. `debris_cap` halves the burst instead of the
# old behaviour of skipping whole bursts.

const POOL := 128
const SHARDS_PER_CUT := 10
const SHARDS_PER_CUT_CAPPED := 6
const LIFE_S := 0.5
const SHARD_SIZE := 0.035

static var instance: DebrisField

var _next := 0
var _now := 0.0
# Total bursts emitted this run; the benchmark reads deltas from it (FR-001 probe).
var bursts_total := 0
var _active := true
var _mat: ShaderMaterial

func _ready() -> void:
	instance = self
	var mm := MultiMesh.new()
	# Order matters: format and the per-instance arrays are fixed when instance_count is set.
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE * SHARD_SIZE
	mm.mesh = box
	mm.instance_count = POOL
	multimesh = mm
	# The shader moves shards well outside the mesh's own bounds; without this the whole pool
	# is culled with the mesh AABB and the debris pops in and out.
	custom_aabb = AABB(Vector3(-12.0, -4.0, -44.0), Vector3(24.0, 20.0, 52.0))
	_mat = material_override as ShaderMaterial
	if _mat != null:
		_mat.set_shader_parameter(&"now", _now)
		_mat.set_shader_parameter(&"life", LIFE_S)
	set_enabled(Settings.debris_shards)

func set_enabled(value: bool) -> void:
	_active = value
	visible = value
	set_process(value)

func _process(delta: float) -> void:
	_now += delta
	_mat.set_shader_parameter(&"now", _now)

# `cut_normal` is the plane the blade swept; `blade_velocity` is the saber's own speed, used
# only as a small bias so a fast swing throws its debris further. Shards alternate sides of
# the plane, which is what makes a horizontal cut look different from a diagonal one.
func emit_burst(origin: Vector3, cut_normal: Vector3, blade_velocity: Vector3, color: Color) -> void:
	if not _active or _mat == null:
		return
	var n := cut_normal.normalized()
	if n.length_squared() < 0.5:
		n = Vector3.RIGHT
	# Along the cut line: the normal rotated 90 degrees in the plane the blade sweeps.
	var along := Vector3(-n.y, n.x, 0.0).normalized()
	bursts_total += 1
	var count := SHARDS_PER_CUT_CAPPED if Settings.debris_cap else SHARDS_PER_CUT
	for i in count:
		var side := 1.0 if (i & 1) == 0 else -1.0
		var spread := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 0.35
		var v := n * (side * randf_range(2.0, 2.5)) + blade_velocity * 0.2 + spread
		var p := origin + along * randf_range(-0.28, 0.28) + n * randf_range(-0.03, 0.03)
		var slot := _next
		_next = (_next + 1) % POOL
		multimesh.set_instance_transform(slot, Transform3D(Basis(), p))
		multimesh.set_instance_custom_data(slot, Color(_now, v.x, v.y, v.z))
		multimesh.set_instance_color(slot, color)
