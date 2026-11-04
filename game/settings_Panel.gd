extends Panel
class_name SettingsPanel

signal apply()
@export var beepsaber_game : BeepSaber_Game

@onready var saber_control := $ScrollContainer/VBox/SaberTypeRow/saber as OptionButton
# Visual additions (FR-045..FR-048).
@onready var floor_light_control := $ScrollContainer/VBox/floor_light as CheckButton
@onready var saber_halo_control := $ScrollContainer/VBox/saber_halo as CheckButton
@onready var mirror_reflections_control := $ScrollContainer/VBox/mirror_reflections as CheckButton
@onready var saber_tail_control := $ScrollContainer/VBox/saber_tail as CheckButton
# Round 2 visual additions (specs/007-visual-options). Each one is its own switch, like the
# rows above; the tooltip states the cost.
@onready var hit_flash_control := $ScrollContainer/VBox/hit_flash as CheckButton
@onready var floor_grid_control := $ScrollContainer/VBox/floor_grid as CheckButton
@onready var event_tint_control := $ScrollContainer/VBox/event_tint as CheckButton
@onready var debris_cap_control := $ScrollContainer/VBox/debris_cap as CheckButton
@onready var debris_shards_control := $ScrollContainer/VBox/debris_shards as CheckButton
@onready var environment_mode_control := $ScrollContainer/VBox/environment_mode as OptionButton
@onready var sky_style_control := $ScrollContainer/VBox/sky_style as OptionButton
var perf_control: OptionButton
@onready var saber_thickness := $ScrollContainer/VBox/SaberThicknessRow/saber_thickness as HSlider
@onready var cut_blocks := $ScrollContainer/VBox/cut_blocks as CheckButton
@onready var d_background := $ScrollContainer/VBox/d_background as CheckButton
@onready var left_saber_col := $ScrollContainer/VBox/SaberColorsRow/left_saber_col as ColorPickerButton
@onready var right_saber_col := $ScrollContainer/VBox/SaberColorsRow/right_saber_col as ColorPickerButton
@onready var show_debug_control := $ScrollContainer/VBox/show_debug as CheckButton
@onready var show_collisions := $ScrollContainer/VBox/show_collisions as CheckButton
@onready var bombs_enabled_control := $ScrollContainer/VBox/bombs_enabled as CheckButton
@onready var ui_volume_slider := $ScrollContainer/VBox/UI_VolumeRow/ui_volume_slider as HSlider
@onready var disable_map_color_control := $ScrollContainer/VBox/disable_map_color as CheckButton
@onready var upload_server_control := $ScrollContainer/VBox/upload_server as CheckButton
@onready var left_saber_posx_control := $ScrollContainer/VBox/left_saber_offset/posx as SpinBox
@onready var left_saber_posy_control := $ScrollContainer/VBox/left_saber_offset/posy as SpinBox
@onready var left_saber_posz_control := $ScrollContainer/VBox/left_saber_offset/posz as SpinBox
@onready var left_saber_rotx_control := $ScrollContainer/VBox/left_saber_offset/rotx as SpinBox
@onready var left_saber_roty_control := $ScrollContainer/VBox/left_saber_offset/roty as SpinBox
@onready var left_saber_rotz_control := $ScrollContainer/VBox/left_saber_offset/rotz as SpinBox
@onready var right_saber_posx_control := $ScrollContainer/VBox/right_saber_offset/posx as SpinBox
@onready var right_saber_posy_control := $ScrollContainer/VBox/right_saber_offset/posy as SpinBox
@onready var right_saber_posz_control := $ScrollContainer/VBox/right_saber_offset/posz as SpinBox
@onready var right_saber_rotx_control := $ScrollContainer/VBox/right_saber_offset/rotx as SpinBox
@onready var right_saber_roty_control := $ScrollContainer/VBox/right_saber_offset/roty as SpinBox
@onready var right_saber_rotz_control := $ScrollContainer/VBox/right_saber_offset/rotz as SpinBox
@onready var player_height_offset_control := $ScrollContainer/VBox/player_height_offset/pos as SpinBox
@onready var audio_master_control := $ScrollContainer/VBox/audio/master/master_slider as HSlider
@onready var audio_music_control := $ScrollContainer/VBox/audio/music/music_slider as HSlider
@onready var audio_sfx_control := $ScrollContainer/VBox/audio/sfx/sfx_slider as HSlider
@onready var spectator_view_control := $ScrollContainer/VBox/spectator_view as CheckButton
@onready var spectator_hud_control := $ScrollContainer/VBox/spectator_hud as CheckButton

# Performance rows (FR-040). Each one is hidden when the running XR interface cannot apply it.
@onready var refresh_rate_row := $ScrollContainer/VBox/RefreshRateRow as HBoxContainer
@onready var refresh_rate_control := $ScrollContainer/VBox/RefreshRateRow/refresh_rate as OptionButton
@onready var render_scale_control := $ScrollContainer/VBox/RenderScaleRow/render_scale as HSlider
@onready var render_scale_value := $ScrollContainer/VBox/RenderScaleRow/render_scale_value as Label
@onready var msaa_control := $ScrollContainer/VBox/MSAARow/msaa as OptionButton
@onready var foveation_row := $ScrollContainer/VBox/FoveationRow as HBoxContainer
@onready var foveation_control := $ScrollContainer/VBox/FoveationRow/foveation as OptionButton

# Index in these arrays is the OptionButton id, the value is the engine value. MSAA matches
# Viewport.MSAA (and rendering/anti_aliasing/quality/msaa_3d): 0 = off, 1 = 2x, 2 = 4x.
const MSAA_VALUES: Array[int] = [0, 1, 2]
const MSAA_LABELS: Array[String] = ["Off", "2x", "4x"]
const FOVEATION_LABELS: Array[String] = ["Off", "Low", "Medium"]

var _refresh_rates: Array[float] = []

var _play_ui_sound_demo := false

const VR_SLIDER := preload("res://game/vr_slider.tscn")

func _ready() -> void:
	UI_AudioEngine.attach_children(self)
	
	set_controls_from_settings()
	_play_ui_sound_demo = true
	_fit_scroll_area()
	_add_scroll_slider()

# The list used to be wider than the panel, which produced a horizontal scrollbar and cut words off
# at the right edge. Horizontal scrolling is disabled and labels wrap instead, so the list only ever
# moves vertically.
func _fit_scroll_area() -> void:
	var scroll := $ScrollContainer as ScrollContainer
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_allow_wrapping(scroll.get_node("VBox"))

func _allow_wrapping(node: Node) -> void:
	for child in node.get_children():
		# Label, Button and CheckButton all expose autowrap_mode in Godot 4; the `in` guard keeps
		# this from erroring on any other control type in the list.
		if "autowrap_mode" in child:
			child.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if child is Label or child is Button:
			child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_allow_wrapping(child)

# The same thumbstick scroller the BeatSaver list uses, pointed at this list.
func _add_scroll_slider() -> void:
	if has_node("settings_slider"):
		return
	var slider := VR_SLIDER.instantiate()
	slider.name = "settings_slider"
	slider.scroll_node_path = NodePath("../ScrollContainer")
	add_child(slider)

func set_controls_from_settings() -> void:
	saber_control.clear()
	for s in Settings.SABER_VISUALS:
		saber_control.add_item(s[0])
	
	show_collisions.button_pressed = get_tree().debug_collisions_hint
	show_collisions.visible = OS.is_debug_build()
	
	# set the selections to the loaded values
	await get_tree().process_frame
	saber_thickness.value = Settings.thickness
	cut_blocks.button_pressed = Settings.cube_cuts_falloff
	left_saber_col.color = Settings.color_left
	right_saber_col.color = Settings.color_right
	saber_tail_control.button_pressed = Settings.saber_tail
	floor_light_control.button_pressed = Settings.floor_light
	saber_halo_control.button_pressed = Settings.saber_halo
	mirror_reflections_control.button_pressed = Settings.mirror_reflections
	hit_flash_control.button_pressed = Settings.hit_flash
	floor_grid_control.button_pressed = Settings.floor_grid
	event_tint_control.button_pressed = Settings.event_tint
	debris_cap_control.button_pressed = Settings.debris_cap
	debris_shards_control.button_pressed = Settings.debris_shards
	if environment_mode_control.item_count == 0:
		environment_mode_control.add_item("Auto (map)")
		environment_mode_control.add_item("Classic")
	environment_mode_control.select(clampi(Settings.environment_mode, 0, 1))
	_populate_sky_style()
	_populate_perf_preset()
	d_background.button_pressed = Settings.events
	saber_control.select(Settings.saber_visual)
	show_debug_control.button_pressed = Settings.show_debug_info
	bombs_enabled_control.button_pressed = Settings.bombs_enabled
	ui_volume_slider.value = Settings.ui_volume
	disable_map_color_control.button_pressed = Settings.disable_map_color
	upload_server_control.button_pressed = Settings.upload_server
	left_saber_posx_control.value = Settings.left_saber_offset_pos.x
	left_saber_posy_control.value = Settings.left_saber_offset_pos.y
	left_saber_posz_control.value = Settings.left_saber_offset_pos.z
	left_saber_rotx_control.value = Settings.left_saber_offset_rot.x
	left_saber_roty_control.value = Settings.left_saber_offset_rot.y
	left_saber_rotz_control.value = Settings.left_saber_offset_rot.z
	right_saber_posx_control.value = Settings.right_saber_offset_pos.x
	right_saber_posy_control.value = Settings.right_saber_offset_pos.y
	right_saber_posz_control.value = Settings.right_saber_offset_pos.z
	right_saber_rotx_control.value = Settings.right_saber_offset_rot.x
	right_saber_roty_control.value = Settings.right_saber_offset_rot.y
	right_saber_rotz_control.value = Settings.right_saber_offset_rot.z
	player_height_offset_control.value = Settings.player_height_offset
	audio_master_control.value = Settings.audio_master
	audio_music_control.value = Settings.audio_music
	audio_sfx_control.value = Settings.audio_sfx
	spectator_view_control.button_pressed = Settings.spectator_view
	spectator_hud_control.button_pressed = Settings.spectator_hud
	_set_up_performance_controls()

# Builds the performance rows from what the current XR session actually offers, so a headset
# without XR_FB_foveation or without adjustable refresh rates simply does not show those rows.
func _set_up_performance_controls() -> void:
	var iface := XRServer.primary_interface
	
	# Refresh rate: only the rates the panel reports are offered, because anything else is
	# silently rejected by the runtime.
	_refresh_rates.clear()
	if iface != null and iface.has_method(&"get_available_display_refresh_rates"):
		var available: Array = iface.call(&"get_available_display_refresh_rates")
		for rate in available:
			var hz := float(rate)
			if hz > 0.0 and not _refresh_rates.has(hz):
				_refresh_rates.append(hz)
	_refresh_rates.sort()
	refresh_rate_control.clear()
	refresh_rate_row.visible = not _refresh_rates.is_empty()
	if not _refresh_rates.is_empty():
		var selected := 0
		var best_delta := INF
		for i in _refresh_rates.size():
			refresh_rate_control.add_item("%d Hz" % int(round(_refresh_rates[i])))
			var delta := absf(_refresh_rates[i] - Settings.display_refresh_rate)
			if delta < best_delta:
				best_delta = delta
				selected = i
		refresh_rate_control.select(selected)
	
	# Render scale: applies live (the OpenXR layer recreates its swapchains when the resulting
	# size changes), so it is always offered.
	render_scale_control.value = Settings.render_scale
	_update_render_scale_label()
	
	msaa_control.clear()
	for label in MSAA_LABELS:
		msaa_control.add_item(label)
	var msaa_index := MSAA_VALUES.find(Settings.msaa_3d)
	msaa_control.select(msaa_index if msaa_index >= 0 else MSAA_VALUES.size() - 1)
	
	# Foveation is only real when the runtime advertises XR_FB_foveation.
	var foveation_supported := false
	if iface != null and iface.has_method(&"is_foveation_supported"):
		foveation_supported = bool(iface.call(&"is_foveation_supported"))
	foveation_control.clear()
	for label in FOVEATION_LABELS:
		foveation_control.add_item(label)
	foveation_control.select(clampi(Settings.foveation_level, 0, FOVEATION_LABELS.size() - 1))
	foveation_row.visible = foveation_supported
	vr.log_info("perf panel: refresh rates offered=%s, selected=%.0f Hz, render scale=%.4f (setting %.4f), msaa=%d (index %d), foveation supported=%s level=%d" % [
		str(_refresh_rates), Settings.display_refresh_rate, render_scale_control.value, Settings.render_scale,
		Settings.msaa_3d, msaa_control.selected, str(foveation_supported), Settings.foveation_level])

func _update_render_scale_label() -> void:
	render_scale_value.text = "%.2fx" % render_scale_control.value

func _restore_defaults() -> void:
	Settings.restore_defaults()
	set_controls_from_settings()

#settings down here
func _on_thickness_value_changed(value: float) -> void:
	Settings.thickness = value

func _on_cut_blocks_toggled(button_pressed: bool) -> void:
	Settings.cube_cuts_falloff = button_pressed

func _on_left_saber_color_changed(color: Color) -> void:
	Settings.color_left = color

func _on_right_saber_color_changed(color: Color) -> void:
	Settings.color_right = color

func _on_saber_tail_toggled(button_pressed: bool) -> void:
	Settings.saber_tail = button_pressed

func _on_floor_light_toggled(button_pressed: bool) -> void:
	Settings.floor_light = button_pressed

func _on_saber_halo_toggled(button_pressed: bool) -> void:
	Settings.saber_halo = button_pressed

func _on_mirror_reflections_toggled(button_pressed: bool) -> void:
	Settings.mirror_reflections = button_pressed

func _on_hit_flash_toggled(button_pressed: bool) -> void:
	Settings.hit_flash = button_pressed

func _on_floor_grid_toggled(button_pressed: bool) -> void:
	Settings.floor_grid = button_pressed

func _on_event_tint_toggled(button_pressed: bool) -> void:
	Settings.event_tint = button_pressed

func _on_debris_cap_toggled(button_pressed: bool) -> void:
	Settings.debris_cap = button_pressed

func _on_debris_shards_toggled(button_pressed: bool) -> void:
	Settings.debris_shards = button_pressed

func _on_environment_mode_selected(index: int) -> void:
	Settings.environment_mode = index

func _populate_sky_style() -> void:
	if sky_style_control.item_count == 0:
		sky_style_control.add_item("Black void")
		sky_style_control.add_item("Gradient")
		sky_style_control.add_item("Panorama")
	sky_style_control.select(clampi(Settings.sky_style, 0, 2))

func _on_sky_style_selected(index: int) -> void:
	Settings.sky_style = index

func _on_d_background_toggled(button_pressed: bool) -> void:
	Settings.events = button_pressed

func _on_saber_item_selected(index: int) -> void:
	Settings.saber_visual = index

func _on_show_debug_toggled(button_pressed: bool) -> void:
	Settings.show_debug_info = button_pressed

func _on_bombs_enabled_toggled(button_pressed: bool) -> void:
	Settings.bombs_enabled = button_pressed

func _on_ui_volume_slider_value_changed(value: float) -> void:
	UI_AudioEngine.set_volume(linear_to_db(float(value)/10.0))
	if _play_ui_sound_demo:
		UI_AudioEngine.play_click()
	
	Settings.ui_volume = value

func _on_left_saber_pos_x_changed(value: float) -> void:
	Settings.left_saber_offset_pos.x = value

func _on_left_saber_pos_y_changed(value: float) -> void:
	Settings.left_saber_offset_pos.y = value

func _on_left_saber_pos_z_changed(value: float) -> void:
	Settings.left_saber_offset_pos.z = value

func _on_left_saber_rot_x_changed(value: float) -> void:
	Settings.left_saber_offset_rot.x = value

func _on_left_saber_rot_y_changed(value: float) -> void:
	Settings.left_saber_offset_rot.y = value

func _on_left_saber_rot_z_changed(value: float) -> void:
	Settings.left_saber_offset_rot.z = value

func _on_right_saber_pos_x_changed(value: float) -> void:
	Settings.right_saber_offset_pos.x = value

func _on_right_saber_pos_y_changed(value: float) -> void:
	Settings.right_saber_offset_pos.y = value

func _on_right_saber_pos_z_changed(value: float) -> void:
	Settings.right_saber_offset_pos.z = value

func _on_right_saber_rot_x_changed(value: float) -> void:
	Settings.right_saber_offset_rot.x = value

func _on_right_saber_rot_y_changed(value: float) -> void:
	Settings.right_saber_offset_rot.y = value

func _on_right_saber_rot_z_changed(value: float) -> void:
	Settings.right_saber_offset_rot.z = value

func _on_player_height_offset_changed(value: float) -> void:
	Settings.player_height_offset = value

func _on_disable_map_color_toggled(toggled_on: bool) -> void:
	Settings.disable_map_color = toggled_on

func _on_upload_server_toggled(toggled_on: bool) -> void:
	Settings.upload_server = toggled_on

func _force_update_show_coll_shapes(node: Node) -> void:
	# toggle enable to make engine show collision shapes
	if node is CollisionShape3D:
		var col := node as CollisionShape3D
		col.disabled = not col.disabled
		col.disabled = not col.disabled
	elif node is RayCast3D:
		var ray := node as RayCast3D
		ray.enabled = not ray.enabled
		ray.enabled = not ray.enabled
	
	for c in node.get_children():
		_force_update_show_coll_shapes(c)

func _on_show_collisions_toggled(button_pressed: bool) -> void:
	get_tree().debug_collisions_hint = button_pressed
	# must toggle 
	_force_update_show_coll_shapes(get_tree().root)

func _on_apply_pressed() -> void:
	Settings.save()
	apply.emit()
	left_saber_col.get_popup().hide()
	right_saber_col.get_popup().hide()


func _on_master_slider_value_changed(value: float) -> void:
	Settings.audio_master = value

func _on_music_slider_value_changed(value: float) -> void:
	Settings.audio_music = value

func _on_sfx_slider_value_changed(value: float) -> void:
	Settings.audio_sfx = value

func _on_spectator_view_toggled(value: bool) -> void:
	Settings.spectator_view = value

func _on_spectator_hud_toggled(value: bool) -> void:
	Settings.spectator_hud = value

# Performance rows. The values are only stored here; BeepSaber_Game.on_settings_changed applies
# them, so there is exactly one place that talks to the XR session.
func _on_refresh_rate_item_selected(index: int) -> void:
	if index < 0 or index >= _refresh_rates.size():
		return
	Settings.display_refresh_rate = _refresh_rates[index]

func _on_render_scale_value_changed(value: float) -> void:
	Settings.render_scale = value
	_update_render_scale_label()

func _on_msaa_item_selected(index: int) -> void:
	if index < 0 or index >= MSAA_VALUES.size():
		return
	Settings.msaa_3d = MSAA_VALUES[index]

func _on_foveation_item_selected(index: int) -> void:
	if index < 0 or index >= FOVEATION_LABELS.size():
		return
	Settings.foveation_level = index


func _on_recenter_button_up() -> void:
	var recenter_button : Button = $ScrollContainer/VBox/recenter
	recenter_button.disabled = true
	recenter_button.text = "3.."
	await get_tree().create_timer(1).timeout
	recenter_button.text = "2.."
	await get_tree().create_timer(1).timeout
	recenter_button.text = "1.."
	await get_tree().create_timer(1).timeout
	recenter_button.text = "Recenter"
	recenter_button.disabled = false
	beepsaber_game.recenter()
# One row for the three GPU levers, inserted above the sky choice. Their individual names
# (render scale / MSAA / foveation) mean nothing to a player, and they are only meaningful
# together: the measured curve is Quality ~86% GPU, Balanced ~75%, Performance ~64%.
func _populate_perf_preset() -> void:
	# Refreshing the controls (which "Default" triggers) must reuse the row that already exists.
	# Creating it unconditionally appended another identical row on every press, and nothing ever
	# removed them - the player ended up with a stack of "Performance:" rows.
	var vbox := $ScrollContainer/VBox
	if perf_control != null and is_instance_valid(perf_control):
		perf_control.select(clampi(Settings.perf_preset, 0, 2))
		return
	var existing := vbox.get_node_or_null("PerfPresetRow")
	if existing != null:
		existing.queue_free()
	var row := HBoxContainer.new()
	row.name = "PerfPresetRow"
	var label := Label.new()
	label.text = "Performance:  "
	perf_control = OptionButton.new()
	perf_control.add_item("Quality (sharpest)")
	perf_control.add_item("Balanced")
	perf_control.add_item("Performance (smoothest)")
	perf_control.select(clampi(Settings.perf_preset, 0, 2))
	perf_control.item_selected.connect(_on_perf_preset_selected)
	row.add_child(label)
	row.add_child(perf_control)
	vbox.add_child(row)
	if sky_style_control != null:
		vbox.move_child(row, sky_style_control.get_index())

func _on_perf_preset_selected(index: int) -> void:
	Settings.perf_preset = index
	Settings._apply_perf_preset(index)
