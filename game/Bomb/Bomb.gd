extends Cuttable
class_name Bomb

# Spike attribution (FR-033): deferred free on the main thread, see Wall.gd.
# (CostProbe/Cost is inherited from Cuttable.)

@export var min_speed := 0.5
@onready var collision_shape := $Area3D/CollisionShape3D as CollisionShape3D

func set_collision_disabled(value: bool) -> void:
	collision_shape.disabled = value

@warning_ignore("unused_parameter")
func cut(saber_type: int, cut_speed: Vector3, cut_plane: Plane, controller: BeepSaberController) -> HitInfo:
	_unregister_hit()
	Scoreboard.bad_cut(transform.origin)
	var info := HitInfo.new()
	info.kind = HitInfo.Kind.BAD
	info.speed_len = cut_speed.length()
	info.is_correct_saber = false
	info.note_pos = global_position
	if Cost.enabled: Cost.objs_freed += 1
	queue_free()
	return info

func on_miss() -> void:
	_unregister_hit()
	if Cost.enabled: Cost.objs_freed += 1
	queue_free()

func spawn(info: BombInfo, current_beat: float) -> void:
	speed = NoteMotion.speed_at(info.beat)
	beat = info.beat
	
	var distance: float = info.beat - current_beat
	
	transform.origin.x = Constants.LANE_DISTANCE * float(info.line_index) + Constants.LANE_ZERO_X
	transform.origin.y = Constants.LANE_DISTANCE * float(info.line_layer) + Constants.LAYER_ZERO_Y
	transform.origin.z = -distance * Constants.BEAT_DISTANCE
	
	var anim := $AnimationPlayer as AnimationPlayer
	var anim_speed := Map.current_difficulty.note_jump_movement_speed / 9.0
	anim.speed_scale = maxf(min_speed, anim_speed)
	anim.play(&"Spawn")
