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
static var fake_objects := 0
# The loaded difficulty's Chroma environment: how many entries remove a stock environment object,
# and whether that is enough to say the map replaces the environment (see environment_removals).
static var environment_removals := 0
static var replaces_environment := false
# 15 removals or more. The fixture library has a clear gap here: maps that only tweak a few
# objects remove at most 7, maps that clear the stock room remove 19 or more.
const ENVIRONMENT_REPLACE_MIN := 15

static func reset() -> void:
	unsupported_features = PackedStringArray()
	fake_objects = 0
	environment_removals = 0
	replaces_environment = false

## How many entries of a Chroma `environment` / `_environment` list remove a stock environment
## object: turned off (`active` false), scaled to zero on any axis, or moved 500 units or more
## away. Entries that build new geometry are not removals. Pure.
static func environment_removals_in(entries: Array) -> int:
	var n := 0
	for e: Variant in entries:
		if not (e is Dictionary):
			continue
		var d := e as Dictionary
		if d.has("geometry") or d.has("_geometry"):
			continue
		var active: Variant = d.get("active", d.get("_active", null))
		if active is bool and not active:
			n += 1
			continue
		var removed := false
		var scale: Variant = d.get("scale", d.get("_scale", null))
		if scale is Array:
			for i in mini((scale as Array).size(), 3):
				var v: Variant = (scale as Array)[i]
				if (v is float or v is int) and absf(float(v)) < 0.001:
					removed = true
		for key: String in ["position", "_position", "localPosition", "_localPosition"]:
			var pos: Variant = d.get(key, null)
			if pos is Array:
				for i in mini((pos as Array).size(), 3):
					var v: Variant = (pos as Array)[i]
					if (v is float or v is int) and absf(float(v)) >= 500.0:
						removed = true
		if removed:
			n += 1
	return n

## True while the stock room should be hidden: the player's setting is on, a song is being played
## (playing or paused), and the loaded map replaces the environment.
static func hide_room(setting_on: bool, in_song: bool) -> bool:
	return setting_on and in_song and replaces_environment

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
		environment_removals = environment_removals_in(Utils.get_array(cd, "environment", Utils.get_array(cd, "_environment", [])))
		replaces_environment = environment_removals >= ENVIRONMENT_REPLACE_MIN
		if replaces_environment:
			vr.log_info("MAP replaces the environment: %d stock objects removed" % environment_removals)
	if cd.has("materials") or cd.has("_materials"):
		found.append("Chroma geometry materials")
	# Noodle v3 keeps decorative objects in their own arrays (drawn, never scored; MapData).
	# v2 `_fake` objects are counted by the loader.
	var cd_all := Utils.get_dict(map_data, "customData", {})
	for key: String in ["fakeColorNotes", "fakeBombNotes", "fakeObstacles"]:
		fake_objects += Utils.get_array(cd_all, key, []).size()
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

