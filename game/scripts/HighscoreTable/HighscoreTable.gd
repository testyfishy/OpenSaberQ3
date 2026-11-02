extends Node
class_name HighscoreTable

# location to store the highscores on filesystem
const HIGHSCORES_FILEPATH := "user://highscores.json"

# maximum records to store in each song's record table. once list
# grows past this length, the lowest ranking score will get bumped.
const MAX_RECORDS_PER_KEY := 10

# internal copy of the highscore table
# restored from user file in _ready()
# {
#   "<hs_key>" : {# records for a given song
#       "1" : [ # records at diffucultyRank 1
#           {"player_name":"Bob","score":10000,"epoch_time":0}
#           {"player_name":"Alice","score":5000,"epoch_time":0}
#       ],
#       "3" : [ # records at diffucultyRank 3
#           {"player_name":"Bob","score":10000,"epoch_time":0}
#           {"player_name":"Alice","score":5000,"epoch_time":0}
#       ]
#   }
# }
var _hs_table: Dictionary = {}

func _ready() -> void:
	load_hs_table()

# clears the whole highscore table
func clear_table() -> void:
	_hs_table = {}

# removes a given map from the table, effectively resetting that map's records
func remove_map(map_info: MapInfo) -> void:
	var hs_key := map_info.get_key()
	@warning_ignore("return_value_discarded")
	_hs_table.erase(hs_key)
	save_hs_table()
	
# returns true if score is a new highscore in the table, false otherwise
func is_new_highscore(map_info: MapInfo, diff_rank: int, score: int) -> bool:
	var hs_key := map_info.get_key()
	return _is_new_highscore(hs_key, diff_rank, score)
	
# adds a new score record to the table. if the score is not a highscore
# then the record will not be stored.
#
# map_info : data structure as read for map's info.dat file
# diff_rank : difficulty rank (1,3,etc.) that the score was set on
# player_name : string name for the player
# score : integer score to store
# user_id : profile id the score belongs to ("" for records without a profile)
#
# return : the stored record, or {} when the score did not make the table
func add_highscore(map_info: MapInfo, diff_rank: int ,player_name: String, score: int, user_id: String = "") -> Dictionary:
	# get existing records for song + difficulty
	var hs_key := map_info.get_key()
	var records := _get_records(hs_key,diff_rank)
	
	# construct a new record and resort the list
	var record := _make_record(score,player_name,user_id)
	records.append(record)
	records.sort_custom(_highest_and_oldest)
	
	# remove the lowest ranking score
	if records.size() > MAX_RECORDS_PER_KEY:
		records.pop_back()
		
	# store updated records in table
	if not _hs_table.has(hs_key):
		_hs_table[hs_key] = {}
	_hs_table[hs_key][str(diff_rank)] = records
	
	save_hs_table()
	
	# the new record might have been the one that got bumped
	return record if _index_of_record(records,record) != -1 else {}

# moves a stored record to another player name / profile. The record keeps its score and
# epoch_time, so the score itself is never lost or reordered within the table.
#
# return : the moved record, or {} when the record is no longer in the table
func move_record(map_info: MapInfo, diff_rank: int, record: Dictionary, player_name: String, user_id: String) -> Dictionary:
	var hs_key := map_info.get_key()
	var records := _get_records(hs_key,diff_rank)
	
	var index := _index_of_record(records,record)
	if index == -1:
		# bumped out of the table since it was saved: nothing to move
		return {}
	
	var moved := _make_record(int(record.score),player_name,user_id)
	moved["epoch_time"] = int(record.epoch_time)
	records.remove_at(index)
	records.append(moved)
	records.sort_custom(_highest_and_oldest)
	
	if records.size() > MAX_RECORDS_PER_KEY:
		records.pop_back()
		
	if not _hs_table.has(hs_key):
		_hs_table[hs_key] = {}
	_hs_table[hs_key][str(diff_rank)] = records
	save_hs_table()
	
	return moved if _index_of_record(records,moved) != -1 else {}

# return : the list of records for the given map + difficulty
func get_records(map_info: MapInfo, diff_rank: int) -> Array:
	var hs_key := map_info.get_key()
	return _get_records(hs_key,diff_rank)
	
# return : the overall highscore for the given map + difficulty. -1 is
# returned if no record exist for this song yet
func get_highscore(map_info: MapInfo, diff_rank: int) -> int:
	var hs_key := map_info.get_key()
	var records := _get_records(hs_key,diff_rank)
	if records.size() == 0:
		return -1
	else:
		return records[0].score
	
# return : list of all unique players names in highscore table
func get_all_player_names() -> Array[String]:
	var unique_names: Array[String] = []
	for song_records: Dictionary in _hs_table.values():
		for diff_record: Array in song_records.values():
			for hs_entry: Dictionary in diff_record:
				var player_name: String = hs_entry.player_name
				# add name to list if we haven't seen it before
				if not unique_names.has(player_name):
					unique_names.append(player_name)
	return unique_names

# return : list of all unique player names, most recently scored name first
func get_player_names_by_recency() -> Array[String]:
	var latest_epoch: Dictionary = {}
	for song_records: Dictionary in _hs_table.values():
		for diff_record: Array in song_records.values():
			for hs_entry: Dictionary in diff_record:
				var player_name: String = hs_entry.player_name
				var epoch_time := int(hs_entry.get("epoch_time",0))
				if not latest_epoch.has(player_name) or int(latest_epoch[player_name]) < epoch_time:
					latest_epoch[player_name] = epoch_time
	
	var names: Array[String] = []
	for player_name: String in latest_epoch.keys():
		names.append(player_name)
	names.sort_custom(func(a: String, b: String) -> bool:
		return int(latest_epoch[a]) > int(latest_epoch[b]))
	return names

# restores highscore table from filesystem
func load_hs_table() -> void:
	var file := FileAccess.open(HIGHSCORES_FILEPATH,FileAccess.READ)
	if file:
		var text := file.get_as_text()
		file.close()
		var json_res := JSON.parse_string(text) as Dictionary
		if json_res:
			_hs_table = json_res
	else:
		print("WARN: Failed to open %s (might not exist yet)" % HIGHSCORES_FILEPATH)

# saves highscore table to filesystem
func save_hs_table() -> void:
	var file := FileAccess.open(HIGHSCORES_FILEPATH,FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_hs_table,"   ",true))
		file.close()
	else:
		print("ERROR: Failed to open %s" % HIGHSCORES_FILEPATH)

# internal function used to lookup records for a given song + diffculty
func _get_records(hs_key: String, diff_rank: int) -> Array:
	var records: Array = []
	
	if _hs_table.has(hs_key):
		var i: Variant = _hs_table[hs_key]
		if not i is Dictionary: return []
		var hs_row := i as Dictionary
		if hs_row.has(str(diff_rank)):
			records = hs_row[str(diff_rank)]
	
	return records

# internal function used too check if a score is a new highscore
func _is_new_highscore(hs_key: String, diff_rank: int, score: int) -> bool:
	var records := _get_records(hs_key,diff_rank)
	# make a temporary record just for lookup purposes
	var temp_record := _make_record(score,"**TEMP_PLAYER**")
	return _get_insert_index(records,temp_record) < MAX_RECORDS_PER_KEY

# creates a "record" structure for storage in the highscore table
func _make_record(score: int, player_name: String, user_id: String = "") -> Dictionary:
	return {
		"score" : score,
		"player_name" : player_name,
		"epoch_time" : Time.get_unix_time_from_system(),
		"user_id" : user_id
	}

# return : index of the given record in records, or -1 when it is not there.
# records are matched by value because they are plain dictionaries
func _index_of_record(records: Array, record: Dictionary) -> int:
	for i in records.size():
		var candidate: Variant = records[i]
		if not candidate is Dictionary: continue
		var other := candidate as Dictionary
		if (int(other.get("score",0)) == int(record.get("score",0))
			and int(other.get("epoch_time",0)) == int(record.get("epoch_time",0))
			and String(other.get("player_name","")) == String(record.get("player_name",""))
			and String(other.get("user_id","")) == String(record.get("user_id",""))):
			return i
	return -1

# records: the list of records for a given (song + diff_rank)
# record: the score record to request the insertion index for
func _get_insert_index(records: Array, record: Dictionary) -> int:
	return records.bsearch_custom(record, _highest_and_oldest, false)

static func _highest_and_oldest(lhs: Dictionary, rhs: Dictionary) -> bool:
	if lhs.score > rhs.score:
		return true
	elif lhs.score < rhs.score:
		return false
	else:
		#  Older score's should be sorted with higher precedance
		# than newer scores.
		if lhs.epoch_time < rhs.epoch_time:
			return true
	return false
