extends Node
class_name MapSourceBackfill

## One-shot, menu-only backfill of the source tag for maps that predate the sidecar
## (specs/020 FR-007/FR-008).
##
## For each map with no sidecar: compute the Beat Saber level hash, ask BeatSaver
## `GET /maps/hash/{hash}`, then write `source=beatsaver` + map id on a hit, or
## `source=unknown` + the hash on a 404. A network failure writes nothing, so the map is retried
## in a later session instead of being branded Unknown by a flaky connection.
##
## Everything happens from the menu, one map at a time, with a frame yielded between maps. There
## is no timer and no per-frame work: the loop only runs while `can_run` says the menu is up.

signal map_updated(info: MapInfo)
signal progress(done: int, total: int)
signal finished(updated: int)

const BeatSaverApi := preload("res://game/ui/BeatSaverPanel/BeatSaverApi.gd")
const LOOKUP_URL := "https://api.beatsaver.com/maps/hash/%s"

var _http: HTTPRequest
var _queue: Array[MapInfo] = []
var _total := 0
var _done := 0
var _updated := 0
var _running := false
var _stop := false
var _can_run: Callable
var _last_map_id := ""

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)

func is_running() -> bool:
	return _running

## Starts one pass over `maps`. Only maps without a sidecar are considered: a map already
## classified (including a previous 404 with its hash) is not looked up again every session.
func start(maps: Array[MapInfo], can_run: Callable = Callable()) -> void:
	if _running:
		return
	_running = true
	_stop = false
	_can_run = can_run
	_queue.clear()
	for info: MapInfo in maps:
		if info == null:
			continue
		if info.source != MapSource.SOURCE_UNKNOWN:
			continue
		if MapSource.has_sidecar(info.filepath):
			continue
		_queue.append(info)
	_total = _queue.size()
	_done = 0
	_updated = 0
	if _total == 0:
		_running = false
		finished.emit(0)
		return
	_run()

## Stops the pass without writing anything for the map in flight. Called when the player leaves
## the menu or starts a map.
func stop() -> void:
	_stop = true
	_queue.clear()
	if _http != null:
		_http.cancel_request()
	_running = false

func _run() -> void:
	while not _stop and not _queue.is_empty():
		if _can_run.is_valid() and not bool(_can_run.call()):
			break
		var info: MapInfo = _queue.pop_front()
		# One frame between maps: hashing reads the whole map and must not stack up into a
		# menu hitch.
		await get_tree().process_frame
		if _stop or not is_instance_valid(info):
			break
		var hash := info.level_hash
		if hash.is_empty():
			hash = MapSource.compute_level_hash(info.filepath)
			if hash.is_empty():
				# Unreadable or incomplete map: leave it Unknown, do not write a guess.
				_done += 1
				progress.emit(_done, _total)
				continue
			info.level_hash = hash
		var code := await _lookup(hash)
		if _stop:
			break
		if code == 200:
			MapSource.write(info.filepath, MapSource.SOURCE_BEATSAVER, _last_map_id, hash)
			info.source = MapSource.SOURCE_BEATSAVER
			info.source_id = _last_map_id
			_updated += 1
			map_updated.emit(info)
		elif code == 404:
			MapSource.write(info.filepath, MapSource.SOURCE_UNKNOWN, "", hash)
			info.source = MapSource.SOURCE_UNKNOWN
			info.source_id = ""
		_done += 1
		progress.emit(_done, _total)

	_running = false
	if not _stop:
		finished.emit(_updated)

## Returns the HTTP status, or -1 for any transport/parse failure (which must not be persisted).
func _lookup(hash: String) -> int:
	var err := _http.request(LOOKUP_URL % hash, PackedStringArray(["User-Agent: " + BeatSaverApi.USER_AGENT]))
	if err != OK:
		return -1
	var res: Array = await _http.request_completed
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
		return -1
	var code := int(res[1])
	if code == 404:
		return 404
	if code != 200:
		return -1
	var id := _map_id(res[3] as PackedByteArray)
	if id.is_empty():
		return -1
	_last_map_id = id
	return 200

func _map_id(body: PackedByteArray) -> String:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		return ""
	return Utils.get_str(parsed as Dictionary, "id", "").strip_edges()
