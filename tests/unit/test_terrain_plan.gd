extends GutTest

## Tests for the endless terrain.
##
## The guardrail matters more than the shape here. An endless runner that leaks
## one segment per span is fine in review and dead after ten minutes, so the
## ring buffer's ceiling is asserted directly rather than trusted.

const A_SEED: int = 20260824
const FAR: float = 400000.0

var _tuning: LevelTuning
var _plan: TerrainPlan


func before_each() -> void:
	_tuning = LevelTuning.new()
	_plan = TerrainPlan.new(_tuning, Vector2.ZERO)
	_plan.reset(A_SEED)


# --- the guardrail ---------------------------------------------------------


func test_segment_count_never_exceeds_the_cap() -> void:
	for step: int in range(400):
		_plan.advance_to(float(step) * 500.0)
		assert_lte(
			_plan.segment_count(),
			TerrainPlan.MAX_SEGMENTS,
			"segments stay capped at step %d" % step
		)


func test_the_cap_is_a_named_constant_under_the_node_ceiling() -> void:
	# One collision polygon per segment, so this constant is the terrain's whole
	# contribution to the 64-node ceiling in CLAUDE.md section 4.
	assert_lt(TerrainPlan.MAX_SEGMENTS, 64, "the pool cannot breach the node ceiling")


func test_advancing_terminates_even_for_an_absurd_target() -> void:
	# The loop is capped per call, so this returns rather than hanging a runner.
	_plan.advance_to(FAR)
	assert_lte(_plan.segment_count(), TerrainPlan.MAX_SEGMENTS, "still capped")
	assert_lt(_plan.frontier_x(), FAR, "one call does not try to build it all")


func test_repeated_advancing_does_reach_a_far_target() -> void:
	for _step: int in range(200):
		_plan.advance_to(20000.0)
	assert_gt(_plan.frontier_x(), 20000.0, "called in a loop, it gets there")


# --- the shape of a run ----------------------------------------------------


func test_the_same_seed_builds_the_same_terrain() -> void:
	_plan.advance_to(12000.0)
	var first: Vector2 = _plan.segment_start(0)
	var last: Vector2 = _plan.segment_end(_plan.segment_count() - 1)

	var other := TerrainPlan.new(_tuning, Vector2.ZERO)
	other.reset(A_SEED)
	other.advance_to(12000.0)

	assert_eq(other.segment_start(0), first, "same seed, same first live segment")
	assert_eq(other.segment_end(other.segment_count() - 1), last, "and same frontier")


func test_the_run_opens_on_an_unbroken_runway() -> void:
	# The first thing a player meets should be a roll they can feel, not a hole.
	var opening: Vector2 = _plan.segment_end(0)
	assert_almost_eq(
		opening.x - _plan.segment_start(0).x,
		_tuning.start_runway_behind + _tuning.start_runway_length,
		1.0,
		"the opening span covers the runway both sides of the spawn"
	)
	assert_almost_eq(opening.y, _plan.start_point().y, 0.01, "and it is flat")


func test_the_runway_extends_behind_the_spawn_point() -> void:
	# An opening tap is usually mistimed, and a mistimed one on a standing frog
	# can genuinely launch it backward. Landing on ground teaches the player
	# something; dropping off the back of the world does not.
	assert_lte(
		_plan.segment_start(0).x,
		_plan.start_point().x - _tuning.start_runway_behind + 1.0,
		"there is ground behind the frog to land on"
	)


func test_the_terrain_contains_gaps_that_must_be_jumped() -> void:
	_plan.advance_to(12000.0)
	var gaps: int = 0
	for index: int in range(1, _plan.segment_count()):
		if _plan.segment_start(index).x - _plan.segment_end(index - 1).x > 1.0:
			gaps += 1
	assert_gt(gaps, 0, "a level with no gaps never asks for a jump")


func test_the_surface_stays_inside_the_drift_limit() -> void:
	for _step: int in range(200):
		_plan.advance_to(_plan.frontier_x() + 4000.0)
		for index: int in range(_plan.segment_count()):
			var height: float = absf(_plan.segment_start(index).y - _plan.start_point().y)
			assert_lte(height, _tuning.vertical_drift_limit + 1.0, "no runaway climb or dive")


func test_a_flat_only_mix_produces_a_continuous_surface() -> void:
	# Proves the weights actually steer generation, so tuning them is real.
	_tuning.weight_downhill = 0.0
	_tuning.weight_uphill = 0.0
	_tuning.weight_gap_step = 0.0
	_tuning.weight_stairs = 0.0
	var flat := TerrainPlan.new(_tuning, Vector2.ZERO)
	flat.reset(A_SEED)
	flat.advance_to(9000.0)
	for index: int in range(flat.segment_count()):
		assert_almost_eq(
			flat.segment_end(index).y, flat.start_point().y, 0.01, "every span stays level"
		)


# --- the kill plane --------------------------------------------------------


func test_the_kill_plane_reads_the_ground_under_the_frog() -> void:
	_plan.advance_to(9000.0)
	var here: Vector2 = _plan.segment_start(1)
	var lowest: float = _plan.lowest_surface_y(here.x - 10.0, here.x + 10.0)
	assert_gte(lowest, here.y - 0.01, "the plane sits at or below the surface there")


func test_the_kill_plane_still_answers_over_a_gap() -> void:
	# Asked about empty air, it must fall back rather than return an infinity
	# that would make the frog immortal or kill it instantly.
	_plan.advance_to(9000.0)
	var beyond: float = _plan.frontier_x() + 50000.0
	var lowest: float = _plan.lowest_surface_y(beyond, beyond + 10.0)
	assert_true(is_finite(lowest), "always a real height")
