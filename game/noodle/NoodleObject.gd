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
# The object's own path animation (`animation` / `_animation`): points per path property, empty
# when it has none, and a bit per property it animates. It replaces the tracks' path for those
# properties (Heck AnimationHelper).
var anim: Array[NoodlePoints] = []
var anim_mask := 0
# v3 `uninteractable: true` / v2 `_interactable: false`: never hittable, never missed.
var uninteractable := false
# True when the object needs the per-tick animation path at all.
var animated := false
# Per-object jump (step 5): `noteJumpMovementSpeed` (0 = the map's), `noteJumpStartBeatOffset`,
# `disableNoteGravity`, and the resulting half jump in seconds (0 = the map's; set at load).
var njs := 0.0
var jump_offset := 0.0
var has_jump_offset := false
var disable_gravity := false
var half_sec := 0.0


## `cd` is the object's customData / _customData dictionary (either spelling is read, as the
## static parse already does). Returns null when the object uses none of these features.
static func from_custom_data(cd: Dictionary) -> NoodleObject:
	var names := NoodleTracks.names_from(cd.get("track", cd.get("_track", null)))
	var block: Variant = cd.get("animation", null)
	var block_names: Dictionary = NoodleTracks.V3_NAMES
	if not (block is Dictionary):
		block = cd.get("_animation", null)
		block_names = NoodleTracks.V2_NAMES
	var v3_flag: Variant = cd.get("uninteractable", null)
	var v2_flag: Variant = cd.get("_interactable", null)
	var uninteractable: bool = (v3_flag is bool and v3_flag) or (v2_flag is bool and not v2_flag)
	var own_njs: Variant = cd.get("noteJumpMovementSpeed", cd.get("_noteJumpMovementSpeed", null))
	var own_offset: Variant = cd.get("noteJumpStartBeatOffset", cd.get("_noteJumpStartBeatOffset", null))
	var gravity: Variant = cd.get("disableNoteGravity", cd.get("_disableNoteGravity", null))
	var has_njs := (own_njs is float or own_njs is int) and float(own_njs) > 0.0
	var has_offset := own_offset is float or own_offset is int
	var no_gravity: bool = gravity is bool and gravity
	var jump_only := has_njs or has_offset or no_gravity
	if names.is_empty() and not (block is Dictionary) and not uninteractable and not jump_only:
		return null
	var obj := NoodleObject.new()
	if has_njs:
		obj.njs = float(own_njs)
	if has_offset:
		obj.has_jump_offset = true
		obj.jump_offset = float(own_offset)
	obj.disable_gravity = no_gravity
	obj.track_names = names
	obj.uninteractable = uninteractable
	if block is Dictionary:
		for key: Variant in block as Dictionary:
			if not block_names.has(key):
				continue
			var p := int(block_names[key])
			if p > NoodleTracks.P_DEFINITE_POSITION:
				continue  # not a path property
			var pts := NoodlePoints.from_value((block as Dictionary)[key], NoodleTracks.KINDS[p], NoodleTracks.named)
			if pts == null or pts.unsupported != "":
				continue
			if obj.anim.is_empty():
				obj.anim.resize(NoodleTracks.P_COUNT)
			obj.anim[p] = pts
			obj.anim_mask |= 1 << p
	obj.animated = not names.is_empty() or obj.anim_mask != 0 or uninteractable
	return obj


static func from_entry(entry: Dictionary) -> NoodleObject:
	var cd: Variant = entry.get("customData", entry.get("_customData", null))
	if cd is Dictionary:
		return from_custom_data(cd as Dictionary)
	return null
