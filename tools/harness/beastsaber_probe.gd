extends Node

# Exercises the BeastSaber panel against the live BeatSaver JSON API without VR:
# playlist page -> .bplist -> one map lookup. Prints BEASTPROBE lines for the report.

func _ready() -> void:
	var panel := preload("res://game/ui/BeastSaberPanel/BeastSaberPanel.tscn").instantiate() as BeastSaberPanel
	add_child(panel)
	await get_tree().process_frame
	panel._load_page(0)
	var waited := 0.0
	while panel._busy != BeastSaberPanel.Busy.NONE and waited < 20.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	print("BEASTPROBE list busy=%d loaded=%s playlists=%d status=%s" % [
		panel._busy, panel._loaded, panel._playlists.size(), panel.status_label.text])
	if panel._playlists.is_empty():
		get_tree().quit()
		return
	for i in range(mini(3, panel._playlists.size())):
		var doc: Dictionary = panel._playlists[i]
		print("BEASTPROBE item %d: %s | %s | maps=%s" % [
			i, doc.get("name", "?"), (doc.get("owner", {}) as Dictionary).get("name", "?"),
			(doc.get("stats", {}) as Dictionary).get("totalMaps", 0)])

	# Open the smallest playlist on the page and read its .bplist plus one map lookup.
	var pick := 0
	var best := 1 << 30
	for i in range(panel._playlists.size()):
		var maps := int((panel._playlists[i].get("stats", {}) as Dictionary).get("totalMaps", 0))
		if maps > 0 and maps < best:
			best = maps
			pick = i
	panel._on_playlist_pressed(pick)
	var doc: Dictionary = panel._playlists[pick]
	print("BEASTPROBE selected: %s maps=%d" % [doc.get("name", "?"), best])

	var req := HTTPRequest.new()
	req.timeout = 20.0
	add_child(req)
	var url: String = str(doc.get("downloadURL", ""))
	req.request(url, PackedStringArray(["User-Agent: OpenSaberQ3/0.6 probe"]))
	var res: Array = await req.request_completed
	var body: PackedByteArray = res[3]
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	var songs: Array = (parsed as Dictionary).get("songs", []) if parsed is Dictionary else []
	print("BEASTPROBE bplist code=%d songs=%d first_hash=%s" % [
		res[1], songs.size(),
		str((songs[0] as Dictionary).get("hash", "")) if not songs.is_empty() else ""])
	if songs.is_empty():
		get_tree().quit()
		return
	var hash := str((songs[0] as Dictionary).get("hash", ""))
	req.request("https://api.beatsaver.com/maps/hash/%s" % hash,
		PackedStringArray(["User-Agent: OpenSaberQ3/0.6 probe"]))
	res = await req.request_completed
	parsed = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if parsed is Dictionary:
		var versions: Array = (parsed as Dictionary).get("versions", [])
		print("BEASTPROBE map code=%d name=%s version=%s url=%s" % [
			res[1], (parsed as Dictionary).get("name", "?"),
			(versions[0] as Dictionary).get("hash", "") if not versions.is_empty() else "",
			(versions[0] as Dictionary).get("downloadURL", "") if not versions.is_empty() else ""])
		# --- zip guard + real install path ---------------------------------------------
		var tempdir := Constants.APPDATA_PATH + "temp"
		DirAccess.make_dir_recursive_absolute(tempdir)
		var good := tempdir + "/probe_good.zip"
		var bad := tempdir + "/probe_bad.zip"
		_make_zip(good, "Info.dat")
		_make_zip(bad, "readme.txt")
		print("BEASTPROBE zip good=%s bad=%s" % [panel._zip_has_info(good), panel._zip_has_info(bad)])
		DirAccess.remove_absolute(good)
		DirAccess.remove_absolute(bad)

		if not (versions as Array).is_empty():
			var zip_url := str((versions[0] as Dictionary).get("downloadURL", ""))
			req.request(zip_url, PackedStringArray(["User-Agent: OpenSaberQ3/0.6 probe"]))
			res = await req.request_completed
			panel._current_name = panel._safe_name(str((parsed as Dictionary).get("name", "probe")))
			panel._current_id = str((parsed as Dictionary).get("id", ""))
			panel._current_hash = str((versions[0] as Dictionary).get("hash", ""))
			var dir := Constants.APPDATA_PATH + "Songs/" + panel._current_name + "/"
			var first := panel._install_zip(res[3] as PackedByteArray)
			var tag := MapSource.read(dir)
			var second := panel._install_zip(res[3] as PackedByteArray)
			print("BEASTPROBE install zip_code=%d first=%d source=%s hash_ok=%s second=%d" % [
				res[1], first, tag.get("source", "?"),
				str(tag.get("hash", "")) == panel._current_hash, second])
			panel._remove_tree(dir)
			DirAccess.remove_absolute(dir.trim_suffix("/"))
	else:
		print("BEASTPROBE map code=%d parse failed" % res[1])
	get_tree().quit()

func _make_zip(path: String, entry: String) -> void:
	var packer := ZIPPacker.new()
	if packer.open(path) != OK:
		return
	packer.start_file(entry)
	packer.write_file("{}".to_utf8_buffer())
	packer.close_file()
	packer.close()
