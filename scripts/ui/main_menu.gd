extends Control

## The first screen a player lands on.
##
## Every game from this template gets one, so there is always a deliberate
## entry point rather than dropping straight into play. START is the contract:
## whatever your game is, it begins here.

## Scene START hands off to. Change this rather than the button wiring.
const GAME_SCENE: String = "res://scenes/game.tscn"

@onready var _start_button: Button = %Start
@onready var _quit_button: Button = %Quit


func _ready() -> void:
	# Wired in code so the connection shows up in the diff rather than being
	# buried in the .tscn.
	_start_button.pressed.connect(_on_start_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)

	# A browser tab has no meaningful "quit", and the button would be a dead
	# end there. Everywhere else it is the polite way out.
	_quit_button.visible = not OS.has_feature("web")
	_start_button.grab_focus()


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
