extends DefaultSaber

@onready var particles := $CPUParticles3D as CPUParticles3D

func _sub_ready() -> void:
	if OS.get_name() in ["Android","Web"]:
		particles.free()

var last_tip_pos := Vector3.ZERO

func _process(delta: float) -> void:
	# Hit sounds are owned by DefaultSaber: this override used to swallow the
	# pending-hit queue (a future-beat hit never fired and the array grew), so
	# drain it first. There is deliberately no hit() override here any more —
	# the old one called play() then wrote pitch_scale, which fought the
	# polyphonic playback (one play() kills every live voice).
	super._process(delta)
	var current_tip_pos := tip.global_transform.origin
	var speed := (current_tip_pos-last_tip_pos).length()
	if is_instance_valid(particles):
		particles.speed_scale = 2.5+(30*speed)
		#Particles.lifetime = max(0.1, 2-(20*speed))
	last_tip_pos = current_tip_pos

func set_thickness(_value: float) -> void: #ignore set thinkness on this saber
	pass
