extends RefCounted
class_name PaletteResolver

# One implementation of the Chroma colour rules (v0.4 FR-005).
#
# Chroma stores a per-entry colour either as {r,g,b} in 0..1 or as an RGB hex string. The same
# parser was copied into the note, obstacle and event infos; this is the single source of truth.

static func chroma_color(value: Variant) -> Color:
	if value is Dictionary:
		@warning_ignore("unsafe_cast")
		var d := value as Dictionary
		return Color(
			Utils.get_float(d, "r", 1.0),
			Utils.get_float(d, "g", 1.0),
			Utils.get_float(d, "b", 1.0),
			1.0
		)
	if value is String:
		var hex := (value as String).strip_edges().trim_prefix("#")
		if hex.length() == 6:
			return Color(
				("0x" + hex.substr(0, 2)).hex_to_int() / 255.0,
				("0x" + hex.substr(2, 2)).hex_to_int() / 255.0,
				("0x" + hex.substr(4, 2)).hex_to_int() / 255.0,
				1.0
			)
	return Color(0.0, 0.0, 0.0, 0.0)
