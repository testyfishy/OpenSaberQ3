extends Node

# Deterministic cover source for the BeatSaver screenshot harness: every cover resolves to the
# packaged placeholder immediately, so shots do not depend on the network or on cache timing.
# It implements the same surface the panel uses on BeatSaverCovers.

const PLACEHOLDER := preload("res://game/data/beepsaber_logo.png")

func request(_url: String, callback: Callable = Callable()) -> void:
	if callback.is_valid():
		callback.call_deferred(PLACEHOLDER)

func prefetch(_url: String) -> void:
	pass

func get_cached(_url: String) -> Texture2D:
	return PLACEHOLDER

func has_cached(_url: String) -> bool:
	return true

func cancel_all() -> void:
	pass
