extends Node

# Lightweight user profiles: who is playing right now, and the name scores are stored under.
#
# Everything lives in user://profiles.json:
#   {"version":1,"current":"<id>","users":[{"id":"u1","name":"Alice","created":1700000000}]}
#
# This autoload reads the highscore table when it bootstraps, so it has to be listed after
# Highscores in project.godot. Existing scores are never touched: records keep player_name,
# new records also carry user_id.
signal changed

const PROFILES_FILEPATH := "user://profiles.json"
const VERSION := 1
const DEFAULT_PLAYER_NAME := "Player"

var _users: Array[Dictionary] = []
var _current_id := ""

func _ready() -> void:
	load_profiles()

func get_users() -> Array[Dictionary]:
	return _users

func current_id() -> String:
	return _current_id

func current_name() -> String:
	return String(current_user().get("name",""))

func current_user() -> Dictionary:
	return get_user(_current_id)

func get_user(id: String) -> Dictionary:
	for user in _users:
		if String(user.get("id","")) == id:
			return user
	return {}

# return : the profile with this name (case-insensitive), or {} when there is none
func find_user_by_name(player_name: String) -> Dictionary:
	var wanted := player_name.strip_edges().to_lower()
	if wanted.is_empty():
		return {}
	for user in _users:
		if String(user.get("name","")).to_lower() == wanted:
			return user
	return {}

# switches the current profile. returns false when the id is unknown or already current
func set_current(id: String) -> bool:
	if id == _current_id:
		return false
	if get_user(id).is_empty():
		return false
	_current_id = id
	save()
	changed.emit()
	return true

# creates a profile and makes it current. A name that already exists (case-insensitive)
# returns the existing profile instead of duplicating it.
func create_user(player_name: String) -> Dictionary:
	var wanted := player_name.strip_edges()
	if wanted.is_empty():
		return {}
	var existing := find_user_by_name(wanted)
	if not existing.is_empty():
		set_current(String(existing.id))
		return existing
	var user := {"id": _next_id(), "name": wanted, "created": int(Time.get_unix_time_from_system())}
	_users.append(user)
	_current_id = String(user.id)
	save()
	changed.emit()
	return user

# restores user://profiles.json, falling back to bootstrapping when it is missing or unusable
func load_profiles() -> void:
	_users.clear()
	_current_id = ""
	if FileAccess.file_exists(PROFILES_FILEPATH):
		var file := FileAccess.open(PROFILES_FILEPATH, FileAccess.READ)
		if file:
			var text := file.get_as_text()
			file.close()
			var parsed: Variant = JSON.parse_string(text)
			if parsed is Dictionary and _read_profiles(parsed as Dictionary):
				return
		vr.log_warning("profiles.json is unreadable, rebuilding profiles from the highscore table")
	bootstrap()

# builds profiles from the distinct player names already in the highscore table, newest first.
# The most recently scored name becomes the current profile. Reads only - the highscore file
# is never written here.
func bootstrap() -> void:
	_users.clear()
	for player_name in Highscores.get_player_names_by_recency():
		if find_user_by_name(player_name).is_empty():
			_users.append(_new_user(player_name))
	if _users.is_empty():
		_users.append(_new_user(DEFAULT_PLAYER_NAME))
	_current_id = String(_users[0].id)
	save()

func save() -> void:
	var data := {
		"version": VERSION,
		"current": _current_id,
		"users": _users
	}
	var file := FileAccess.open(PROFILES_FILEPATH, FileAccess.WRITE)
	if file == null:
		vr.log_file_error(FileAccess.get_open_error(), PROFILES_FILEPATH, "save() in ProfileManager.gd")
		return
	file.store_string(JSON.stringify(data, "  ", true))
	file.close()

# return : true when the parsed file had at least one usable profile
func _read_profiles(data: Dictionary) -> bool:
	var raw: Variant = data.get("users",null)
	if not raw is Array:
		return false
	
	var users: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	for entry: Variant in (raw as Array):
		if not entry is Dictionary:
			continue
		var record := entry as Dictionary
		var id := String(record.get("id",""))
		var name := String(record.get("name","")).strip_edges()
		# a hand-edited file could hold duplicate or empty ids: treat the whole file as corrupt
		# and rebuild instead of guessing which profile is meant
		if id.is_empty() or name.is_empty() or seen_ids.has(id):
			return false
		seen_ids[id] = true
		users.append({"id": id, "name": name, "created": int(record.get("created",0))})
	
	if users.is_empty():
		return false
	
	_users = users
	var current := String(data.get("current",""))
	if get_user(current).is_empty():
		# stale current id: fall back to the first profile and persist the repair
		_current_id = String(users[0].id)
		save()
	else:
		_current_id = current
	return true

func _new_user(player_name: String) -> Dictionary:
	return {
		"id": _next_id(),
		"name": player_name.strip_edges(),
		"created": int(Time.get_unix_time_from_system())
	}

# ids are u1, u2, ... and are never reused, even after profiles are removed by hand
func _next_id() -> String:
	var highest := 0
	for user in _users:
		var id := String(user.get("id",""))
		if id.begins_with("u") and id.substr(1).is_valid_int():
			highest = maxi(highest, int(id.substr(1)))
	return "u%d" % (highest + 1)
