extends GutTest

## Tests for the arrow — the entire visual language of the game.
##
## The body is a bare circle, so the arrow is the only thing on screen carrying
## information: where it points is the aim, and it shoots out on a press so the
## jump reads as a shove off the floor rather than the ball teleporting upward.
## That makes it worth asserting, even though it is "just" a visual.

const GAME_SCENE: String = "res://scenes/game.tscn"
const A_PINNED_SEED: int = 20260824

var _screen: Node2D


func before_each() -> void:
	_screen = (load(GAME_SCENE) as PackedScene).instantiate()
	add_child_autofree(_screen)


func test_the_arrow_fires_on_a_jump_and_springs_back() -> void:
	# The arrow shooting out is what makes a press read as a shove off the
	# floor. If it stopped firing, the jump would look like a teleport.
	_screen.run_seed = A_PINNED_SEED
	_screen.start_run()
	var frog: FrogBody = _screen.get_node("%Frog")
	await wait_physics_frames(20)
	assert_almost_eq(frog.arrow_push(), 0.0, 0.01, "sits at the rim at rest")

	frog.begin_tap()
	await wait_physics_frames(2)
	assert_gt(frog.arrow_push(), 0.5, "shoots out on the press")

	frog.release_tap()
	# Recoil runs on the render clock, so wait on frames rather than physics.
	await wait_frames(int(_screen.frog_tuning.arrow_recoil_sec * 70.0) + 20)
	assert_almost_eq(frog.arrow_push(), 0.0, 0.01, "springs back afterwards")


func test_the_arrow_stays_out_while_the_press_is_still_feeding_power() -> void:
	_screen.run_seed = A_PINNED_SEED
	_screen.start_run()
	var frog: FrogBody = _screen.get_node("%Frog")
	await wait_physics_frames(20)
	frog.begin_tap()
	await wait_frames(4)
	assert_almost_eq(frog.arrow_push(), 1.0, 0.01, "held out while charging")
