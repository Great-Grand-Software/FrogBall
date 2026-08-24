extends GutTest

## Tests for the clock-face jump.
##
## This is the one mechanic the prototype exists to evaluate, so what is
## asserted here is the design intent itself, not just that the maths runs: a
## neutral tap preserves momentum, a late tap is a boost and not merely a carry,
## and the backward half is NOT a mirror of the forward one. If a tuning change
## breaks one of these, it has changed the game rather than tuned it.

## Body rotations that put the feet at each clock position, facing right.
## Rotating the body positively in Godot's y-down space carries the feet
## backward, toward 9 o'clock, so forward positions are negative rotations.
const AT_SIX: float = 0.0
const AT_FOUR_THIRTY: float = -PI / 4.0
const AT_THREE: float = -PI / 2.0
const AT_SEVEN_THIRTY: float = PI / 4.0
const AT_NINE: float = PI / 2.0
const AT_TWELVE: float = PI

var _tuning: FrogTuning


func before_each() -> void:
	_tuning = FrogTuning.new()


func _solve(rotation: float, velocity: Vector2, facing: int = 1) -> JumpOutcome:
	return JumpSolver.solve(_tuning, rotation, velocity, facing)


# --- where the feet are ----------------------------------------------------


func test_feet_phase_maps_to_the_clock_face() -> void:
	assert_almost_eq(JumpSolver.feet_phase_deg(AT_SIX, 1), 0.0, 0.01, "6 o'clock is zero")
	assert_almost_eq(JumpSolver.feet_phase_deg(AT_THREE, 1), 90.0, 0.01, "3 o'clock is +90")
	assert_almost_eq(JumpSolver.feet_phase_deg(AT_NINE, 1), -90.0, 0.01, "9 o'clock is -90")
	assert_almost_eq(absf(JumpSolver.feet_phase_deg(AT_TWELVE, 1)), 180.0, 0.01, "12 is +/-180")


func test_the_clock_follows_the_direction_of_travel() -> void:
	# "Forward" is wherever the frog is going, so facing left mirrors the clock.
	assert_almost_eq(JumpSolver.feet_phase_deg(AT_THREE, -1), -90.0, 0.01, "mirrored")
	assert_almost_eq(JumpSolver.feet_phase_deg(AT_NINE, -1), 90.0, 0.01, "mirrored")


# --- the neutral jump ------------------------------------------------------


func test_a_neutral_tap_launches_straight_up() -> void:
	var outcome: JumpOutcome = _solve(AT_SIX, Vector2(600.0, 0.0))
	assert_true(outcome.fired, "a tap at bottom dead centre jumps")
	assert_false(outcome.mistimed, "6 o'clock is the centre of the window")
	assert_almost_eq(outcome.tilt_deg, 0.0, 0.01, "no tilt at 6 o'clock")
	assert_almost_eq(outcome.velocity.y, -_tuning.base_jump_impulse, 0.01, "impulse is vertical")


func test_a_neutral_tap_preserves_horizontal_velocity_exactly() -> void:
	var outcome: JumpOutcome = _solve(AT_SIX, Vector2(600.0, 0.0))
	assert_almost_eq(outcome.velocity.x, 600.0, 0.01, "carried, not changed")


# --- the forward half: a boost, not a carry --------------------------------


func test_the_halfway_forward_tap_is_a_forty_five_degree_arc() -> void:
	# The reference point from the design brief, and the reason the default
	# curve is linear with a 90 degree edge.
	var outcome: JumpOutcome = _solve(AT_FOUR_THIRTY, Vector2(600.0, 0.0))
	assert_almost_eq(outcome.tilt_deg, 45.0, 0.5, "~4:30 launches on a 45 degree arc")


func test_a_forward_tap_adds_power_rather_than_only_redirecting() -> void:
	var neutral: JumpOutcome = _solve(AT_SIX, Vector2(600.0, 0.0))
	var forward: JumpOutcome = _solve(AT_FOUR_THIRTY, Vector2(600.0, 0.0))
	assert_gt(forward.power, neutral.power, "a late tap is boosted, not just angled")
	assert_gt(forward.velocity.x, neutral.velocity.x + 200.0, "and it kicks forward hard")


func test_tilt_and_power_rise_together_toward_three_oclock() -> void:
	var last_tilt: float = -1.0
	var last_power: float = -1.0
	for step: int in range(9):
		var phase: float = float(step) / 8.0
		var outcome: JumpOutcome = _solve(-phase * PI / 2.0, Vector2(600.0, 0.0))
		assert_gt(outcome.tilt_deg, last_tilt - 0.001, "tilt never dips at %.2f" % phase)
		assert_gt(outcome.power, last_power - 0.001, "power never dips at %.2f" % phase)
		last_tilt = outcome.tilt_deg
		last_power = outcome.power


func test_facing_left_launches_left() -> void:
	# "Forward" is the direction of travel, so for a left-facing frog the
	# forward half of the window is the rotation that would be backward for a
	# right-facing one. Same tap, mirrored.
	var outcome: JumpOutcome = _solve(AT_SEVEN_THIRTY, Vector2(-600.0, 0.0), -1)
	assert_lt(outcome.velocity.x, -600.0, "a forward boost going left goes further left")
	assert_almost_eq(outcome.tilt_deg, 45.0, 0.5, "and it is the same 45 degree arc")


# --- the backward half: momentum wins --------------------------------------


func test_a_standing_frog_can_launch_backward() -> void:
	var outcome: JumpOutcome = _solve(AT_SEVEN_THIRTY, Vector2.ZERO)
	assert_lt(outcome.velocity.x, -100.0, "with no momentum, a late tap really reverses")


func test_forward_momentum_cancels_a_backward_tap() -> void:
	var outcome: JumpOutcome = _solve(
		AT_SEVEN_THIRTY, Vector2(_tuning.backward_dominance_speed, 0.0)
	)
	assert_almost_eq(outcome.backward_suppression, 1.0, 0.01, "fully suppressed at the threshold")
	assert_almost_eq(outcome.tilt_deg, 0.0, 0.01, "collapses to a vertical hop")
	assert_gt(outcome.velocity.x, 0.0, "the frog keeps going forward")


func test_backward_suppression_grows_with_speed() -> void:
	var last: float = -1.0
	for step: int in range(6):
		var speed: float = float(step) * 0.2 * _tuning.backward_dominance_speed
		var outcome: JumpOutcome = _solve(AT_NINE, Vector2(speed, 0.0))
		assert_gt(outcome.backward_suppression, last - 0.001, "monotonic at %.0f px/s" % speed)
		last = outcome.backward_suppression


func test_the_backward_half_is_not_a_mirror_of_the_forward_half() -> void:
	# The asymmetry is the design, not an accident: a moving frog must not get a
	# reliable reverse button out of the same window that gives it a boost.
	var speed := Vector2(_tuning.backward_dominance_speed, 0.0)
	var forward: JumpOutcome = _solve(AT_FOUR_THIRTY, speed)
	var backward: JumpOutcome = _solve(AT_SEVEN_THIRTY, speed)
	assert_gt(absf(forward.tilt_deg), 40.0, "the forward side tilts hard")
	assert_almost_eq(backward.tilt_deg, 0.0, 0.01, "the backward side does not, at speed")


# --- the top half is a miss ------------------------------------------------


func test_a_tap_in_the_top_half_is_flagged_as_mistimed() -> void:
	var outcome: JumpOutcome = _solve(AT_TWELVE, Vector2(600.0, 0.0))
	assert_true(outcome.mistimed, "12 o'clock is outside the window")


func test_a_mistimed_tap_is_far_weaker_than_a_real_one() -> void:
	var missed: JumpOutcome = _solve(AT_TWELVE, Vector2(600.0, 0.0))
	var hit: JumpOutcome = _solve(AT_SIX, Vector2(600.0, 0.0))
	assert_lt(missed.power, hit.power * 0.5, "a whiff must never rival a real jump")


func test_a_mistimed_tap_can_be_configured_to_do_nothing() -> void:
	_tuning.mistimed_tap = FrogTuning.MistimedTap.NO_OP
	var outcome: JumpOutcome = _solve(AT_TWELVE, Vector2(600.0, 0.0))
	assert_false(outcome.fired, "the no-op policy swallows the tap")
	assert_eq(outcome.velocity, Vector2(600.0, 0.0), "and leaves velocity untouched")


func test_the_window_edges_follow_the_tuning() -> void:
	_tuning.window_arc_deg = 90.0
	assert_false(_solve(AT_FOUR_THIRTY, Vector2.ZERO).mistimed, "45 deg is inside a 90 deg arc")
	assert_true(_solve(AT_THREE, Vector2.ZERO).mistimed, "90 deg is outside it")


func test_the_window_can_be_rotated_off_bottom_dead_centre() -> void:
	_tuning.window_arc_deg = 90.0
	_tuning.window_centre_offset_deg = 45.0
	assert_false(_solve(AT_THREE, Vector2.ZERO).mistimed, "3 o'clock is now in the window")
	assert_true(_solve(AT_SEVEN_THIRTY, Vector2.ZERO).mistimed, "and 7:30 has fallen out of it")


# --- the reusable buffer ---------------------------------------------------


func test_solving_into_a_reused_outcome_leaves_nothing_behind() -> void:
	# The frog holds one JumpOutcome and rewrites it every tap, so a stale field
	# would silently leak the previous jump into the next one.
	var buffer := JumpOutcome.new()
	JumpSolver.solve_into(buffer, _tuning, AT_NINE, Vector2.ZERO, 1)
	assert_gt(absf(buffer.tilt_deg), 0.0, "the first solve tilts")
	JumpSolver.solve_into(buffer, _tuning, AT_SIX, Vector2.ZERO, 1)
	assert_almost_eq(buffer.tilt_deg, 0.0, 0.01, "the second solve starts clean")
	assert_almost_eq(buffer.backward_suppression, 0.0, 0.01, "and so does every other field")
