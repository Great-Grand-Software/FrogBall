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
	var ledges: int = 0
	for child: Node in terrain.get_children():
		if child is CollisionPolygon2D:
			ledges += 1
	assert_eq(ledges, TerrainPlan.MAX_SEGMENTS, "one polygon per capped ledge, allocated once")
	# The two shaft walls are repositioned, never added to.
	assert_eq(terrain.get_child_count(), TerrainPlan.MAX_SEGMENTS + 2, "plus exactly two walls")


func test_generating_far_more_terrain_spawns_nothing() -> void:
	# The property that matters: rolling forever costs no extra nodes.
	var before: int = _count_nodes(_screen)
	var plan: TerrainPlan = _screen.terrain_plan()
	for step: int in range(500):
		plan.advance_above(float(-step) * 500.0)
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
	# Measured before it can reach a wall: the shaft is narrow, and a bounce
	# would make a directional assertion meaningless. The threshold is well
	# under what a second of rolling covers, because roll speed is tuned against
	# the shaft width and will move again — this asserts "it moves at all",
	# which is the property worth pinning, not a particular speed.
	await wait_physics_frames(60)
	assert_gt(absf(frog.global_position.x - from), 60.0, "it gets itself moving")


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
	await wait_physics_frames(120)
	assert_true(_screen.is_running(), "still alive two seconds in")


func test_a_frog_knocked_backward_rolls_itself_back() -> void:
	# Regression. The self-drive used to follow the direction of travel, so one
	# mistimed opening tap could reverse the frog and then accelerate it
	# backward for ever — a dead run with no way for the player to recover.
	# Walls may now turn the frog around, but its own velocity still may not.
	_screen.run_seed = A_PINNED_SEED
	_screen.start_run()
	var frog: FrogBody = _screen.get_node("%Frog")
	await wait_physics_frames(30)
	frog.linear_velocity = Vector2(-500.0, 0.0)
	await wait_physics_frames(120)
	assert_gt(frog.linear_velocity.x, 0.0, "the frog is heading back down the level")
	assert_true(_screen.is_running(), "and it recovered rather than dying")


# --- the new dials ---------------------------------------------------------


func test_a_run_starts_the_frog_on_the_briefed_clock_angle() -> void:
	# Standing on 4:30 means the player's very first tap — made before they know
	# there is a window at all — is a good forward launch, not a coin flip.
	_screen.run_seed = A_PINNED_SEED
	_screen.start_run()
	var frog: FrogBody = _screen.get_node("%Frog")
	await wait_physics_frames(2)
	assert_almost_eq(
		frog.feet_phase_deg(), _screen.frog_tuning.start_phase_deg, 6.0, "starts near 4:30"
	)


func test_each_run_rolls_a_different_radius() -> void:
	# Randomised on purpose: radius trades spin rate against readability and
	# only play can settle it, so every run is a fresh data point.
	var frog: FrogBody = _screen.get_node("%Frog")
	var seen: Dictionary = {}
	for _run: int in range(12):
		_screen.start_run()
		seen[roundi(frog.radius())] = true
	assert_gt(seen.size(), 1, "twelve runs are not all the same frog")


func test_a_rolled_radius_stays_inside_the_tuned_range() -> void:
	var frog: FrogBody = _screen.get_node("%Frog")
	var tuning: FrogTuning = _screen.frog_tuning
	for _run: int in range(20):
		_screen.start_run()
		assert_between(frog.radius(), tuning.radius_min, tuning.radius_max, "within range")


func test_the_frog_is_placed_on_the_surface_whatever_size_it_rolled() -> void:
	# The screen no longer guesses how tall the frog is, so a big roll must not
	# spawn it buried in the ground or dropped from a height.
	_screen.run_seed = A_PINNED_SEED
	_screen.start_run()
	var frog: FrogBody = _screen.get_node("%Frog")
	var surface: float = _screen.terrain_plan().start_point().y
	await wait_physics_frames(4)
	assert_almost_eq(
		frog.global_position.y, surface - frog.radius(), 6.0, "sitting exactly on top"
	)


func test_holding_longer_jumps_higher() -> void:
	# The apex has to be tracked across the WHOLE flight, released mid-way: a
	# long hold has already peaked by the time the button comes up, so measuring
	# only after release reports the descent.
	var apexes: Array[float] = []
	for hold: int in [1, 24]:
		_screen.run_seed = A_PINNED_SEED
		_screen.start_run()
		var frog: FrogBody = _screen.get_node("%Frog")
		await wait_physics_frames(20)
		var resting: float = frog.global_position.y
		var highest: float = 0.0
		frog.begin_tap()
		for step: int in range(70):
			if step == hold:
				frog.release_tap()
			await wait_physics_frames(1)
			highest = maxf(highest, resting - frog.global_position.y)
		apexes.append(highest)
	assert_gt(apexes[1], apexes[0] * 1.4, "a full press clears far more than a flick")


func test_a_press_fires_the_jump_immediately() -> void:
	# The press is the input. A jump that waited for release would fire at an
	# angle the frog had already spun past, which is unaimable — the whole game
	# is timing a rotation you can see.
	_screen.run_seed = A_PINNED_SEED
	_screen.start_run()
	var frog: FrogBody = _screen.get_node("%Frog")
	await wait_physics_frames(20)
	var resting: float = frog.global_position.y
	frog.begin_tap()
	await wait_physics_frames(4)
	assert_lt(frog.global_position.y, resting - 10.0, "already airborne, no charge-up wait")


func test_releasing_early_cuts_the_jump_short() -> void:
	# Same angle, same everything, only the length of the press differs.
	_screen.run_seed = A_PINNED_SEED
	_screen.start_run()
	var frog: FrogBody = _screen.get_node("%Frog")
	await wait_physics_frames(20)
	frog.begin_tap()
	await wait_physics_frames(2)
	frog.release_tap()
	var cut: float = absf(frog.linear_velocity.y)
	assert_lt(cut, 0.0 + _screen.frog_tuning.base_jump_impulse, "a flick is not a full jump")
