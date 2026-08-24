extends GutTest

## Tests for the run screen, and specifically for what it does NOT do.
##
## Frog Ball has no end state: a player can roll until they get bored. That
## makes a leak the risk worth testing for — a build that adds one node per
## terrain segment reviews fine and dies after a long session. So the assertions
## here are about node count staying flat, not about the game being fun.

const GAME_SCENE: String = "res://scenes/game.tscn"

## The ceiling from CLAUDE.md section 4, asserted rather than remembered.
const NODE_CEILING: int = 64

## Pinned so the integration tests replay one known course. A random course
## would make them flaky, and a flaky test gets deleted.
const A_PINNED_SEED: int = 20260824

var _screen: Node2D


func before_each() -> void:
	_screen = (load(GAME_SCENE) as PackedScene).instantiate()
	add_child_autofree(_screen)


func _count_nodes(root: Node) -> int:
	var total: int = 1
	for child: Node in root.get_children():
		total += _count_nodes(child)
	return total


func test_the_run_scene_loads() -> void:
	assert_not_null(_screen, "game.tscn instantiates")


func test_the_whole_run_fits_under_the_node_ceiling() -> void:
	var total: int = _count_nodes(_screen)
	assert_lt(total, NODE_CEILING, "the run uses %d nodes" % total)


func test_terrain_collision_is_a_fixed_pool() -> void:
	var terrain: Node = _screen.get_node("%Terrain")
	assert_eq(
		terrain.get_child_count(),
		TerrainPlan.MAX_SEGMENTS,
		"one polygon per capped segment, allocated once"
	)


func test_generating_far_more_terrain_spawns_nothing() -> void:
	# The property that matters: rolling forever costs no extra nodes.
	var before: int = _count_nodes(_screen)
	var plan: TerrainPlan = _screen.terrain_plan()
	for step: int in range(500):
		plan.advance_to(float(step) * 800.0)
	_screen.refresh_terrain()
	assert_eq(_count_nodes(_screen), before, "500 advances later, the same nodes")


func test_restarting_many_times_spawns_nothing() -> void:
	var before: int = _count_nodes(_screen)
	for _run: int in range(30):
		_screen.start_run()
	assert_eq(_count_nodes(_screen), before, "30 runs later, the same nodes")


func test_the_run_starts_the_frog_above_the_opening_runway() -> void:
	var plan: TerrainPlan = _screen.terrain_plan()
	var frog: Node2D = _screen.get_node("%Frog")
	# reset_to() defers to the next physics step, so compare against the plan
	# rather than the body's not-yet-applied transform.
	assert_almost_eq(
		plan.start_point().y, plan.segment_start(0).y, 0.01, "spawn sits on the first span"
	)
	assert_not_null(frog, "the frog is in the scene")


func test_the_debug_overlay_is_off_by_default() -> void:
	# The prototype asks whether the timing reads with nothing explained. An
	# overlay that draws the window would answer that question for the player.
	assert_false(_screen.debug_overlay, "no overlay unless someone turns it on")
	assert_false(_screen.get_node("%Debug").visible, "and it is not on screen")


# --- it actually plays -----------------------------------------------------


func test_the_frog_rolls_forward_on_its_own() -> void:
	# Rolling is automatic and momentum-driven; there is no input for it. If
	# this fails the player is sitting still with nothing to time a tap against.
	_screen.run_seed = A_PINNED_SEED
	_screen.start_run()
	var frog: Node2D = _screen.get_node("%Frog")
	await wait_physics_frames(6)
	var from: float = frog.global_position.x
	await wait_physics_frames(90)
	assert_gt(frog.global_position.x - from, 200.0, "1.5 s of rolling covers real ground")


func test_the_frog_settles_onto_the_terrain_rather_than_falling_through() -> void:
	_screen.run_seed = A_PINNED_SEED
	_screen.start_run()
	var frog: FrogBody = _screen.get_node("%Frog")
	await wait_physics_frames(30)
	assert_true(frog.grounded, "the opening runway holds the frog up")


func test_a_tap_gets_the_frog_off_the_ground() -> void:
	_screen.run_seed = A_PINNED_SEED
	_screen.start_run()
	var frog: FrogBody = _screen.get_node("%Frog")
	await wait_physics_frames(30)
	var resting_y: float = frog.global_position.y
	frog.queue_tap()
	await wait_physics_frames(12)
	assert_lt(frog.global_position.y, resting_y - 40.0, "the tap launched it upward")


func test_a_run_survives_its_opening_seconds() -> void:
	# Not a fun test, a fairness one: whatever the generator rolls, the player
	# should not be dead before they have worked out what the tap does.
	_screen.run_seed = A_PINNED_SEED
	_screen.start_run()
	var frog: Node2D = _screen.get_node("%Frog")
	var start_x: float = _screen.terrain_plan().start_point().x
	await wait_physics_frames(120)
	assert_gt(frog.global_position.x, start_x, "still going forward two seconds in")


func test_a_frog_knocked_backward_rolls_itself_back() -> void:
	# Regression. The self-drive used to follow the direction of travel, so one
	# mistimed opening tap could reverse the frog and then accelerate it
	# backward for ever — a dead run with no way for the player to recover.
	_screen.run_seed = A_PINNED_SEED
	_screen.start_run()
	var frog: FrogBody = _screen.get_node("%Frog")
	await wait_physics_frames(30)
	frog.linear_velocity = Vector2(-500.0, 0.0)
	await wait_physics_frames(120)
	assert_gt(frog.linear_velocity.x, 0.0, "the frog is heading back down the level")
	assert_true(_screen.is_running(), "and it recovered rather than dying")
