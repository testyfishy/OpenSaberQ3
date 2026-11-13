extends RefCounted
class_name NoodleObject

# The Noodle Extensions data of one note, bomb or wall that the static parse does not cover:
# which tracks it belongs to (and, in later steps, its own animation and jump overrides).
#
# Built by the object parsers on MapData's loader threads, so from_custom_data() is pure: it
# reads its arguments and NoodleTracks.named, and leaves the track names unresolved. An object
# without any of this data gets no NoodleObject at all (null), which is what keeps the per-tick
# path of an ordinary map unchanged.

var track_names := PackedStringArray()
# Indices into NoodleTracks.tracks, filled by NoodleTracks.resolve_objects().
var tracks := PackedInt32Array()


## `cd` is the object's customData / _customData dictionary (either spelling is read, as the
## static parse already does). Returns null when the object uses none of these features.
static func from_custom_data(cd: Dictionary) -> NoodleObject:
	var names := NoodleTracks.names_from(cd.get("track", cd.get("_track", null)))
	if names.is_empty():
		return null
	var obj := NoodleObject.new()
	obj.track_names = names
	return obj


static func from_entry(entry: Dictionary) -> NoodleObject:
	var cd: Variant = entry.get("customData", entry.get("_customData", null))
	if cd is Dictionary:
		return from_custom_data(cd as Dictionary)
	return null
