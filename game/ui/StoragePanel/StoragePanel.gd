extends Panel
class_name StoragePanel

## Storage panel (specs/026): every library map with its size and source, multi-select bulk
## delete and "delete all from a source", both behind a count + size confirmation.
##
## Deleting goes through StorageTools, which refuses any path that is not a direct child of
## `Songs/`; the panel never builds a recursive delete of its own.

signal closed

const CONFIRM_SECONDS := 5.0

@onready var total_label := $Margin/VBox/Header/TotalLabel as Label
@onready var select_all_button := $Margin/VBox/Toolbar/SelectAllButton as Button
@onready var clear_button := $Margin/VBox/Toolbar/ClearButton as Button
@onready var source_picker := $Margin/VBox/Toolbar/SourcePicker as OptionButton
@onready var delete_source_button := $Margin/VBox/Toolbar/DeleteSourceButton as Button
@onready var selected_label := $Margin/VBox/Toolbar/SelectedLabel as Label
@onready var rows_box := $Margin/VBox/ListScroll/Rows as VBoxContainer
@onready var status_label := $Margin/VBox/StatusLabel as Label
@onready var delete_button := $Margin/VBox/Footer/DeleteButton as Button
@onready var back_button := $Margin/VBox/Footer/BackButton as Button

var main_menu_ref: MainMenu

var _entries: Array = []       # {map: MapInfo, size: int}
var _rows: Array = []          # {check: CheckBox, entry: Dictionary}
var _pending: Array = []
var _pending_bytes := 0
var _pending_button: Button = null
var _confirm_timer: Timer

func _ready() -> void:
	UI_AudioEngine.attach_children(self)
	_confirm_timer = Timer.new()
	_confirm_timer.one_shot = true
	_confirm_timer.wait_time = CONFIRM_SECONDS
	_confirm_timer.timeout.connect(_reset_confirm)
	add_child(_confirm_timer)
	select_all_button.pressed.connect(_on_select_all_pressed)
	clear_button.pressed.connect(_on_clear_pressed)
	source_picker.item_selected.connect(_on_source_changed)
	delete_source_button.pressed.connect(_on_delete_source_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_update_selected()

## Called by the game after the canvas is shown. The scan is deferred so the panel draws first.
func open(menu_ref: MainMenu) -> void:
	main_menu_ref = menu_ref
	_reset_confirm()
	status_label.text = ""
	call_deferred("_load_maps")

func _load_maps() -> void:
	var started := Time.get_ticks_msec()
	for child in rows_box.get_children():
		rows_box.remove_child(child)
		child.queue_free()
	_rows.clear()
	_entries.clear()
	if main_menu_ref == null:
		return
	var maps: Array = main_menu_ref.get_library_maps()
	for map in maps:
		_entries.append({"map": map, "size": StorageTools.folder_size(map.filepath)})
	_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["size"]) > int(b["size"]))
	var total := 0
	for entry in _entries:
		total += int(entry["size"])
		_add_row(entry)
	total_label.text = "%d maps - %s" % [_entries.size(), StorageTools.format_bytes(total)]
	_update_source_picker()
	_update_selected()
	if _entries.is_empty():
		status_label.text = "No maps in the library."
	else:
		status_label.text = "Scanned %d folders in %d ms." % [_entries.size(), Time.get_ticks_msec() - started]
	_canvas_input_update()

func _add_row(entry: Dictionary) -> void:
	var map: MapInfo = entry["map"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var check := CheckBox.new()
	check.custom_minimum_size = Vector2(56, 0)
	check.toggled.connect(_on_row_toggled)
	row.add_child(check)
	var name_label := Label.new()
	name_label.text = map.song_name
	name_label.size_flags_horizontal = 3
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 24)
	row.add_child(name_label)
	var source_label := Label.new()
	source_label.text = MapSource.label(map.source)
	source_label.custom_minimum_size = Vector2(190, 0)
	source_label.add_theme_font_size_override("font_size", 22)
	row.add_child(source_label)
	var size_label := Label.new()
	size_label.text = StorageTools.format_bytes(int(entry["size"]))
	size_label.custom_minimum_size = Vector2(150, 0)
	size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	size_label.add_theme_font_size_override("font_size", 24)
	row.add_child(size_label)
	rows_box.add_child(row)
	_rows.append({"check": check, "entry": entry})

func _update_source_picker() -> void:
	var previous := ""
	if source_picker.item_count > 0 and source_picker.selected >= 0:
		previous = str(source_picker.get_item_metadata(source_picker.selected))
	var counts := {}
	for entry in _entries:
		var source := str(entry["map"].source)
		counts[source] = int(counts.get(source, 0)) + 1
	source_picker.clear()
	source_picker.add_item("All sources (%d)" % _entries.size())
	source_picker.set_item_metadata(0, StorageTools.SOURCE_ALL)
	var sources := counts.keys()
	sources.sort()
	for source in sources:
		var label := "%s (%d)" % [MapSource.label(str(source)), int(counts[source])]
		source_picker.add_item(label)
		source_picker.set_item_metadata(source_picker.item_count - 1, str(source))
	if previous.is_empty():
		source_picker.select(0)
	else:
		for i in range(source_picker.item_count):
			if str(source_picker.get_item_metadata(i)) == previous:
				source_picker.select(i)
				break
	_on_source_changed(source_picker.selected)

func _selected_entries() -> Array:
	var out: Array = []
	for row in _rows:
		if (row["check"] as CheckBox).button_pressed:
			out.append(row["entry"])
	return out

func _update_selected() -> void:
	var selected := _selected_entries()
	var total := 0
	for entry in selected:
		total += int(entry["size"])
	selected_label.text = "Selected: %d maps (%s)" % [selected.size(), StorageTools.format_bytes(total)]
	delete_button.disabled = selected.is_empty()
	_canvas_input_update()

func _on_row_toggled(_pressed: bool) -> void:
	_update_selected()
	_reset_confirm()

func _on_select_all_pressed() -> void:
	for row in _rows:
		(row["check"] as CheckBox).button_pressed = true
	_update_selected()
	_reset_confirm()

func _on_clear_pressed() -> void:
	for row in _rows:
		(row["check"] as CheckBox).button_pressed = false
	_update_selected()
	_reset_confirm()

func _on_source_changed(_index: int) -> void:
	var source := _current_source()
	var count := 0
	if source != StorageTools.SOURCE_ALL:
		for entry in _entries:
			if str(entry["map"].source) == source:
				count += 1
	delete_source_button.disabled = source == StorageTools.SOURCE_ALL or count == 0
	_reset_confirm()

func _current_source() -> String:
	if source_picker.item_count == 0 or source_picker.selected < 0:
		return StorageTools.SOURCE_ALL
	return str(source_picker.get_item_metadata(source_picker.selected))

func _arm(batch: Array, button: Button, verb: String) -> void:
	if batch.is_empty():
		status_label.text = "Nothing to delete for that choice."
		_reset_confirm()
		return
	_reset_confirm()
	_pending = batch.duplicate()
	_pending_bytes = 0
	for entry in _pending:
		_pending_bytes += int(entry["size"])
	_pending_button = button
	button.text = "Sure? %s (%s)" % [verb, StorageTools.format_bytes(_pending_bytes)]
	_confirm_timer.start()
	_canvas_input_update()

func _on_delete_pressed() -> void:
	if _pending_button == delete_button and not _pending.is_empty():
		_execute(_pending)
		return
	var selected := _selected_entries()
	_arm(selected, delete_button, "Delete %d maps" % selected.size())

func _on_delete_source_pressed() -> void:
	var source := _current_source()
	if source == StorageTools.SOURCE_ALL:
		return
	if _pending_button == delete_source_button and not _pending.is_empty():
		_execute(_pending)
		return
	var batch: Array = []
	for entry in _entries:
		# Re-read the sidecar so a stale tag cannot delete a folder that changed since load.
		if StorageTools.source_of(entry["map"].filepath) == source:
			batch.append(entry)
	_arm(batch, delete_source_button, "Delete %d %s maps" % [batch.size(), MapSource.label(source)])

func _execute(batch: Array) -> void:
	_reset_confirm()
	var removed := 0
	var removed_bytes := 0
	var failed := 0
	for entry in batch:
		var map: MapInfo = entry["map"]
		if not StorageTools.remove_map(map.filepath):
			failed += 1
			continue
		Highscores.remove_map(map)
		PlayCount.remove_map(map)
		removed += 1
		removed_bytes += int(entry["size"])
	var text := "Deleted %d maps (%s)" % [removed, StorageTools.format_bytes(removed_bytes)]
	if failed > 0:
		text += ", %d could not be deleted" % failed
	status_label.text = text
	_canvas_input_update()
	if main_menu_ref != null and removed > 0:
		main_menu_ref._on_LoadPlaylists_Button_pressed()
	call_deferred("_load_maps")

func _reset_confirm() -> void:
	_pending.clear()
	_pending_bytes = 0
	_pending_button = null
	if _confirm_timer != null:
		_confirm_timer.stop()
	if delete_button != null:
		delete_button.text = "Delete selected"
	if delete_source_button != null:
		delete_source_button.text = "Delete all from source"
	_canvas_input_update()

func _canvas_input_update() -> void:
	var node: Node = self
	while node != null:
		if node is OQ_UI2DCanvas:
			# The panel's _ready runs before the canvas's own _ready, when its viewport is null.
			if node.is_node_ready():
				(node as OQ_UI2DCanvas)._input_update()
			return
		node = node.get_parent()

func _on_back_pressed() -> void:
	_reset_confirm()
	closed.emit()

