extends RigidBody3D
class_name CutPiece

# structure of nodes that represent a cut piece of a cube (ie. one half)
static var cube_phys_mat := load("res://game/BeepCube/BeepCube_Cut.phymat") as PhysicsMaterial
var mesh := MeshInstance3D.new()
var coll := CollisionShape3D.new()
var lifetime: float = 0.0
var parent_cube : Node3D = null

func _init(parent: Node3D, mesh_in: Mesh, mat_in: ShaderMaterial, bouncy: bool) -> void:
	parent_cube = parent
	
	# cut pieces will reside inside of their parent_cube's node tree, but we want
	# them to move independently, thus setting their transform to be 'top_level'
	parent_cube.add_child(self)
	top_level = true
	
	add_to_group(&"cutted_cube")
	mat_in.set_shader_parameter(&"cutted", true)
	collision_layer = 0
	collision_mask = CollisionLayerConstants.Floor_mask
	gravity_scale = 1
	if bouncy:
		# set a phyiscs material for some more bouncy behaviour
		physics_material_override = cube_phys_mat
	
	mesh.mesh = mesh_in
	mesh.layers = 3 # visible to both spectator and player
	mesh.material_override = mat_in
	# The note's per-instance look (colour, dot flag, edge mask size) lives on the
	# MeshInstance3D, not on the shared material (FR-002), so a cut piece has to be told
	# about it explicitly - it does not inherit the note's instance parameters.
	mesh.set_instance_shader_parameter(&"note_half_extent", mesh_in.get_aabb().size * 0.5)
	
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.25, 0.25, 0.125)
	coll.shape = shape
	
	add_child(coll)
	add_child(mesh)
	
	hide_piece()

func start_cut(dist_from_center, angle) -> void:
	# re-enable our process_mode first otherwise it seems like Godot-internals
	# can behave weirdly (ex. AnimationPlayer won't always play correctly)
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	lifetime = 0.0
	visible = true
	angular_velocity = Vector3()
	linear_velocity = Vector3()
	mesh.material_override.set_shader_parameter(&"cut_dist_from_center", dist_from_center)
	mesh.material_override.set_shader_parameter(&"cut_angle", angle)

func set_color(new_color: Color) -> void:
	mesh.set_instance_shader_parameter(&"note_color", new_color)

func set_dot(value: bool) -> void:
	mesh.set_instance_shader_parameter(&"note_is_dot", 1.0 if value else 0.0)

func set_chain_head(is_chain_head: bool) -> void:
	mesh.set_instance_shader_parameter(&"note_chain_head", 1.0 if is_chain_head else 0.0)

func hide_piece():
	visible = false
	# disable processing on this node and all children to help with performance
	process_mode = Node.PROCESS_MODE_DISABLED

const MAX_LIFETIME := 0.3;

func _physics_process(delta: float) -> void:
	lifetime += delta
	if lifetime > MAX_LIFETIME:
		parent_cube._on_cut_piece_died()
		hide_piece()
	else:
		# the "cut_vanish" shader parameter controls how faded-out the
		# piece is. 0.0 is not faded out at all, and higher numbers make it
		# more faded. we use ease() with a curve arguments of 2.0 which starts
		# the fade slowly, but then ramps up more quickly toward the end of the
		# lifetime. see this reddit post for a visual of ease() curve values.
		# https://forum.godotengine.org/t/how-do-i-properly-use-the-ease-function/20396/2
		var fade := lifetime / MAX_LIFETIME
		mesh.material_override.set_shader_parameter(&"cut_vanish",ease(fade,2.0)*0.5)
