extends Panel
class_name SettingsPanel

signal apply()
@export var beepsaber_game : BeepSaber_Game

@onready var saber_control := %saber as OptionButton
# Visual additions (FR-045..FR-048).
@onready var floor_light_control := %floor_light as CheckButton
@onready var saber_halo_control := %saber_halo as CheckButton
@onready var mirror_reflections_control := %mirror_reflections as CheckButton
@onready var saber_tail_control := %saber_tail as CheckButton
# Round 2 visual additions (specs/007-visual-options). Each one is its own switch, like the
# rows above; the tooltip states the cost.
@onready var hit_flash_control := %hit_flash as CheckButton
@onready var floor_grid_control := %floor_grid as CheckButton
@onready var event_tint_control := %event_tint as CheckButton
@onready var debris_cap_control := %debris_cap as CheckButton
@onready var debris_shards_control := %debris_shards as CheckButton
@onready var environment_mode_control := %environment_mode as OptionButton
@onready var glow_mode_control := %glow_mode as OptionButton
@onready var hit_sound_control := %hit_sound as OptionButton
@onready var audio_ducking_control := %audio_ducking as CheckButton
@onready var sky_style_control := %sky_style as OptionButton
var perf_control: OptionButton
@onready var saber_thickness := %saber_thickness as HSlider
@onready var cut_blocks := %cut_blocks as CheckButton
@onready var d_background := %d_background as CheckButton
@onready var left_saber_col := %left_saber_col as ColorPickerButton
@onready var right_saber_col := %right_saber_col as ColorPickerButton
@onready var show_debug_control := %show_debug as CheckButton
@onready var show_collisions := %show_collisions as CheckButton
@onready var bombs_enabled_control := %bombs_enabled as CheckButton
@onready var ui_volume_slider := %ui_volume_slider as HSlider
@onready var disable_map_color_control := %disable_map_color as CheckButton
@onready var upload_server_control := %upload_server as CheckButton
@onready var left_saber_posx_control := %left_posx as SpinBox
@onready var left_saber_posy_control := %left_posy as SpinBox
@onready var left_saber_posz_control := %left_posz as SpinBox
@onready var left_saber_rotx_control := %left_rotx as SpinBox
@onready var left_saber_roty_control := %left_roty as SpinBox
@onready var left_saber_rotz_control := %left_rotz as SpinBox
@onready var right_saber_posx_control := %right_posx as SpinBox
@onready var right_saber_posy_control := %right_posy as SpinBox
@onready var right_saber_posz_control := %right_posz as SpinBox
@onready var right_saber_rotx_control := %right_rotx as SpinBox
@onready var right_saber_roty_control := %right_roty as SpinBox
@onready var right_saber_rotz_control := %right_rotz as SpinBox
@onready var player_height_offset_control := %pos as SpinBox
@onready var audio_master_control := %master_slider as HSlider
@onready var audio_music_control := %music_slider as HSlider
@onready var audio_sfx_control := %sfx_slider as HSlider
@onready var spectator_view_control := %spectator_view as CheckButton
@onready var spectator_hud_control := %spectator_hud as CheckButton

# Performance rows (FR-040). Each one is hidden when the running XR interface cannot apply it.
@onready var refresh_rate_row := %RefreshRateRow as HBoxContainer
@onready var refresh_rate_control := %refresh_rate as OptionButton
@onready var render_scale_control := %render_scale as HSlider
@onready var render_scale_value := %render_scale_value as Label
@onready var msaa_control := %msaa as OptionButton
@onready var foveation_row := %FoveationRow as HBoxContainer
@onready var foveation_control := %foveation as OptionButton

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
	_build_tabs()

# The list used to be wider than the panel, which produced a horizontal scrollbar and cut words off
# at the right edge. Horizontal scrolling is disabled and labels wrap instead, so the list only ever
# moves vertically.
func _fit_scroll_area() -> void:
	var scroll := %ScrollContainer as ScrollContainer
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_allow_wrapping(scroll.get_node("VBox"))

func _allow_wrapping(node: Node) -> void:
	for child in node.get_children():
		# Only full-width text (a Label that sits directly in the vertical list) should wrap and
		# expand. A Label inside an HBox row is a column heading - wrapping it turns
		# "Left Saber Offset:" into three lines and squeezes the spin boxes next to it.
		var in_row := child.get_parent() is HBoxContainer
		if not in_row:
			# Label, Button and CheckButton all expose autowrap_mode in Godot 4; the `in` guard
			# keeps this from erroring on any other control type in the list.
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

# Ranges live in Settings.SCHEMA, so a slider cannot offer a value its setter would clamp away and
# a config.ini cannot hold a value the panel could never produce. The authored range in the scene
# is only a fallback for a control whose key has no schema range.
func _apply_schema_ranges() -> void:
	var sliders := [
		[saber_thickness, &"thickness"],
		[ui_volume_slider, &"ui_volume"],
		[render_scale_control, &"render_scale"],
		[audio_master_control, &"audio_master"],
		[audio_sfx_control, &"audio_sfx"],
		[audio_music_control, &"audio_music"],
	]
	for pair: Array in sliders:
		var control: Range = pair[0]
		var spec: Dictionary = Settings.SCHEMA.get(String(pair[1]), {})
		if not spec.has("min"):
			continue
		control.min_value = spec["min"]
		control.max_value = spec["max"]
		control.step = spec.get("step", control.step)

# An option button offers exactly the range the setter accepts: the last index is the schema max.
func _schema_max(key: StringName) -> int:
	var spec: Dictionary = Settings.SCHEMA.get(String(key), {})
	return int(spec.get("max", 0))

func set_controls_from_settings() -> void:
	_apply_schema_ranges()
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
		environment_mode_control.add_item("Environment: Auto (map)")
		environment_mode_control.add_item("Environment: Classic")
	environment_mode_control.select(clampi(Settings.environment_mode, 0, _schema_max(&"environment_mode")))
	if glow_mode_control.item_count == 0:
		glow_mode_control.add_item("Glow: Off")
		glow_mode_control.add_item("Glow: Subtle")
		glow_mode_control.add_item("Glow: Full")
	glow_mode_control.select(clampi(Settings.glow_mode, 0, _schema_max(&"glow_mode")))
	if hit_sound_control.item_count == 0:
		hit_sound_control.add_item("Hit sound: Classic")
		hit_sound_control.add_item("Hit sound: Thump")
	hit_sound_control.select(clampi(Settings.hit_sound, 0, _schema_max(&"hit_sound")))
	audio_ducking_control.button_pressed = Settings.audio_ducking
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
	_snapshot_settings()
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
	foveation_control.select(clampi(Settings.foveation_level, 0, _schema_max(&"foveation_level")))
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

func _on_glow_mode_selected(index: int) -> void:
	Settings.glow_mode = index

func _on_hit_sound_selected(index: int) -> void:
	Settings.hit_sound = index

func _on_audio_ducking_toggled(button_pressed: bool) -> void:
	Settings.audio_ducking = button_pressed

func _populate_sky_style() -> void:
	if sky_style_control.item_count == 0:
		# These option buttons are full-width bars with no separate label, so each item names
		# its own setting. "Auto (map)" alone left the player guessing what it belonged to.
		sky_style_control.add_item("Sky: Black void")
		sky_style_control.add_item("Sky: Gradient")
		sky_style_control.add_item("Sky: Panorama")
	sky_style_control.select(clampi(Settings.sky_style, 0, _schema_max(&"sky_style")))

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
	var recenter_button : Button = %recenter
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
	var vbox := %ScrollContainer/VBox
	if perf_control != null and is_instance_valid(perf_control):
		perf_control.select(clampi(Settings.perf_preset, 0, _schema_max(&"perf_preset")))
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
	perf_control.select(clampi(Settings.perf_preset, 0, _schema_max(&"perf_preset")))
	perf_control.item_selected.connect(_on_perf_preset_selected)
	row.add_child(label)
	row.add_child(perf_control)
	vbox.add_child(row)
	if sky_style_control != null:
		vbox.move_child(row, sky_style_control.get_index())

func _on_perf_preset_selected(index: int) -> void:
	Settings.perf_preset = index
	Settings._apply_perf_preset(index)

# --- Tabs (v4 FR-004/tabs) -----------------------------------------------------------------
# The panel is one long list; the player asked for tabs. The advisor's layout: a top bar, five
# tabs, and hidden rows simply not visible (a hidden Control gets no input, so the ray cannot hit
# a control on another tab). Rows are hidden in place rather than rebuilt, so scroll positions and
# control state survive a tab switch; the stick scroller keeps pointing at the same container.
const TAB_NAMES := ["Audio", "Sabers", "Visuals", "Performance", "Debug"]
const TAB_ROWS := {
	0: ["audio", "hit_sound", "audio_ducking", "UI_VolumeRow"],
	1: ["recenter", "cut_blocks", "bombs_enabled", "SaberThicknessRow", "SaberTypeRow",
		"SaberColorsRow", "left_saber_offset", "right_saber_offset", "player_height_offset"],
	2: ["d_background", "floor_light", "saber_halo", "mirror_reflections", "saber_tail",
		"hit_flash", "floor_grid", "event_tint", "debris_shards", "debris_cap",
		"environment_mode", "glow_mode", "sky_style", "disable_map_color"],
	3: ["PerfHeader", "RefreshRateRow", "RenderScaleRow", "MSAARow", "FoveationRow", "PerfNote",
		"PerfPresetRow"],
	4: ["show_debug", "show_collisions", "spectator_view", "spectator_hud", "upload_server"],
}

var _tab_buttons: Array[Button] = []
var _tab := 2

func _build_tabs() -> void:
	if not _tab_buttons.is_empty():
		return
	var bar := HBoxContainer.new()
	bar.name = "TabBar"
	bar.position = Vector2(16, 46)
	bar.size = Vector2(864, 34)
	bar.add_theme_constant_override("separation", 6)
	for i in TAB_NAMES.size():
		var b := Button.new()
		b.text = TAB_NAMES[i]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(160, 32)
		b.pressed.connect(_on_tab_pressed.bind(i))
		bar.add_child(b)
		_tab_buttons.append(b)
	add_child(bar)
	# Make room for the bar without touching the list's authored width.
	var sc := %ScrollContainer as Control
	sc.offset_top += 84
	_set_tab(_tab)

func _on_tab_pressed(index: int) -> void:
	_set_tab(index)

func _set_tab(index: int) -> void:
	_tab = clampi(index, 0, TAB_NAMES.size() - 1)
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = i == _tab
	var vbox := %ScrollContainer/VBox
	for tab: int in TAB_ROWS:
		for row_name: String in TAB_ROWS[tab]:
			var row := vbox.get_node_or_null(NodePath(row_name))
			if row is CanvasItem:
				(row as CanvasItem).visible = tab == _tab
			elif row != null and "visible" in row:
				row.visible = tab == _tab
	(%ScrollContainer as ScrollContainer).scroll_vertical = 0

# --- Back (v4 FR-004) ----------------------------------------------------------------------
# Settings apply live (resolution, foveation and colours change as you touch them), so Back has
# to put the values back, not merely skip Settings.save().
var _snapshot := {}

func _snapshot_settings() -> void:
	_snapshot.clear()
	for key: String in Settings.default_values:
		_snapshot[key] = Settings.get(key)

func _on_back_pressed() -> void:
	for key: String in _snapshot:
		Settings.set(key, _snapshot[key])
	# Same close path as Apply, but no Settings.save(): the file keeps the last applied state.
	apply.emit()
