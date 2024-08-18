extends Node3D
class_name EventDriver

var ring_rot_speed := 0.0
var ring_rot_inv_dir := false
var rings_in := false

@export var disabled := false

func _ready() -> void:
	if not RenderingServer.get_rendering_device():
		$Level/Sphere.material_override.set_shader_parameter("contrast", 1)
		for im in range(5):
			$Level/Sphere.material_override.set_shader_parameter("bg_%s_intensity_mult"%[im], 
			$Level/Sphere.material_override.get_shader_parameter("bg_%s_intensity_mult"%[im]) * 2.2)
	#update_colors()

func _process(delta: float) -> void:
	# update the level animations
	#procces ring rotations
	if ring_rot_speed > 0:
		for ring in $Level/rings.get_children():
			if ring is Node3D:
				var rot = ring_rot_speed
				if ring_rot_inv_dir: rot *= -1
				(ring as Node3D).rotate_z((rot * delta) * (float(ring.get_index()+1)/5))

func update_colors(left: Color, right: Color) -> void:
	for i in [0,2,3]:
		change_light_color(i,left)
	for i in [1,4]:
		change_light_color(i,right)
		
func set_all_off() -> void:
	if not disabled:
		for i in range(5):
			change_light_color(i,-1)
	else:
		for i in range(1,4):
			change_light_color(i,-1)
		$Level/rings.visible = false

func set_all_on(left: Color, right: Color) -> void:
		update_colors(left, right)
		$Level/rings.visible = true

func process_event(data: EventInfo, left: Color, right: Color) -> void:
	if disabled: return
	if data.type in range(0,5):
		match data.value:
			0:
				change_light_color(data.type,-1)
			1:
				change_light_color(data.type,right)
			2:
				change_light_color(data.type,right,1)
			3:
				change_light_color(data.type,right,2)
			5:
				change_light_color(data.type,left)
			6:
				change_light_color(data.type,left,1)
			7:
				change_light_color(data.type,left,2)
	else:
		match data.type:
			8:
				var ringtween = $Level/rings.create_tween()
				if abs(ring_rot_speed) < 1:
					ring_rot_inv_dir = !ring_rot_inv_dir
				ringtween.set_trans(Tween.TRANS_QUAD)
				ringtween.set_ease(Tween.EASE_OUT)
				ringtween.tween_property(self,"ring_rot_speed",0.0, 2).from(3.0)
				ringtween.play()
			9:
				$Level/rings/AnimationPlayer.stop(false)
				if !rings_in:
					$Level/rings/AnimationPlayer.play("in")
					rings_in = true
				else:
					$Level/rings/AnimationPlayer.play("out")
					rings_in = false
					
			12:
				var val = float(data.value)/8
				$Level/t2/AnimationPlayer.speed_scale = val
				$Level/t2/AnimationPlayer.seek(randf_range(0,$Level/t2/AnimationPlayer.current_animation_length),true)
			13:
				var val = float(data.value)/8
				$Level/t3/AnimationPlayer.speed_scale = val
				$Level/t3/AnimationPlayer.seek(randf_range(0,$Level/t3/AnimationPlayer.current_animation_length),true)

func stop_prev_tween(type) -> void:
	if prev_tweeners[type] != null:
		prev_tweeners[type].kill()
		prev_tweeners[type] = null

var prev_tweeners = [null,null,null,null,null]
func change_light_color(type: int,color=-1,transition_mode=0) -> void:
	var group : Node3D
	var material = []
	var shader = []
	var tween : Tween
	match int(type):
		0:
			group = $Level/t0
			material = [$Level/t0/laser1/Bar7.material_override]
			tween = $Level/t0.create_tween()
		1:
			group = $Level/t1
			material = [$Level/t1/Bar7.material_override]
			tween = $Level/t1.create_tween()
		2:
			group = $Level/t2
			material = [$Level/t2/laser1/Bar7.material_override]
			tween = $Level/t2.create_tween()
		3:
			group = $Level/t3
			material = [$Level/t3/laser1/Bar7.material_override]
			tween = $Level/t3.create_tween()
		4:
			group = $Level/t4
			material = [$Level/t4/Bar1.material_override, $Level/floor.material_override]
			shader = []#[$wall_material_holder.material_override]
			tween = $Level/t4.create_tween()
	
	if not color is Color:
		for m in material:
			m.albedo_color = Color.BLACK
		tween.kill()
		stop_prev_tween(type)
		_on_Tween_tween_step(Color.BLACK, type)
		group.visible = false
		return
	else:
		for m in shader:
			m.set_shader_parameter("albedo_color",color)
		$Level/Sphere.material_override.set_shader_parameter("bg_%d_tint"%int(type),color)
	
	match transition_mode:
		0:
			stop_prev_tween(type)
			tween.kill()
			for m in material:
				m.albedo_color = color
			_on_Tween_tween_step(color, type)
			group.visible = true
		1:
			stop_prev_tween(type)
			tween.set_parallel()
			tween.set_trans(Tween.TRANS_LINEAR)
			tween.set_ease(Tween.EASE_OUT)
			for m in material:
				tween.tween_property(m, "albedo_color", color, 0.3).from(color*3)
			tween.tween_method(_on_Tween_tween_step.bind(int(type)), color*3, color, 0.3)
			tween.play()
			prev_tweeners[type] = tween
			group.visible = true
		2:
			stop_prev_tween(type)
			tween.set_parallel()
			tween.set_trans(Tween.TRANS_QUAD)
			tween.set_ease(Tween.EASE_IN)
			for m in material:
				tween.tween_property(m, "albedo_color", Color(0,0,0), 1).from(color*3)
			tween.tween_method(_on_Tween_tween_step.bind(int(type)), color*3, Color(0,0,0), 1)
			group.visible = true
			tween.play()
			prev_tweeners[type] = tween
			await tween.finished
			if material[0].albedo_color == Color(0,0,0):
				group.visible = false
				tween.kill()
				_on_Tween_tween_step(Color.BLACK, type)

func _on_Tween_tween_step(value : Color, id) -> void:
	if id == null: return
	$Level/Sphere.material_override.set_shader_parameter("bg_%d_intensity"%id,value.v)
