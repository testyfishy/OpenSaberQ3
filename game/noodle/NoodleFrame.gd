extends RefCounted
class_name NoodleFrame

# The once-per-drawn-frame part of Noodle animation. A Noodle note or wall travels every physics
# tick, but its animated pose (NoodleAnim.evaluate, the transform write, dissolve, grow) is only
# seen when a frame is drawn. When a slow frame makes the engine run several physics ticks before
# the next one (up to 8, the catch-up spiral), working the pose out on every tick multiplied the
# cost of the frame by the number of ticks, which slowed the next frame further.
#
# So an object that ticks adds itself here once per frame, and BeepSaber_Game._process poses
# every object on the list once, after the frame's last tick and before it is drawn: the state
# drawn is the same as posing on every tick. Objects whose collision must follow every tick
# (notes in the hit window, hittable walls near the head) also pose in their tick; their frame
# pass then only does what is left. Ordinary maps never add anything, so flush() returns at once.

static var walls: Array[Wall] = []
static var cubes: Array[Cuttable] = []
const Cost := preload("res://game/scripts/CostProbe.gd")


static func flush() -> void:
	if not walls.is_empty():
		var t0 := Time.get_ticks_usec() if Cost.enabled else 0
		for w in walls:
			if is_instance_valid(w):
				w._noodle_frame()
		walls.clear()
		if Cost.enabled:
			Cost.wall_usec += Time.get_ticks_usec() - t0
	if not cubes.is_empty():
		var t0 := Time.get_ticks_usec() if Cost.enabled else 0
		for c in cubes:
			if is_instance_valid(c):
				c._noodle_frame()
		cubes.clear()
		if Cost.enabled:
			Cost.cuttable_usec += Time.get_ticks_usec() - t0


static func reset() -> void:
	walls.clear()
	cubes.clear()
