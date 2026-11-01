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
#   ConfigFile (standard INI) rules apply: string values MUST be double-quoted, numbers
#   bare, `;` or `#` start a comment line. The section name is required.
#
#   Precedence: difficulty_index > difficulty > difficulty_rank > default, where the
#   default is the lowest ranked difficulty listed in the map.
#
# ── Output ────────────────────────────────────────────────────────────────────
#   bench.csv       one header row, then one row per rendered frame:
#                   frame,ticks_usec,delta_usec,process_delta_usec,song_pos_usec,frames_drawn,focused
#   bench_meta.txt  key=value block describing the run (map, difficulty, samples, exit reason, device)
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

const CSV_HEADER := "frame,ticks_usec,delta_usec,process_delta_usec,song_pos_usec,frames_drawn,focused"

var _game: Node3D
var _song_player: AudioStreamPlayer

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
var _song_pos := PackedInt64Array()
var _drawn := PackedInt32Array()
var _focus_col := PackedByteArray()

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
	
	_start_recording()

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
	_song_pos.append(int(_song_player.get_playback_position() * 1000000.0))
	_drawn.append(Engine.get_frames_drawn())
	_focus_col.append(1 if _focused else 0)
	
	if _song_player.playing:
		_saw_playing = true
	elif _saw_playing:
		_finish("song_end")
		return
	
	if now - _start_usec >= _limit_usec:
		_finish(_limit_reason)

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
		rows[i + 1] = "%d,%d,%d,%d,%d,%d,%d" % [
			i, _ticks[i], _deltas[i], _proc_deltas[i],
			_song_pos[i], _drawn[i], _focus_col[i]]
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
