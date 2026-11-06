extends Control

# The BeatSaver results pane (UI-4 step 3): the card list, its status line and Retry.
#
# Pure display. The panel owns fetching, paging, cover requests and selection; it calls
# set_rows()/clear_cards()/set_status() and listens to card_pressed/retry_pressed. Nothing here
# touches the API, an HTTPRequest or the cover cache.
#
# Full-panel Control with MOUSE_FILTER_IGNORE: every child keeps the rect it always had and the
# raycast targets are unchanged.

signal card_pressed(index: int)
signal retry_pressed

const MapCardScript := preload("res://game/ui/BeatSaverPanel/BeatSaverMapCard.gd")
const PANEL_SIZE := Vector2(1536, 960)

var card_pool_size := 20

var scroll: ScrollContainer
var card_list: VBoxContainer
var cards: Array = []
var status_label: Label
var retry_button: Button

func _ready() -> void:
	name = "ResultsView"
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Cards.
	scroll = ScrollContainer.new()
	scroll.name = "CardsScroll"
	scroll.position = Vector2(16, 204)
	scroll.size = Vector2(864, 636)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)

	card_list = VBoxContainer.new()
	card_list.name = "CardList"
	card_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_list.add_theme_constant_override("separation", 8)
	scroll.add_child(card_list)

	for i in card_pool_size:
		var card = MapCardScript.new()
		card.name = "MapCard%d" % i
		card.visible = false
		card_list.add_child(card)
		card.pressed.connect(_on_card_pressed.bind(i))
		cards.append(card)

	# Status line next to the difficulty chips, and Retry at the right edge of that row.
	status_label = Label.new()
	status_label.position = Vector2(600, 138)
	status_label.size = Vector2(776, 54)
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status_label)

	retry_button = Button.new()
	retry_button.position = Vector2(1392, 138)
	retry_button.size = Vector2(120, 54)
	retry_button.text = "Retry"
	retry_button.clip_text = true
	retry_button.visible = false
	retry_button.pressed.connect(_on_retry_pressed)
	add_child(retry_button)

# Shows `rows` and returns the cover requests the panel should make, as [index, url] pairs.
func set_rows(rows: Array) -> Array:
	var requests: Array = []
	for i in cards.size():
		var card = cards[i]
		if i < rows.size():
			card.set_map(rows[i], i)
			requests.append([i, rows[i].cover_url])
		else:
			card.clear()
	return requests

func clear_cards() -> void:
	for card: Variant in cards:
		card.clear()

func apply_cover(index: int, url: String, texture: Texture2D) -> void:
	if index < 0 or index >= cards.size():
		return
	cards[index].apply_cover(url, texture)

func set_status(text: String, retry_visible: bool) -> void:
	status_label.text = text
	retry_button.visible = retry_visible

func _on_card_pressed(index: int) -> void:
	card_pressed.emit(index)

func _on_retry_pressed() -> void:
	retry_pressed.emit()
