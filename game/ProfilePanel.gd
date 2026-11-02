extends Panel
class_name ProfilePanel

# The household's list of players. One chip per profile; the chip of the profile that is
# currently playing is disabled, which is also how it is highlighted (the disabled style is
# the light one). The panel does not know why it was opened - the owner decides whether
# choosing a profile is a plain switch or also re-attributes the score that was just saved.
signal user_chosen(id: String)
signal new_user_requested()
signal close_requested()

const CHIP_HEIGHT := 48

# @onready var _base_chip = $.../BaseChip.duplicate() (see below) keeps one copy of the chip
# around so the list can be rebuilt, the way HighscorePanel keeps its BaseRecordRow.
@onready var _base_chip := ($Margin/VBox/ScrollContainer/Margin/UsersList/BaseChip as Button).duplicate()
@onready var _user_list := $Margin/VBox/ScrollContainer/Margin/UsersList as VBoxContainer

func _ready() -> void:
	_clear_users()

# rebuilds the chips from ProfileManager and takes over from there = "open the panel"
func open() -> void:
	_clear_users()
	for user in ProfileManager.get_users():
		_add_chip(user)

func _add_chip(user: Dictionary) -> void:
	var id := String(user.get("id",""))
	var player_name := String(user.get("name",""))
	var is_current := id == ProfileManager.current_id()
	
	var chip := _base_chip.duplicate() as Button
	chip.text = player_name
	chip.custom_minimum_size = Vector2(0, CHIP_HEIGHT)
	chip.toggle_mode = true
	# the current profile is shown pressed and cannot be pressed again
	chip.button_pressed = is_current
	chip.disabled = is_current
	chip.pressed.connect(_on_chip_pressed.bind(id))
	_user_list.add_child(chip)

func _clear_users() -> void:
	for child in _user_list.get_children():
		child.queue_free()

func _on_chip_pressed(id: String) -> void:
	user_chosen.emit(id)

func _on_New_Button_pressed() -> void:
	new_user_requested.emit()

func _on_Close_Button_pressed() -> void:
	close_requested.emit()
