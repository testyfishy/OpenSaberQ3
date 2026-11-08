extends Node3D
class_name WallBatch

# specs/027 0.7.6 wall-overdraw follow-up: draw every live wall through one MultiMeshInstance3D.
# The Wall nodes keep collision, motion, grow and fade; this node only carries the visuals, so the
# wall-dense sections stop paying one draw call per panel. A/B behind `Wall.batch_visual`.

const MATERIAL := preload("res://game/Wall/wall_batch.tres")
const MIN_INSTANCES := 256

static var instance: WallBatch = null

var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _walls: Array[Node3D] = []

static func setup(track: Node3D) -> void:
	if instance != null or track == null:
		return
	instance = (load("res://game/scripts/WallBatch.gd") as Script).new()
	track.add_child(instance)
	instance._build()

func _build() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_mm.mesh = box
	_mm.instance_count = MIN_INSTANCES
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.material_override = MATERIAL
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.custom_aabb = AABB(Vector3(-60.0, -20.0, -140.0), Vector3(120.0, 40.0, 260.0))
	add_child(_mmi)

func register(wall: Node3D) -> void:
	if wall == null or _walls.has(wall):
		return
	_walls.append(wall)

func unregister(wall: Node3D) -> void:
	_walls.erase(wall)

func _process(_delta: float) -> void:
	if _mm == null:
		return
	var count := 0
	var local := global_transform.affine_inverse()
	for wall: Node3D in _walls:
		if wall == null or not is_instance_valid(wall) or not wall.visible:
			continue
		var xf: Transform3D = local * wall.global_transform
		# The wall mesh is shrunk about its centre while it grows; the batch has to apply the
		# same downward offset so the bottom stays on the floor.
		xf.origin += xf.basis * Vector3(0.0, float(wall.call("batch_offset_y")), 0.0)
		var size: Vector3 = wall.call("batch_size")
		_mm.set_instance_transform(count, xf)
		_mm.set_instance_custom_data(count, Color(size.x, size.y, size.z,
			float(wall.call("batch_rim"))))
		var tint: Color = wall.call("batch_color")
		_mm.set_instance_color(count, Color(tint.r, tint.g, tint.b,
			float(wall.call("batch_fade"))))
		count += 1
	if count > _mm.instance_count:
		_mm.instance_count = maxi(count, MIN_INSTANCES)
	_mm.visible_instance_count = count
