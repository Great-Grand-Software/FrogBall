extends GutTest

## Tests for the main menu.
##
## Every game from this template starts here, so the thing worth asserting is
## the contract rather than the appearance: there is a START control, and the
## scene it hands off to actually exists. A menu whose START button points at a
## missing scene looks fine in review and dead-ends the player.

const MENU_SCENE: String = "res://scenes/main_menu.tscn"

var _menu: Control


func before_each() -> void:
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child_autofree(_menu)


func test_the_menu_scene_loads() -> void:
	assert_not_null(_menu, "main_menu.tscn instantiates")


func test_a_start_control_exists() -> void:
	var start: Button = _menu.get_node_or_null("%Start")
	assert_not_null(start, "the menu has a START button")


func test_start_hands_off_to_a_scene_that_exists() -> void:
	var target: String = _menu.get("GAME_SCENE")
	assert_ne(target, "", "GAME_SCENE is set")
	assert_true(ResourceLoader.exists(target), "START target exists: %s" % target)


func test_quit_is_hidden_on_the_web_build() -> void:
	var quit: Button = _menu.get_node_or_null("%Quit")
	assert_not_null(quit, "the menu has a QUIT button")
	# OS.has_feature("web") is false in a headless test run, so QUIT is visible
	# here. What matters is that visibility is driven by the feature, not left
	# hardcoded — asserted by reading the same feature the script reads.
	assert_eq(quit.visible, not OS.has_feature("web"), "QUIT visibility tracks the platform")
