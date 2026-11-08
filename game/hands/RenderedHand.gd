extends XRNode3D

# Renders one tracked hand from the MIT Godot demo hand assets.
#
# The hand mesh is positioned by this XRNode3D at the hand tracker's palm pose, and the
# XRHandModifier3D child of the imported Skeleton3D applies the live finger joints. Only
# rotation is applied to the bones so a small player's hand does not squash the mesh; the
# hand stays human-sized.

@export_enum("Left", "Right") var hand := 0

const LEFT_HAND := preload("res://game/hands/LeftHandHumanoid.gltf")
const RIGHT_HAND := preload("res://game/hands/RightHandHumanoid.gltf")
const HAND_TEXTURE := preload("res://game/hands/hand.png")

var _material: StandardMaterial3D

func _ready() -> void:
	var side := "left" if hand == 0 else "right"
	tracker = StringName("/user/hand_tracker/" + side)
	pose = &"default"
	show_when_tracked = true

	var model := (LEFT_HAND if hand == 0 else RIGHT_HAND).instantiate()
	add_child(model)

	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton != null:
		var modifier := XRHandModifier3D.new()
		modifier.hand_tracker = tracker
		modifier.bone_update = XRHandModifier3D.BONE_UPDATE_ROTATION_ONLY
		skeleton.add_child(modifier)
	else:
		push_warning("Hand model has no Skeleton3D; finger tracking will not render")

	# Map scenes are lit differently and some are very dark. An unshaded override keeps the
	# hands visible without adding lights; shadows off keeps the two skinned meshes cheap.
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_texture = HAND_TEXTURE
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		mesh_instance.material_override = _material
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _process(_dt: float) -> void:
	# The quick-settings Hands toggle hides the visual even while a hand is tracked; the saber
	# gate in BeepSaberController uses the same setting.
	visible = Settings.hand_tracking_enabled and get_has_tracking_data()
