extends Node3D
class_name SaberTail

@onready var material := ($Mesh as MeshInstance3D).material_override as StandardMaterial3D
@onready var imm_geo := ($Mesh as MeshInstance3D).mesh as ImmediateMesh

@export var size := 1.0

# for the math in _process to work properly and the tail to be drawn in the
# right spot,the mesh has to be reparented to root.
# TODO: reparenting to root like this is difficult for any future coders to
# follow.  the math should be rewritten to work without reparenting.
func _ready() -> void:
	var mesh := $Mesh as MeshInstance3D
	remove_child(mesh)
	get_tree().get_root().add_child.call_deferred(mesh)

func set_color(color: Color) -> void:
	material.albedo_color = color
	material.emission = color

var last_pos: Array[Array] = []
var time := 0.15
func _process(delta: float) -> void:
	if visible and size > 0:
		var pos := PackedVector3Array([global_position,to_global(position + Vector3(0,size,0))])
		imm_geo.clear_surfaces()
		if last_pos.size() > 0:
			imm_geo.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

			for i in range(last_pos.size()):
				var posA := pos
				if i > 0:
					posA = last_pos[i-1][0]
				var posB = last_pos[i][0]
				
				var t := clampf(last_pos[i][1] / time, 0.02, 0.98)
				var offsetted := clampf(t + (1.0/last_pos.size()), 0.02, 0.98)

				imm_geo.surface_set_uv(Vector2(t,0.98))
				imm_geo.surface_add_vertex(posA[0])
				imm_geo.surface_set_uv(Vector2(t,0.02))
				imm_geo.surface_add_vertex(posA[1])
				imm_geo.surface_set_uv(Vector2(offsetted,0.02))
				imm_geo.surface_add_vertex(posB[1])

				imm_geo.surface_set_uv(Vector2(t,0.98))
				imm_geo.surface_add_vertex(posA[0])
				imm_geo.surface_set_uv(Vector2(offsetted,0.98))
				imm_geo.surface_add_vertex(posB[0])
				imm_geo.surface_set_uv(Vector2(offsetted,0.02))
				imm_geo.surface_add_vertex(posB[1])
				
				last_pos[i][1] += delta
				if last_pos[i][1] > time:
					last_pos[i][1] = -1

			imm_geo.surface_end()

		last_pos.push_front([pos,0.0])
		for i in range(last_pos.size()):
			if last_pos[i][1] < 0:
				last_pos.resize(i-1)
				break
	elif last_pos.size() > 0:
		imm_geo.clear_surfaces()
		last_pos = []
