# Deterministic, unattended gameplay run for frame-time capture (spec FR-006, FR-007,
# FR-014, FR-019). Normal launches are untouched: BeepSaber_Game._ready() only creates
# this node when a bench flag file exists.
#
# ── Trigger ───────────────────────────────────────────────────────────────────
# The flag is an INI file (Godot ConfigFile) called `bench.flag`, looked up in two
# places; the results are written next to whichever one was found:
#
#   1. user://bench.flag
#        reachable only through `adb shell run-as <package> ...`, i.e. a debuggable
#        (Godot "debug") APK. This is the primary location.
#   2. <external data dir>/bench.flag, on Android
#        /sdcard/Android/data/<package>/files/bench.flag
#        works on every APK, no storage permission required.
#
#   [bench]
#   map = "Timelapse"         ; required. case-insensitive substring of song_name or filepath
#   difficulty_index = 0      ; optional. 0-based index into difficulty_beatmaps
#   difficulty = "Easy"       ; optional. case-insensitive match on difficulty or custom_name
#   difficulty_rank = 1       ; optional. exact DifficultyInfo.difficulty_rank
#   duration = 60             ; optional. seconds of gameplay to record; 0/absent = until the song ends
#   max_duration = 180        ; optional. hard cap in seconds (default 180)
#
#   [bot]
#   enabled = true            ; optional. deterministic autoplay workload; absent/false = no bot
#   miss_percent = 0          ; optional. deterministic fraction of notes deliberately not swung at
#   sway = true               ; optional. head sway on the XROrigin3D (default true)
#
#   See game/scripts/BotDriver.gd for the workload's geometry and tools/perf/benchmark.md
#   for the device recipe.
#
#   ConfigFile (standard INI) rules apply: string values MUST be double-quoted, numbers
#   bare, `;` or `#` start a comment line. The section name is required.
#
#   Precedence: difficulty_index > difficulty > difficulty_rank > default, where the
#   default is the lowest ranked difficulty listed in the map.
#
# ── Output ────────────────────────────────────────────────────────────────────
#   bench.csv       one header row, then one row per rendered frame:
#                   frame,ticks_usec,delta_usec,process_delta_usec,song_pos_usec,frames_drawn,focused,
#                   cubes_in_use,links_in_use,debris_live,slice_bursts
#   bench_meta.txt  key=value block describing the run (map, difficulty, samples, exit reason, device)
#
#   The four workload columns are what makes a run comparable to real play:
#     cubes_in_use / links_in_use  pool in-use counts = notes and chain links currently spawned
#     debris_live                  CutPiece nodes with visible = true, i.e. live cut debris
#                                  (0.3 s lifetime, BeepCube_CutPiece.gd:64)
#     slice_bursts                 slice-particle bursts started since the previous sample
#   These are sampled every COUNTER_STRIDE rendered frames, not every frame, so the
#   counter itself stays off the measured frame path; the peak is still caught because
#   debris lives ~27 frames at 90 Hz.
#
#   There is deliberately no "live particle count": GPUParticles3D has no live count,
#   the game never clears `slice_particles.visible`/`c1.emitting` after a burst (only
#   the next spawn's reset() does), and on Android the GPUParticles3D is freed at
#   startup (BeepCube_SliceParticles.gd:9-10). A burst counter is the honest measure
#   of particle load, and it works on device because the wrapper Node3D still toggles.
#
#   The flag is renamed to bench.flag.consumed before the run starts, so a crash in
#   the middle of a benchmark cannot trap every later launch in benchmark mode.
#
# ── Measurement notes ─────────────────────────────────────────────────────────
# Sampling happens in _process(), which runs once per display frame: frame pacing is a
# display-frame property (SC-010), and delta_usec is wall clock (Time.get_ticks_usec),
# never the engine's scaled delta. Every frame is recorded, including song-start
# shader/spawn frames; discarding warm-up is a host-side analysis decision (FR-033).
# Engine.get_frames_drawn() cannot see frames the XR compositor drops - use logcat
# `VrApi` / OVR Metrics for those (FR-023). `focused` is 1 while the app has focus;
# a drop to 0 means the headset was taken off mid-run and the run is not trustworthy.
extends Node
class_name BenchmarkRunner

const FLAG_NAME := "bench.flag"
const CONSUMED_NAME := "bench.flag.consumed"
const CSV_NAME := "bench.csv"
const META_NAME := "bench_meta.txt"
const DEFAULT_MAX_DURATION_S := 180.0
# Workload counters are sampled every Nth rendered frame; see the Output notes.
const COUNTER_STRIDE := 4

# Spike attribution (FR-033). A frame is recorded as a spike when its process-step
# time exceeds this. 12 ms is just over a 90 Hz budget (11.11 ms) and well below
# the p99 the run is being judged on, so the log catches the causes, not only the
# worst symptom. Time in the log is microsecond-resolution, so the threshold only
# decides which frames get a line, never how they are measured.
const SPIKE_USEC := 12000
const MAX_SPIKE_WINDOWS := 200

const CSV_HEADER := "frame,ticks_usec,delta_usec,process_delta_usec,song_pos_usec,frames_drawn,focused,cubes_in_use,links_in_use,debris_live,slice_bursts,process_usec,physics_usec,phys_ticks,swing_usec,cuttable_usec,floor_ray_usec,spawn_usec,shape_reenable,notes_live,cuts_this_frame,labels_spawned,objs_spawned,objs_freed,arcs_spawned,text_mesh_writes,track_children,static_mem,pipeline_compiles_total"

# Per-path self-time instrumentation (FR-033). A total physics time is not an
# attribution: `physics_usec` is the whole tick, so the columns below split it
# into the paths that were actually suspects. See game/scripts/CostProbe.gd.
const Cost := preload("res://game/scripts/CostProbe.gd")

# Preloaded by path so benchmark mode does not depend on the editor's global
# class cache being up to date on a clean clone (same reason as BenchmarkRunner).
const BotDriverScript := preload("res://game/scripts/BotDriver.gd")
const HitResolver := preload("res://game/scripts/HitResolver.gd")

var _game: Node3D
var _song_player: AudioStreamPlayer
var _track: Node3D
var _bot: Node = null

var _out_dir := "user://"
var _meta: Dictionary = {}

var _recording := false
var _start_usec := 0
var _prev_usec := 0
var _limit_usec := int(DEFAULT_MAX_DURATION_S * 1000000.0)
var _limit_reason := "max_duration"
var _saw_playing := false
var _focused := true

# Buffered, not streamed: no per-frame file IO on the main thread.
var _ticks := PackedInt64Array()
var _deltas := PackedInt64Array()
var _proc_deltas := PackedInt64Array()
var _proc_times := PackedInt64Array()
var _phys_times := PackedInt64Array()
var _phys_ticks := PackedInt32Array()
var _swing_usec := PackedInt64Array()
var _cuttable_usec := PackedInt64Array()
var _floor_usec := PackedInt64Array()
var _spawn_usec := PackedInt64Array()
var _reenable := PackedInt32Array()
var _notes_live := PackedInt32Array()
var _song_pos := PackedInt64Array()
var _drawn := PackedInt32Array()
var _focus_col := PackedByteArray()

# Spike-attribution columns (FR-033), one value per rendered frame. Everything
# here is either a static counter from CostProbe (no allocation on the writer's
# path) or a single O(1) engine read, so recording stays cheap next to the
# 11 ms budget it is measuring.
var _col_cuts := PackedInt32Array()
var _col_labels := PackedInt32Array()
var _col_objs := PackedInt32Array()
var _col_objs_freed := PackedInt32Array()
var _col_arcs := PackedInt32Array()
var _col_tm := PackedInt32Array()
var _col_track := PackedInt32Array()
var _col_mem := PackedInt64Array()
var _col_pipe := PackedInt64Array()

# Rows whose process time is over SPIKE_USEC, waiting for their following frame so
# spike-1/spike/spike+1 can all be printed. Empty on a normal run: the per-frame
# cost is one `is_empty()` test.
var _spike_queue: Array[int] = []
var _spikes := 0
var _spike_windows := 0
var _deep_probe := false
var _last_logged_row := -10

# Workload counters (see CSV_HEADER). Last sampled value is repeated on the
# rows in between, so the columns are always aligned with their frame.
var _col_cubes := PackedInt32Array()
var _col_links := PackedInt32Array()
var _col_debris := PackedInt32Array()
var _col_bursts := PackedInt32Array()
var _last_cubes := 0
var _last_links := 0
var _last_debris := 0
var _last_bursts := 0
var _bursts_total := 0
var _burst_state: Dictionary = {}
var _cube_cache: Array[BeepCube] = []
var _cube_cache_children := -1

func _init(game: Node3D) -> void:
	_game = game
	set_process(false)

# Cheap existence check used by BeepSaber_Game._ready(); the runner is only created
# when this is true, so a normal launch never pays for anything in this file.
static func has_bench_flag() -> bool:
	return not _find_flag_path().is_empty()

static func _find_flag_path() -> String:
	if FileAccess.file_exists("user://" + FLAG_NAME):
		return "user://" + FLAG_NAME
	var external := _android_external_files_dir()
	if external.is_empty():
		return ""
	var path := external.path_join(FLAG_NAME)
	if FileAccess.file_exists(path):
		return path
	return ""

# Godot 4 exposes no external-data-dir accessor, so derive it from the app's own
# internal data dir: /data/user/0/<package>/files -> /storage/emulated/0/Android/data/<package>/files
# That directory is app-owned, so it is readable without any storage permission.
static func _android_external_files_dir() -> String:
	if not OS.has_feature("android"):
		return ""
	var internal := OS.get_user_data_dir()
	var marker := "/data/user/0/"
	var idx := internal.find(marker)
	if idx < 0:
		marker = "/data/data/"
		idx = internal.find(marker)
	if idx < 0:
		return ""
	var rest := internal.substr(idx + marker.length())
	var slash := rest.find("/")
	if slash <= 0:
		return ""
	return "/storage/emulated/0/Android/data/" + rest.substr(0, slash) + "/files"

func _ready() -> void:
	# Deferred so the map is started after the main scene has finished _ready().
	call_deferred("_begin")

func _begin() -> void:
	var flag_path := _find_flag_path()
	if flag_path.is_empty():
		vr.log_info("BENCH: exit=no_flag")
		get_tree().quit()
		return
	_out_dir = flag_path.get_base_dir()
	_meta["flag_path"] = flag_path
	_meta["engine"] = str(Engine.get_version_info().get("string", ""))
	_meta["os"] = OS.get_name()
	_meta["model"] = OS.get_model_name()
	_meta["rendering_method"] = str(ProjectSettings.get_setting("rendering/renderer/rendering_method", ""))
	# E0 instrumentation: these settle the native-resolution question on device instead of
	# trusting a remembered default (advisor flagged its own figures as unverified).
	var xr_iface := XRServer.primary_interface
	if xr_iface != null:
		var rt := xr_iface.get_render_target_size()
		_meta["render_target_size"] = "%dx%d" % [int(rt.x), int(rt.y)]
		_meta["render_target_size_v2"] = str(rt)
	# Effective runtime values, not the project.godot keys: the app now applies these from
	# Settings, and Godot 4.6 reads no project setting for the multiplier or the refresh rate
	# at all (only foveation), so recording the project value would be recording a value the
	# app does not use.
	_meta["render_scale_multiplier"] = str(Settings.render_scale)
	_meta["msaa_3d"] = str(get_viewport().msaa_3d)
	_meta["physics_ticks_per_second"] = str(Engine.physics_ticks_per_second)
	_meta["physics_engine"] = str(ProjectSettings.get_setting("physics/3d/physics_engine", ""))
	_meta["foveation_level"] = str(Settings.foveation_level)
	_meta["display_refresh_rate_setting"] = str(Settings.display_refresh_rate)
	_meta["viewport_size"] = str(get_viewport().get_visible_rect().size)
	_meta["video_adapter"] = RenderingServer.get_video_adapter_name()
	vr.log_info("BENCH: start flag=%s" % flag_path)
	
	var cfg := ConfigFile.new()
	var load_err := cfg.load(flag_path)
	_consume_flag()
	if load_err != OK:
		vr.log_error("BENCH: cannot parse %s (%s)" % [flag_path, error_string(load_err)])
		_abort("bad_config")
		return
	
	# Human-play capture: record whatever the player does, with no bot and no map forced.
	# The CSV is identical to a bot run's, so play-time stutter can be measured from real play
	# instead of inferred from a scripted swing. One song per launch; relaunch to capture again.
	if bool(cfg.get_value("bench", "player_capture", false)):
		_player_capture = true
		_meta["mode"] = "player_capture"
		vr.log_info("BENCH: player capture armed - start a map")
		return
	# In-app download probe: exercises the exact chain the BeatSaver panel uses - search API,
	# download URL, zip write, unzip into the songs directory, map parse - and records each
	# step. "The API answers from my PC" does not prove it answers from inside the headset, and
	# the panel itself cannot be driven without a player wearing the headset.
	if bool(cfg.get_value("bench", "beatsaver_probe", false)):
		_run_beatsaver_probe()
		return
	# UI scroll probe: opens the BeatSaver panel, drives the stick from code (vr_slider.debug_stick)
	# and records the scroll value every frame. "It feels notchy" is not measurable, but the
	# per-frame delta sequence is: a smooth scroll moves a little on most frames, a notchy one
	# alternates zero-delta frames with large jumps.
	if bool(cfg.get_value("bench", "ui_scroll_probe", false)):
		_run_ui_scroll_probe()
		return

	var query := str(cfg.get_value("bench", "map", "")).strip_edges()
	if query.is_empty():
		vr.log_error("BENCH: [bench] map= is required")
		_abort("bad_config")
		return
	
	# Refresh-rate selection: the panel rate is not fixed. Pin it explicitly so the
	# physics tick can match it, and record what the runtime actually offers rather
	# than assuming 72/90/120 are all available on this unit.
	var xr := XRServer.primary_interface
	if xr != null:
		var avail: Array = xr.get_available_display_refresh_rates() if xr.has_method("get_available_display_refresh_rates") else []
		_meta["refresh_rates_available"] = str(avail)
		_meta["refresh_rate_before"] = str(xr.get_display_refresh_rate()) if xr.has_method("get_display_refresh_rate") else "unknown"
		var want_hz := float(cfg.get_value("bench", "refresh_hz", 0.0))
		if want_hz > 0.0 and xr.has_method("set_display_refresh_rate"):
			xr.set_display_refresh_rate(want_hz)
			_meta["refresh_rate_requested"] = str(want_hz)
		_meta["refresh_rate_after"] = str(xr.get_display_refresh_rate()) if xr.has_method("get_display_refresh_rate") else "unknown"
		# Pin physics to what the display ACTUALLY runs at, not what we asked for.
		# Requesting 90 on a runtime that only offers 72 must not leave physics at 90 -
		# that is strictly worse than the default because it burns CPU for no visual gain.
		var actual_hz := float(_meta["refresh_rate_after"]) if _meta["refresh_rate_after"].is_valid_float() else 0.0
		if actual_hz > 0.0:
			Engine.physics_ticks_per_second = int(round(actual_hz))
	_meta["physics_ticks_effective"] = str(Engine.physics_ticks_per_second)
	_apply_overrides(cfg)

	var requested := float(cfg.get_value("bench", "duration", 0.0))
	_deep_probe = bool(cfg.get_value("bench", "deep_probe", false))
	_meta["deep_probe"] = "true" if _deep_probe else "false"
	var max_duration := float(cfg.get_value("bench", "max_duration", DEFAULT_MAX_DURATION_S))
	if max_duration <= 0.0:
		max_duration = DEFAULT_MAX_DURATION_S
	if requested <= 0.0 or requested >= max_duration:
		_limit_usec = int(max_duration * 1000000.0)
		_limit_reason = "max_duration"
	else:
		_limit_usec = int(requested * 1000000.0)
		_limit_reason = "duration"
	
	# MainMenu loads the playlists in its own _ready(), which runs before this.
	@warning_ignore("unsafe_property_access")
	var menu: MainMenu = _game.menu
	@warning_ignore("unsafe_property_access")
	_song_player = _game.song_player
	@warning_ignore("unsafe_property_access")
	_track = _game.track
	if menu == null or _song_player == null:
		vr.log_error("BENCH: main scene is missing its menu or song player")
		_abort("no_scene_refs")
		return
	
	var songs := menu._all_songs
	if songs.is_empty():
		# Fresh install: the menu may not have found anything yet. Same loading path.
		menu._load_playlists()
		songs = menu._all_songs
	if songs.is_empty():
		vr.log_error("BENCH: no maps found under %sSongs/" % Constants.APPDATA_PATH)
		_abort("no_maps")
		return
	
	var map := _pick_map(songs, query)
	if map == null:
		vr.log_error("BENCH: no map matches \"%s\" (%d songs scanned)" % [query, songs.size()])
		_abort("map_not_found")
		return
	
	var difficulty_sel := _pick_difficulty(map, cfg)
	if difficulty_sel.is_empty():
		vr.log_error("BENCH: map \"%s\" lists no difficulties" % map.song_name)
		_abort("no_difficulties")
		return
	var difficulty: DifficultyInfo = difficulty_sel["info"]
	
	_meta["map_query"] = query
	_meta["map_song_name"] = map.song_name
	_meta["map_filepath"] = map.filepath
	_meta["difficulty"] = difficulty.difficulty
	_meta["difficulty_custom_name"] = difficulty.custom_name
	_meta["difficulty_rank"] = difficulty.difficulty_rank
	_meta["difficulty_index"] = difficulty_sel["index"]
	_meta["difficulty_rule"] = difficulty_sel["rule"]
	_meta["limit_s"] = "%.3f" % (_limit_usec / 1000000.0)
	vr.log_info("BENCH: map=\"%s\" filepath=%s" % [map.song_name, map.filepath])
	vr.log_info("BENCH: difficulty=%s rank=%d index=%d rule=%s" % [
		difficulty.difficulty, difficulty.difficulty_rank,
		difficulty_sel["index"], difficulty_sel["rule"]])
	
	# Same entry point the menu's `start_map` signal is bound to
	# (BeepSaber_Game.tscn:299), so no menu UI state or audio preview is touched.
	@warning_ignore("unsafe_method_access")
	_game.start_map(map, difficulty)
	if Map.current_info != map:
		vr.log_error("BENCH: start_map did not load %s" % map.filepath)
		_abort("start_failed")
		return
	
	_start_bot(cfg)
	_start_recording()

# The bot is created here, in the same call stack as start_map(), i.e. before the
# first physics tick can pop notes off Map.note_stack: it snapshots them itself.
# Measurement-only switches, applied from the run's own flag so one build can
# produce both arms of a comparison. Each one changes behaviour, so each one is
# recorded in the meta file and each one defaults to "leave the shipped value".
# None of them exist outside benchmark mode (FR-031: no app-imposed frame cap in
# normal operation; `max_fps` here only pins conditions while measuring).
func _apply_overrides(cfg: ConfigFile) -> void:
	var applied := PackedStringArray()
	# Stress-test switch: force every visual setting on so the frame budget can be measured
	# with the full feature set, which is what the shipped defaults must eventually hold.
	if bool(cfg.get_value("bench", "visuals_all", false)):
		Settings.floor_light = true
		Settings.saber_halo = true
		Settings.note_edge_glow = true
		Settings.hit_flash = true
		Settings.note_map_colors = true
		Settings.event_tint = true
		Settings.floor_grid = true
		Settings.sky_style = 2
		Settings.debris_cap = true
		Settings.mirror_reflections = true
		applied.append("visuals_all=true")
	# Settings live in memory per process: only the settings panel and the BeatSaver panel call
	# Settings.save(), so a benchmark override never reaches config.ini. Arms are therefore
	# independent of each other. This key still exists because it makes an arm state its
	# visual configuration explicitly instead of depending on whatever defaults the build has.
	if bool(cfg.get_value("bench", "visuals_default", false)):
		Settings.floor_light = true
		Settings.saber_halo = true
		Settings.note_edge_glow = true
		Settings.hit_flash = true
		Settings.note_map_colors = true
		Settings.event_tint = true
		Settings.floor_grid = true
		Settings.sky_style = 0
		Settings.debris_cap = false
		Settings.mirror_reflections = false
		applied.append("visuals_default=true")
	# Everything off in one key. The comma-list `visual_off` form below fails ConfigFile
	# parsing when the list is long ("Parse error" -> bad_config), which silently produced
	# empty runs; this key is the reliable way to take the whole visual layer out.
	if bool(cfg.get_value("bench", "visuals_none", false)):
		Settings.floor_light = false
		Settings.saber_halo = false
		Settings.note_edge_glow = false
		Settings.hit_flash = false
		Settings.note_map_colors = false
		Settings.event_tint = false
		Settings.floor_grid = false
		Settings.sky_style = 0
		Settings.debris_cap = false
		Settings.mirror_reflections = false
		applied.append("visuals_none=true")
	# Per-feature attribution: `[bench] visual_off=mirrors,sky` turns individual features
	# off from the full set, which is how the cost of each one is isolated (removing one from
	# all-on captures the interactions, adding one to defaults does not).
	var visual_off := str(cfg.get_value("bench", "visual_off", "")).strip_edges()
	if not visual_off.is_empty():
		for name in visual_off.split(",", false):
			match name.strip_edges():
				"mirrors": Settings.mirror_reflections = false
				"halo": Settings.saber_halo = false
				"floor_light": Settings.floor_light = false
				"debris": Settings.debris_cap = false
				"note_glow": Settings.note_edge_glow = false
				"flash": Settings.hit_flash = false
				"grid": Settings.floor_grid = false
				"sky": Settings.sky_style = 0
				"tint": Settings.event_tint = false
				"note_colors": Settings.note_map_colors = false
				_: vr.log_warning("BENCH: unknown visual_off entry %s" % name)
		applied.append("visual_off=%s" % visual_off)
	# Audio verification: counts every attempted voice so a run can prove hit audio is
	# actually being queued (valid ids, layer mix) instead of merely compiling.
	if bool(cfg.get_value("bench", "audio_probe", false)):
		DefaultSaber.probe_enabled = true
		DefaultSaber.probe_calls = 0
		DefaultSaber.probe_invalid = 0
		DefaultSaber.probe_soft = 0
		DefaultSaber.probe_hard = 0
		DefaultSaber.probe_accent = 0
		DefaultSaber.probe_dull = 0
		applied.append("audio_probe=true")
	# GPU attribution: hide the floor pad, which is a large screen-area surface with per-pixel
	# streak, grid and flash maths. If it is a big share of GPU%, simplifying it beats dropping
	# resolution, because it costs sharpness nowhere.
	if bool(cfg.get_value("bench", "floor_off", false)):
		@warning_ignore("unsafe_property_access")
		_game.standing_ground.visible = false
		applied.append("floor_off=true")
	# Floor measurement: no notes at all. Everything left is engine + XR + audio + UI + render,
	# which is the number the 8.33 ms budget has to be judged against - no note optimisation can
	# go below it.
	if bool(cfg.get_value("bench", "no_notes", false)):
		Map.spawn_disabled = true
		applied.append("no_notes=true")

	# HUD text writes are the other per-cut cost: every score change rewrites two TextMeshes and
	# each write re-triangulates glyphs on the main thread.
	if bool(cfg.get_value("bench", "hud_off", false)):
		_hud_disabled = true
		applied.append("hud_off=true")

	# Physics rate, decoupled from the display. The sweep fix means the ray fan accumulates
	# motion between ticks, so 60 Hz physics is not the hit-registration loss it would have
	# been before.
	var phys = cfg.get_value("bench", "physics_hz", null)
	if phys != null:
		Engine.physics_ticks_per_second = int(phys)
		applied.append("physics_hz=%d" % Engine.physics_ticks_per_second)
	# Audio churn switch: skips the hit-sound calls entirely, so a drift caused by voices
	# accumulating in the mixer shows up as a flat run instead of a rising frame time.
	if bool(cfg.get_value("bench", "no_audio", false)):
		DefaultSaber.audio_disabled = true
		applied.append("no_audio=true")
	# A/B switch for the CSG arc ribbon, which is the prime suspect for the main-thread tail.
	var arcs = cfg.get_value("bench", "arcs", null)
	if arcs != null:
		Arc.spawn_enabled = bool(arcs)
		applied.append("arcs=%s" % str(bool(arcs)))
	var rays := int(cfg.get_value("bench", "rays", 0))
	if rays > 0:
		ProjectSettings.set_setting(&"gameplay/swing_hit/num_collision_raycasts", rays)
		applied.append("rays=%d" % rays)
	var once = cfg.get_value("bench", "enable_collision_once", null)
	if once != null:
		ProjectSettings.set_setting(&"gameplay/notes/enable_collision_once", bool(once))
		applied.append("enable_collision_once=%s" % str(bool(once)))
	var isolate = cfg.get_value("bench", "isolate_shapes", null)
	if isolate != null:
		ProjectSettings.set_setting(&"gameplay/notes/isolate_collision_shapes", bool(isolate))
		applied.append("isolate_shapes=%s" % str(bool(isolate)))
	# A/B arm for specs/006-swing-hit-sweep: "rays" is the pre-006 fan, "analytic"
	# the swept-blade resolver. The mode is cached on first use, so the cache is
	# dropped here for the sabers that already exist.
	var detection = cfg.get_value("bench", "detection", null)
	if detection != null:
		var mode := str(detection).strip_edges().to_lower()
		ProjectSettings.set_setting(&"gameplay/swing_hit/detection", mode)
		HitResolver.reset_mode_cache()
		applied.append("detection=%s" % mode)
	var max_fps := int(cfg.get_value("bench", "max_fps", 0))
	if max_fps > 0:
		Engine.max_fps = max_fps
		applied.append("max_fps=%d" % max_fps)
	# GPU-vs-CPU discriminator: dropping the render scale removes roughly half the pixel work	# while leaving every node, script and physics tick untouched. If frame time falls, the
	# frame is GPU-limited; if it holds, the main thread is the limit and no visual change helps.
	var scale = cfg.get_value("bench", "render_scale", null)
	if scale != null:
		Settings.render_scale = float(scale)
		applied.append("render_scale=%.3f" % Settings.render_scale)
	# Fixed foveation is the classic Quest GPU lever: level 2 shades the periphery at reduced
	# rate, which costs sharpness only where the player is not looking.
	var fov = cfg.get_value("bench", "foveation", null)
	if fov != null:
		Settings.foveation_level = int(fov)
		applied.append("foveation=%d" % Settings.foveation_level)
	var msaa = cfg.get_value("bench", "msaa", null)
	if msaa != null:
		Settings.msaa_3d = int(msaa)
		applied.append("msaa=%d" % Settings.msaa_3d)
	# The upload page is a live setting (Settings.changed -> SongUploader.apply_enabled), so
	# this arm proves the toggle really closes the port instead of only ignoring requests.
	var upload = cfg.get_value("bench", "upload_server", null)
	if upload != null:
		Settings.upload_server = bool(upload)
		applied.append("upload_server=%s" % str(bool(upload)))
	_meta["overrides"] = ", ".join(applied) if not applied.is_empty() else "none"
	vr.log_info("BENCH: overrides %s" % _meta["overrides"])
# --- In-app download probe (bench-only) ---------------------------------------------------
# Each step writes its own result key, so a partial failure says exactly where it stopped
# instead of reporting a generic "download failed".
func _run_beatsaver_probe() -> void:
	var http := HTTPRequest.new()
	http.timeout = 40.0
	add_child(http)
	var headers := PackedStringArray(["User-Agent: " + BeatSaverApi.USER_AGENT])
	var search_url: String = BeatSaverApi.build_search_url({}, 0)
	_meta["probe_search_url"] = search_url
	if http.request(search_url, headers) != OK:
		_meta["probe_error"] = "search request failed to start"
		_probe_done()
		return
	var res: Array = await http.request_completed
	_meta["probe_search_code"] = str(res[1])
	var body: PackedByteArray = res[3]
	_meta["probe_search_bytes"] = str(body.size())
	var search: Variant = BeatSaverApi.parse_search(body)
	if search == null or not search.ok or (search.docs as Array).is_empty():
		_meta["probe_error"] = "search did not return a map list"
		_probe_done()
		return
	var rec: Variant = search.docs[0]
	@warning_ignore("unsafe_property_access")
	_meta["probe_map_id"] = str(rec.id)
	@warning_ignore("unsafe_property_access")
	_meta["probe_map_name"] = str(rec.song_name)
	@warning_ignore("unsafe_property_access")
	var download_url := str(rec.download_url)
	if download_url.is_empty():
		_meta["probe_error"] = "first result had no download URL"
		_probe_done()
		return
	if http.request(download_url, headers) != OK:
		_meta["probe_error"] = "download request failed to start"
		_probe_done()
		return
	res = await http.request_completed
	_meta["probe_download_code"] = str(res[1])
	body = res[3]
	_meta["probe_download_bytes"] = str(body.size())
	if body.is_empty():
		_meta["probe_error"] = "download body was empty"
		_probe_done()
		return
	# Same destination layout the panel uses (BeatSaverPanel._on_download_completed).
	var tempdir: String = Constants.APPDATA_PATH + "temp"
	DirAccess.make_dir_recursive_absolute(tempdir)
	var zippath: String = tempdir.path_join("probe.zip")
	var file := FileAccess.open(zippath, FileAccess.WRITE)
	if file == null:
		_meta["probe_error"] = "cannot write " + zippath
		_probe_done()
		return
	file.store_buffer(body)
	file.close()
	@warning_ignore("unsafe_property_access")
	var dirname := "Probe-" + str(rec.id)
	var outdir: String = Constants.APPDATA_PATH + "Songs/" + dirname + "/"
	if DirAccess.make_dir_recursive_absolute(outdir) != OK:
		_meta["probe_error"] = "cannot create " + outdir
		_probe_done()
		return
	Utils.unzip(zippath, outdir)
	DirAccess.remove_absolute(zippath)
	var info: MapInfo = Map.load_map_info(outdir)
	_meta["probe_map_parsed"] = "true" if info != null else "false"
	if info != null:
		_meta["probe_map_version"] = info.version
		_meta["probe_map_title"] = info.song_name
		_meta["probe_map_difficulties"] = str(info.difficulty_beatmaps.size())
	_probe_done()


func _probe_done() -> void:
	_meta["samples"] = 0
	_meta["exit_reason"] = "beatsaver_probe"
	_write_meta()
	vr.log_info("BENCH: beatsaver probe complete")
	get_tree().quit()

func _start_bot(cfg: ConfigFile) -> void:
	var enabled := bool(cfg.get_value("bot", "enabled", false))
	_meta["bot_enabled"] = "true" if enabled else "false"
	_meta["counter_stride"] = str(COUNTER_STRIDE)
	if not enabled:
		return
	var miss_percent := float(cfg.get_value("bot", "miss_percent", 0.0))
	var sway := bool(cfg.get_value("bot", "sway", true))
	_bot = BotDriverScript.new(_game, miss_percent, sway)
	_game.add_child(_bot)
	vr.log_info("BENCH: bot enabled miss_percent=%.1f sway=%s" % [miss_percent, str(sway)])

func _start_recording() -> void:
	# Refresh-rate changes are asynchronous: the runtime applies them some frames later.
	# Reading get_display_refresh_rate() right after requesting returns the OLD rate, so
	# pinning physics there produced 120 Hz physics against a 90 Hz display for a whole run.
	# Settle here, immediately before recording, and pin physics to what actually applies.
	var xr_settle := XRServer.primary_interface
	if xr_settle != null and xr_settle.has_method("get_display_refresh_rate"):
		# The runtime applies a refresh change late (measured: still reporting the old rate at
		# record start, settled only later in the run), so the read-back here is not
		# trustworthy. Pin physics to the rate we REQUESTED - that is the rate the display
		# converges to - and let _write_meta prove whether it matched.
		var want := float(_meta.get("refresh_rate_requested", "0"))
		var settled := float(xr_settle.get_display_refresh_rate())
		var target_hz := want if want > 0.0 else settled
		if target_hz > 0.0:
			Engine.physics_ticks_per_second = int(round(target_hz))
			_meta["refresh_rate_at_record_start"] = str(settled)
			_meta["physics_ticks_settled"] = str(Engine.physics_ticks_per_second)
			vr.log_info("BENCH: physics pinned to requested %.1f Hz (read-back at start was %.1f)" % [target_hz, settled])
	_recording = true
	_start_usec = Time.get_ticks_usec()
	_prev_usec = _start_usec
	Cost.reset()
	Cost.enabled = true
	vr.log_info("BENCH: recording started limit=%.1fs reason=%s" % [
		_limit_usec / 1000000.0, _limit_reason])

# Counts the physics ticks that ran before this frame's _process, so a frame
# that absorbed two catch-up ticks can be told apart from a frame that ran one.
# `physics_usec` sums over all of them (that is what TIME_PHYSICS_PROCESS does),
# so without this column a render hitch looks like expensive physics.
func _physics_process(_delta: float) -> void:
	if _recording:
		Cost.physics_ticks += 1

func _process(delta: float) -> void:
	if _player_capture and not _recording:
		_poll_player_capture()
		return
	if not _recording:
		return
	var now := Time.get_ticks_usec()
	_ticks.append(now)
	_deltas.append(now - _prev_usec)
	_prev_usec = now
	_proc_deltas.append(int(delta * 1000000.0))
	var proc_usec := int(Performance.get_monitor(Performance.TIME_PROCESS) * 1000000.0)
	_proc_times.append(proc_usec)
	_phys_times.append(int(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000000.0))
	_phys_ticks.append(Cost.physics_ticks)
	_swing_usec.append(Cost.swing_usec)
	_cuttable_usec.append(Cost.cuttable_usec)
	_floor_usec.append(Cost.floor_ray_usec)
	_spawn_usec.append(Cost.spawn_usec)
	_reenable.append(Cost.shape_reenable)
	_song_pos.append(int(_song_player.get_playback_position() * 1000000.0))
	_drawn.append(Engine.get_frames_drawn())
	_focus_col.append(1 if _focused else 0)
	
	# Spike attribution columns (FR-033).
	_col_cuts.append(Cost.cuts)
	_col_labels.append(Cost.labels_spawned)
	_col_objs.append(Cost.objs_spawned)
	_col_objs_freed.append(Cost.objs_freed)
	_col_arcs.append(Cost.arcs_spawned)
	_col_tm.append(Cost.text_mesh_writes)
	_col_track.append(_track.get_child_count() if _track != null else 0)
	# EXPENSIVE monitors. Measured cost: calling these every frame pushed main-thread
	# TIME_PROCESS p95 from 10.2 ms to 44.2 ms - the harness measurably perturbed the thing
	# it was measuring. They are sampled once every 30 frames and only under deep_probe.
	if _deep_probe and (_ticks.size() % 30) == 0:
		_col_mem.append(int(Performance.get_monitor(Performance.MEMORY_STATIC)))
		# Cumulative engine-wide pipeline-compilation count (GPU side, cannot be timed
		# from GDScript). Adjacent rows give the per-frame delta.
		_col_pipe.append(int(
			Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS)
			+ Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH)
			+ Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE)
			+ Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)
		+ Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)))
	else:
		# Column count must stay constant; the sampler repeats the last known value.
		_col_mem.append(_col_mem[_col_mem.size() - 1] if _col_mem.size() > 0 else 0)
		_col_pipe.append(_col_pipe[_col_pipe.size() - 1] if _col_pipe.size() > 0 else 0)
	
	if _ticks.size() % COUNTER_STRIDE == 1:
		_sample_counters()
	_col_cubes.append(_last_cubes)
	_col_links.append(_last_links)
	_col_debris.append(_last_debris)
	_col_bursts.append(_last_bursts)
	_notes_live.append(_last_cubes)
	# Readers own the reset: nothing on a hot path zeroes these.
	Cost.reset()
	
	if _deep_probe:
	
		_check_spike(proc_usec)
	
	if _song_player.playing:
		_saw_playing = true
	elif _saw_playing:
		if _player_capture:
			_finish_player()
			return
		_finish("song_end")
		return
	
	if now - _start_usec >= _limit_usec:
		_finish(_limit_reason)

# ── spike attribution (FR-033) ───────────────────────────────────────────────
# Godot's TIME_PROCESS for frame N is only observable once frame N has finished, so
# a spike row is held until two more rows exist. By then spike-1, spike and
# spike+1 are all in the recorded columns and the line is printed from them, which
# is what lets a spike be blamed on the frame that caused it (debris/CSG/text
# rebuilds often land one frame after the spawn that dirtied them) instead of on
# the frame that merely paid for it.
#
# Cost on a normal frame: one `is_empty()` test and one integer compare. Nothing is
# formatted unless a spike fires.
func _check_spike(proc_usec: int) -> void:
	var n := _ticks.size() - 1
	while not _spike_queue.is_empty() and n - _spike_queue[0] >= 2:
		_log_spike(_spike_queue.pop_front())
	if proc_usec > SPIKE_USEC:
		_spikes += 1
		if _spike_windows < MAX_SPIKE_WINDOWS:
			_spike_queue.append(n)

func _log_spike(row: int) -> void:
	# Overlapping windows would just repeat lines, and a pathological run (or a
	# platform where the monitor stops updating) must not be able to flood the log.
	if row <= _last_logged_row + 1:
		return
	_last_logged_row = row
	_spike_windows += 1
	for offset in range(-1, 2):
		var i := row + offset
		if i < 0 or i >= _ticks.size():
			continue
		vr.log_info("BENCH: spike frame=%d off=%d frame_usec=%d proc_usec=%d phys_usec=%d ticks=%d spawn_usec=%d cuts=%d labels=%d objs=%d freed=%d arcs=%d tm_writes=%d debris=%d bursts=%d notes=%d track=%d mem=%d pipe=%d" % [
			i, offset, _deltas[i], _proc_times[i], _phys_times[i], _phys_ticks[i], _spawn_usec[i],
			_col_cuts[i], _col_labels[i], _col_objs[i], _col_objs_freed[i],
			_col_arcs[i], _col_tm[i], _col_debris[i], _col_bursts[i],
			_notes_live[i], _col_track[i], _col_mem[i], _col_pipe[i]])

# ── workload counters ────────────────────────────────────────────────────────
func _sample_counters() -> void:
	_last_cubes = _pool_in_use(GlobalReferences.cube_pool)
	_last_links = _pool_in_use(GlobalReferences.link_pool)
	_last_debris = 0
	_last_bursts = 0
	if _track == null:
		return
	if _track.get_child_count() != _cube_cache_children:
		_refresh_cube_cache()
	for cube in _cube_cache:
		if cube.piece_left != null and cube.piece_left.visible:
			_last_debris += 1
		if cube.piece_right != null and cube.piece_right.visible:
			_last_debris += 1
		# Count slice-particle bursts started since the last sample: fire() sets
		# the wrapper visible, the next spawn's reset() clears it. Guarded
		# because the inner GPUParticles3D is freed on Android.
		if not is_instance_valid(cube.slice_particles):
			continue
		var fired := cube.slice_particles.visible
		if fired and not bool(_burst_state.get(cube, false)):
			_last_bursts += 1
			_bursts_total += 1
		_burst_state[cube] = fired

func _refresh_cube_cache() -> void:
	_cube_cache.clear()
	_cube_cache_children = _track.get_child_count()
	for child in _track.get_children():
		if child is BeepCube:
			_cube_cache.append(child as BeepCube)

# A pool's in-use count is the number of notes/links currently spawned, i.e. the
# live workload. O(1), so it is cheap enough to read every sampled frame.
func _pool_in_use(pool: ScenePool) -> int:
	if pool == null:
		return 0
	return pool.total_count() - pool.free_count()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_set_focus(true)
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_set_focus(false)

func _set_focus(value: bool) -> void:
	if value == _focused:
		return
	_focused = value
	if _recording:
		# Losing focus (headset off, prox_close, home button) distorts frame data.
		vr.log_info("BENCH: focus=%s t_usec=%d" % [str(value), Time.get_ticks_usec() - _start_usec])

func _pick_map(songs: Array[MapInfo], query: String) -> MapInfo:
	var needle := query.to_lower()
	var found: MapInfo = null
	var matches := 0
	for song in songs:
		if song.song_name.to_lower().contains(needle) or song.filepath.to_lower().contains(needle):
			matches += 1
			if found == null:
				found = song
	if matches > 1:
		vr.log_warning("BENCH: %d maps match \"%s\", using \"%s\"" % [matches, query, found.song_name])
	return found

# Returns {"info": DifficultyInfo, "index": int, "rule": String}, or {} when the map
# lists no difficulties. `start_map` takes the DifficultyInfo object itself, not a rank.
func _pick_difficulty(map: MapInfo, cfg: ConfigFile) -> Dictionary:
	var diffs := map.difficulty_beatmaps
	if diffs.is_empty():
		return {}
	
	var want_index := int(cfg.get_value("bench", "difficulty_index", -1))
	if want_index >= 0:
		if want_index < diffs.size():
			return {"info": diffs[want_index], "index": want_index, "rule": "difficulty_index=%d" % want_index}
		vr.log_warning("BENCH: difficulty_index=%d out of range (%d difficulties)" % [want_index, diffs.size()])
	
	var want_name := str(cfg.get_value("bench", "difficulty", "")).strip_edges().to_lower()
	if not want_name.is_empty():
		for i in diffs.size():
			if diffs[i].difficulty.to_lower() == want_name or diffs[i].custom_name.to_lower() == want_name:
				return {"info": diffs[i], "index": i, "rule": "difficulty=%s" % want_name}
		vr.log_warning("BENCH: no difficulty named \"%s\"" % want_name)
	
	var want_rank := int(cfg.get_value("bench", "difficulty_rank", -1))
	if want_rank >= 0:
		for i in diffs.size():
			if diffs[i].difficulty_rank == want_rank:
				return {"info": diffs[i], "index": i, "rule": "difficulty_rank=%d" % want_rank}
		vr.log_warning("BENCH: no difficulty with rank %d" % want_rank)
	
	# Default: the lowest rank the map lists, first entry winning ties.
	var lowest := 0
	for i in range(1, diffs.size()):
		var rank := diffs[i].difficulty_rank
		var best := diffs[lowest].difficulty_rank
		if rank > 0 and (best <= 0 or rank < best):
			lowest = i
	return {"info": diffs[lowest], "index": lowest, "rule": "default lowest (%s)" % diffs[lowest].difficulty}

func _consume_flag() -> void:
	# Renamed before the run starts: a crash mid-benchmark must not leave a flag
	# behind that traps every later launch in benchmark mode.
	var from := _out_dir.path_join(FLAG_NAME)
	var to := _out_dir.path_join(CONSUMED_NAME)
	if FileAccess.file_exists(to):
		@warning_ignore("return_value_discarded")
		DirAccess.remove_absolute(to)
	var err := DirAccess.rename_absolute(from, to)
	if err != OK:
		vr.log_warning("BENCH: could not rename the flag (%s), removing it" % error_string(err))
		@warning_ignore("return_value_discarded")
		DirAccess.remove_absolute(from)

func _finish(reason: String, quit_after: bool = true) -> void:
	if not _recording:
		return
	_recording = false
	set_process(false)
	Cost.enabled = false
	var elapsed_usec := Time.get_ticks_usec() - _start_usec
	_meta["samples"] = _ticks.size()
	_meta["elapsed_s"] = "%.3f" % (elapsed_usec / 1000000.0)
	_meta["exit_reason"] = reason
	_meta["debris_peak"] = str(_peak_of(_col_debris))
	_meta["slice_bursts_total"] = str(_bursts_total)
	_meta["cubes_peak"] = str(_peak_of(_col_cubes))
	_meta["spikes"] = str(_spikes)
	_meta["spike_threshold_usec"] = str(SPIKE_USEC)
	while not _spike_queue.is_empty():
		_log_spike(_spike_queue.pop_front())
	if _bot != null:
		@warning_ignore("unsafe_method_access")
		_meta.merge(_bot.get_stats(), true)
	_write_csv()
	_write_meta()
	vr.log_info("BENCH: samples=%d elapsed=%.3fs exit=%s" % [
		_ticks.size(), elapsed_usec / 1000000.0, reason])
	if not _deltas.is_empty():
		var sorted := _deltas.duplicate()
		sorted.sort()
		var total := 0
		for d in _deltas:
			total += d
		vr.log_info("BENCH: frame_us mean=%d p50=%d p95=%d p99=%d max=%d" % [
			total / _deltas.size(), _pct(sorted, 0.50), _pct(sorted, 0.95),
			_pct(sorted, 0.99), sorted[sorted.size() - 1]])
	get_tree().quit()

func _abort(reason: String) -> void:
	_meta["samples"] = 0
	_meta["exit_reason"] = reason
	_write_meta()
	vr.log_error("BENCH: exit=%s" % reason)
	get_tree().quit(1)

func _write_csv() -> void:
	var path := _out_dir.path_join(CSV_NAME)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		vr.log_error("BENCH: cannot write %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return
	_meta["csv_path"] = path
	var rows := PackedStringArray()
	rows.resize(_ticks.size() + 1)
	rows[0] = CSV_HEADER
	for i in _ticks.size():
		rows[i + 1] = "%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d" % [
			i, _ticks[i], _deltas[i], _proc_deltas[i],
			_song_pos[i], _drawn[i], _focus_col[i],
			_col_cubes[i], _col_links[i], _col_debris[i], _col_bursts[i],
			_proc_times[i], _phys_times[i],
			_phys_ticks[i], _swing_usec[i], _cuttable_usec[i], _floor_usec[i],
			_spawn_usec[i], _reenable[i], _notes_live[i],
			_col_cuts[i], _col_labels[i], _col_objs[i], _col_objs_freed[i],
			_col_arcs[i], _col_tm[i], _col_track[i], _col_mem[i], _col_pipe[i]]
	f.store_string("\n".join(rows) + "\n")
	f.close()
	vr.log_info("BENCH: csv=%s" % path)

func _write_meta() -> void:
	# Re-read the render target at the end: get_render_target_size() taken at startup can
	# report the runtime's recommended size before the multiplier is applied.
	var xr_end := XRServer.primary_interface
	if xr_end != null:
		var rtf := xr_end.get_render_target_size()
		_meta["render_target_size_final"] = "%dx%d" % [int(rtf.x), int(rtf.y)]
		if xr_end.has_method("get_display_refresh_rate"):
			_meta["refresh_rate_final"] = str(xr_end.get_display_refresh_rate())
	_meta["physics_ticks_final"] = str(Engine.physics_ticks_per_second)
	# Audio verification counters (see _apply_overrides).
	_meta["audio_probe_enabled"] = "true" if DefaultSaber.probe_enabled else "false"
	_meta["audio_play_calls"] = str(DefaultSaber.probe_calls)
	_meta["audio_invalid_ids"] = str(DefaultSaber.probe_invalid)
	_meta["audio_layer_soft"] = str(DefaultSaber.probe_soft)
	_meta["audio_layer_hard"] = str(DefaultSaber.probe_hard)
	_meta["audio_layer_accent"] = str(DefaultSaber.probe_accent)
	_meta["audio_layer_dull"] = str(DefaultSaber.probe_dull)
	_meta["detection"] = "analytic" if HitResolver.is_analytic() else "rays"
	# Validity: physics must have run at the rate the display actually ended at.
	var rej := float(_meta.get("refresh_rate_requested", "0"))
	var ref := float(_meta.get("refresh_rate_final", "0"))
	_meta["refresh_request_honoured"] = "true" if (rej <= 0.0 or abs(ref - rej) < 0.5) else "false"
	_meta["physics_matches_display"] = "true" if (ref <= 0.0 or abs(float(Engine.physics_ticks_per_second) - ref) < 0.5) else "false"
	var path := _out_dir.path_join(META_NAME)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		vr.log_error("BENCH: cannot write %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return
	var lines := PackedStringArray()
	for key in _meta.keys():
		lines.append("%s=%s" % [key, str(_meta[key])])
	f.store_string("\n".join(lines) + "\n")
	f.close()
	vr.log_info("BENCH: meta=%s" % path)

func _pct(sorted_values: PackedInt64Array, p: float) -> int:
	var n := sorted_values.size()
	if n == 0:
		return 0
	return sorted_values[clampi(int(round(float(n - 1) * p)), 0, n - 1)]

func _peak_of(values: PackedInt32Array) -> int:
	var peak := 0
	for v in values:
		if v > peak:
			peak = v
	return peak

const VRSlider := preload("res://game/vr_slider.gd")

func _run_ui_scroll_probe() -> void:
	var panel: Node = _game.find_child("BeatSaverPanel", true, false)
	if panel == null:
		_meta["probe_error"] = "panel node missing"
		_probe_done()
		return
	_game.show_MapSourceDialogs(true)
	@warning_ignore("unsafe_method_access")
	panel._show()
	# Give the first page time to arrive: there is nothing to scroll until cards exist.
	for i in 300:
		await get_tree().process_frame
	var slider: Node = panel.get_node_or_null("list_slider")
	if slider == null:
		_meta["probe_error"] = "list_slider missing"
		_probe_done()
		return
	var bar: Variant = slider.get("v_scroll")
	if bar == null:
		_meta["probe_error"] = "v_scroll missing"
		_probe_done()
		return
	# If the page has not arrived (or the run has no network), give the list known content so
	# the scroll mechanism itself can still be measured.
	if float(bar.get("max_value")) <= 0.0:
		var list_node: Node = panel.get_node_or_null("CardsScroll/CardList")
		if list_node == null:
			_meta["probe_error"] = "CardList missing"
			_probe_done()
			return
		for i in 20:
			var probe_card := Button.new()
			probe_card.custom_minimum_size = Vector2(100, 120)
			probe_card.text = "probe %d" % i
			list_node.add_child(probe_card)
		for i in 10:
			await get_tree().process_frame
	_meta["probe_scroll_range"] = "%.1f" % float(bar.get("max_value"))
	# Hold the stick fully up for 120 frames, hovering as if the ray were on the list.
	VRSlider.debug_hover = true
	VRSlider.debug_stick = -1.0
	var steps: Array[float] = []
	var last := float(bar.get("value"))
	for i in 120:
		await get_tree().process_frame
		var now := float(bar.get("value"))
		steps.append(now - last)
		last = now
	VRSlider.debug_stick = INF
	VRSlider.debug_hover = false
	var moved := 0
	var zero := 0
	var biggest := 0.0
	var total := 0.0
	for s in steps:
		total += s
		if absf(s) > 0.0:
			moved += 1
		else:
			zero += 1
		biggest = maxf(biggest, absf(s))
	_meta["probe_scroll_frames"] = str(steps.size())
	_meta["probe_scroll_moved_frames"] = str(moved)
	_meta["probe_scroll_zero_frames"] = str(zero)
	_meta["probe_scroll_max_step"] = "%.3f" % biggest
	_meta["probe_scroll_total"] = "%.1f" % total
	var head := PackedStringArray()
	for i in mini(24, steps.size()):
		head.append("%.1f" % steps[i])
	_meta["probe_scroll_first_steps"] = ",".join(head)
	_probe_done()

# --- human-play capture ------------------------------------------------------------------
var _player_capture := false
# Read by BeepSaber_Game._on_score_changed when hud_off is set.
static var _hud_disabled := false

func _poll_player_capture() -> void:
	if _song_player == null:
		@warning_ignore("unsafe_property_access")
		_song_player = _game.song_player
	if _song_player == null:
		return
	if _song_player.playing and Map.current_info != null:
		_meta["map_song_name"] = Map.current_info.song_name
		_meta["map_filepath"] = Map.current_info.filepath
		_start_recording()
		_saw_playing = true


# Same numbers as _finish(), but the game keeps running: the point is to play, so quitting at
# the end of the song would defeat it. Player capture is one song per launch.
func _finish_player() -> void:
	_player_capture = false
	_finish("player_song_end", false)





