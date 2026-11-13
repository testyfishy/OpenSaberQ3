extends Node3D
class_name EndScore

signal mainmenu
signal repeat
# the player wants to move the score that was just saved to another profile
signal switch_requested

var animated_percent: float = 0.0
@onready var raycast_area := $RaycastArea as Area3D
@onready var collision := $RaycastArea/CollisionShape3D as CollisionShape3D

# is there a score on disk behind the "Saved as ..." line? Without one there is nothing to
# switch, so the line and the Switch button stay away entirely (FR-006).
var _has_saved := false
# buttons are collision-disabled while the board fades in and while the profile panel is up
var _buttons_disabled := true

func _ready() -> void:
	# The ring is shared with the in-song HUD, where its label has room. On this board the word
	# ACCURACY ran over the ring on both sides; shrink the label here only.
	var ring_label := get_node_or_null("PercentIndicator/PercentLabel") as MeshInstance3D
	if ring_label != null:
		ring_label.scale = Vector3.ONE * 0.8
	_apply_saved_state()
	set_buttons_disabled(true)

func _show() -> void:
	raycast_area.collision_layer = CollisionLayerConstants.Ui_mask
	collision.disabled = false
	($Repeat as UIRaycastButton).collision_layer = CollisionLayerConstants.Ui_mask
	($MainMenu as UIRaycastButton).collision_layer = CollisionLayerConstants.Ui_mask
	($Switch as UIRaycastButton).collision_layer = CollisionLayerConstants.Ui_mask
	show()

func _hide() -> void:
	raycast_area.collision_layer = 0
	collision.disabled = true
	($Repeat as UIRaycastButton).collision_layer = 0
	($MainMenu as UIRaycastButton).collision_layer = 0
	($Switch as UIRaycastButton).collision_layer = 0
	hide()

# names the profile the score was stored under, next to the score itself
func show_saved_as(player_name: String) -> void:
	var text := "Saved as %s" % player_name
	var label := $SavedViewport/SavedLabel as RichTextLabel
	# RobotoMono advances roughly 0.6em per character, so shrink the font until the line
	# fits the 256px viewport instead of clipping it. 16px is the legible floor.
	# 236, not the full 256: at exactly the viewport width the last glyph was cut off.
	var wanted := int(236.0 / (float(maxi(text.length(),1)) * 0.6))
	label.add_theme_font_size_override("normal_font_size", clampi(wanted, 16, 32))
	label.text = "[center]%s" % text
	_has_saved = true
	_apply_saved_state()

func hide_saved() -> void:
	_has_saved = false
	_apply_saved_state()

func _apply_saved_state() -> void:
	($SavedMesh as MeshInstance3D).visible = _has_saved
	($Switch as UIRaycastButton).visible = _has_saved
	# a hidden Area3D keeps colliding, so the shape has to go too
	($Switch/Collision as CollisionShape3D).disabled = _buttons_disabled or not _has_saved

func show_score(score: int, record: int, percent: float, song_string: String, is_full_combo: bool, is_new_record: bool) -> void:
	var details_mesh := ($Details as MeshInstance3D).mesh as TextMesh
	var details_material := ($Details as MeshInstance3D).material_override as StandardMaterial3D
	var percent_indicator := $PercentIndicator as PercentIndicator
	var grade_label := $GradeViewport/GradeLabel as RichTextLabel
	var fc_label := $FCViewport/FCLabel as RichTextLabel
	var nr_label := $NRViewport/NRLabel as RichTextLabel
	var name_label := ($NameLabel as MeshInstance3D).mesh as TextMesh
	
	details_material.albedo_color = Color.TRANSPARENT
	grade_label.modulate = Color.TRANSPARENT
	fc_label.modulate = Color.TRANSPARENT
	nr_label.modulate = Color.TRANSPARENT
	percent_indicator.endscore()
	fc_label.visible = is_full_combo
	nr_label.visible = is_new_record
	name_label.text = song_string
	# Four lines, no spacer: the profile line and its Switch button sit directly underneath,
	# and the old five-line block ran straight through both of them.
	details_mesh.text = "Score\n%d\nBest\n%d" % [score,record]
	
	# The standard rank bands for score / best possible score.
	if percent >= 0.90:
		grade_label.text = "[center][rainbow freq=0.5 sat=0.7 val=2]SS"
	elif percent >= 0.80:
		grade_label.text = "[center]S"
	elif percent >= 0.65:
		grade_label.text = "[center]A"
	elif percent >= 0.50:
		grade_label.text = "[center]B"
	elif percent >= 0.35:
		grade_label.text = "[center]C"
	elif percent >= 0.20:
		grade_label.text = "[center]D"
	else:
		grade_label.text = "[center]E"
	
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self,^"animated_percent",percent,3.0).from(0.0)
	tw.play()
	while tw.is_running():
		percent_indicator.update_percent(animated_percent)
		await get_tree().process_frame
	#_on_Tween_tween_completed()
	
	percent_indicator.update_percent(animated_percent)
	tw = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT).set_parallel()
	tw.tween_property(details_material,^"albedo_color",Color.WHITE,2).from(Color.TRANSPARENT)
	tw.tween_property(grade_label,^"modulate",Color.WHITE,2).from(Color.TRANSPARENT)
	tw.tween_property(fc_label,^"modulate",Color.WHITE,2).from(Color.TRANSPARENT)
	tw.tween_property(nr_label,^"modulate",Color.WHITE,2).from(Color.TRANSPARENT)
	tw.play()

func set_buttons_disabled(disabled: bool) -> void:
	_buttons_disabled = disabled
	($Repeat/Collision as CollisionShape3D).disabled = disabled
	($MainMenu/Collision as CollisionShape3D).disabled = disabled
	($Switch/Collision as CollisionShape3D).disabled = disabled or not _has_saved

func _on_Repeat_button_up() -> void:
	repeat.emit()

func _on_MainMenu_button_up() -> void:
	set_buttons_disabled(true)
	mainmenu.emit()

func _on_Switch_button_up() -> void:
	# the board stays up behind the profile panel: the owner disables our buttons, asks for
	# a profile, and re-enables them when the panel closes
	switch_requested.emit()
