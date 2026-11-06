extends Node

# UI-1 gate: the canvas refresh authority's liveness contract.
#
# The bug this exists to catch: the watchdog treats 0.5 s without a heartbeat as a lost owner and
# stops rendering. If the caller registers once and never heartbeats (the old `_set_live` early
# return), a scroll longer than 0.5 s goes dark while the scroll value keeps moving.
#
# Checks:
#  1. heartbeats every frame keep the viewport UPDATE_ALWAYS past the watchdog window;
#  2. no heartbeat for the window makes it DISABLED and clears the owner;
#  3. registering again recovers (ALWAYS, owner present);
#  4. end_live leaves it DISABLED with one final frame requested.
#
# Run: godot --headless --path . res://tools/harness/verify_canvas_refresh.tscn

const WINDOW_MS := 800  # comfortably past CanvasRefresh.WATCHDOG_S (0.5 s)

var _bad := 0

func _ready() -> void:
	var vp := SubViewport.new()
	add_child(vp)
	var holder := Node.new()
	vp.add_child(holder)
	var refresh := CanvasRefresh.of(holder)
	if refresh == null:
		fail("CanvasRefresh.of() returned null")
		finish()
		return

	# 1. Heartbeat every frame for longer than the watchdog window.
	var start := Time.get_ticks_msec()
	var frames := 0
	while Time.get_ticks_msec() - start < WINDOW_MS:
		refresh.begin_live(holder)
		await get_tree().process_frame
		frames += 1
	if vp.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
		fail("heartbeat lost live mode after %d frames / %d ms" % [frames, Time.get_ticks_msec() - start])
	if (refresh.get("_live") as Dictionary).is_empty():
		fail("heartbeat lost its owner registration")

	# 2. Silence: the watchdog must stop continuous rendering rather than pin the viewport. It
	# requests one final frame, so UPDATE_ONCE is the healthy result as well as DISABLED.
	start = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < WINDOW_MS:
		await get_tree().process_frame
	if vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
		fail("watchdog left the viewport rendering continuously after silence")
	if not (refresh.get("_live") as Dictionary).is_empty():
		fail("watchdog did not clear the stale owner")

	# 3. A scroll that resumes after the watchdog must recover.
	refresh.begin_live(holder)
	await get_tree().process_frame
	if vp.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
		fail("re-registering after the watchdog did not restore live mode")
	if (refresh.get("_live") as Dictionary).is_empty():
		fail("re-registering after the watchdog did not restore the owner")

	# 4. Normal stop: disabled, owner gone, one final frame requested.
	refresh.end_live(holder)
	if vp.render_target_update_mode != SubViewport.UPDATE_DISABLED:
		fail("end_live did not disable the viewport")
	if not (refresh.get("_live") as Dictionary).is_empty():
		fail("end_live did not clear the owner")
	await get_tree().process_frame
	if bool(refresh.get("_dirty")):
		fail("end_live's final frame request was never consumed")

	finish()

func fail(message: String) -> void:
	push_error("VERIFYCANVAS " + message)
	_bad += 1

func finish() -> void:
	print("VERIFYCANVAS bad=%d" % _bad)
	get_tree().quit(0 if _bad == 0 else 1)
