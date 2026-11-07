extends RefCounted
class_name LibraryView

## Pure library query helpers for the Cards view (specs/029 FR-004..FR-008).
##
## Cards are metadata over the flat `Songs/` folder: one for All, one per source, one per
## BeastSaber playlist from `Songs/.playlists.json`, plus "BeastSaber (other)" for maps whose
## playlist was never recorded. Nothing here touches the network or the filesystem.

const CARD_ALL := "all"
const CARD_SOURCE := "source:"
const CARD_PLAYLIST := "playlist:"
const CARD_BEASTSABER_OTHER := "beastsaber_other"

const SORT_NAME := "name"
const SORT_ARTIST := "artist"
const SORT_MAPPER := "mapper"
const SORT_DATE := "date"
const SORT_SIZE := "size"
const SORT_PLAYS := "plays"
const SORT_FIELDS: Array[String] = [SORT_NAME, SORT_ARTIST, SORT_MAPPER, SORT_DATE, SORT_SIZE, SORT_PLAYS]
const SORT_LABELS := {
	SORT_NAME: "Name",
	SORT_ARTIST: "Artist",
	SORT_MAPPER: "Mapper",
	SORT_DATE: "Date added",
	SORT_SIZE: "Size",
	SORT_PLAYS: "Play count",
}

static func _bytes_of(maps: Array) -> int:
	var total := 0
	for map in maps:
		total += int((map as MapInfo).bytes)
	return total

static func _in_playlist(map: MapInfo, playlist_id: String) -> bool:
	for entry in map.playlists:
		if entry is Dictionary and str((entry as Dictionary).get("id", "")) == playlist_id:
			return true
	return false

## Builds the card list in display order: All, BeatSaver, each playlist, BeastSaber (other),
## then the remaining sources that actually contain maps.
static func cards(maps: Array, manifest: Dictionary) -> Array:
	var out: Array = []
	out.append({
		"key": CARD_ALL,
		"label": "All maps",
		"kind": "all",
		"count": maps.size(),
		"bytes": _bytes_of(maps),
	})
	var by_source := {}
	for map in maps:
		var s := str((map as MapInfo).source)
		by_source[s] = int(by_source.get(s, 0)) + 1
	if by_source.has(MapSource.SOURCE_BEATSAVER):
		out.append(_source_card(maps, MapSource.SOURCE_BEATSAVER))

	var playlists: Array = (manifest.get("playlists", []) as Array).duplicate()
	playlists.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("title", "")).nocasecmp_to(str(b.get("title", ""))) < 0)
	for entry in playlists:
		if not (entry is Dictionary):
			continue
		var id := str((entry as Dictionary).get("id", ""))
		var list: Array = []
		for map in maps:
			if _in_playlist(map as MapInfo, id):
				list.append(map)
		if list.is_empty():
			continue
		out.append({
			"key": CARD_PLAYLIST + id,
			"label": str(entry.get("title", "Playlist")),
			"kind": "playlist",
			"count": list.size(),
			"bytes": _bytes_of(list),
			"playlist_id": id,
		})

	var other: Array = []
	for map in maps:
		if (map as MapInfo).source == MapSource.SOURCE_BEASTSABER and (map as MapInfo).playlists.is_empty():
			other.append(map)
	if not other.is_empty():
		out.append({
			"key": CARD_BEASTSABER_OTHER,
			"label": "BeastSaber (other)",
			"kind": "source",
			"count": other.size(),
			"bytes": _bytes_of(other),
		})

	for source in [MapSource.SOURCE_UPLOADED, MapSource.SOURCE_LOCAL, MapSource.SOURCE_UNKNOWN]:
		if by_source.has(source):
			out.append(_source_card(maps, source))
	return out

static func _source_card(maps: Array, source: String) -> Dictionary:
	var list: Array = []
	for map in maps:
		if (map as MapInfo).source == source:
			list.append(map)
	return {
		"key": CARD_SOURCE + source,
		"label": MapSource.label(source),
		"kind": "source",
		"count": list.size(),
		"bytes": _bytes_of(list),
	}

## Applies a card key and a free-text filter.
static func filter(maps: Array, card_key: String, text: String = "") -> Array:
	var needle := text.strip_edges().to_lower()
	var out: Array = []
	for map in maps:
		var m := map as MapInfo
		if not _matches_card(m, card_key):
			continue
		if not needle.is_empty():
			var hay := ("%s %s %s" % [m.song_name, m.song_author_name, m.level_author_name]).to_lower()
			if not hay.contains(needle):
				continue
		out.append(m)
	return out

static func _matches_card(map: MapInfo, card_key: String) -> bool:
	if card_key == CARD_ALL or card_key.is_empty():
		return true
	if card_key == CARD_BEASTSABER_OTHER:
		return map.source == MapSource.SOURCE_BEASTSABER and map.playlists.is_empty()
	if card_key.begins_with(CARD_SOURCE):
		return map.source == card_key.substr(CARD_SOURCE.length())
	if card_key.begins_with(CARD_PLAYLIST):
		return _in_playlist(map, card_key.substr(CARD_PLAYLIST.length()))
	return true

static func sort(maps: Array, field: String, descending: bool) -> Array:
	var out := maps.duplicate()
	out.sort_custom(func(a: MapInfo, b: MapInfo) -> bool:
		return _before(a, b, field, descending))
	return out

static func _before(a: MapInfo, b: MapInfo, field: String, descending: bool) -> bool:
	var c := 0
	match field:
		SORT_ARTIST:
			c = _cmp_text(a.song_author_name, b.song_author_name, descending)
		SORT_MAPPER:
			c = _cmp_text(a.level_author_name, b.level_author_name, descending)
		SORT_DATE:
			c = _cmp_num(a.added_unix, b.added_unix, descending)
		SORT_SIZE:
			c = _cmp_num(a.bytes, b.bytes, descending)
		SORT_PLAYS:
			c = _cmp_num(PlayCount.get_total_play_count(a), PlayCount.get_total_play_count(b), descending)
		_:
			c = _cmp_text(a.song_name, b.song_name, descending)
	if c != 0:
		return c < 0
	# Stable, direction-independent tie-break: name, then hash.
	var name_cmp := a.song_name.nocasecmp_to(b.song_name)
	if name_cmp != 0:
		return name_cmp < 0
	return a.level_hash < b.level_hash

## Empty artist/mapper sorts last in both directions; otherwise case-insensitive.
static func _cmp_text(a: String, b: String, descending: bool) -> int:
	var ea := a.strip_edges().is_empty()
	var eb := b.strip_edges().is_empty()
	if ea != eb:
		return 1 if ea else -1
	var c := a.nocasecmp_to(b)
	return -c if descending else c

static func _cmp_num(a: int, b: int, descending: bool) -> int:
	var c := 0
	if a < b:
		c = -1
	elif a > b:
		c = 1
	return -c if descending else c
