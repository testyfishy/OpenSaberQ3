extends Control

# The BeatSaver details pane (UI-4 step 2): cover, song text, Download and Maps-by.
#
# Pure display. The panel owns the selection, the cover cache and the download queue, calls
# show_map()/show_placeholder()/set_cover(), and listens to the two signals. Nothing here touches
# the API or an HTTPRequest.
#
# It is a code-built control because the whole panel is: the children keep the absolute rects the
# panel always used, and the container ignores the mouse so the raycast targets do not change.

signal download_pressed
signal maps_by_pressed

const PLACEHOLDER_COVER := preload("res://game/data/beepsaber_logo.png")
const PANEL_SIZE := Vector2(1536, 960)

var cover: TextureRect
var song_data: RichTextLabel
var download_button: Button
var maps_by_button: Button

func _ready() -> void:
	name = "DetailView"
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	cover = TextureRect.new()
	cover.name = "DetailsCover"
	cover.position = Vector2(904, 204)
	cover.size = Vector2(616, 264)
	cover.texture = PLACEHOLDER_COVER
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cover)

	song_data = RichTextLabel.new()
	song_data.name = "SongData"
	song_data.position = Vector2(904, 478)
	song_data.size = Vector2(616, 308)
	song_data.bbcode_enabled = true
	song_data.scroll_active = false
	song_data.text = "Select a map to see the details.\n\nPress Download to add it to your library."
	add_child(song_data)

	download_button = _button(Rect2(904, 796, 296, 56), "Download")
	download_button.pressed.connect(_on_download_pressed)
	maps_by_button = _button(Rect2(1216, 796, 304, 56), "Maps by…")
	maps_by_button.pressed.connect(_on_maps_by_pressed)
	maps_by_button.disabled = true

# What the pane shows before a map is selected and after a new search clears the selection.
func show_placeholder() -> void:
	cover.texture = PLACEHOLDER_COVER
	song_data.text = "Select a map to see the details.\n\nPress Download to add it to your library."
	maps_by_button.text = "Maps by…"
	maps_by_button.disabled = true

# `details_text` is built by the panel: the view does not know how a map is formatted.
func show_map(map: Variant, details_text: String) -> void:
	cover.texture = PLACEHOLDER_COVER
	song_data.text = details_text
	maps_by_button.text = "Maps by %s" % map.mapper
	maps_by_button.disabled = map.uploader_name.is_empty() and map.mapper.is_empty()

func set_cover(texture: Texture2D) -> void:
	if texture != null:
		cover.texture = texture

func _on_download_pressed() -> void:
	download_pressed.emit()

func _on_maps_by_pressed() -> void:
	maps_by_pressed.emit()

func _button(rect: Rect2, text: String) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.text = text
	button.clip_text = true
	add_child(button)
	return button
