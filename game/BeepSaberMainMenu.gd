# The main menu is shown at game start or pause on an OQ_UI2DCanvas
# some logic is in the BeepSaber_Game.gd to set the correct state
#
# This file also contains the logic to load a beatmap in the format that
# normal Beat Saber uses. So you can load here custom beat saber songs too
extends Panel
class_name MainMenu

# emitted when a new map difficulty is selected
signal difficulty_changed(map_info: MapInfo, diff_rank: int)
# emitted when the settings button is pressed
signal settings_requested()
signal users_requested()
signal start_map(info: MapInfo, difficulty: DifficultyInfo)
# emitted when the player wants the BeatLeader board for the selected map/difficulty
signal leaderboard_requested(map_info: MapInfo, difficulty: DifficultyInfo)
# emitted when the player opens the storage panel
signal storage_requested()

var _cover_texture_create_sw := StopwatchFactory.create("cover_texture_create",10,true)

@export var main_song_player_ref: AudioStreamPlayer
@export var keyboard: OQ_UI2DKeyboard
@export var beepsaber_game : BeepSaber_Game

@export var song_uploader_ref: SongUploader

@onready var playlist_selector := $PlaylistSelector as OptionButton
@onready var source_filter := $SourceFilter as OptionButton
@onready var wall_colour_toggle := $MapWallColour_Toggle as CheckButton
@onready var quick_hands_toggle := $QuickSettings/Row/Hands_Toggle as CheckButton
@onready var quick_refresh_toggle := $QuickSettings/Row/Refresh_Toggle as CheckButton
@onready var quick_events_toggle := $QuickSettings/Row/Events_Toggle as CheckButton
@onready var _bg_img_loader := preload("res://game/scripts/BackgroundImgLoader.gd").new()

# Source backfill (specs/020 FR-007): menu-only, one map at a time, once per session.
const MapSourceBackfillScript := preload("res://game/scripts/MapSourceBackfill.gd")
var _backfill: MapSourceBackfill

@onready var cover := $cover as TextureRect
@onready var songs_menu := $SongsMenu as ItemList
@onready var diff_menu := $DifficultyMenu as ItemList
@onready var delete_button := $Delete_Button as Button

@onready var song_preview := $song_prev as AudioStreamPlayer
var song_preview_transition_time := 1.0

var current_selected: int

enum PlaylistOptions {
	AllSongs,
	RecentlyAdded,
	MostPlayed
}

# several different lists of maps, for use with the sort-by bar up top
var _all_songs: Array[MapInfo]
var _recently_added_songs: Array[MapInfo] # newest is first, oldest is last
var _most_played_songs: Array[MapInfo] # most played is first, least played is last
var _currently_selected_songlist_ref: Array[MapInfo] = _all_songs # reference to whichever map list is the currently selected one
# The map the info panel and Play button currently describe. Kept across a list rebuild (filter
# change, backfill refresh) so the selection stays on the same song when it is still visible.
var _selected_map: MapInfo = null

# specs/029: card/sort state and the runtime Cards UI.
var _manifest: Dictionary = {}
var _cards: Array = []
var _card_key := Settings.library_card
var _sort_field := Settings.library_sort_field
var _sort_desc := Settings.library_sort_desc
var _view_cards := false
var _view_button: Button
var _sort_button: OptionButton
var _dir_button: Button
var _card_label: Label
var _card_scroll: ScrollContainer
var _card_grid: GridContainer

# stop the preview player if the main song player is going
func _physics_process(_delta: float) -> void:
	if main_song_player_ref.playing:
		song_preview.stop()

func refresh_playlist() -> void:
	_apply_library_view()

class MapInfoWithSort:
	var num: int
	var info: MapInfo
	
	func _init(n: int, i: MapInfo) -> void:
		num = n
		info = i

func compare(a: MapInfoWithSort, b: MapInfoWithSort) -> bool:
	return a.num > b.num

func _load_playlists() -> void:
	# No sample song is copied any more: the 0.6.1 build ships an empty library. Remove the old
	# bundled demo once (hash-matched), then discover whatever the player has.
	var songs_dir := Constants.APPDATA_PATH + "Songs/"
	@warning_ignore("return_value_discarded")
	DirAccess.make_dir_recursive_absolute(songs_dir)
	BundledDemo.cleanup(songs_dir)
	StorageTools.run_requested_cleanup()
	_discover_all_songs(songs_dir)
	# specs/029: playlist membership from the manifest, cached size/date in the sidecar. The
	# sidecar values are written once and then stay frozen, so the library scan does not repeat the
	# folder walk on every launch.
	_manifest = PlaylistManifest.read(songs_dir)
	for song in _all_songs:
		_ensure_stats(song)
		song.playlists = PlaylistManifest.playlists_for(_manifest, song.level_hash)
	var songs_with_modify_times: Array[MapInfoWithSort] = []
	var songs_with_play_count: Array[MapInfoWithSort] = []
	for song in _all_songs:
		var song_path := song.filepath
		var modified_time := FileAccess.get_modified_time(song_path)
		var play_count := PlayCount.get_total_play_count(song)
		songs_with_modify_times.append(MapInfoWithSort.new(modified_time, song))
		songs_with_play_count.append(MapInfoWithSort.new(play_count, song))
	
	songs_with_modify_times.sort_custom(compare)
	songs_with_play_count.sort_custom(compare)
	_recently_added_songs = []
	_most_played_songs = []
	for song in songs_with_modify_times:
		_recently_added_songs.append(song.info)
	for song in songs_with_play_count:
		_most_played_songs.append(song.info)
	
	refresh_playlist()
	_start_backfill()
	
	var canvas := get_parent().get_parent()
	if canvas is OQ_UI2DCanvas:
		# The canvas's refresh authority coalesces this into one frame; calling the canvas's
		# `_input_update` directly would start a competing update path.
		var refresh := CanvasRefresh.of(self)
		if refresh != null:
			refresh.request()

func _discover_all_songs(seek_path: String) -> void:
	_all_songs.clear()
	var dir := DirAccess.open(seek_path)
	if dir:
		@warning_ignore("return_value_discarded")
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if dir.current_is_dir(): # TODO: or file_name.ends_with(".zip"):
				var new_dir := seek_path+file_name+"/"
				var song := Map.load_map_info(new_dir)
				if song:
					_all_songs.append(song)
			file_name = dir.get_next()

func _build_library_ui() -> void:
	_view_button = Button.new()
	_view_button.position = Vector2(140, 12)
	_view_button.size = Vector2(160, 48)
	_view_button.add_theme_font_size_override("font_size", 22)
	_view_button.text = "Cards"
	_view_button.pressed.connect(_toggle_view)
	add_child(_view_button)

	_card_label = Label.new()
	_card_label.position = Vector2(305, 12)
	_card_label.size = Vector2(120, 48)
	_card_label.add_theme_font_size_override("font_size", 16)
	_card_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card_label.clip_text = true
	add_child(_card_label)

	_sort_button = OptionButton.new()
	_sort_button.position = Vector2(432, 12)
	_sort_button.size = Vector2(198, 48)
	_sort_button.add_theme_font_size_override("font_size", 20)
	for field in LibraryView.SORT_FIELDS:
		@warning_ignore("return_value_discarded")
		_sort_button.add_item(LibraryView.SORT_LABELS[field])
	_sort_button.select(maxi(0, LibraryView.SORT_FIELDS.find(_sort_field)))
	_sort_button.item_selected.connect(_on_sort_selected)
	add_child(_sort_button)

	_dir_button = Button.new()
	_dir_button.position = Vector2(634, 12)
	_dir_button.size = Vector2(90, 48)
	_dir_button.add_theme_font_size_override("font_size", 20)
	_dir_button.text = "Z-A" if _sort_desc else "A-Z"
	_dir_button.pressed.connect(_toggle_direction)
	add_child(_dir_button)

	_card_scroll = ScrollContainer.new()
	_card_scroll.position = Vector2(16, 64)
	_card_scroll.size = Vector2(832, 496)
	_card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_card_scroll.visible = false
	_card_grid = GridContainer.new()
	_card_grid.columns = 2
	_card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_scroll.add_child(_card_grid)
	add_child(_card_scroll)
	_update_card_label()

func _ensure_stats(song: MapInfo) -> void:
	var changed := false
	if song.bytes == 0:
		song.bytes = StorageTools.folder_size(song.filepath)
		changed = true
	if song.added_unix == 0:
		var info_path := song.filepath + "Info.dat"
		if not FileAccess.file_exists(info_path):
			info_path = song.filepath + "info.dat"
		var stamp := FileAccess.get_modified_time(info_path)
		if stamp <= 0:
			stamp = FileAccess.get_modified_time(song.filepath)
		song.added_unix = stamp
		changed = true
	if changed:
		MapSource.set_stats(song.filepath, song.added_unix, song.bytes)

func _apply_library_view() -> void:
	_cards = LibraryView.cards(_all_songs, _manifest)
	var known := _card_key == LibraryView.CARD_ALL
	for card in _cards:
		if str(card["key"]) == _card_key:
			known = true
			break
	if not known:
		_card_key = LibraryView.CARD_ALL
	_build_card_buttons()
	var filtered := LibraryView.filter(_all_songs, _card_key)
	var sorted := LibraryView.sort(filtered, _sort_field, _sort_desc)
	var typed: Array[MapInfo] = []
	for map in sorted:
		typed.append(map as MapInfo)
	_set_cur_playlist(typed)
	_update_card_label()

func _build_card_buttons() -> void:
	if _card_grid == null:
		return
	for child in _card_grid.get_children():
		_card_grid.remove_child(child)
		child.queue_free()
	for card in _cards:
		var button := Button.new()
		button.custom_minimum_size = Vector2(396, 112)
		button.add_theme_font_size_override("font_size", 22)
		var marker := "> " if str(card["key"]) == _card_key else ""
		button.text = "%s%s\n%d maps - %s" % [marker, str(card["label"]), int(card["count"]),
			StorageTools.format_bytes(int(card["bytes"]))]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_card_pressed.bind(str(card["key"])))
		_card_grid.add_child(button)

func _on_card_pressed(key: String) -> void:
	_card_key = key
	Settings.library_card = key
	Settings.save()
	_view_cards = false
	if _view_button != null:
		_view_button.text = "Cards"
	songs_menu.visible = true
	_card_scroll.visible = false
	_apply_library_view()

func _toggle_view() -> void:
	_view_cards = not _view_cards
	_view_button.text = "List" if _view_cards else "Cards"
	songs_menu.visible = not _view_cards
	_card_scroll.visible = _view_cards
	if _view_cards:
		_cards = LibraryView.cards(_all_songs, _manifest)
		_build_card_buttons()

func _on_sort_selected(index: int) -> void:
	if index < 0 or index >= LibraryView.SORT_FIELDS.size():
		return
	_sort_field = LibraryView.SORT_FIELDS[index]
	Settings.library_sort_field = _sort_field
	Settings.save()
	_apply_library_view()

func _toggle_direction() -> void:
	_sort_desc = not _sort_desc
	_dir_button.text = "Z-A" if _sort_desc else "A-Z"
	Settings.library_sort_desc = _sort_desc
	Settings.save()
	_apply_library_view()

func _update_card_label() -> void:
	if _card_label == null:
		return
	var label := "All maps"
	for card in _cards:
		if str(card["key"]) == _card_key:
			label = str(card["label"])
			break
	_card_label.text = label

func _set_cur_playlist(songs: Array[MapInfo]) -> void:
	# specs/029 FR-014: the callers hand in the already-filtered and sorted view (LibraryView),
	# so this function only builds the rows; there is no second source filter here.
	_currently_selected_songlist_ref = songs
	var current_id := songs_menu.get_selected_items()
	
	songs_menu.clear()
	
	var song_count := songs.size()
	var map_index := 0
	for map in songs:
		@warning_ignore("return_value_discarded")
		songs_menu.add_item(
			"%s - %s  [%s]" % [map.song_author_name, map.song_name, map.source_label()],
			default_song_icon)
		var filepath := map.filepath + map.cover_image_filename
		_bg_img_loader.load_texture(filepath, _on_cover_loaded, false, map_index)
		map_index += 1
	
	# An empty view must not leave Play/Delete/Leaderboard pointing at a map the player cannot
	# see, and a click on a stale difficulty must not index an empty list.
	var play_button := $Play_Button as Button
	play_button.disabled = song_count == 0
	delete_button.disabled = song_count == 0
	($Leaderboard_Button as Button).disabled = song_count == 0
	if song_count == 0:
		var message := "No maps match this source."
		if _all_songs.is_empty():
			message = "No songs yet. Use Online Map Source to download maps."
		($SongInfo_Label as Label).text = message
		cover.texture = null
		diff_menu.clear()
		song_preview.stop()
		return
	
	# Keep the same song selected across a rebuild (backfill refresh, filter change). A map that
	# dropped out of the view falls back to the first visible one; the info panel and Play then
	# describe the same row.
	var wanted := -1
	for i in songs.size():
		if songs[i] == _selected_map:
			wanted = i
			break
	if wanted < 0 and (current_id.size() > 0 or _selected_map != null):
		wanted = 0
	if wanted >= 0:
		songs_menu.select(wanted)
		_select_song(wanted)
	elif current_id.size() > 0:
		var selected_id := current_id[0]
		if selected_id >= song_count:
			selected_id = song_count - 1
		_select_song(selected_id)

var default_song_icon := preload("res://game/data/beepsaber_logo.png")

# callback from ImageUtils when background image loading is complete. if image
# failed to load, tex will be null
func _on_cover_loaded(img_tex: Texture2D, is_main_cover: bool, list_idx: int) -> void:
	if img_tex != null:
		if is_main_cover:
			cover.call_deferred("set_texture", img_tex)
		else:
			songs_menu.call_deferred("set_item_icon", list_idx,img_tex)
			#songs_menu.set_item_icon(list_idx,img_tex)

func _load_cover(cover_path: String, filename: String) -> ImageTexture:
	# parse buffer into an ImageTexture
	_cover_texture_create_sw.start()
	var tex := ImageTexture.create_from_image(Image.load_from_file(cover_path+filename))
	_cover_texture_create_sw.stop()
	return tex

func play_preview(buffer: PackedByteArray, start_time: float = 0.0, duration: float = -1.0, buffer_data_type_hint: String = 'ogg') -> void:
	var stream: AudioStream
	# take song preview data from buffer as-is. trust passed type hint
	if buffer_data_type_hint == 'ogg':
		stream = AudioStreamOggVorbis.load_from_buffer(buffer)
	elif buffer_data_type_hint == 'mp3':
		stream = AudioStreamMP3.new()
		(stream as AudioStreamMP3).data = buffer
	
	if not stream: return
	
	if duration < 0.0:
		# assume preview duration based on parsed audio length
		duration = stream.get_length()
	
	
	# fade out preview if ones already running
	if song_preview.playing:
		await _on_stop_prev_timeout()
	
	# start the requested preview, if still on song select
	if not main_song_player_ref.playing:
		song_preview.stream = stream
		var song_prev_Tween := song_preview.create_tween().set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
		@warning_ignore("return_value_discarded")
		song_prev_Tween.tween_property(song_preview, ^"volume_db", 0, song_preview_transition_time)
		song_prev_Tween.play()
		song_preview.play(start_time)
		($song_prev/stop_prev as Timer).start(duration)

func _select_song(id: int) -> void:
	current_selected = id
	songs_menu.ensure_current_is_visible()
	delete_button.disabled = false
	
	var map := _currently_selected_songlist_ref[id]
	_selected_map = map
	($SongInfo_Label as Label).text = """Song Author: %s
	Song Title: %s
	Beatmap Author: %s
	Source: %s
	Play Count: %d""" % [
		map.song_author_name,
		map.song_name,
		map.level_author_name,
		map.source_label(),
		PlayCount.get_total_play_count(map)
	]
	
	# load cover in background to avoid freezing UI
	_bg_img_loader.load_texture(map.filepath + map.cover_image_filename, _on_cover_loaded, true, -1)
	
	# preview song
	play_preview(FileAccess.get_file_as_bytes(map.filepath + map.song_filename), map.preview_start_time, map.preview_duration)
	var result := FileAccess.get_open_error()
	if result != OK:
		vr.log_file_error(result, map.filepath + map.song_filename, "BeepSaberMainMenu.gd at line 223 ")
	
	diff_menu.clear()
	for diff in map.difficulty_beatmaps:
		var diff_index := diff_menu.add_item(diff.custom_name)
		diff_menu.set_item_tooltip(diff_index, diff.difficulty + " / " + diff.custom_name)
	
	_select_difficulty(0)

func _on_stop_prev_timeout() -> void:
	var song_prev_Tween := song_preview.create_tween().set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	@warning_ignore("return_value_discarded")
	song_prev_Tween.tween_property(song_preview, "volume_db", -50, song_preview_transition_time)
	song_prev_Tween.play()
	await get_tree().create_timer(song_preview_transition_time).timeout
	song_preview.stop()


var _map_difficulty := 0

func _select_difficulty(id: int) -> void:
	if _currently_selected_songlist_ref.is_empty():
		return
	if current_selected < 0 or current_selected >= _currently_selected_songlist_ref.size():
		return
	var map := _currently_selected_songlist_ref[current_selected]
	if map == null or id < 0 or id >= map.difficulty_beatmaps.size():
		return
	_map_difficulty = id
	diff_menu.select(id)
	
	# notify listeners that difficulty has changed
	var difficulty := map.difficulty_beatmaps[id]
	difficulty_changed.emit(map, difficulty.difficulty_rank)


func _load_map_and_start(map: MapInfo) -> void:
	if map.is_empty(): return
	
	# No network work once play starts (FR-008).
	if _backfill != null:
		_backfill.stop()
	
	var set0 := map.difficulty_beatmaps
	if (set0.size() == 0):
		vr.log_error("No _difficultyBeatmaps in set")
		return
	
	var diff_info := set0[_map_difficulty]
	
	start_map.emit(map, diff_info)

func _on_Delete_Button_button_up() -> void:
	if delete_button.text != "Sure?":
		delete_button.text = "Sure?"
		await get_tree().create_timer(5).timeout
		delete_button.text = "Delete"
	else:
		delete_button.text = "Delete"
		if _currently_selected_songlist_ref.is_empty():
			return
		if current_selected < 0 or current_selected >= _currently_selected_songlist_ref.size():
			return
		_delete_map(_currently_selected_songlist_ref[current_selected])
	
func _delete_map(map: MapInfo) -> void:
	# specs/026 FR-012/FR-013: one recursive delete, shared with the Storage panel, and only for
	# a direct child of Songs/. A bad MapInfo must never turn this into a library wipe.
	if map.filepath.is_empty() or not StorageTools.is_safe_map_path(map.filepath):
		vr.log_info("Refusing to delete outside Songs/: " + map.filepath)
		return
	Utils.remove_tree(map.filepath)
	if DirAccess.dir_exists_absolute(map.filepath):
		vr.log_info("Error removing song " + map.filepath)
		return
	PlaylistManifest.remove_map(Constants.APPDATA_PATH + "Songs", map.level_hash)
	Highscores.remove_map(map)
	PlayCount.remove_map(map)
	vr.log_info(map.filepath+" Removed")
	delete_button.disabled = true
	_on_LoadPlaylists_Button_pressed()

func _ready() -> void:
	wall_colour_toggle.button_pressed = Settings.wall_map_color
	# Quick settings pinned at the top of the main menu. Values are set before connecting so a
	# programmatic button_pressed change cannot write a different value back on load.
	quick_hands_toggle.button_pressed = Settings.hand_tracking_enabled
	# Hand tracking is a Labs feature since 0.7.22: its switch lives in Settings > Labs, not in
	# the pinned panel. The node stays (and stays in sync) so the scene layout is untouched.
	quick_hands_toggle.visible = false
	quick_refresh_toggle.button_pressed = Settings.display_refresh_rate >= 120.0
	quick_events_toggle.button_pressed = Settings.events
	quick_hands_toggle.toggled.connect(_on_quick_hands_toggled)
	quick_refresh_toggle.toggled.connect(_on_quick_refresh_toggled)
	quick_events_toggle.toggled.connect(_on_quick_events_toggled)
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)
	UI_AudioEngine.attach_children(self)
	vr.log_info("BeepSaber search path is " + Constants.APPDATA_PATH)
	if not ProfileManager.changed.is_connected(_refresh_user_badge):
		ProfileManager.changed.connect(_refresh_user_badge)
	_refresh_user_badge()
	
	playlist_selector.clear()
	playlist_selector.add_item("All Songs")
	playlist_selector.add_item("Recently Added")
	playlist_selector.add_item("Most Played")
	
	# Source filter (FR-002). It composes with the playlist choice above; the selection is
	# persisted so a player who works from one library keeps that view across launches.
	source_filter.clear()
	source_filter.add_item(MapSource.label(MapSource.ALL))
	for source: String in MapSource.SOURCES:
		@warning_ignore("return_value_discarded")
		source_filter.add_item(MapSource.label(source))
	source_filter.select(_source_filter_index(Settings.library_source_filter))
	if not source_filter.item_selected.is_connected(_on_SourceFilter_item_selected):
		@warning_ignore("return_value_discarded")
		source_filter.item_selected.connect(_on_SourceFilter_item_selected)
	
	# One-shot backfill of old maps' source tags (FR-007). It only runs while this menu is
	# visible and stops the moment a map starts.
	_backfill = MapSourceBackfillScript.new()
	_backfill.name = "MapSourceBackfill"
	add_child(_backfill)
	@warning_ignore("return_value_discarded")
	_backfill.map_updated.connect(_on_backfill_map_updated)
	@warning_ignore("return_value_discarded")
	_backfill.finished.connect(_on_backfill_finished)
	# The menu's visibility lives on the OQ_UI2DCanvas above the SubViewport, not on this Panel,
	# so `is_visible_in_tree()` inside the panel cannot see the canvas being hidden. Watch the
	# canvas itself: hiding it (starting a map, opening another overlay) stops the backfill.
	var canvas := _parent_canvas()
	if canvas != null and not canvas.visibility_changed.is_connected(_on_canvas_visibility_changed):
		@warning_ignore("return_value_discarded")
		canvas.visibility_changed.connect(_on_canvas_visibility_changed)
	
	_build_library_ui()
	_load_playlists()
	
	await keyboard.ready
	@warning_ignore("return_value_discarded")
	keyboard.text_input_enter.connect(_text_input_enter)
	@warning_ignore("return_value_discarded")
	keyboard.text_input_cancel.connect(_text_input_cancel)
	@warning_ignore("return_value_discarded")
	keyboard._text_edit.text_changed.connect(_text_input_changed)
	# focus_exited was connected to _text_input_enter here, but that handler takes the entered
	# text and focus_exited passes nothing, so every emission only logged "expected 1 argument"
	# and the keyboard stayed up. The connection is dropped rather than repaired: closing the
	# keyboard on focus loss has never actually happened, and turning it on is a UI change.
	
	playlist_selector.visible = false
	source_filter.visible = false
	_apply_library_view()
	
	if song_uploader_ref and song_uploader_ref.active:
		$upload_url.text = "Manually Upload Custom Songs: \n%s"%[
			song_uploader_ref.get_server_url()
		]
	else:
		$upload_url.text = ""
	
	$version.text = beepsaber_game.version
	if OS.get_name() == &"Web":
		$Exit_Button.hide()


func _on_Play_Button_pressed() -> void:
	song_preview.stop()
	if _currently_selected_songlist_ref.is_empty():
		return
	if current_selected < 0 or current_selected >= _currently_selected_songlist_ref.size():
		return
	_load_map_and_start(_currently_selected_songlist_ref[current_selected])


# Used by the left-side BeatLeader sign (specs/025 FR-007): same map/difficulty as the
# in-panel Leaderboard button, so both entry points cannot disagree.
func open_leaderboard_for_selection() -> void:
	_on_Leaderboard_Button_pressed()

func _on_Leaderboard_Button_pressed() -> void:
	if _currently_selected_songlist_ref.is_empty():
		return
	if current_selected < 0 or current_selected >= _currently_selected_songlist_ref.size():
		return
	var map := _currently_selected_songlist_ref[current_selected]
	if map == null or map.difficulty_beatmaps.is_empty():
		return
	var index := clampi(_map_difficulty, 0, map.difficulty_beatmaps.size() - 1)
	leaderboard_requested.emit(map, map.difficulty_beatmaps[index])


func _on_Exit_Button_pressed() -> void:
	get_tree().quit()


func _on_Users_Button_pressed() -> void:
	users_requested.emit()

func _on_Storage_Button_pressed() -> void:
	storage_requested.emit()

## The full library, independent of the current source filter (specs/026 FR-002).
func get_library_maps() -> Array:
	return _all_songs

# The badge is the "who is playing" reminder the user asked for: it must track the
# current profile, so it is refreshed on ProfileManager.changed rather than only once.
func _refresh_user_badge() -> void:
	var badge := get_node_or_null("User_Badge") as Label
	if badge != null:
		badge.text = "Playing as: %s" % ProfileManager.current_name()

func _on_Settings_Button_pressed() -> void:	settings_requested.emit()

const READ_PERMISSION = "android.permission.READ_EXTERNAL_STORAGE"

func is_in_array(arr: Array, val: Variant) -> bool:
	for e: Variant in arr:
		if (e == val): return true
	return false
	
func _check_required_permissions() -> bool:
	if not vr.inVR: return true # desktop is always allowed
	
	var permissions := OS.get_granted_permissions()
	var read_storage_permission := is_in_array(permissions, READ_PERMISSION)
	
	vr.log_info(str(permissions))
	
	if not read_storage_permission:
		return false

	return true

func _check_and_request_permission() -> bool:
	vr.log_info("Checking permissions")
	
	if not _check_required_permissions():
		vr.log_info("Requesting permissions")
		OS.request_permissions()
		return false
	else:
		return true


func _on_LoadPlaylists_Button_pressed() -> void:
	# Note: this call is non-blocking; so a user has to click again after
	#       granting the permissions; we need to find a solutio for this
	#       maybe polling after the button press?
	_check_and_request_permission()
	_load_playlists()


func _on_Search_Button_button_up() -> void:
	keyboard.visible=true
	keyboard._text_edit.grab_focus()

func _text_input_enter(_text: String) -> void:
	keyboard.visible=false

func _text_input_cancel() -> void:
	keyboard.visible=false
	_clean_search()

func _text_input_changed() -> void:
	var text := keyboard._text_edit.text
	($Search_Button/Label as Label).text = text
	if text == "":
		_clean_search()
		return
	text = text.to_upper() # ignore case
	var songs_sorted_by_similarity: Array[MapInfoWithSort] = []
	for song in _all_songs:
		# similarity is between 0.0 and 1.0, MapInfoWithSort takes an int,
		# gotta make the number larger else it'll just be 0 or 1 later
		var similarity := song.song_name.to_upper().similarity(text) * 65536.0
		songs_sorted_by_similarity.append(MapInfoWithSort.new(int(similarity), song))
	songs_sorted_by_similarity.sort_custom(compare)
	var songs_sorted: Array[MapInfo] = []
	for song in songs_sorted_by_similarity:
		songs_sorted.append(song.info)
	_set_cur_playlist(songs_sorted)

func _clean_search() -> void:
	_on_PlaylistSelector_item_selected(playlist_selector.get_selected_id())
	($Search_Button/Label as Label).text = ""

func _on_PlaylistSelector_item_selected(id: int) -> void:
	match id:
		PlaylistOptions.AllSongs:
			_set_cur_playlist(_all_songs)
		PlaylistOptions.MostPlayed:
			_set_cur_playlist(_most_played_songs)
		PlaylistOptions.RecentlyAdded:
			_set_cur_playlist(_recently_added_songs)
		_:
			vr.log_warning("Unsupported playlist option %s" % id)
			_set_cur_playlist(_all_songs)


func _source_filter_index(source: String) -> int:
	var wanted := source.strip_edges().to_lower()
	if wanted == MapSource.ALL:
		return 0
	var index := MapSource.SOURCES.find(wanted)
	return index + 1 if index >= 0 else 0


func _on_SourceFilter_item_selected(index: int) -> void:
	var source := MapSource.ALL
	if index > 0 and index <= MapSource.SOURCES.size():
		source = MapSource.SOURCES[index - 1]
	Settings.library_source_filter = source
	Settings.save()
	refresh_playlist()
	# The list was rebuilt, so the previous row is gone. Put the panel and the Play button on
	# the first map of the new view instead of leaving the info from a map no longer shown.
	if songs_menu.item_count > 0:
		songs_menu.select(0)
		_select_song(0)


func _start_backfill() -> void:
	if _backfill == null:
		return
	_backfill.start(_all_songs, func() -> bool: return is_visible_in_tree())


func _on_backfill_map_updated(_info: MapInfo) -> void:
	# Nothing per-map: the list is rebuilt once when the pass ends, so a filter on Unknown only
	# changes when it can show a stable result.
	pass


func _on_backfill_finished(updated: int) -> void:
	if updated > 0:
		refresh_playlist()


func _parent_canvas() -> OQ_UI2DCanvas:
	var node: Node = get_parent()
	while node != null:
		if node is OQ_UI2DCanvas:
			return node as OQ_UI2DCanvas
		node = node.get_parent()
	return null


func _on_canvas_visibility_changed() -> void:
	var canvas := _parent_canvas()
	if canvas != null and not canvas.visible and _backfill != null:
		_backfill.stop()



func _on_MapWallColour_Toggle_toggled(pressed: bool) -> void:
	Settings.wall_map_color = pressed

func _on_quick_hands_toggled(pressed: bool) -> void:
	Settings.hand_tracking_enabled = pressed

func _on_quick_refresh_toggled(pressed: bool) -> void:
	Settings.display_refresh_rate = 120.0 if pressed else 90.0

func _on_quick_events_toggled(pressed: bool) -> void:
	Settings.events = pressed

# Keep the pinned toggles honest when the same setting is changed in the full settings panel.
func _on_setting_changed(key: StringName) -> void:
	match key:
		&"hand_tracking_enabled":
			quick_hands_toggle.set_pressed_no_signal(Settings.hand_tracking_enabled)
		&"display_refresh_rate":
			quick_refresh_toggle.set_pressed_no_signal(Settings.display_refresh_rate >= 120.0)
		&"events":
			quick_events_toggle.set_pressed_no_signal(Settings.events)

func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)
