# Mirrored saber copies under the floor (specs/001-quest3-saber-perf FR-047).
#
# Why a rig and not a second scene: the copies must be *visual only*. These are two plain
# MeshInstance3D nodes created here, sharing the live saber's Mesh resource (so the Show/Hide
# animation, which drives the capsule's height and radius, is reflected for free). There is no
# Area3D, no CollisionShape3D and no script on them, and Cuttable._register_hit only ever walks
# Area3D children, so neither the physics server nor the HitResolver can ever see them.
#
# Cost: when the setting is off, `_process` returns after one bool test. When it is on, it is
# two transform writes per frame — no allocation, no node creation, no scene query.
extends Node3D

const MIRROR_SHADER := preload("res://game/shaders/mirror_copy.gdshader")
# Reflection in the plane y = 0.
const FLIP := Transform3D(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3.ZERO)
# FR-038: draw the copies for a few frames at load, deep below the floor, so their material
# compiles then rather than the first time the setting is switched on mid-song.
const PREWARM_FRAMES := 3
const PREWARM_POSITION := Vector3(0.0, -100.0, 0.0)
const MIRROR_DIM := 0.22

@export var left_saber: LightSaber
@export var right_saber: LightSaber

var _sabers: Array[LightSaber] = []
var _blades: Array[MeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []
var _enabled := false
var _prewarm := PREWARM_FRAMES

func _ready() -> void:
	_sabers = [left_saber, right_saber]
	for i in _sabers.size():
		var blade := MeshInstance3D.new()
		blade.layers = 3
		blade.position = PREWARM_POSITION
		var mat := ShaderMaterial.new()
		mat.shader = MIRROR_SHADER
		mat.set_shader_parameter(&"dim", MIRROR_DIM)
		blade.material_override = mat
		add_child(blade)
		_blades.append(blade)
		_materials.append(mat)
	refresh_meshes()
	apply_colors()
	@warning_ignore("return_value_discarded")
	Settings.changed.connect(_on_settings_changed)

func _process(_delta: float) -> void:
	if _prewarm > 0:
		_prewarm -= 1
		if _prewarm == 0:
			_apply_enabled()
		return
	if not _enabled:
		return
	# Two transform writes. The mesh is a shared resource, so this is the whole per-frame cost.
	for i in _blades.size():
		var saber := _sabers[i]
		if saber == null or saber.saber_visual == null:
			continue
		_blades[i].global_transform = FLIP * saber.saber_visual.light_mesh.global_transform

func refresh_meshes() -> void:
	for i in _sabers.size():
		var saber := _sabers[i]
		if saber == null or saber.saber_visual == null:
			continue
		_blades[i].mesh = saber.saber_visual.light_mesh.mesh

func apply_colors() -> void:
	if _materials.size() < 2:
		return
	_materials[0].set_shader_parameter(&"color", Settings.color_left)
	_materials[1].set_shader_parameter(&"color", Settings.color_right)

func _apply_enabled() -> void:
	_enabled = Settings.mirror_reflections
	visible = _enabled

func _on_settings_changed(key: StringName) -> void:
	match key:
		&"mirror_reflections":
			_apply_enabled()
		&"color_left", &"color_right":
			apply_colors()
		&"saber_visual":
			refresh_meshes()
			apply_colors()
