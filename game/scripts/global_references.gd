extends Node

const HitAudioScript := preload("res://game/scripts/HitAudio.gd")
const AudioAnalyserScript := preload("res://game/scripts/AudioAnalyser.gd")

var cube_pool : ScenePool # the pool of BeepCubes
var link_pool : ScenePool # the pool of ChainLinks
var wall_pool : ScenePool # the pool of Walls - a wall map spawns tens per second
var main_game_scene : BeepSaber_Game
# Positioned hit voices (Part 6, FR-031).
var hit_audio
var audio_analyser

func _ready() -> void:
	hit_audio = HitAudioScript.new()
	hit_audio.name = "HitAudio"
	add_child(hit_audio)
	audio_analyser = AudioAnalyserScript.new()
	audio_analyser.name = "AudioAnalyser"
	add_child(audio_analyser)
