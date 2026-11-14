extends Cuttable
class_name Bomb

# Spike attribution (FR-033): deferred free on the main thread, see Wall.gd.
# (CostProbe/Cost is inherited from Cuttable.)

@export var min_speed := 0.5
@onready var collision_shape := $Area3D/CollisionShape3D as CollisionShape3D

# Noodle dissolve. The scene's two StandardMaterial3Ds cannot take a per-instance value, so a bomb
# whose dissolve is below 1 swaps in shader copies of them (shared by every bomb, the value is an
# instance uniform) and swaps the scene's own back at 1 and on every spawn. An ordinary bomb never
# touches any of this.
const DISSOLVE_BODY_SHADER := preload("res://game/Bomb/bomb_dissolve.gdshader")
const DISSOLVE_RIM_SHADER := preload("res://game/Bomb/bomb_rim_dissolve.gdshader")
static var _dissolve_body_mat: ShaderMaterial
static var _dissolve_rim_mat: ShaderMaterial
var _body_mesh: MeshInstance3D
var _rim_mesh: MeshInstance3D
var _body_mat: Material
var _rim_mat: Material
var _dissolve_swapped := false

func set_collision_disabled(value: bool) -> void:
	collision_shape.disabled = value

@warning_ignore("unused_parameter")
func cut(saber_type: int, cut_speed: Vector3, cut_plane: Plane, controller: BeepSaberController) -> HitInfo:
	_unregister_hit()
	# A bomb was never worth points, so it does not raise the best possible score.
	Scoreboard.bad_cut(transform.origin, 0, Scoreboard.ENERGY_MISS)
	var info := HitInfo.new()
	info.kind = HitInfo.Kind.BAD
	info.speed_len = cut_speed.length()
	info.is_correct_saber = false
	info.note_pos = global_position
	if Cost.enabled: Cost.objs_freed += 1
	_despawn()
	return info

func on_miss() -> void:
	_unregister_hit()
	if Cost.enabled: Cost.objs_freed += 1
	_despawn()

func spawn(info: BombInfo, current_beat: float) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	var own_njs := info.noodle.njs if info.noodle != null else 0.0
	speed = NoteMotion.speed_at(info.beat, own_njs)
	beat = info.beat
	
	
	# A pooled bomb may carry the last Noodle pose; a plain bomb's basis is always identity.
	transform.basis = Basis.IDENTITY
	$BombAnimation.visible = true
	transform.origin.x = Constants.LANE_DISTANCE * float(info.line_index) + Constants.LANE_ZERO_X
	transform.origin.y = Constants.LANE_DISTANCE * float(info.line_layer) + Constants.LAYER_ZERO_Y
	transform.origin.z = -NoteMotion.distance_between(current_beat, info.beat, own_njs)

	var anim := $AnimationPlayer as AnimationPlayer
	var anim_speed := Map.current_difficulty.note_jump_movement_speed / 9.0
	anim.speed_scale = maxf(min_speed, anim_speed)
	anim.play(&"Spawn")
	fake = info.fake
	noodle_spawn(info.noodle, _noodle_half_sec(info.noodle))

func _noodle_set_shown(shown: bool) -> void:
	$BombAnimation.visible = shown

func _noodle_set_dissolve(dissolve: float, _dissolve_arrow: float) -> void:
	if _body_mesh == null:
		_body_mesh = get_node_or_null(^"BombAnimation/Mesh/Icosphere") as MeshInstance3D
		_rim_mesh = get_node_or_null(^"BombAnimation/Mesh/Icosphere2") as MeshInstance3D
		if _body_mesh == null or _rim_mesh == null:
			return
		_body_mat = _body_mesh.material_override
		_rim_mat = _rim_mesh.material_override
	var swap := dissolve < 1.0
	if swap and _dissolve_body_mat == null:
		_dissolve_body_mat = _dissolve_material(DISSOLVE_BODY_SHADER, _body_mat)
		_dissolve_rim_mat = _dissolve_material(DISSOLVE_RIM_SHADER, _rim_mat)
	_body_mesh.set_instance_shader_parameter(&"bomb_dissolve", dissolve)
	_rim_mesh.set_instance_shader_parameter(&"bomb_dissolve", dissolve)
	if swap != _dissolve_swapped:
		_dissolve_swapped = swap
		_body_mesh.material_override = _dissolve_body_mat if swap else _body_mat
		_rim_mesh.material_override = _dissolve_rim_mat if swap else _rim_mat

## Startup warm-up (BeepSaber_Game): builds the shared dissolve materials and shows this bomb
## dissolved, so their shaders are compiled before any song needs them.
func prewarm_dissolve() -> void:
	_noodle_set_dissolve(0.5, 1.0)

# Built once, the first time any bomb dissolves (normally at the startup warm-up); the colour comes from the scene's material so
# the two cannot drift apart.
static func _dissolve_material(shader: Shader, original: Material) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var std := original as BaseMaterial3D
	if std != null:
		mat.set_shader_parameter(&"albedo", std.albedo_color)
		if std.grow:
			mat.set_shader_parameter(&"grow", std.grow_amount)
	return mat

func _noodle_vanish() -> void:
	_unregister_hit()
	_despawn()

func hide_bomb() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED

func _despawn() -> void:
	hide_bomb()
	if not is_released():
		release()

func clear_from_track() -> void:
	hide_bomb()
	if not is_released():
		release()
