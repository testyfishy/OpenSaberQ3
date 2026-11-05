extends Node
class_name CanvasRefresh

# One refresh authority per OQ_UI2D canvas (v0.4 UI-1).
#
# Before this, three places asked the canvas to redraw in different ways: `vr_slider` called
# `canvas._input_update()` on every moved frame (which starts a three-frame `update_once`
# coroutine), the BeatSaver panel called the same method for its own reasons, and the settings
# panel had a third path. Several coroutines could be alive at once, sharing one frame counter,
# and frames rendered while the viewport was DISABLED showed the previous scroll position.
#
# This node owns the viewport's update mode:
#   request()          - coalesce any number of requests into one render on the next frame
#   begin_live(owner)  - keep rendering every frame while owners are registered (scrolling)
#   end_live(owner)    - release; the last release requests one final frame
#   keep_alive()       - watchdog heartbeat; a lost end_live cannot pin the viewport on forever
#
# It lives as a child of the canvas's SubViewport and is found through that viewport's meta, so
# there is no autoload and no cross-canvas state.

const WATCHDOG_S := 0.5

static func of(node: Node) -> CanvasRefresh:
	if node == null:
		return null
	var vp := node.get_viewport()
	if vp == null:
		return null
	var existing: Variant = vp.get_meta(&"canvas_refresh", null)
	if existing is CanvasRefresh:
		return existing as CanvasRefresh
	var created := CanvasRefresh.new()
	created.name = "CanvasRefresh"
	created._viewport = vp
	vp.add_child(created)
	vp.set_meta(&"canvas_refresh", created)
	return created

var _viewport: SubViewport
var _dirty := false
var _live: Dictionary = {}
var _last_keepalive := 0.0

func request() -> void:
	_dirty = true
	set_process(true)

func begin_live(owner: Object) -> void:
	if owner == null:
		return
	_live[owner.get_instance_id()] = true
	keep_alive()
	if owner is Node and not (owner as Node).tree_exiting.is_connected(_on_owner_exiting.bind(owner)):
		(owner as Node).tree_exiting.connect(_on_owner_exiting.bind(owner), CONNECT_ONE_SHOT)
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	set_process(true)

func end_live(owner: Object) -> void:
	if owner == null:
		return
	_live.erase(owner.get_instance_id())
	if _live.is_empty():
		if _viewport != null:
			_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		request()

func keep_alive() -> void:
	_last_keepalive = Time.get_ticks_msec() * 0.001

func _on_owner_exiting(owner: Object) -> void:
	end_live(owner)

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() * 0.001
	if not _live.is_empty() and now - _last_keepalive > WATCHDOG_S:
		# An owner vanished without end_live. Stop rendering rather than pinning the viewport.
		_live.clear()
		if _viewport != null:
			_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		request()
	if _dirty and _live.is_empty():
		_dirty = false
		if _viewport != null:
			_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if _dirty == false and _live.is_empty():
		set_process(false)
