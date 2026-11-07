# This is a stand-alone version of the demo game Beep Saber. It started (and is still included)
# in the godot oculus quest toolkit (https://github.com/NeoSpark314/godot_oculus_quest_toolkit)
# But this stand-alone version as additional features and will be developed independently
# This file contains the main game logic for the BeepSaber demo implementation
extends Node3D
class_name BeepSaber_Game

var version := str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
# Set by the benchmark runner's `hud_off` arm. A plain member, because the runner class is not in
# release builds (specs/013 FR-004).
var bench_hud_disabled := false

var gamestate_bootup := GameState.new()
var gamestate_mapcomplete := GameStateMapComplete.new()
var gamestate_mapselection := GameStateMapSelection.new()
var gamestate_newhighscore := GameStateNewHighScore.new()
var gamestate_paused := GameStatePaused.new()
var gamestate_playing := GameStatePlaying.new()
var gamestate_settings := GameStateSettings.new()
var gamestate: GameState = gamestate_bootup

@onready var xr_origin := $XROrigin3D as XROrigin3D
@onready var left_controller := $XROrigin3D/LeftController as BeepSaberController
@onready var right_controller := $XROrigin3D/RightController as BeepSaberController
@onready var left_saber := $XROrigin3D/LeftController/LeftLightSaber as LightSaber
@onready var right_saber := $XROrigin3D/RightController/RightLightSaber as LightSaber
@onready var left_ui_raycast := $XROrigin3D/LeftController/LeftLightSaber/UIRaycast as UIRaycast
@onready var right_ui_raycast := $XROrigin3D/RightController/RightLightSaber/UIRaycast as UIRaycast

const ScreenshotServiceScript := preload("res://game/scripts/ScreenshotService.gd")
# In-game capture (specs/024). Created after vr.initialize so it has the XR camera.
var screenshot: ScreenshotService
var _trigger_hold_start := -1
var _trigger_latched := false
@onready var goggles_shader := ($XROrigin3D/XRCamera3D/VRGoggles as MeshInstance3D).material_override as ShaderMaterial
@onready var debug_info_label := $XROrigin3D/XRCamera3D/PlayerHead/DebugInfoLabel as MeshInstance3D

@onready var main_menu := $MainMenu_OQ_UI2DCanvas as OQ_UI2DCanvas
@onready var pause_menu := $PauseMenu_canvas as OQ_UI2DCanvas
@onready var pause_countdown := $Pause_countdown as OQ_UI2DLabel
@onready var settings_canvas := $Settings_canvas as OQ_UI2DCanvas
@onready var settings_panel := settings_canvas.ui_control as SettingsPanel
@onready var highscore_canvas := $Highscores_Canvas as OQ_UI2DCanvas
@onready var highscore_panel := highscore_canvas.ui_control as HighscorePanel
@onready var leaderboard_canvas := $Leaderboard_Canvas as OQ_UI2DCanvas
# Untyped on purpose: the panel's class_name is not in the editor's global class cache on a
# clean clone (same reason as the profile panel).
@onready var leaderboard_panel = leaderboard_canvas.ui_control
@onready var name_selector_canvas := $NameSelector_Canvas as OQ_UI2DCanvas
@onready var highscore_keyboard := $Keyboard_highscore as OQ_UI2DKeyboard
@onready var endscore := $EndScore as EndScore

# Untyped on purpose: the panel's class_name is not in the editor's global class cache on a
# clean clone.
@onready var profile_canvas := $Profile_canvas as OQ_UI2DCanvas
@onready var profile_panel = profile_canvas.ui_control

@onready var points_label_driver := $Points_label_driver as PointsLabelDriver
@onready var event_driver := $event_driver as EventDriver

@onready var multiplier_label := $Multiplier_Label as MeshInstance3D
@onready var point_label := $Point_Label as MeshInstance3D
@onready var percent_indicator := $Percent_Indicator as PercentIndicator

@onready var map_source_dialogs := $MapSourceDialogs as Node3D
@onready var storage_canvas := $Storage_Canvas as OQ_UI2DCanvas
@onready var storage_panel = storage_canvas.ui_control
@onready var online_search_keyboard := $Keyboard_online_search as OQ_UI2DKeyboard

@onready var cube_template := preload("res://game/BeepCube/BeepCube.tscn").instantiate() as BeepCube

@onready var track := $Track as Node3D
@onready var standing_ground := $StandingGround as Floor

@onready var song_player := $SongPlayer as AudioStreamPlayer

@onready var menu := main_menu.ui_control as MainMenu

# Spike attribution (FR-033): per-path counters, cheap when off.
const Cost := preload("res://game/scripts/CostProbe.gd")

# What the HUD TextMeshes currently read. -1 forces the first write after a load.
var _shown_points := -1
var _shown_multiplier := -1
var _shown_combo := -1


# There's an interesting issue where the AudioStreamPlayer's playback_position
# doesn't immediately return to 0.0 after restarting the song_player. This
# causes issues with restarting a map because the process_physics routine will
# execute for a times and attempt to process the map up to the playback_position
# prior to the AudioStreamPlayer restart. This bug can presents itself as notes
# persisting between map restarts.
# To remidy this issue, this flag is set to true when the map is restarted. The
# process_physics routine won't begin processing the map until after the
# AudioStreamPlayer has reset it's playback_position to zero. This flag is set
# to false once the AudioStreamPlayer reset is detected.
var _audio_synced_after_restart := false

var _in_wall := false

#prevents the song for starting from the start when pausing and unpausing
var pause_position := 0.0

func start_map(info: MapInfo, map_difficulty: DifficultyInfo) -> void:
	var map_filename := info.filepath + map_difficulty.beatmap_filename
	var map_data := vr.load_json_file(map_filename)
	# v4 keeps every lighting event in a separate lightshow file (FR: map formats v2/v3/v4).
	var lightshow_data := {}
	# v4 tempo lives in the audio file (FR-025), not in the beatmap.
	var audio_data := {}
	if info.version.begins_with("4."):
		audio_data = vr.load_json_file(info.filepath + "AudioData.dat")
		if audio_data == null:
			audio_data = {}
	if not map_difficulty.lightshow_filename.is_empty():
		lightshow_data = vr.load_json_file(info.filepath + map_difficulty.lightshow_filename)
		if lightshow_data == null:
			lightshow_data = {}
	
	# a new song starts with nothing on the end screen to re-attribute
	_saved_record = {}
	# ...and with no light event carried over from the last one (FR-005).
	_event_tint = Color.WHITE
	
	if (map_data == null):
		vr.log_error("Could not read map data from " + map_filename)
	if not Map.load_beatmap(info, map_difficulty, map_data, lightshow_data, audio_data):
		return
	
	_apply_map_colours()
	if MapData.event_stack.is_empty():
		event_driver.set_all_on(MapPalette.env_left, MapPalette.env_right)
	else:
		event_driver.set_all_off()
	
	vr.log_info("loading: " + info.filepath + info.song_filename)
	song_player.stream = AudioStreamOggVorbis.load_from_file(info.filepath + info.song_filename)
	
	_audio_synced_after_restart = false
	song_player.play(0.0)
	song_player.volume_db = 0.0
	_in_wall = false
	Scoreboard.restart()
	
	_display_points()
	percent_indicator.start_map()
	
	_clear_track()
	_transition_game_state(gamestate_playing)

# This function will transitioning the game from it's current state into
# the provided 'next_state'.
func _transition_game_state(next_state: GameState) -> void:
	gamestate = next_state
	gamestate._ready(self)

func show_MapSourceDialogs(showing: bool = true) -> void:
	map_source_dialogs.visible = showing
	if storage_canvas != null and not showing:
		storage_canvas._hide()
	for c in map_source_dialogs.get_children():
		if c is OQ_UI2DCanvas:
			(c as OQ_UI2DCanvas)._hide()
	if showing:
		var first_dialog := map_source_dialogs.get_child(0)
		if first_dialog is OQ_UI2DCanvas:
			(first_dialog as OQ_UI2DCanvas)._show()

func _check_and_update_saber(controller: BeepSaberController, saber: LightSaber) -> void:
	# to allow extending/sheething the saber while not playing a song
	if ((not song_player.playing)
		and (controller.ax_just_pressed() or controller.by_just_pressed())
		and (not saber._anim.is_playing())):
		if (saber.is_extended()): saber._hide()
		else: saber._show()
	
	# check for saber rumble (only when extended and not already rumbling)
	# this check is necessary to not overwrite a rumble set from somewhere else
	# (in this case it can come from cutting cubes)
	if not controller.is_simple_rumbling(): 
		if _in_wall:
			# weak rumble on both controllers when player is inside wall
			controller.simple_rumble(0.1, 0.1)
		elif saber.get_overlapping_areas().size() > 0 or saber.get_overlapping_bodies().size() > 0:
			# strong rumble when saber is cutting into wall or other saber
			controller.simple_rumble(0.5, 0.1)
		else:
			controller.simple_rumble(0.0, 0.1)


func _physics_process(_dt: float) -> void:
	if debug_info_label.visible:
		var dbg_text := "FPS: %d\nCube Pool: %d free of %d\nLink Pool: %d free of %d" % [
			Engine.get_frames_per_second(),
			GlobalReferences.cube_pool.free_count(), GlobalReferences.cube_pool.total_count(),
			GlobalReferences.link_pool.free_count(), GlobalReferences.link_pool.total_count()]
		(debug_info_label.mesh as TextMesh).text = dbg_text
	
	gamestate._physics_process(self)
	
	_check_and_update_saber(left_controller, left_saber)
	_check_and_update_saber(right_controller, right_saber)
	_poll_screenshot_trigger()

func _poll_screenshot_trigger() -> void:
	if screenshot == null or not Settings.screenshot_trigger:
		return
	# Players clench both triggers while swinging, and each capture can stall; the combo is for
	# menus and the end screen only. Gameplay shots use Pause -> Screenshot.
	if gamestate == gamestate_playing or gamestate == gamestate_paused:
		_trigger_hold_start = -1
		_trigger_latched = false
		return
	var both := left_controller.trigger_pressed() and right_controller.trigger_pressed()
	if not both:
		_trigger_hold_start = -1
		_trigger_latched = false
		return
	if _trigger_latched:
		return
	var now := Time.get_ticks_msec()
	if _trigger_hold_start < 0:
		_trigger_hold_start = now
	if now - _trigger_hold_start >= 500:
		_trigger_latched = true
		_trigger_hold_start = -1
		screenshot.capture()


func _on_screenshot_button() -> void:
	if screenshot != null:
		screenshot.capture_from([pause_menu, left_ui_raycast, right_ui_raycast])


func _enter_tree() -> void:
	GlobalReferences.main_game_scene = self
	
	@warning_ignore("return_value_discarded")
	Settings.changed.connect(on_settings_changed)

func _ready() -> void:
	# pre-allocate scenes in our scene pools
	GlobalReferences.cube_pool = $BeepCubePool
	GlobalReferences.link_pool = $ChainLinkPool
	GlobalReferences.wall_pool = $WallPool
	GlobalReferences.cube_pool.presize(100)
	GlobalReferences.link_pool.presize(100)
	# Wall maps spawn tens of walls a second (Gloom: 12,340 in one song). Measured peak usage on
	# that map is 569 live walls, so a pool below that grows during play; 256 covers every normal
	# map without presizing 570 nodes at startup, and the growth on Gloom is amortised.
	GlobalReferences.wall_pool.presize(256)
	
	var xr_camera := $XROrigin3D/XRCamera3D as XRCamera3D
	vr.initialize(
		xr_origin,
		xr_camera,
		left_controller,
		right_controller
	)

	screenshot = ScreenshotServiceScript.new()
	screenshot.name = "ScreenshotService"
	screenshot.xr_camera = xr_camera
	add_child(screenshot)

	# Godot does not honour xr/openxr/render_target_size_multiplier from project.godot on this
	# path: measured render_target_size stayed at the runtime's recommended 1680x1760 with the
	# setting present in the build. Apply it explicitly so the eye buffers actually render at
	# (or above) the panel's native resolution instead of ~81% of it. Same for the refresh rate,
	# MSAA and foveation: all four now come from Settings so the panel can change them.
	_apply_render_settings()

	debug_info_label.visible = Settings.show_debug_info
	set_colors_from_settings()
	_apply_sky()
	_capture_glow_levels()
	_apply_glow()
	@warning_ignore("return_value_discarded")
	event_driver.light_event_color.connect(_on_light_event_color)
	_apply_light_tint()
	
	if not vr.inVR:
		xr_origin.add_child(preload("res://OQ_Toolkit/OQ_ARVROrigin/Feature_VRSimulator.tscn").instantiate())
	
	UI_AudioEngine.attach_children(highscore_keyboard)
	UI_AudioEngine.attach_children(online_search_keyboard)
	
	_transition_game_state(gamestate_mapselection)
	
	@warning_ignore("return_value_discarded")
	Scoreboard.score_changed.connect(_display_points)
	@warning_ignore("return_value_discarded")
	Scoreboard.points_awarded.connect(points_label_driver.show_points)
	
	#render common assets for a couple of frames to prevent performance issues when loading them mid game
	($pre_renderer as Node3D).visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	($pre_renderer as Node3D).queue_free()
	
	recenter()

	# React to the headset's own recenter (Meta button). The OpenXR docs are explicit that the
	# game must re-orient on `pose_recentered`: in stage/local-floor spaces the runtime does not
	# move our XROrigin3D, so ignoring it leaves the play space and UI rotated by whatever
	# alignment offset this game applied at startup - observed in play as the menu sitting ~45
	# degrees to the left after pressing the Meta button.
	var xr_iface := XRServer.primary_interface
	if xr_iface != null and xr_iface.has_signal("pose_recentered"):
		if not xr_iface.pose_recentered.is_connected(_on_pose_recentered):
			xr_iface.pose_recentered.connect(_on_pose_recentered)

	# Prewarm the arc ribbon. Arcs are instantiated per spawn rather than pooled, and they
	# carry a material_override - which Godot's mesh pipeline precompile step explicitly does
	# not cover - so the first arc of a song can compile a pipeline on the main thread mid-play.
	# Bombs and walls are instantiated per spawn the same way, so they get the same treatment:
	# the first of each used to cost a first-of-song hitch.
	var arc_warm := preload("res://game/Arc/Arc.tscn").instantiate()
	track.add_child(arc_warm)
	var bomb_warm := preload("res://game/Bomb/Bomb.tscn").instantiate()
	track.add_child(bomb_warm)
	var wall_warm := preload("res://game/Wall/Wall.tscn").instantiate()
	track.add_child(wall_warm)
	await get_tree().process_frame
	await get_tree().process_frame
	arc_warm.queue_free()
	bomb_warm.queue_free()
	wall_warm.queue_free()

	# Deterministic benchmark mode. The runner is normally debug-only; a sideloaded flag opts a
	# release build in, so a device run can be measured without shipping a debug APK (0.7.5).
	var runner: Script = load("res://game/scripts/BenchmarkRunner.gd")
	if runner != null:
		if not OS.has_feature("release") or bool(runner.call("has_bench_flag")):
			var instance: Node = runner.call("new", self)
			if instance != null and bool(instance.call("is_flagged")):
				add_child(instance)
			elif instance != null:
				instance.free()

# Applies the four settings that decide what the headset actually renders. Called once at
# startup, and again per setting whenever the user changes it (see on_settings_changed).
# Everything here is a no-op when the API in question is missing, so a runtime without the
# OpenXR FB extensions still boots.
func _apply_render_settings() -> void:
	_apply_display_refresh_rate()
	_apply_render_scale(Settings.render_scale)
	_apply_msaa()
	_apply_foveation_level()

# Refresh rate + physics cadence. Physics is pinned to the rate the panel ACTUALLY runs at, not
# the one we asked for: requesting 90 on a runtime that only offers 72 must not leave physics
# sampling at 90 (which would burn CPU for no visual gain, and desynchronise saber sampling).
func _apply_display_refresh_rate() -> void:
	var iface := XRServer.primary_interface
	if iface == null:
		return
	var target_hz := _resolve_refresh_rate(Settings.display_refresh_rate)
	if target_hz <= 0.0:
		return
	if iface.has_method(&"set_display_refresh_rate"):
		iface.call(&"set_display_refresh_rate", target_hz)
	if target_hz > 0.0:
		Engine.physics_ticks_per_second = int(round(target_hz))
	vr.log_info("display refresh requested %.0f Hz -> using %.0f Hz, physics %d Hz" % [
		Settings.display_refresh_rate, target_hz, Engine.physics_ticks_per_second])

# Picks the nearest rate the headset actually offers. A stored value from another headset (e.g.
# 120 from a Quest 3 on a 90 Hz device) must not be requested blindly.
func _resolve_refresh_rate(want_hz: float) -> float:
	if want_hz <= 0.0:
		return 0.0
	var iface := XRServer.primary_interface
	if iface == null or not iface.has_method(&"get_available_display_refresh_rates"):
		return want_hz
	var avail: Array = iface.call(&"get_available_display_refresh_rates")
	if avail.is_empty():
		return want_hz
	var best := 0.0
	var best_delta := INF
	for rate in avail:
		var hz := absf(float(rate))
		if hz <= 0.0:
			continue
		var delta := absf(hz - want_hz)
		if delta < best_delta:
			best_delta = delta
			best = hz
	return best if best > 0.0 else want_hz

# OpenXR consumes render_target_size_multiplier every frame and frees/recreates its main
# swapchains when the resulting size changes (OpenXRAPI::process), so this is live - it costs
# one frame of hitch, which is why the slider is debounced by the caller.
func _apply_render_scale(scale: float) -> void:
	var iface := XRServer.primary_interface
	if iface == null or not iface.has_method(&"set_render_target_size_multiplier"):
		return
	iface.call(&"set_render_target_size_multiplier", scale)
	vr.log_info("render scale %.4f applied" % scale)

var _render_scale_generation := 0

# A slider drag fires value_changed on every step; each step would recreate the eye swapchains.
# Coalesce them so the change is applied once, shortly after the user stops moving the slider.
func _apply_render_scale_debounced(scale: float) -> void:
	_render_scale_generation += 1
	var generation := _render_scale_generation
	await get_tree().create_timer(0.4).timeout
	if generation != _render_scale_generation:
		return
	_apply_render_scale(scale)

# MSAA regenerates render pipelines, so this is a menu-only change (the settings panel is only
# reachable from the main menu - GameState/Playing.gd hides it). The panel warns about the hitch.
func _apply_msaa() -> void:
	var vp := get_viewport()
	if vp.msaa_3d == Settings.msaa_3d:
		return
	vp.msaa_3d = Settings.msaa_3d
	vr.log_info("msaa_3d set to %d" % Settings.msaa_3d)

# Fixed foveated rendering (XR_FB_foveation). Applied to the live swapchain via
# xrUpdateSwapchainFB, and re-applied by the runtime whenever the swapchains are recreated.
func _apply_foveation_level() -> void:
	var iface := XRServer.primary_interface
	if iface == null:
		return
	if iface.has_method(&"is_foveation_supported") and not bool(iface.call(&"is_foveation_supported")):
		return
	if iface.has_method(&"set_foveation_level"):
		iface.call(&"set_foveation_level", Settings.foveation_level)
		vr.log_info("foveation level %d applied" % Settings.foveation_level)

func on_settings_changed(key: StringName) -> void:
	# ensures proper initialization of tree for proper first frame setting loading
	await get_tree().process_frame
	match key:
		&"color_left":
			update_left_color(Settings.color_left)
			update_arc_colors()
		&"color_right":
			update_right_color(Settings.color_right)
			update_arc_colors()
		&"events":
			disable_events(not Settings.events)
		&"show_debug_info":
			debug_info_label.visible = Settings.show_debug_info
		&"player_height_offset":
			xr_origin.transform.origin.y = Settings.player_height_offset
		&"display_refresh_rate":
			_apply_display_refresh_rate()
		&"render_scale":
			_apply_render_scale_debounced(Settings.render_scale)
		&"msaa_3d":
			_apply_msaa()
		&"foveation_level":
			_apply_foveation_level()
		# Visual additions. The saber halo lives on the saber visual, which listens for its
		# own key; these only change how the floor is drawn.
		&"floor_light", &"mirror_reflections", &"floor_grid", &"hit_flash":
			standing_ground.apply_visual_settings()
		&"event_tint":
			_apply_light_tint()
		&"sky_style":
			_apply_sky()
		# FR-013: one pool for the whole game, so the switch is one node's visibility.
		&"debris_shards":
			if DebrisField.instance != null:
				DebrisField.instance.set_enabled(Settings.debris_shards)
		&"debris_cap":
			pass
		&"environment_mode":
			Map.set_colors_from_custom_data()
			_apply_map_colours()
		&"glow_mode":
			_apply_glow()

# --- Light tint (specs/007-visual-options FR-005) ---------------------------------------
#
# The map's light events tint the light the blades throw. The tint is applied ONCE, here, and
# published as `light_left`/`light_right`; the floor shader and the glow strip only READ that
# value and never multiply a tint of their own (007 rule 6). Until now nothing wrote these
# globals at all, so the floor streak and the blade glow sat on the project.godot defaults
# (red/blue) whatever colour the blades or the map actually were.
#
# Strength is 0.5, not 1.0: at full strength a red event drives the blue blade's light down
# to the brightness floor, which reads as the blade losing its colour rather than as the room
# changing colour.
const EVENT_TINT_STRENGTH := 0.5
# Blade light never disappears: every channel keeps at least this share of the blade colour.
const EVENT_TINT_BRIGHTNESS_FLOOR := 0.35

var _event_tint := Color.WHITE

func _on_light_event_color(color: Color) -> void:
	_event_tint = color
	_apply_light_tint()

func _apply_light_tint() -> void:
	# `events` off means the map's whole lighting system is off, so there is nothing to tint
	# by: the blades get their own colour back rather than the last event's.
	var k := EVENT_TINT_STRENGTH if (Settings.event_tint and Settings.events) else 0.0
	RenderingServer.global_shader_parameter_set(
		&"light_left", _tinted_light(left_saber.light_color, k))
	RenderingServer.global_shader_parameter_set(
		&"light_right", _tinted_light(right_saber.light_color, k))

# lerp(blade, blade * tint, k) per channel, floored so a lights-off (black) event dims the
# blade light instead of deleting it. Returns the vec3 the shader globals are declared as.
func _tinted_light(base: Color, k: float) -> Vector3:
	return Vector3(
		maxf(lerpf(base.r, base.r * _event_tint.r, k), base.r * EVENT_TINT_BRIGHTNESS_FLOOR),
		maxf(lerpf(base.g, base.g * _event_tint.g, k), base.g * EVENT_TINT_BRIGHTNESS_FLOOR),
		maxf(lerpf(base.b, base.b * _event_tint.b, k), base.b * EVENT_TINT_BRIGHTNESS_FLOOR))

# --- Gradient sky (FR-007) --------------------------------------------------------------
#
# One Sky resource built on first use and swapped in whole, which is what makes it "updates on
# load / setting change" rather than per frame: the sky shader has no TIME, so the engine
# renders it (and its radiance cubemap) once, and assigning a different Sky is the only thing
# that retriggers it. `RADIANCE_SIZE_32` is the smallest the engine offers, which is what the
# ambient filter has to work through.
const SKY_GRADIENT_SHADER := preload("res://game/shaders/sky_gradient.gdshader")
var _panorama_sky: Sky
var _gradient_sky: Sky

# FR-027/FR-028: the room follows the map's environment palette; the sabers keep the note
# colours. Called at map start and when the Environment setting changes.
# FR-031: glow. Godot's default chain is measured at ~1% GPU on Quest 3, so it ships as a
# setting; Subtle keeps one blur level, Full restores Godot's authored levels.
var _glow_base_levels := PackedFloat32Array()

func _capture_glow_levels() -> void:
	_glow_base_levels.clear()
	var env := ($WorldEnvironment as WorldEnvironment).environment
	if env == null:
		return
	for i in range(1, 8):
		_glow_base_levels.append(env.get_glow_level(i))

func _apply_glow() -> void:
	var env := ($WorldEnvironment as WorldEnvironment).environment
	if env == null:
		return
	var mode := Settings.glow_mode
	env.glow_enabled = mode != 0
	vr.log_info("GLOW mode=%d enabled=%s" % [mode, env.glow_enabled])
	if mode == 0:
		return
	env.glow_intensity = 0.6
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	if mode == 1:
		for i in range(1, 8):
			env.set_glow_level(i, 0.0)
		env.set_glow_level(4, 1.0)
	elif _glow_base_levels.size() == 7:
		for i in range(1, 8):
			env.set_glow_level(i, _glow_base_levels[i - 1])

func _apply_map_colours() -> void:
	update_left_color(MapPalette.env_left)
	update_right_color(MapPalette.env_right)
	update_arc_colors()
	# FR-001: the blades are the same colour as the cubes they cut. The map wins unless the
	# player has explicitly overridden colours.
	if not Settings.disable_map_color:
		left_saber.set_color(MapPalette.color_left)
		right_saber.set_color(MapPalette.color_right)
	standing_ground.apply_visual_settings()
	vr.log_info("MAP palette: env=%s notes=%s/%s room=%s/%s wall=%s mode=%d" % [
		MapPalette.environment_name, MapPalette.color_left, MapPalette.color_right, MapPalette.env_left, MapPalette.env_right,
		MapPalette.wall_color, Settings.environment_mode])

func _apply_sky() -> void:
	var env := ($WorldEnvironment as WorldEnvironment).environment
	if env == null:
		return
	if _panorama_sky == null:
		_panorama_sky = env.sky
	if _gradient_sky == null:
		_gradient_sky = Sky.new()
		_gradient_sky.radiance_size = Sky.RADIANCE_SIZE_32
		var sky_mat := ShaderMaterial.new()
		sky_mat.shader = SKY_GRADIENT_SHADER
		_gradient_sky.sky_material = sky_mat

	match Settings.sky_style:
		1:
			env.background_mode = Environment.BG_SKY
			env.sky = _gradient_sky
			env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
			env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		2:
			env.background_mode = Environment.BG_SKY
			env.sky = _panorama_sky
			env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
			env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		_:
			# Black void. The sky used to supply ambient and reflected light, so removing it
			# darkens the blades and notes unless those sources are set explicitly - the
			# advisor flagged this as the trap in a void background, and it is why the
			# ambient colour below is tuned rather than zero.
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.0, 0.0, 0.0)
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.62, 0.62, 0.68)
			env.ambient_light_energy = 1.0
			env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED

func set_colors_from_settings() -> void:
	update_left_color(Settings.color_left)
	update_right_color(Settings.color_right)
	update_arc_colors()

func update_left_color(color: Color) -> void:
	if !left_saber:
		await get_tree().process_frame
	left_saber.set_color(color)
	goggles_shader.set_shader_parameter(&"left_color", color)
	event_driver.update_left_color(color)
	standing_ground.update_left_color(color)
	_apply_light_tint()

func update_right_color(color: Color) -> void:
	if !left_saber:
		await get_tree().process_frame
	right_saber.set_color(color)
	goggles_shader.set_shader_parameter(&"right_color", color)
	event_driver.update_right_color(color)
	standing_ground.update_right_color(color)
	_apply_light_tint()

# Arcs belong to the two notes they join, not to the room: paint them with the map's note
# palette. `update_left_color`/`update_right_color` receive the environment colours for the
# blades/lights, so writing the arcs from there was why every arc came out in the room colour.
func update_arc_colors() -> void:
	var left := Settings.color_left
	var right := Settings.color_right
	if not Settings.disable_map_color and MapPalette.color_left.a > 0.0:
		left = MapPalette.color_left
		right = MapPalette.color_right
	Arc.left_material.set_shader_parameter(&"color", left)
	Arc.left_material_magnet.set_shader_parameter(&"color", left)
	Arc.right_material.set_shader_parameter(&"color", right)
	Arc.right_material_magnet.set_shader_parameter(&"color", right)

func disable_events(disabled: bool) -> void:
	event_driver.disabled = disabled
	if disabled:
		event_driver.set_all_off()
	else:
		event_driver.set_all_on(Settings.color_left, Settings.color_right)
	_apply_light_tint()

func _clear_track() -> void:
	for c in track.get_children():
		if c.has_method("clear_from_track"):
			c.clear_from_track()
		elif c.name.begins_with("Lane"):
			# specs/027 FR-006: a 360 lane is a container, not an object. Release its pooled
			# children and keep the lane for the next map.
			for child in c.get_children():
				if child.has_method("clear_from_track"):
					child.clear_from_track()
				else:
					c.remove_child(child)
					child.queue_free()
		else:
			track.remove_child(c)
			c.queue_free()

func _display_points() -> void:
	var hit_rate: float
	if Scoreboard.right_notes+Scoreboard.wrong_notes > 0:
		hit_rate = Scoreboard.right_notes/(Scoreboard.right_notes+Scoreboard.wrong_notes)
	else:
		hit_rate = 1.0
	
	# FR-033: this runs once per cut (Scoreboard.score_changed) and a TextMesh.text
	# assignment re-triangulates glyphs and re-uploads the mesh. The displayed
	# string is unchanged when the underlying value is unchanged, so only write
	# when it actually differs. Same rendered pixels, fewer mesh rebuilds.
	if bench_hud_disabled:
		return
	if Scoreboard.points != _shown_points:
		_shown_points = Scoreboard.points
		if Cost.enabled: Cost.text_mesh_writes += 1
		(point_label.mesh as TextMesh).text = "Score: %6d" % Scoreboard.points
	if Scoreboard.multiplier != _shown_multiplier or Scoreboard.combo != _shown_combo:
		_shown_multiplier = Scoreboard.multiplier
		_shown_combo = Scoreboard.combo
		if Cost.enabled: Cost.text_mesh_writes += 1
		(multiplier_label.mesh as TextMesh).text = "x %d\nCombo %d" % [Scoreboard.multiplier, Scoreboard.combo]
	percent_indicator.update_percent(hit_rate)

# accessor method for the player name selector UI element
func _name_selector() -> NameSelector:
	return name_selector_canvas.ui_control

func _on_PlayerHead_area_entered(area: Area3D) -> void:
	if area.is_in_group(&"wall"):
		song_player.volume_db = -15.0
		_in_wall = true

func _on_PlayerHead_area_exited(area: Area3D) -> void:
	if area.is_in_group(&"wall"):
		song_player.volume_db = 0.0
		_in_wall = false

# when the song ended we want to display the current score and
# the high score
# Headset idle can suspend the app and leave the audio session dead. On resume, re-seat the music
# stream and poke the mixer; if the headset's system audio is still dead, a reboot is the only fix.
var _audio_recovering := false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		_recover_audio_after_idle()

func _recover_audio_after_idle() -> void:
	if _audio_recovering:
		return
	_audio_recovering = true
	await get_tree().process_frame
	if song_player == null or get_tree().paused or song_player.stream_paused:
		_audio_recovering = false
		return
	var was_playing := song_player.playing
	var resume_at := song_player.get_playback_position()
	var stream := song_player.stream
	if was_playing:
		song_player.stop()
		song_player.stream = null
		await get_tree().process_frame
		song_player.stream = stream
		song_player.play(resume_at)
	var master := AudioServer.get_bus_index(&"Master")
	if master >= 0:
		AudioServer.set_bus_mute(master, true)
		await get_tree().create_timer(0.08).timeout
		AudioServer.set_bus_mute(master, false)
	vr.log_info("AUDIO recovered after resume (was_playing=%s)" % str(was_playing))
	_audio_recovering = false

func _on_song_ended() -> void:
	song_player.stop()
	PlayCount.increment_play_count(Map.current_info,Map.current_difficulty.difficulty_rank)
	
	var new_record := false
	var highscore := Highscores.get_highscore(Map.current_info,Map.current_difficulty.difficulty_rank)
	if highscore == -1:
		# no highscores exist yet
		highscore = Scoreboard.points
	elif Scoreboard.points > highscore:
		# player's score is the new highscore!
		highscore = Scoreboard.points
		new_record = true

	var current_percent := Scoreboard.right_notes/(Scoreboard.right_notes+Scoreboard.wrong_notes)
	
	# FR-005: no name prompt any more. The score is written under the profile that is
	# currently playing, before the board is faded in, and only when it earns a slot - a
	# run that does not make the table must not touch the file at all.
	_saved_record = {}
	_saved_map_info = Map.current_info
	_saved_diff_rank = Map.current_difficulty.difficulty_rank
	if Highscores.is_new_highscore(Map.current_info, Map.current_difficulty.difficulty_rank, Scoreboard.points):
		_saved_record = Highscores.add_highscore(
			Map.current_info,
			Map.current_difficulty.difficulty_rank,
			ProfileManager.current_name(),
			Scoreboard.points,
			ProfileManager.current_id())
	if _saved_record.is_empty():
		endscore.hide_saved()
	else:
		endscore.show_saved_as(ProfileManager.current_name())
	
	endscore.show_score(
		Scoreboard.points,
		highscore,
		current_percent,
		"%s By %s\n%s     Map author: %s" % [
			Map.current_info.song_name,
			Map.current_info.song_author_name,
			Map.current_difficulty.custom_name,
			Map.current_info.level_author_name],
		Scoreboard.full_combo,
		new_record
	)
	
	_transition_game_state(gamestate_mapcomplete)

# --- profiles -------------------------------------------------------------------------
#
# The end screen's "Saved as <name>" line and the main menu's "Playing as: <name>" badge both
# follow ProfileManager. Switching a profile is two taps either way: Users/chip in the menu,
# Switch/chip on the end screen.

var _saved_record: Dictionary = {}
var _saved_map_info: MapInfo = null
var _saved_diff_rank := 0
# true while the panel was opened by the end screen's Switch: choosing a profile then also
# re-attributes the record that was just stored (FR-007)
var _profile_panel_from_endscore := false
# true while the shared keyboard is collecting a name for "+ New"
var _new_user_pending := false
var _main_menu_hidden_by_profile_panel := false

func _users_button() -> void:
	_open_profile_panel(false)


# BeatLeader is read-only, menu-only (specs/020, 028 FR-004..006). It now lives in the
# high-score panel's BeatLeader tab, so there is no second canvas to hide the menu for.
func _leaderboard_button(map_info: MapInfo, diff: DifficultyInfo) -> void:
	if highscore_panel == null:
		return
	highscore_canvas._show()
	highscore_panel.show_beatleader(map_info, diff)

# The centred panel is no longer opened from the menu, but the scene still connects its Close
# signal; keep the handler so the hidden canvas can be dismissed if it is ever shown.
func _on_leaderboard_closed() -> void:
	leaderboard_canvas._hide()

# Storage panel (specs/026): opened from the main menu's Storage button.
func _storage_button() -> void:
	if storage_panel == null or gamestate != gamestate_mapselection:
		return
	storage_panel.open(menu)
	main_menu._hide()
	leaderboard_canvas._hide()
	storage_canvas._show()

func _on_storage_closed() -> void:
	storage_canvas._hide()
	if gamestate == gamestate_mapselection:
		main_menu._show()

func _on_endscore_switch_requested() -> void:
	_open_profile_panel(true)

func _open_profile_panel(move_saved_record: bool) -> void:
	_profile_panel_from_endscore = move_saved_record
	if move_saved_record:
		# the board stays visible but must not swallow the clicks meant for the panel
		endscore.set_buttons_disabled(true)
	elif gamestate == gamestate_mapselection:
		# the menu shares Keyboard_highscore with "+ New" typing, and its buttons sit
		# behind the panel: take it off screen while the panel is up
		main_menu._hide()
		_main_menu_hidden_by_profile_panel = true
	profile_panel.open()
	profile_canvas._show()

# Single teardown for the profile UI. Every GameState calls this, and so does Close, so a
# state change in the middle of name entry can never strand the keyboard on screen.
func hide_profile_panel() -> void:
	_new_user_pending = false
	_set_keyboard_cancelable(false)
	highscore_keyboard._hide()
	profile_canvas._hide()
	_profile_panel_from_endscore = false
	if _main_menu_hidden_by_profile_panel:
		_main_menu_hidden_by_profile_panel = false
		if gamestate == gamestate_mapselection:
			main_menu._show()
	if gamestate == gamestate_mapcomplete:
		endscore.set_buttons_disabled(false)

func _on_profile_user_chosen(id: String) -> void:
	if id == ProfileManager.current_id():
		# already playing as this one: nothing to switch and nothing to rename
		hide_profile_panel()
		return
	var user := ProfileManager.get_user(id)
	if user.is_empty():
		hide_profile_panel()
		return
	_move_saved_record(user)
	ProfileManager.set_current(id)
	hide_profile_panel()

# FR-007: re-attributes the just-saved record to `user`, keeping score and epoch_time. A
# record that has since dropped out of the table is simply left alone; the switch itself
# still happens.
func _move_saved_record(user: Dictionary) -> void:
	if not _profile_panel_from_endscore or _saved_record.is_empty():
		return
	var player_name := String(user.get("name",""))
	# move_record returns the record it re-added, which is what a second Switch has to move
	_saved_record = Highscores.move_record(
		_saved_map_info, _saved_diff_rank, _saved_record, player_name, String(user.get("id","")))
	endscore.show_saved_as(player_name)

func _on_profile_new_user_requested() -> void:
	_new_user_pending = true
	profile_canvas._hide()
	highscore_keyboard._show()
	# with an empty field the Enter key is disabled, so the cancel key is the only way out
	_set_keyboard_cancelable(true)

func _on_keyboard_entered(text: String) -> void:
	if not _new_user_pending:
		return
	_new_user_pending = false
	_set_keyboard_cancelable(false)
	highscore_keyboard._hide()
	# create_user strips the name, refuses an empty one and returns the existing profile when
	# the typed name only differs in case
	var user := ProfileManager.create_user(text)
	if not user.is_empty():
		_move_saved_record(user)
	profile_panel.open()
	profile_canvas._show()

func _on_keyboard_cancel() -> void:
	if not _new_user_pending:
		return
	_new_user_pending = false
	_set_keyboard_cancelable(false)
	highscore_keyboard._hide()
	profile_panel.open()
	profile_canvas._show()

# OQ_UI2DKeyboard keeps its VirtualKeyboard private, so reach it the same way it does. Only
# the "+ New" flow shows the cancel key; the menu's search keyboard keeps its own behaviour.
func _set_keyboard_cancelable(cancelable: bool) -> void:
	var virtual_keyboard := highscore_keyboard.find_child("VirtualKeyboard", true, false)
	if virtual_keyboard != null and virtual_keyboard.has_method(&"set_cancelable"):
		virtual_keyboard.call(&"set_cancelable", cancelable)

func _restart_button() -> void:
	start_map(Map.current_info, Map.current_difficulty)
	endscore.visible = false
	pause_menu.visible = false

func _main_menu_button() -> void:
	_clear_track()
	_transition_game_state(gamestate_mapselection)

func _unpause_button() -> void:
	pause_menu.visible = false
	pause_countdown.visible = true
	track.visible = true
	pause_countdown.set_label_text("3")
	await get_tree().create_timer(0.5).timeout
	pause_countdown.set_label_text("2")
	await get_tree().create_timer(0.5).timeout
	pause_countdown.set_label_text("1")
	await get_tree().create_timer(0.5).timeout
	pause_countdown.visible = false
	
	# continue game play
	song_player.play(pause_position)
	_transition_game_state(gamestate_playing)

func _on_BeepSaberMainMenu_difficulty_changed(map_info: MapInfo, diff_rank: int) -> void:
	# menu loads playlist in _ready(), must yield until scene is loaded
	if not highscore_canvas:
		await self.ready
	
	highscore_canvas._show()
	highscore_panel.load_highscores(map_info,diff_rank)

func _settings_button() -> void:
	# The panel builds its rows in its own _ready(), which runs before vr.initialize() has an XR
	# session, so it could not see the headset's refresh rates or foveation support then. Re-read
	# the interface capabilities each time the panel opens.
	if settings_panel != null:
		settings_panel._set_up_performance_controls()
	_transition_game_state(gamestate_settings)

func _on_settings_Panel_apply() -> void:
	set_colors_from_settings()
	_transition_game_state(gamestate_mapselection)

func _on_ScenePool_new_scene_instanced(obj: Node3D, during_presizing: bool) -> void:
	# add obj to the track. it will reside inside the track for eternity, only
	# to be reposition and made visible again when it is acquired and spawned.
	track.add_child(obj)
	
	# make obj visible and wait for a frame to be processed. this tricks
	# shaders to be loaded at startup time.
	if during_presizing:
		# FR-038: cube/wall/bomb/arc materials compile on this frame. Mirrored copies are now a
		# material next_pass on the mesh itself rather than a child node, so nothing extra to warm.
		obj.position.z = -2.0
		await get_tree().process_frame
		
		if obj is BeepCube:
			obj.hide_cube()
		elif obj is ChainLink:
			obj.hide_cube()
		elif obj is Wall:
			obj.hide_wall()
		else:
			obj.visible = false

func _on_pose_recentered() -> void:
	# The runtime has re-based tracking. Re-apply our alignment so the play space and the UI
	# are in front of the player again, rather than keeping the startup offset.
	recenter()

func recenter():
	var xr_camera := $XROrigin3D/XRCamera3D as XRCamera3D
	xr_origin.rotation.y -= xr_camera.global_rotation.y
	xr_origin.position -= (xr_camera.global_position * Vector3(1,0,1)) - Vector3(0,0,1)



