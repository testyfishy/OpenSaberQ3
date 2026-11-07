extends Node

# specs/029 SC-004: sidecar v2 round-trip, manifest many-to-many, card grouping and comparators.

const ROOT := "user://OpenSaber/Songs/"

func _ready() -> void:
	var probe_dir := ROOT + "LibProbe/"
	DirAccess.make_dir_recursive_absolute(probe_dir)
	var wrote := MapSource.write(probe_dir, MapSource.SOURCE_BEATSAVER, "id1", "HASH1", 1234, 5678)
	var side := MapSource.read(probe_dir)
	print("LIBPROBE sidecar write=%s schema_ok=%s added=%d bytes=%d source=%s" % [
		wrote, int(side.get("added_unix", 0)) == 1234, int(side.get("added_unix", 0)),
		int(side.get("bytes", 0)), str(side.get("source", ""))])

	var manifest_file := PlaylistManifest.path_for(ROOT)
	var had_manifest := FileAccess.file_exists(manifest_file)
	var backup := ""
	if had_manifest:
		backup = FileAccess.get_file_as_string(manifest_file)
	PlaylistManifest.add_maps(ROOT, "p1", "Pack One", ["h1", "h2"])
	PlaylistManifest.add_maps(ROOT, "p2", "Pack Two", ["h1"])
	var data := PlaylistManifest.read(ROOT)
	print("LIBPROBE manifest p1_for_h1=%d has_h2=%s" % [
		PlaylistManifest.playlists_for(data, "h1").size(),
		str(PlaylistManifest.playlists_for(data, "h2")).contains("Pack One")])
	PlaylistManifest.remove_map(ROOT, "h1")
	data = PlaylistManifest.read(ROOT)
	print("LIBPROBE manifest after_remove p1_h1=%d p2_present=%s p1_h2=%d" % [
		PlaylistManifest.playlists_for(data, "h1").size(),
		str(PlaylistManifest.playlists_for(data, "h2")).contains("Pack Two"),
		PlaylistManifest.playlists_for(data, "h2").size()])

	var p1 := [{"id": "p1", "title": "Pack One"}]
	var maps: Array = [
		_map("Zeta", "Artist B", "Mapper B", MapSource.SOURCE_BEATSAVER, "h10", 1000, 100, []),
		_map("Alpha", "Artist A", "Mapper A", MapSource.SOURCE_BEASTSABER, "h2", 2000, 200, p1),
		_map("NoArtist", "", "", MapSource.SOURCE_BEASTSABER, "h3", 3000, 300, []),
		_map("Local", "Artist C", "Mapper C", MapSource.SOURCE_LOCAL, "h4", 500, 400, []),
	]
	var cards := LibraryView.cards(maps, data)
	var keys: Array = []
	for card in cards:
		keys.append(str(card["key"]))
	print("LIBPROBE cards=", keys)
	var beat := LibraryView.filter(maps, LibraryView.CARD_SOURCE + MapSource.SOURCE_BEATSAVER)
	var pack := LibraryView.filter(maps, LibraryView.CARD_PLAYLIST + "p1")
	var other := LibraryView.filter(maps, LibraryView.CARD_BEASTSABER_OTHER)
	print("LIBPROBE filter beat=%d pack=%d other=%d" % [beat.size(), pack.size(), other.size()])
	var by_artist := LibraryView.sort(maps, LibraryView.SORT_ARTIST, false)
	var by_size := LibraryView.sort(maps, LibraryView.SORT_SIZE, true)
	print("LIBPROBE sort artist_first=%s artist_last=%s size_first=%s" % [
		(by_artist[0] as MapInfo).song_name, (by_artist[by_artist.size() - 1] as MapInfo).song_name,
		(by_size[0] as MapInfo).song_name])

	# cleanup
	Utils.remove_tree(probe_dir)
	if had_manifest:
		var f := FileAccess.open(manifest_file, FileAccess.WRITE)
		if f != null:
			f.store_string(backup)
			f.close()
	else:
		DirAccess.remove_absolute(manifest_file)
	get_tree().quit()

func _map(song: String, artist: String, mapper: String, source: String, hash: String,
		bytes: int, added: int, playlists: Array) -> MapInfo:
	var diffs: Array[DifficultyInfo] = []
	var m := MapInfo.new("2.0.0", song, "", artist, mapper, 120.0, 0.0, 0.0, "", "", "", 0.0,
		{}, "user://x/", diffs, source, "", hash)
	m.bytes = bytes
	m.added_unix = added
	m.playlists = playlists
	return m
