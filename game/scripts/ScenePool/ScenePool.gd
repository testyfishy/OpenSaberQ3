extends Node
class_name BeepCubePool

# emitted when the pool intances a scene for the first time
signal scene_instanced(cube: BeepCube)

var scene := load("res://game/BeepCube/BeepCube.tscn") as PackedScene
var _free_list: Array[BeepCube] = []

func _enter_tree() -> void:
	GlobalReferences.scene_pool = self

func _ready() -> void:
	print("creating initial cube pool")
	await get_tree().process_frame
	var init_cubes: Array[BeepCube] = []
	const pre_pool := 100
	for pp in pre_pool:
		var cube := acquire()
		cube.visible = true
		cube.position.z = -2
		init_cubes.append(cube)
		if pp%4 == 0:
			await get_tree().process_frame
	#this forces the game to render all of the cubes in a couple of frames to prevent slow downs in the first pool cycle
	for cube in init_cubes:
		cube.release()
	print("cubes in pool: ",_free_list.size())

func acquire() -> BeepCube:
	var cube := _free_list.pop_back() as BeepCube
	if not cube:
		var new_cube := scene.instantiate() as BeepCube
		new_cube.scene_released.connect(_on_scene_released)
		scene_instanced.emit(new_cube)
		cube = new_cube
	return cube

func _on_scene_released(cube: BeepCube) -> void:
	cube.scene_released.disconnect(_on_scene_released)
	_free_list.push_back(cube)


## cutted cube material pool:

var cut_material_pool: Array[Material] = []

func generate_cut_material_pool(og_material_rev : Material = null, expected_pool_size := 10):
	if og_material_rev and cut_material_pool.size() < expected_pool_size:
		while cut_material_pool.size() < expected_pool_size:
			cut_material_pool.append(og_material_rev.duplicate())

func get_pooled_cut_material(og_material_rev : Material = null, expected_pool_size := 10):
	if cut_material_pool.is_empty():
		if og_material_rev:
			generate_cut_material_pool(og_material_rev, expected_pool_size)
		else:
			return null
	if cut_material_pool.size() < expected_pool_size:
		generate_cut_material_pool(og_material_rev, expected_pool_size)
	var to_Return = cut_material_pool.pop_front()
	cut_material_pool.push_back(to_Return)
	return to_Return
