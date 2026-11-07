extends Panel

## The left-side BeatLeader launcher (specs/025 FR-007).
##
## A sign beside the song list that opens the existing read-only leaderboard for whatever map
## and difficulty the main menu has selected. It owns no leaderboard logic of its own.

signal open_requested()

@onready var open_button := $Margin/VBox/OpenButton as Button

func _ready() -> void:
	UI_AudioEngine.attach_children(self)
	open_button.pressed.connect(_on_open_pressed)

func _on_open_pressed() -> void:
	open_requested.emit()
