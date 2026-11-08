extends SceneTree

# Adds the OpenXR hand interaction profile to the project's custom action map.
# Godot only auto-creates these bindings for its built-in map, and this project ships its own
# (openxr_action_map.tres), so the hand pose and the pinch float input must be bound here.
# Idempotent: rerunning replaces the hand profile and reuses the pinch action.
#
# Why a dedicated `pinch` float action and not select_button/pinch_ext/ready_ext:
# ready_ext means "a pinch can be detected", not "the fingers are touching", and Godot's
# is_button_pressed() treats any nonzero float as pressed. The game reads the float with
# hysteresis instead (BeepSaberController.PINCH_PRESS/RELEASE).

const PROFILE_PATH := "/interaction_profiles/ext/hand_interaction_ext"
const MAP_PATH := "res://openxr_action_map.tres"

func _init() -> void:
	var map := load(MAP_PATH) as OpenXRActionMap
	if map == null:
		push_error("Could not load %s" % MAP_PATH)
		quit(1)
		return
	if map.get_action_set_count() == 0:
		push_error("Action map has no action set")
		quit(1)
		return

	var action_set: OpenXRActionSet = map.get_action_set(0)
	var pinch: OpenXRAction = null
	for action in action_set.actions:
		if action.resource_name == "pinch":
			pinch = action

	if pinch == null:
		pinch = OpenXRAction.new()
		pinch.resource_name = "pinch"
		pinch.localized_name = "Pinch"
		pinch.action_type = OpenXRAction.OPENXR_ACTION_FLOAT
		pinch.toplevel_paths = PackedStringArray(["/user/hand/left", "/user/hand/right"])
		action_set.add_action(pinch)

	for i in range(map.get_interaction_profile_count() - 1, -1, -1):
		var existing := map.get_interaction_profile(i)
		if existing != null and existing.interaction_profile_path == PROFILE_PATH:
			map.remove_interaction_profile(existing)

	var actions := {}
	for set in map.get_action_sets():
		for action in set.actions:
			actions[action.resource_name] = action

	# Pose actions the existing controller rig already consumes, plus the pinch float.
	var bindings := {
		"default_pose": "aim/pose",
		"aim_pose": "aim/pose",
		"grip_pose": "grip/pose",
		"pinch": "pinch_ext/value",
	}

	var profile := OpenXRInteractionProfile.new()
	profile.interaction_profile_path = PROFILE_PATH
	for action_name: String in bindings:
		var action: OpenXRAction = actions.get(action_name)
		if action == null:
			push_warning("Missing action %s; hand profile binding skipped" % action_name)
			continue
		for side in ["left", "right"]:
			# 4.6 keeps one path per binding resource; the old multi-path add_path is deprecated.
			var binding := OpenXRIPBinding.new()
			binding.action = action
			binding.binding_path = "/user/hand/%s/input/%s" % [side, bindings[action_name]]
			profile.bindings.append(binding)

	map.add_interaction_profile(profile)
	var err := ResourceSaver.save(map, MAP_PATH)
	if err != OK:
		push_error("Could not save %s: %s" % [MAP_PATH, error_string(err)])
		quit(1)
		return
	print("HAND PROFILE added with %d bindings" % profile.get_binding_count())
	quit()
