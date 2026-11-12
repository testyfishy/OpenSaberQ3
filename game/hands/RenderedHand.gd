extends Node3D

# Draws one tracked hand as a skeleton of light: a glowing bar per bone and nothing else.
#
# 0.7.8/0.7.9 drew the MIT humanoid hand mesh. On the headset it read as a flesh hand in a
# light-show game, and with rotation-only skinning the mesh's own proportions opened a gap between
# the ring and little fingers. Bars drawn straight between the tracked joints have neither
# problem: they sit exactly where the runtime says the joints are, in the hand's saber colour,
# and the whole hand is one MultiMesh draw of 27 boxes (324 triangles).
#
# Space: XRHandTracker joint transforms are in tracking space, which is the XROrigin3D's local
# space. This node must therefore be a plain child of the origin with an identity transform. It is
# deliberately NOT an XRNode3D: that would move the node to the palm pose and apply the palm
# transform to every joint a second time.

@export_enum("Left", "Right") var hand := 0
# Bar thickness in metres, and how far past 1.0 the colour is pushed so the glow pass picks it up.
@export var bone_thickness := 0.007
@export var glow_energy := 2.5

const JOINT_FLAGS := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID

# Finger chains, wrist outwards. The four knuckle joints are also joined into a bar so the palm
# has an outline instead of four unrelated rays.
const CHAINS: Array[Array] = [
	[XRHandTracker.HAND_JOINT_WRIST, XRHandTracker.HAND_JOINT_THUMB_METACARPAL,
		XRHandTracker.HAND_JOINT_THUMB_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_THUMB_PHALANX_DISTAL,
		XRHandTracker.HAND_JOINT_THUMB_TIP],
	[XRHandTracker.HAND_JOINT_WRIST, XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL,
		XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_INTERMEDIATE,
		XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP],
	[XRHandTracker.HAND_JOINT_WRIST, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL,
		XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_INTERMEDIATE,
		XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP],
	[XRHandTracker.HAND_JOINT_WRIST, XRHandTracker.HAND_JOINT_RING_FINGER_METACARPAL,
		XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_INTERMEDIATE,
		XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_RING_FINGER_TIP],
	[XRHandTracker.HAND_JOINT_WRIST, XRHandTracker.HAND_JOINT_PINKY_FINGER_METACARPAL,
		XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_INTERMEDIATE,
		XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP],
	[XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_PROXIMAL,
		XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_PROXIMAL],
]

var _tracker_name := &""
var _segments: Array[Vector2i] = []
var _bars: Array[Transform3D] = []
var _multimesh := MultiMesh.new()
var _instance := MultiMeshInstance3D.new()
var _material := StandardMaterial3D.new()
var _color := Color(0, 0, 0, 0)
var _saber: LightSaber

func _ready() -> void:
	_tracker_name = StringName("/user/hand_tracker/" + ("left" if hand == 0 else "right"))
	for chain in CHAINS:
		for i in range(chain.size() - 1):
			_segments.append(Vector2i(int(chain[i]), int(chain[i + 1])))

	# Unshaded and brighter than 1.0: the bars are light sources to the eye, and the existing
	# glow pass (threshold 1.0) gives them the same bloom as the blades. No lights, no shadows.
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var bar := BoxMesh.new()
	bar.size = Vector3.ONE
	bar.material = _material
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.mesh = bar
	_multimesh.instance_count = _segments.size()
	_bars.resize(_segments.size())
	_bars.fill(_HIDDEN)
	_instance.multimesh = _multimesh
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The bars move every frame; a fixed generous box avoids recomputing the AABB each time and
	# keeps the hand from being culled when the stale box is off-screen.
	_instance.custom_aabb = AABB(Vector3(-3.0, -1.0, -3.0), Vector3(6.0, 4.0, 6.0))
	add_child(_instance)

	# The hand wears its saber's colour, whatever currently sets that (settings or the map).
	var side := "Left" if hand == 0 else "Right"
	_saber = get_node_or_null("../%sController/%sLightSaber" % [side, side]) as LightSaber
	_apply_color(Settings.color_left if hand == 0 else Settings.color_right)
	visible = false

func segment_count() -> int:
	return _segments.size()

# The transform last written for a bar, in this node's space. Kept here because the headless
# renderer does not store MultiMesh transforms, and the harness checks them.
func segment_transform(index: int) -> Transform3D:
	return _bars[index]

func _apply_color(color: Color) -> void:
	if color == _color:
		return
	_color = color
	_material.albedo_color = Color(color.r * glow_energy, color.g * glow_energy, color.b * glow_energy)

func _process(_dt: float) -> void:
	var tracker := XRServer.get_tracker(_tracker_name) as XRHandTracker
	# The quick-settings Hands toggle hides the visual even while a hand is tracked; the saber
	# gate in BeepSaberController uses the same setting.
	visible = Settings.hand_tracking_enabled and tracker != null and tracker.has_tracking_data
	if not visible:
		return
	if _saber != null:
		_apply_color(_saber.light_color)
	for i in _segments.size():
		var from_joint := _segments[i].x as XRHandTracker.HandJoint
		var to_joint := _segments[i].y as XRHandTracker.HandJoint
		var valid := (tracker.get_hand_joint_flags(from_joint) & JOINT_FLAGS) != 0 \
			and (tracker.get_hand_joint_flags(to_joint) & JOINT_FLAGS) != 0
		var a := tracker.get_hand_joint_transform(from_joint).origin
		var b := tracker.get_hand_joint_transform(to_joint).origin
		_bars[i] = _bar_between(a, b) if valid else _HIDDEN
		_multimesh.set_instance_transform(i, _bars[i])

# A zero-scale transform: the instance draws nothing.
const _HIDDEN := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

# The unit box stretched from `a` to `b` along its own Z, `bone_thickness` wide.
func _bar_between(a: Vector3, b: Vector3) -> Transform3D:
	var along := b - a
	var length := along.length()
	if length < 0.0005:
		return _HIDDEN
	var z := along / length
	# Any axis not parallel to the bone will do as an up hint.
	var hint := Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT
	var x := hint.cross(z).normalized()
	var y := z.cross(x)
	return Transform3D(Basis(x * bone_thickness, y * bone_thickness, z * length), (a + b) * 0.5)
