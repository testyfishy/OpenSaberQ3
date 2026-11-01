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

const CSV_HEADER := "frame,ticks_usec,delta_usec,process_delta_usec,song_pos_usec,frames_drawn,focused,cubes_in_use,links_in_use,debris_live,slice_bursts,process_usec,physics_usec"

# Preloaded by path so benchmark mode does not depend on the editor's global
# class cache being up to date on a clean clone (same reason as BenchmarkRunner).
const BotDriverScript := preload("res://game/scripts/BotDriver.gd")

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
var _song_pos := PackedInt64Array()
var _drawn := PackedInt32Array()
var _focus_col := PackedByteArray()

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
	_meta["render_scale_multiplier"] = str(ProjectSettings.get_setting("xr/openxr/render_target_size_multiplier", 1.0))
	_meta["msaa_3d"] = str(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0))
	_meta["physics_ticks_per_second"] = str(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 0))
	_meta["physics_engine"] = str(ProjectSettings.get_setting("physics/3d/physics_engine", ""))
	_meta["foveation_level"] = str(ProjectSettings.get_setting("xr/openxr/foveation_level", 0))
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
			Engine.physics_ticks_per_second = int(round(want_hz))
			_meta["refresh_rate_requested"] = str(want_hz)
		_meta["refresh_rate_after"] = str(xr.get_display_refresh_rate()) if xr.has_method("get_display_refresh_rate") else "unknown"
	_meta["physics_ticks_effective"] = str(Engine.physics_ticks_per_second)

	var requested := float(cfg.get_value("bench", "duration", 0.0))
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
	_recording = true
	_start_usec = Time.get_ticks_usec()
	_prev_usec = _start_usec
	vr.log_info("BENCH: recording started limit=%.1fs reason=%s" % [
		_limit_usec / 1000000.0, _limit_reason])

func _process(delta: float) -> void:
	if not _recording:
		return
	var now := Time.get_ticks_usec()
	_ticks.append(now)
	_deltas.append(now - _prev_usec)
	_prev_usec = now
	_proc_deltas.append(int(delta * 1000000.0))
	_proc_times.append(int(Performance.get_monitor(Performance.TIME_PROCESS) * 1000000.0))
	_phys_times.append(int(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000000.0))
	_song_pos.append(int(_song_player.get_playback_position() * 1000000.0))
	_drawn.append(Engine.get_frames_drawn())
	_focus_col.append(1 if _focused else 0)
	
	if _ticks.size() % COUNTER_STRIDE == 1:
		_sample_counters()
	_col_cubes.append(_last_cubes)
	_col_links.append(_last_links)
	_col_debris.append(_last_debris)
	_col_bursts.append(_last_bursts)
	
	if _song_player.playing:
		_saw_playing = true
	elif _saw_playing:
		_finish("song_end")
		return
	
	if now - _start_usec >= _limit_usec:
		_finish(_limit_reason)

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

func _finish(reason: String) -> void:
	if not _recording:
		return
	_recording = false
	set_process(false)
	var elapsed_usec := Time.get_ticks_usec() - _start_usec
	_meta["samples"] = _ticks.size()
	_meta["elapsed_s"] = "%.3f" % (elapsed_usec / 1000000.0)
	_meta["exit_reason"] = reason
	_meta["debris_peak"] = str(_peak_of(_col_debris))
	_meta["slice_bursts_total"] = str(_bursts_total)
	_meta["cubes_peak"] = str(_peak_of(_col_cubes))
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
		rows[i + 1] = "%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d" % [
			i, _ticks[i], _deltas[i], _proc_deltas[i],
			_song_pos[i], _drawn[i], _focus_col[i],
			_col_cubes[i], _col_links[i], _col_debris[i], _col_bursts[i],
			_proc_times[i], _phys_times[i]]
	f.store_string("\n".join(rows) + "\n")
	f.close()
	vr.log_info("BENCH: csv=%s" % path)

func _write_meta() -> void:
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

