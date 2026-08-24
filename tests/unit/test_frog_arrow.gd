extends GutTest

## Tests for the arrow, which is the entire visible interface.
##
## What matters is that the arrow tracks the AIM and not the body. The ball
## spins constantly; if the arrow inherited that spin it would be unreadable,
## and the player would have nothing to aim with.

const GAME_SCENE: String = "res://scenes/game.tscn"

var _screen: Node2D
var _frog: FrogBody


func before_each() -> void:
	_screen = (load(GAME_SCENE) as PackedScene).instantiate()
	add_child_autofree(_screen)
	_frog = _screen.get_node("%Frog")


func test_the_arrow_follows_the_drag() -> void:
	_frog.begin_aim()
	_frog.update_aim(Vector2.DOWN * 200.0)
	assert_almost_eq(_frog.aim_direction().y, 1.0, 0.01, "dragged down, arrow points down")
	_frog.update_aim(Vector2.RIGHT * 200.0)
	assert_almost_eq(_frog.aim_direction().x, 1.0, 0.01, "dragged right, arrow follows")


func test_aim_power_tracks_drag_length_and_clamps() -> void:
	_frog.begin_aim()
	_frog.update_aim(Vector2.DOWN * (_screen.frog_tuning.max_drag_px * 0.5))
	assert_almost_eq(_frog.aim_power(), 0.5, 0.02, "half a pull is half power")
	_frog.update_aim(Vector2.DOWN * (_screen.frog_tuning.max_drag_px * 4.0))
	assert_almost_eq(_frog.aim_power(), 1.0, 0.001, "clamped at a full pull")


func test_the_arrow_ignores_the_body_spin() -> void:
	# The ball is a wheel and rotates constantly. The aim is in world space and
	# must not rotate with it.
	_frog.begin_aim()
	_frog.update_aim(Vector2.DOWN * 200.0)
	var before: Vector2 = _frog.aim_direction()
	_frog.rotation = PI * 0.5
	await wait_physics_frames(2)
	assert_almost_eq(_frog.aim_direction().dot(before), 1.0, 0.01, "aim unchanged by spin")


func test_cancelling_an_aim_fires_nothing() -> void:
	await wait_physics_frames(20)
	var resting: float = _frog.global_position.y
	_frog.begin_aim()
	_frog.update_aim(Vector2.DOWN * 300.0)
	_frog.cancel_aim()
	await wait_physics_frames(10)
	assert_false(_frog.aiming(), "no longer aiming")
	assert_almost_eq(_frog.global_position.y, resting, 30.0, "and it never left the ground")
