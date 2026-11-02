extends Node

## Cover art for the BeatSaver browser: download through an HTTPRequestPool, decode on a worker
## thread, cache by URL.
##
## Cover URLs are per-hash on the CDN and therefore immutable, so a URL is a perfect cache key.
## `ImageTexture.create_from_image` stays on the main thread; only `Image` decoding and resizing
## happen on the worker (FR-012).

const HTTP_REQUEST_POOL := preload("res://game/scripts/HTTPRequestPool.tscn")
const BeatSaverApi := preload("res://game/ui/BeatSaverPanel/BeatSaverApi.gd")

## Keep one page plus its prefetch plus a little history. 256 px jpgs are ~256 KB of VRAM each.
const MAX_CACHED_TEXTURES := 60
const MAX_CONCURRENT_DOWNLOADS := 4
const MAX_COVER_PIXELS := 256

var _textures := {}          # url -> ImageTexture
var _cache_order: Array[String] = []
var _waiters := {}           # url -> Array[Callable]
var _pending := {}           # url -> true (queued or downloading or decoding)
var _queue: Array[String] = []
var _task_ids := {}          # url -> WorkerThreadPool task id
var _pool: Node
var _active_downloads := 0


func _ready() -> void:
	_pool = HTTP_REQUEST_POOL.instantiate()
	_pool.name = "CoverRequestPool"
	_pool.max_simultaneous_request = MAX_CONCURRENT_DOWNLOADS
	_pool.request_timeout = 8.0
	_pool.default_headers = PackedStringArray(["User-Agent: " + BeatSaverApi.USER_AGENT])
	add_child(_pool)
	_pool.request_complete.connect(_on_request_complete)


## Requests a cover. `callback` is called with an ImageTexture, or null on failure, and is
## called immediately (same frame) when the URL is already cached.
func request(url: String, callback: Callable = Callable()) -> void:
	if url.is_empty():
		return
	if _textures.has(url):
		if callback.is_valid():
			callback.call(_textures[url])
		return
	if _waiters.has(url):
		if callback.is_valid():
			_waiters[url].append(callback)
		return
	_waiters[url] = []
	if callback.is_valid():
		_waiters[url].append(callback)
	if not _pending.has(url):
		_pending[url] = true
		_queue.append(url)
		_pump()


## Warms the cache for a page that is not on screen yet.
func prefetch(url: String) -> void:
	request(url)


func get_cached(url: String) -> ImageTexture:
	return _textures.get(url, null)


func has_cached(url: String) -> bool:
	return _textures.has(url)


func cancel_all() -> void:
	_queue.clear()
	_waiters.clear()
	_pending.clear()
	_active_downloads = 0
	if _pool != null:
		_pool.cancel_all()


func _pump() -> void:
	while _active_downloads < MAX_CONCURRENT_DOWNLOADS and not _queue.is_empty():
		var url: String = _queue.pop_front()
		_active_downloads += 1
		_pool.request(url, {"url": url})


func _on_request_complete(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, _token: int, user_data: Dictionary) -> void:
	_active_downloads = maxi(0, _active_downloads - 1)
	var url := String(user_data.get("url", ""))
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200 and not body.is_empty():
		_start_decode(url, body)
	else:
		_fail(url)
	_pump()


func _start_decode(url: String, body: PackedByteArray) -> void:
	# Fire and forget; the id is waited on in _on_decoded so it is never leaked.
	var task_id := WorkerThreadPool.add_task(_decode_thread.bind(url, body), false, "beatsaver_cover")
	_task_ids[url] = task_id


## Runs on a worker thread. Only CPU work here - no scene tree, no RenderingServer.
func _decode_thread(url: String, body: PackedByteArray) -> void:
	var img := Image.new()
	var err := img.load_jpg_from_buffer(body)
	if err != OK:
		err = img.load_png_from_buffer(body)
	if err != OK:
		_on_decoded.call_deferred(url, null)
		return
	if img.get_width() > MAX_COVER_PIXELS or img.get_height() > MAX_COVER_PIXELS:
		img.resize(MAX_COVER_PIXELS, MAX_COVER_PIXELS, Image.INTERPOLATE_BILINEAR)
	_on_decoded.call_deferred(url, img)


## Back on the main thread.
func _on_decoded(url: String, img: Image) -> void:
	if _task_ids.has(url):
		WorkerThreadPool.wait_for_task_completion(_task_ids[url])
		_task_ids.erase(url)
	if img == null:
		_fail(url)
		return
	var texture := ImageTexture.create_from_image(img)
	_textures[url] = texture
	_cache_order.append(url)
	while _cache_order.size() > MAX_CACHED_TEXTURES:
		var oldest: String = _cache_order.pop_front()
		if oldest != url:
			_textures.erase(oldest)
	_deliver(url, texture)


func _deliver(url: String, texture: ImageTexture) -> void:
	_pending.erase(url)
	var waiters: Array = _waiters.get(url, [])
	_waiters.erase(url)
	for cb: Variant in waiters:
		var callback: Callable = cb
		if callback.is_valid():
			callback.call(texture)


func _fail(url: String) -> void:
	_pending.erase(url)
	var waiters: Array = _waiters.get(url, [])
	_waiters.erase(url)
	for cb: Variant in waiters:
		var callback: Callable = cb
		if callback.is_valid():
			callback.call(null)
