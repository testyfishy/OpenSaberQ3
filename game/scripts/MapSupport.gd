extends RefCounted
class_name MapSupport

# What this build cannot render faithfully, and the decorative entries it filters (specs/013
# FR-007, third Map split).
#
# A map that uses unsupported features still loads, but the pause menu and the log say so instead
# of the map silently playing half its design (spec FR-030). Fake/decorative notes are counted so
# the filter is visible in diagnostics rather than looking inert.
#
# Static state, like Map: explicit reset() because it survives scene changes.

static var unsupported_features := PackedStringArray()
static var fakes_filtered := 0

static func reset() -> void:
	unsupported_features = PackedStringArray()
	fakes_filtered = 0

static func is_fake_v3(entry: Dictionary) -> bool:
	var cd := Utils.get_dict(entry, "customData", {})
	return Utils.get_bool(cd, "fake", false)

static func is_fake_v2(entry: Dictionary) -> bool:
	var cd := Utils.get_dict(entry, "_customData", {})
	return Utils.get_bool(cd, "_fake", false)

# `info` is passed in rather than read from Map, so this class has no dependency on the loader.
static func detect_unsupported(map_data: Dictionary, info: MapInfo) -> void:
	var found := PackedStringArray()
	if not Utils.get_array(map_data, "lightColorEventBoxGroups", []).is_empty() \
			or not Utils.get_array(map_data, "lightRotationEventBoxGroups", []).is_empty() \
			or not Utils.get_array(map_data, "lightTranslationEventBoxGroups", []).is_empty():
		found.append("box-group lighting")
	if not Utils.get_array(map_data, "rotationEvents", []).is_empty():
		found.append("360 rotation")
	for e: Variant in Utils.get_array(map_data, "_events", []):
		if e is Dictionary:
			var t := int(Utils.get_float(e as Dictionary, "_type", -1))
			if t == 14 or t == 15:
				found.append("lane rotation")
				break
	var cd := Utils.get_dict(map_data, "customData", Utils.get_dict(map_data, "_customData", {}))
	for key: String in ["customEvents", "_customEvents", "environment", "_environment", "materials"]:
		if cd.has(key):
			found.append("Chroma/Noodle animation")
			break
	# Noodle keeps decorative notes in their own arrays; we never load them, which is the
	# right outcome but has to show up in the diagnostic or the filter looks inert.
	var cd_all := Utils.get_dict(map_data, "customData", {})
	for key: String in ["fakeColorNotes", "fakeBombNotes", "fakeObstacles"]:
		fakes_filtered += Utils.get_array(cd_all, key, []).size()
	if info != null and info.custom_data.has("_assetBundle"):
		found.append("custom Unity assets")
	unsupported_features = found
	if not found.is_empty():
		vr.log_warning("MAP unsupported features: %s" % ", ".join(found))
