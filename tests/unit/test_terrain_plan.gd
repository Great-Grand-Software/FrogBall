extends GutTest

## Tests for TerrainPlan, the climbing shaft.
##
## Note what is asserted: the guardrails and the reachability, not the scenery.
## That the ring buffer cannot grow matters more than any particular ledge, and
## that a ledge is always reachable matters more than that it looks varied — a
## generator that can emit an unclearable tier ends runs for reasons the player
## cannot see, which is the worst kind of bug in a game with no tutorial.

const A_PINNED_SEED: int = 4242

var _tuning: LevelTuning
var _plan: TerrainPlan


func before_each() -> void:
	_tuning = LevelTuning.new()
	_plan = TerrainPlan.new(_tuning, Vector2.ZERO)
	_plan.reset(A_PINNED_SEED)


## Drives generation the way the screen does — once per frame — because a
## single call is deliberately capped so it can never hang.
func _advance_to(target_y: float) -> void:
	for _tick: int in range(6):
		_plan.advance_above(target_y)


func test_a_fresh_shaft_starts_with_a_floor() -> void:
	assert_eq(_plan.segment_count(), 1, "just the floor")
	assert_almost_eq(_plan.segment_start(0).y, 0.0, 0.01, "the floor is at the origin")


func test_the_ledge_count_never_exceeds_the_ring_buffer() -> void:
	# The guardrail that makes an endless climb safe: the oldest ledge is
	# overwritten by construction, so nothing accumulates.
	for step: int in range(200):
		_plan.advance_above(float(-step) * 400.0)
		assert_lte(
			_plan.segment_count(), TerrainPlan.MAX_SEGMENTS, "at most MAX_SEGMENTS live"
		)


func test_advance_above_always_terminates() -> void:
	# Bounded per call, so even an absurd target cannot hang a CI runner.
	_plan.advance_above(-1_000_000.0)
	assert_lte(_plan.segment_count(), TerrainPlan.MAX_SEGMENTS, "capped rather than looping")


func test_the_shaft_climbs() -> void:
	# Each call is capped at MAX_SPANS_PER_ADVANCE so it cannot hang, which is
	# why this drives it repeatedly the way the screen does, once per frame.
	for _tick: int in range(5):
		_plan.advance_above(-3000.0)
	assert_lt(_plan.frontier_y(), -3000.0, "built past the target, upward")


func test_ledges_are_stacked_in_ascending_order() -> void:
	_advance_to(-2500.0)
	for index: int in range(1, _plan.segment_count()):
		assert_lt(
			_plan.segment_start(index).y,
			_plan.segment_start(index - 1).y,
			"ledge %d sits above the one below it" % index
		)


func test_every_rise_stays_within_the_tuned_range() -> void:
	# A rise taller than a full-power jump makes the climb impossible, and the
	# player has no way to see that it was the level's fault rather than theirs.
	_advance_to(-4000.0)
	for index: int in range(1, _plan.segment_count()):
		var rise: float = _plan.segment_start(index - 1).y - _plan.segment_start(index).y
		assert_between(rise, _tuning.rise_min - 1.0, _tuning.rise_max + 1.0, "reachable rise")


func test_every_ledge_stays_inside_the_shaft() -> void:
	_advance_to(-4000.0)
	for index: int in range(_plan.segment_count()):
		assert_gte(_plan.segment_start(index).x, _plan.shaft_left() - 1.0, "not through the left wall")
		assert_lte(_plan.segment_end(index).x, _plan.shaft_right() + 1.0, "not through the right wall")


func test_consecutive_ledges_stay_within_lateral_reach() -> void:
	# Vertical reach is not enough on its own: a ledge directly above but right
	# across the shaft is just as unclearable.
	_advance_to(-4000.0)
	var reach: float = _tuning.shaft_width * _tuning.max_lateral_step + 1.0
	for index: int in range(2, _plan.segment_count()):
		var previous: float = (_plan.segment_start(index - 1).x + _plan.segment_end(index - 1).x) * 0.5
		var current: float = (_plan.segment_start(index).x + _plan.segment_end(index).x) * 0.5
		assert_lte(absf(current - previous), reach, "ledge %d is within reach sideways" % index)


func test_the_same_seed_builds_the_same_shaft() -> void:
	_advance_to(-3000.0)
	var other := TerrainPlan.new(_tuning, Vector2.ZERO)
	other.reset(A_PINNED_SEED)
	for _tick: int in range(6):
		other.advance_above(-3000.0)
	assert_eq(other.segment_count(), _plan.segment_count(), "same ledge count")
	for index: int in range(_plan.segment_count()):
		assert_almost_eq(
			other.segment_start(index).y, _plan.segment_start(index).y, 0.01, "same height"
		)
		assert_almost_eq(
			other.segment_start(index).x, _plan.segment_start(index).x, 0.01, "same position"
		)


func test_the_lowest_live_ledge_rises_as_the_climb_goes_on() -> void:
	# The kill plane trails this, so it has to keep up or a long climb becomes
	# unloseable.
	# Has to climb far enough to actually exhaust the ring: at ~275px a tier,
	# 26 slots hold roughly 7000px before anything is recycled.
	var early: float = _plan.lowest_surface_y()
	_advance_to(-14000.0)
	assert_lt(_plan.lowest_surface_y(), early, "the floor of the live window moved up")
