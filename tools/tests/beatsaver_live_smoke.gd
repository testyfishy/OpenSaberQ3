extends SceneTree

## Live smoke test for the BeatSaver browser panel: instantiates the real scene against the real
## API (default filters, page 1), then reports what it parsed.
##
##   godot --headless --path . --script res://tools/tests/beatsaver_live_smoke.gd
##
## Not part of the parse gate - it needs network access and takes a few seconds.

const TIMEOUT_SECONDS := 25.0
const PAGE_SIZE := 20

var _panel: Node
var _elapsed := 0.0
var _started := false
var _reported := false


func _initialize() -> void:
	var scene: PackedScene = load("res://game/ui/BeatSaverPanel/BeatSaverPanel.tscn")
	if scene == null:
		printerr("SMOKE FAIL: could not load BeatSaverPanel.tscn")
		quit(1)
		return
	_panel = scene.instantiate()
	root.add_child(_panel)


func _process(delta: float) -> bool:
	_elapsed += delta
	if not _started:
		# _ready has run by now; open the panel exactly like MapDownloadPanel does.
		_started = true
		# The VR scroller expects a headset; it has no business running in this test.
		var slider: Node = _panel.call("get_list_slider")
		if slider != null:
			slider.set_process(false)
		_panel._show()
		print("SMOKE: opened panel, request = %s" % _panel.BeatSaverApi.build_search_url(_panel._query, 0))
		return false
	if _reported:
		return false
	if not _panel._loading and not _panel._rows.is_empty():
		_reported = true
		_report()
		return false
	if _elapsed > TIMEOUT_SECONDS:
		_reported = true
		printerr("SMOKE FAIL: timed out after %ds (loading=%s error='%s')" % [
			int(TIMEOUT_SECONDS), str(_panel._loading), str(_panel._error_message)])
		quit(1)
		return true
	return false


func _report() -> void:
	print("SMOKE: rows=%d total=%d pages=%d page_label='%s'" % [
		_panel._rows.size(), _panel._total, _panel.BeatSaverApi.total_pages(_panel._total), _panel._page_label.text])
	print("SMOKE: status='%s'" % _panel._status_label.text)
	if _panel._rows.size() < PAGE_SIZE:
		printerr("SMOKE FAIL: a display page should hold %d cards, got %d" % [PAGE_SIZE, _panel._rows.size()])
		quit(1)
		return

	for i in mini(3, _panel._rows.size()):
		var map = _panel._rows[i]
		print("SMOKE: [%d] %s | %s | %s | %d BPM | votes=%s | standard_diffs=%d | mods=%s | cover=%s" % [
			i, map.id, map.name, _panel.BeatSaverApi.format_duration(map.duration), roundi(map.bpm),
			_panel.BeatSaverApi.vote_percent(map),
			map.standard_diffs().size(),
			str(map.required_mods()),
			"yes" if not map.cover_url.is_empty() else "no",
		])

	# Covers are decoded off the main thread and delivered deferred, so the count taken
	# immediately is always 0. Wait for the async pipeline before judging it.
	await create_timer(4.0).timeout
	var cached := 0
	for row in _panel._rows:
		if _panel._covers.has_cached(row.cover_url):
			cached += 1
	print("SMOKE: covers decoded and cached after a 4 s wait = %d/%d" % [cached, _panel._rows.size()])

	# Exercise the pager + a client-side filter against the live API.
	_panel._playable_toggle.button_pressed = true
	_panel._on_filter_toggled(true)
	print("SMOKE: filter re-query url = %s" % _panel.BeatSaverApi.build_search_url(_panel._query, 0))
	print("SMOKE OK")
	quit(0)
