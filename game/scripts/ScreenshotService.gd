extends Node
class_name ScreenshotService

## In-game screenshots without the system capture gesture (specs/024 FR-004..FR-008).
##
## The XR eye buffers belong to the runtime swapchain, so `get_viewport().get_texture()` is black
## on the headset. This service renders the same World3D from a normal Camera3D placed at the XR
## camera pose into a SubViewport, reads that texture, and writes the PNG on a worker thread.
##
## The first capture may stall for about a second while the Mobile renderer compiles pipelines for
## the new framebuffer; later captures are short. Encoding/replacing the image is done on
## WorkerThreadPool so the save does not add a second main-thread hitch.

const CAPTURE_SIZE := Vector2i(1920, 1080)
const FOV_VERTICAL := 75.0
const COOLDOWN_MS := 2000
const TOAST_LAYER := 1 << 19  # layer 20, excluded from the capture camera's cull mask
const TOAST_SECONDS := 2.5

var xr_camera: XRCamera3D

var _toast: Label3D
var _toast_timer: Timer
var _last_capture_ms := -100000
var _busy := false
var _tasks: Array[int] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_unhandled_input(true)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.wait_time = TOAST_SECONDS
	_toast_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_toast_timer.timeout.connect(_hide_toast)
	add_child(_toast_timer)
	if xr_camera != null:
		# The toast must be visible to the player's camera but not to the capture camera.
		xr_camera.cull_mask = xr_camera.cull_mask | TOAST_LAYER

func _exit_tree() -> void:
	for id: int in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F12:
		capture()

## Captures whatever is currently visible. Returns {ok, path, error, width, height}.
func capture() -> Dictionary:
	if _busy or xr_camera == null:
		return {"ok": false, "error": "busy"}
	var now := Time.get_ticks_msec()
	if now - _last_capture_ms < COOLDOWN_MS:
		return {"ok": false, "error": "cooldown"}
	_busy = true
	_last_capture_ms = now
	_hide_toast()

	var vp := SubViewport.new()
	vp.size = CAPTURE_SIZE
	vp.own_world_3d = false
	vp.world_3d = xr_camera.get_world_3d()
	vp.transparent_bg = false
	vp.msaa_3d = clampi(Settings.msaa_3d, 0, 2) as Viewport.MSAA
	add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	cam.global_transform = xr_camera.global_transform
	cam.cull_mask = xr_camera.cull_mask & ~TOAST_LAYER
	cam.environment = xr_camera.environment
	cam.attributes = xr_camera.attributes
	cam.fov = FOV_VERTICAL
	cam.near = 0.05
	cam.far = 2000.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE

	# Two post-draw waits: the first schedules the render, the second lets the texture settle.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	_busy = false

	if img == null or img.is_empty():
		show_toast("Screenshot failed")
		return {"ok": false, "error": "empty_image"}
	if _looks_black(img):
		show_toast("Screenshot failed (black)")
		return {"ok": false, "error": "black_image"}

	var path := _next_path()
	var dir := path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		dir = ProjectSettings.globalize_path("user://screenshots")
		DirAccess.make_dir_recursive_absolute(dir)
		path = dir.path_join(path.get_file())
	var task := WorkerThreadPool.add_task(_write_png.bind(img, path), false, "screenshot")
	_tasks.append(task)
	vr.log_info("SCREENSHOT %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	show_toast("Screenshot saved")
	return {"ok": true, "path": path, "width": img.get_width(), "height": img.get_height()}

## Captures after hiding `hide_nodes` (the pause canvas and the UI rays), then restores them.
func capture_from(hide_nodes: Array) -> void:
	var hidden: Array = []
	for node: Node in hide_nodes:
		if node == null or not node.visible:
			continue
		if node.has_method("_hide"):
			node.call("_hide")
		else:
			node.visible = false
		hidden.append(node)
	await get_tree().process_frame
	await get_tree().process_frame
	await capture()
	for node: Node in hidden:
		if node.has_method("_show"):
			node.call("_show")
		else:
			node.visible = true

func show_toast(text: String) -> void:
	if xr_camera == null:
		return
	if _toast == null:
		_toast = Label3D.new()
		_toast.font = preload("res://OQ_Toolkit/OQ_UI2D/theme/Roboto-Medium.ttf")
		_toast.font_size = 32
		_toast.pixel_size = 0.003
		_toast.outline_size = 10
		_toast.outline_modulate = Color(0, 0, 0, 0.85)
		_toast.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_toast.no_depth_test = true
		_toast.layers = TOAST_LAYER
		_toast.position = Vector3(0, -0.32, -0.9)
		xr_camera.add_child(_toast)
	_toast.text = text
	_toast.visible = true
	_toast_timer.start()

func _hide_toast() -> void:
	if _toast != null:
		_toast.visible = false

func _write_png(img: Image, path: String) -> void:
	var err := img.save_png(path)
	if err != OK:
		print("SCREENSHOT write failed: ", path, " err=", err)
	else:
		print("SCREENSHOT saved: ", path)

func _next_path() -> String:
	var dir := screenshots_dir()
	var stamp := Time.get_datetime_string_from_system(false, true)
	stamp = stamp.replace("T", "_").replace(":", "-")
	var base := dir.path_join("OpenSaberQ3_%s" % stamp)
	var path := base + ".png"
	var n := 1
	while FileAccess.file_exists(path):
		path = "%s_%d.png" % [base, n]
		n += 1
	return path

static func screenshots_dir() -> String:
	var dir := ""
	if OS.has_feature("android"):
		var external := _android_external_files_dir()
		if not external.is_empty():
			dir = external.path_join("screenshots")
	if dir.is_empty():
		dir = ProjectSettings.globalize_path("user://screenshots")
	return dir

## Same derivation as the bench flag path: Godot has no external-data-dir accessor, so map
## /data/user/0/<package>/files to /storage/emulated/0/Android/data/<package>/files. The app owns
## that directory, so reading it over adb needs no storage permission.
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

func _looks_black(img: Image) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	for y in 3:
		for x in 5:
			var c := img.get_pixel(int(w * (x + 0.5) / 5.0), int(h * (y + 0.5) / 3.0))
			if c.r > 0.02 or c.g > 0.02 or c.b > 0.02:
				return false
	return true
