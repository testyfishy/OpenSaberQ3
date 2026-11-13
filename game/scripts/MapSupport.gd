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

	var cd := Utils.get_dict(map_data, "customData", Utils.get_dict(map_data, "_customData", {}))
	# Noodle animation (tracks, custom events) is played since 0.7.29: what it cannot do is
	# reported by note_noodle() once the events are parsed. The environment is still not built.
	if cd.has("environment") or cd.has("_environment"):
		found.append("Chroma environment")
	if cd.has("materials") or cd.has("_materials"):
		found.append("Chroma geometry materials")
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


const VIVIFY_EVENTS := ["AssignObjectPrefab", "InstantiatePrefab", "DestroyObject", "Blit",
	"SetMaterialProperty", "SetGlobalProperty", "SetCameraProperty", "SetRenderingSettings",
	"CreateScreenTexture", "CreateCamera", "SetAnimatorProperty", "DeclareCullingTexture",
	"DeclareRenderTexture", "DestroyTexture"]
const CHROMA_EVENTS := ["AnimateComponent", "AssignFogTrack"]
const PROPERTY_NAMES := {
	"time": "track time animation", "_time": "track time animation",
	"dissolveArrow": "arrow dissolve", "_dissolveArrow": "arrow dissolve",
	"color": "Chroma colour animation", "_color": "Chroma colour animation",
}


## Adds what the loaded map's Noodle animation uses that this build does not apply. Called by
## Map.load_beatmap with NoodleEvents' counts once the custom events are parsed. The counts are
## passed in rather than read here: MapData's loaders use this class, so it must not depend on
## the Noodle classes (which depend on MapData) or the static init order breaks.
static func note_noodle(ignored: Dictionary, unsupported_points: int, unsupported_targets: int,
		unapplied: Dictionary) -> void:
	var found := PackedStringArray()
	var others := PackedStringArray()
	for type: Variant in ignored:
		var label := ""
		if VIVIFY_EVENTS.has(type):
			label = "Vivify events"
		elif CHROMA_EVENTS.has(type):
			label = "Chroma component/fog events"
		else:
			others.append(str(type))
			continue
		if not found.has(label):
			found.append(label)
	if not others.is_empty():
		others.sort()
		found.append("custom events %s" % "/".join(others))
	if unsupported_points > 0:
		found.append("Heck point bases/modifiers")
	if unsupported_targets > 0:
		found.append("player head/hand tracks")
	for key: Variant in unapplied:
		var label: String = PROPERTY_NAMES.get(key, "animated %s" % str(key).trim_prefix("_"))
		if not found.has(label):
			found.append(label)
	if found.is_empty():
		return
	for f in found:
		if not unsupported_features.has(f):
			unsupported_features.append(f)
	vr.log_warning("MAP Noodle features not played: %s" % ", ".join(found))

