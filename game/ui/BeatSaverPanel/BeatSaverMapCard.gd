extends Button

## One map, as a card: cover, title, mapper, m:ss, BPM, vote percentage, one pill per difficulty,
## characteristic tags and requirement badges.
##
## Cards are pooled by the panel (20 instances, reused for every page) so changing page does not
## allocate a new node tree in VR. A card remembers the cover URL it asked for and ignores any
## delivery for a different one, which makes a late cover thread harmless.

const BeatSaverApi := preload("res://game/ui/BeatSaverPanel/BeatSaverApi.gd")
const PLACEHOLDER_COVER := preload("res://game/data/beepsaber_logo.png")

const CARD_HEIGHT := 150
const COVER_SIZE := 122

const COLOR_LIT_BG := Color(1, 1, 1, 1)
const COLOR_LIT_TEXT := Color(0.04, 0.04, 0.04, 1)
const COLOR_OFF_BG := Color(0.14, 0.14, 0.14, 1)
const COLOR_OFF_TEXT := Color(0.42, 0.42, 0.42, 1)
const COLOR_TAG_BG := Color(0.22, 0.22, 0.22, 1)
const COLOR_BADGE_BG := Color(0.85, 0.65, 0.15, 1)
const COLOR_STAR := Color(0.95, 0.78, 0.25, 1)

var map_data = null
var cover_url := ""

var _cover: TextureRect
var _title: Label
var _meta: Label
var _rating: Label
var _tags: Label
var _pills: Array[Label] = []
var _badges: Array[Label] = []
var _built := false


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true

	custom_minimum_size = Vector2(0, CARD_HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip_contents = true
	focus_mode = Control.FOCUS_NONE
	tooltip_text = ""

	_apply_card_styles()

	_cover = TextureRect.new()
	_cover.position = Vector2(14, 14)
	_cover.size = Vector2(COVER_SIZE, COVER_SIZE)
	_cover.texture = PLACEHOLDER_COVER
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cover)

	var column := VBoxContainer.new()
	column.anchor_left = 0.0
	column.anchor_top = 0.0
	column.anchor_right = 1.0
	column.anchor_bottom = 1.0
	column.offset_left = 152.0
	column.offset_top = 10.0
	column.offset_right = -12.0
	column.offset_bottom = -8.0
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title_row)

	_title = _make_label("", 22, Color(1, 1, 1, 1))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_row.add_child(_title)

	_rating = _make_label("", 20, COLOR_STAR)
	_rating.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rating.custom_minimum_size = Vector2(132, 0)
	title_row.add_child(_rating)

	_meta = _make_label("", 16, Color(0.78, 0.78, 0.78, 1))
	column.add_child(_meta)

	var pill_row := HBoxContainer.new()
	pill_row.add_theme_constant_override("separation", 6)
	pill_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(pill_row)

	for i in BeatSaverApi.DIFFICULTIES.size():
		var pill := _make_label(BeatSaverApi.DIFFICULTY_SHORT[i], 15, COLOR_OFF_TEXT)
		pill.custom_minimum_size = Vector2(46, 26)
		pill.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pill.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pill.add_theme_stylebox_override("normal", _pill_style(COLOR_OFF_BG))
		pill_row.add_child(pill)
		_pills.append(pill)

	_tags = _make_label("", 15, Color(0.72, 0.72, 0.72, 1))
	_tags.custom_minimum_size = Vector2(96, 0)
	pill_row.add_child(_tags)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill_row.add_child(spacer)

	for i in 4:
		var badge := _make_label("", 14, Color(0.05, 0.05, 0.05, 1))
		badge.custom_minimum_size = Vector2(0, 24)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_stylebox_override("normal", _pill_style(COLOR_BADGE_BG))
		badge.visible = false
		pill_row.add_child(badge)
		_badges.append(badge)


func _apply_card_styles() -> void:
	add_theme_stylebox_override("normal", _card_style(Color(0.09, 0.09, 0.09, 1)))
	add_theme_stylebox_override("hover", _card_style(Color(0.18, 0.18, 0.18, 1)))
	add_theme_stylebox_override("pressed", _card_style(Color(0.28, 0.28, 0.28, 1)))
	add_theme_stylebox_override("focus", _card_style(Color(0.09, 0.09, 0.09, 1)))


func _card_style(background: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = background
	sb.border_color = Color(0.55, 0.55, 0.55, 1)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	return sb


func _pill_style(background: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = background
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb


func _make_label(text: String, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Fills the card. Called for every pool slot on every page, so it must be allocation-light:
## it only sets text, colours and visibility.
func set_map(map, index: int) -> void:
	if not _built:
		_build()
	map_data = map
	visible = true
	name = "MapCard%d" % index

	_title.text = map.name if not map.name.is_empty() else map.song_name
	_meta.text = "%s   %s   %d BPM   %s" % [
		map.mapper,
		BeatSaverApi.format_duration(map.duration),
		roundi(map.bpm),
		BeatSaverApi.vote_percent(map),
	]

	var stars := _best_stars(map)
	_rating.text = "Ranked %.1f" % stars if stars > 0.0 else ""

	for i in BeatSaverApi.DIFFICULTIES.size():
		var lit: bool = map.difficulty_present(BeatSaverApi.DIFFICULTIES[i], true)
		var pill: Label = _pills[i]
		pill.add_theme_color_override("font_color", COLOR_LIT_TEXT if lit else COLOR_OFF_TEXT)
		pill.add_theme_stylebox_override("normal", _pill_style(COLOR_LIT_BG if lit else COLOR_OFF_BG))

	_tags.text = _characteristic_tags(map)

	var mods: Array = map.required_mods()
	for i in _badges.size():
		var badge: Label = _badges[i]
		if i < mods.size():
			badge.text = mods[i]
			badge.visible = true
		else:
			badge.visible = false

	if cover_url != map.cover_url:
		cover_url = map.cover_url
		_cover.texture = PLACEHOLDER_COVER


func clear() -> void:
	map_data = null
	cover_url = ""
	visible = false
	name = "MapCardFree"


## Applies a decoded cover, but only if it is still the one this card asked for.
func apply_cover(url: String, texture: Texture2D) -> void:
	if map_data == null or url != cover_url:
		return
	if texture != null:
		_cover.texture = texture


func _best_stars(map) -> float:
	var best := -1.0
	for d: Variant in map.standard_diffs():
		var diff = d
		if diff.stars > best:
			best = diff.stars
		if diff.bl_stars > best:
			best = diff.bl_stars
	return best


func _characteristic_tags(map) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for characteristic: Variant in map.extra_characteristics():
		match String(characteristic):
			"OneSaber":
				parts.append("1S")
			"90Degree":
				parts.append("90")
			"360Degree":
				parts.append("360")
			"NoArrows":
				parts.append("NA")
			"Lightshow":
				parts.append("LS")
			_:
				parts.append(String(characteristic))
	return " ".join(parts)
