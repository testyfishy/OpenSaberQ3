extends Node

@export var scroll_node_path: NodePath
# The 2D canvas this list lives on. OQ's canvas only re-renders when something asks it to
# (`update_only_on_input`), so a scroll that changes `value` alone moves the list in the
# ScrollContainer while the displayed texture stays put - which reads as "a couple of ticks,
# then it stops". Asking the canvas for an update while scrolling is what makes it smooth.
@export var canvas_path: NodePath

var scroll_node: Control
var canvas: Node
var v_scroll: VScrollBar
var is_mouse_in := false
var relpos := 0.0
var scrollpos := 0.0
var _live := false

# Scrolls only while the pointer is over the list - that is the intended interaction: point at
# the list, then push the stick. Hover does not gate the smoothness, it gates the permission.

# Deadzone pair, so a stick resting near the edge cannot chatter on and off.
const JOYSTICK_SCROLL_ENGAGE := 0.18
const JOYSTICK_SCROLL_RELEASE := 0.10

# Pixels per second at engagement and at full throw. The old low end was 10 px/s, which at
# 120 Hz is under one pixel per frame: the integer scroll position rounded every one of those
# away, so a gentle push produced nothing at all and a hard push produced a jump.
const JOYSTICK_SLOW_SCROLL_SPEED := 260.0
const JOYSTICK_FAST_SCROLL_SPEED := 2400.0
const JOYSTICK_ACCEL := 2600.0

# Bench-only: lets a probe drive the stick without a controller (`INF` = read the real one).
# Used by BenchmarkRunner's ui_scroll_probe to measure the scroll value sequence per frame.
static var debug_stick := INF
static var debug_hover := false
# Countdown of frames left to log the stick reading, so a report of "it still does not scroll" can
# be answered with whether the stick value ever arrived.
static var _debug_frames := 0

var _engaged := false
# Fractional pixels carried between frames, so slow scrolling is not lost to rounding.
var _accum := 0.0
var _speed := 0.0

func _ready() -> void:
	scroll_node = get_node(scroll_node_path) as Control
	if not canvas_path.is_empty():
		canvas = get_node_or_null(canvas_path)
	if canvas == null:
		# Walk up to the OQ_UI2DCanvas that owns this sub-viewport.
		var n := get_parent()
		while n != null:
			if n.has_method(&"_input_update"):
				canvas = n
				break
			n = n.get_parent()
	
	if scroll_node is ItemList:
		v_scroll = (scroll_node as ItemList).get_v_scroll_bar()
	elif scroll_node is ScrollContainer:
		v_scroll = (scroll_node as ScrollContainer).get_v_scroll_bar()
	
	@warning_ignore("return_value_discarded")
	scroll_node.connect(&"mouse_entered", Callable(self, &"_mouse_entered"))
	@warning_ignore("return_value_discarded")
	scroll_node.connect(&"mouse_exited", Callable(self, &"_mouse_exited"))

func _process(delta: float) -> void:
	var newpos := -vr.rightController.rotation_degrees.x - (vr.rightController.transform.origin.y * 20.0)
	# Scrolling is stick-only. Drag-scrolling was removed because pressing the trigger while
	# pointing at a list (to select a card or a setting) also pushed the list, which read as
	# "the screen moves when I click".
	if true:
		# The stick scrolls whenever this slider's page is up, not only while the pointer happens
		# to be inside the scroll rect. Hover-gating the stick (the original behaviour) meant any
		# wobble of the ray off the list silently disabled scrolling, which is what "the joystick
		# does not scroll" turned out to be. Drag still requires the pointer, because dragging
		# without it has no meaning.
		_stick_scroll(delta)
	relpos = newpos

func _stick_scroll(delta: float) -> void:
	if v_scroll == null or not _page_visible():
		_speed = 0.0
		_set_live(false)
		return
	var y_joy: float = debug_stick if is_finite(debug_stick) else vr.rightController.get_vector2("primary").y
	if not is_finite(debug_stick) and _debug_frames > 0:
		_debug_frames -= 1
		if absf(y_joy) > 0.05:
			vr.log_info("SCROLLCHK stick_y=%.2f applied" % y_joy)
	var magnitude := absf(y_joy)
	if _engaged:
		if magnitude < JOYSTICK_SCROLL_RELEASE:
			_engaged = false
	elif magnitude > JOYSTICK_SCROLL_ENGAGE:
		_engaged = true
	if not _engaged:
		_speed = move_toward(_speed, 0.0, JOYSTICK_ACCEL * delta)
		if _speed <= 0.0:
			_set_live(false)
		# Keep the accumulator's remainder, but do not resume at the old speed next time.
		return
	var span := 1.0 - JOYSTICK_SCROLL_ENGAGE
	var t := clampf((magnitude - JOYSTICK_SCROLL_ENGAGE) / maxf(span, 0.001), 0.0, 1.0)
	_speed = move_toward(
		_speed,
		lerpf(JOYSTICK_SLOW_SCROLL_SPEED, JOYSTICK_FAST_SCROLL_SPEED, t),
		JOYSTICK_ACCEL * delta)
	_accum += _speed * -signf(y_joy) * delta
	var whole := int(_accum)
	if whole != 0:
		_accum -= float(whole)
		var before := v_scroll.value
		v_scroll.value += whole
		if v_scroll.value != before:
			# Render every frame while the list is actually moving; the texture then cannot be
			# one or more frames behind the scroll value.
			_set_live(true)

# The canvas redraws only when asked. One call per changed frame is the same thing every other
# panel state change does (BeatSaverPanel._canvas_input_update).
func _request_refresh() -> void:
	if canvas != null and canvas.has_method(&"_input_update"):
		canvas.call(&"_input_update")

# True when the page that owns this slider is visible. The stick scrolls whenever the page is up;
# only dragging needs the pointer on the list.
func _page_visible() -> bool:
	var n := get_parent()
	while n != null:
		if n is Control:
			return (n as Control).is_visible_in_tree()
		n = n.get_parent()
	return true

func _mouse_entered() -> void:
	is_mouse_in = true

func _mouse_exited() -> void:
	is_mouse_in = false
	_engaged = false
	_speed = 0.0

# Switching the owning SubViewport between ALWAYS and DISABLED is the whole redraw policy. On stop
# we request exactly one update, so the last frame is drawn and no coroutine is left pending.
func _set_live(value: bool) -> void:
	if value == _live:
		return
	_live = value
	var vp := get_viewport()
	if vp == null:
		return
	if value:
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	else:
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_request_refresh()
