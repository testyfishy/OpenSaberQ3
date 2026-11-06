extends RefCounted
class_name EnvironmentProfiles

# Per-environment palettes (spec FR-027/FR-028). These are our reading of each Beat Saber
# environment's theme, not its art: the room is ours, so the UI says "Room: OpenSaber" and no
# fidelity is claimed. Every map that names no environment falls back to Default, which is the
# classic red/blue pair, so an unknown name can never produce an unreadable scene.
#
# Keys are note colours (what the cubes use), env colours (what the room's lights use), boost
# colours (FR-029) and the wall tint. Values are linear 0..1 and deliberately below the note
# emissive brightness.

const DEFAULT := {
	"note_left": Color(0.85, 0.10, 0.12),
	"note_right": Color(0.10, 0.25, 0.95),
	"env_left": Color(0.95, 0.14, 0.16),
	"env_right": Color(0.12, 0.36, 1.00),
	"boost_left": Color(1.00, 0.93, 0.93),
	"boost_right": Color(0.90, 0.94, 1.00),
	"wall": Color(0.70, 0.06, 0.06),
}

const PROFILES := {
	"DefaultEnvironment": {},
	"TriangleEnvironment": {},
	"NiceEnvironment": {},
	"BigMirrorEnvironment": {},
	"DragonsEnvironment": {},
	"WeaveEnvironment": {},
	"InterscopeEnvironment": {},
	"BillieEnvironment": {
		"note_left": Color(0.25, 0.90, 0.55),
		"note_right": Color(0.10, 0.62, 0.95),
		"env_left": Color(0.30, 0.95, 0.60),
		"env_right": Color(0.10, 0.55, 0.85),
		"wall": Color(0.06, 0.55, 0.25),
	},
	"BTSEnvironment": {
		"note_left": Color(0.62, 0.25, 0.95),
		"note_right": Color(0.95, 0.25, 0.72),
		"env_left": Color(0.70, 0.30, 1.00),
		"env_right": Color(1.00, 0.30, 0.80),
		"wall": Color(0.42, 0.08, 0.60),
	},
	"PanicEnvironment": {
		"note_left": Color(0.95, 0.22, 0.10),
		"note_right": Color(0.98, 0.60, 0.10),
		"env_left": Color(1.00, 0.25, 0.10),
		"env_right": Color(1.00, 0.65, 0.12),
		"wall": Color(0.62, 0.10, 0.03),
	},
	"RocketEnvironment": {
		"note_left": Color(0.10, 0.45, 0.98),
		"note_right": Color(1.00, 0.55, 0.10),
		"env_left": Color(0.15, 0.50, 1.00),
		"env_right": Color(1.00, 0.60, 0.12),
		"wall": Color(0.05, 0.28, 0.70),
	},
	"FitBeatEnvironment": {
		"note_left": Color(1.00, 0.45, 0.05),
		"note_right": Color(0.05, 0.80, 0.68),
		"env_left": Color(1.00, 0.50, 0.06),
		"env_right": Color(0.06, 0.85, 0.72),
		"wall": Color(0.55, 0.22, 0.02),
	},
	"TimbalandEnvironment": {
		"note_left": Color(0.98, 0.80, 0.20),
		"note_right": Color(0.20, 0.45, 1.00),
		"env_left": Color(1.00, 0.85, 0.25),
		"env_right": Color(0.20, 0.45, 1.00),
		"wall": Color(0.55, 0.42, 0.05),
	},
	"GagaEnvironment": {
		"note_left": Color(1.00, 0.35, 0.62),
		"note_right": Color(0.30, 0.80, 1.00),
		"env_left": Color(1.00, 0.38, 0.66),
		"env_right": Color(0.32, 0.82, 1.00),
		"wall": Color(0.58, 0.12, 0.32),
	},
	"MetallicaEnvironment": {
		"note_left": Color(0.90, 0.12, 0.10),
		"note_right": Color(0.92, 0.92, 0.92),
		"env_left": Color(0.95, 0.14, 0.12),
		"env_right": Color(0.95, 0.95, 0.95),
		"wall": Color(0.60, 0.05, 0.05),
	},
	"LizzoEnvironment": {
		"note_left": Color(0.95, 0.55, 0.10),
		"note_right": Color(0.55, 0.20, 0.95),
		"env_left": Color(1.00, 0.60, 0.12),
		"env_right": Color(0.60, 0.22, 1.00),
		"wall": Color(0.55, 0.28, 0.04),
	},
	"TheWeekndEnvironment": {
		"note_left": Color(0.90, 0.10, 0.25),
		"note_right": Color(0.20, 0.55, 0.95),
		"env_left": Color(0.95, 0.12, 0.30),
		"env_right": Color(0.22, 0.60, 1.00),
		"wall": Color(0.45, 0.05, 0.15),
	},
	"MonstercatEnvironment": {
		"note_left": Color(0.95, 0.35, 0.10),
		"note_right": Color(0.10, 0.75, 0.85),
		"env_left": Color(1.00, 0.40, 0.12),
		"env_right": Color(0.12, 0.80, 0.90),
		"wall": Color(0.40, 0.16, 0.04),
	},
	"CrabRaveEnvironment": {
		"note_left": Color(0.95, 0.20, 0.55),
		"note_right": Color(0.20, 0.85, 0.95),
		"env_left": Color(1.00, 0.22, 0.60),
		"env_right": Color(0.22, 0.90, 1.00),
		"wall": Color(0.40, 0.06, 0.28),
	},
	"OverkillEnvironment": {
		"note_left": Color(0.85, 0.15, 0.10),
		"note_right": Color(0.15, 0.55, 0.95),
		"env_left": Color(0.90, 0.16, 0.12),
		"env_right": Color(0.16, 0.60, 1.00),
		"wall": Color(0.35, 0.06, 0.05),
	},
	"AngelVoicesEnvironment": {
		"note_left": Color(0.95, 0.85, 0.55),
		"note_right": Color(0.45, 0.65, 1.00),
		"env_left": Color(1.00, 0.88, 0.60),
		"env_right": Color(0.50, 0.70, 1.00),
		"wall": Color(0.42, 0.36, 0.20),
	},
	"KDAEnvironment": {
		"note_left": Color(0.75, 0.20, 0.95),
		"note_right": Color(0.20, 0.85, 0.95),
		"env_left": Color(0.80, 0.22, 1.00),
		"env_right": Color(0.22, 0.90, 1.00),
		"wall": Color(0.32, 0.08, 0.45),
	},
	"SkrillexEnvironment": {
		"note_left": Color(0.85, 0.10, 0.35),
		"note_right": Color(0.10, 0.75, 0.95),
		"env_left": Color(0.90, 0.12, 0.40),
		"env_right": Color(0.12, 0.80, 1.00),
		"wall": Color(0.48, 0.05, 0.22),
	},
}

static func get_profile(name: String) -> Dictionary:
	var wanted := name.strip_edges().to_lower()
	var found: Dictionary = {}
	var matched := false
	for key: String in PROFILES:
		if key.to_lower() == wanted:
			found = PROFILES[key]
			matched = true
			break
	# Unknown or future environments (or a map with no name) still get a palette: a stable hash
	# of the name picks two opposite hues. The same map always looks the same, two unknown
	# environments differ, and the readability guards in Map still apply. The room geometry is
	# ours either way, so nothing here can be "wrong" - only unmapped.
	if not matched and not wanted.is_empty():
		found = _derived_profile(name)
	var out := DEFAULT.duplicate()
	out.merge(found, true)
	return out

static func _derived_profile(name: String) -> Dictionary:
	var h := float(absi(hash(name)) % 360) / 360.0
	var left := Color.from_hsv(h, 0.78, 0.80)
	var right := Color.from_hsv(fposmod(h + 0.5, 1.0), 0.78, 0.80)
	return {
		"note_left": left,
		"note_right": right,
		"env_left": left.darkened(0.1),
		"env_right": right.darkened(0.1),
		"boost_left": Color(1.0, 0.95, 0.95),
		"boost_right": right.lightened(0.5),
		"wall": left.darkened(0.45),
	}
