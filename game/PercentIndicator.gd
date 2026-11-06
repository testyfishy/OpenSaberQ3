extends MeshInstance3D
class_name PercentIndicator

# Spike attribution (FR-033): a TextMesh.text assignment re-triangulates the
# glyphs and re-uploads the mesh. `update_percent` is driven by
# Scoreboard.score_changed, i.e. once per cut, but the rendered integer only
# changes every few cuts - so the text is only rewritten when the integer it
# would display actually differs. The displayed value is identical either way.
const Cost := preload("res://game/scripts/CostProbe.gd")

var how_full := 0.0
var how_full_display := 0.0
var label: TextMesh
var shader: ShaderMaterial

var _shown_percent := -1

func _ready() -> void:
	shader = material_override as ShaderMaterial
	var label_instance = $PercentLabel as MeshInstance3D
	label = label_instance.mesh as TextMesh
	label_instance.layers = layers

func _process(delta: float) -> void:
	how_full_display = lerpf(how_full_display, how_full, delta*8)
	shader.set_shader_parameter(&"how_full", how_full_display)

func start_map() -> void:
	how_full = 1.0
	how_full_display = 0.0
	_set_text(100)

func endscore() -> void:
	how_full = 0.0
	how_full_display = 0.0
	_set_text(0)

func update_percent(amount: float) -> void:
	how_full = amount
	_set_text(int(amount * 100))

func _set_text(percent: int) -> void:
	if percent == _shown_percent:
		return
	_shown_percent = percent
	if Cost.enabled: Cost.text_mesh_writes += 1
	# The player read this ring as song progress. Name what it is.
	label.text = "%d%%\nACCURACY" % percent
