extends GutTest

## Tests for the hold-to-charge half of the jump.
##
## The clock decides WHERE a jump goes; the press decides HOW HARD. These are
## deliberately independent, and the tests that matter here are the ones that
## prove they stay independent — a flick and a full press at the same rotation
## must differ in power and in nothing else.

const AT_SIX: float = 0.0
const AT_FOUR_THIRTY: float = -PI / 4.0
const AT_TWELVE: float = PI

var _tuning: FrogTuning


func before_each() -> void:
	_tuning = FrogTuning.new()




func test_a_flick_is_a_hop_and_a_full_press_is_a_jump() -> void:
	var flick: JumpOutcome = JumpSolver.solve(_tuning, AT_SIX, Vector2.ZERO, 1, 0.0)
	var full: JumpOutcome = JumpSolver.solve(_tuning, AT_SIX, Vector2.ZERO, 1, 1.0)
	assert_lt(flick.power, full.power * 0.6, "a flick is clearly weaker")
	assert_gt(flick.power, 0.0, "but it still does something — a dropped input reads as a bug")
	assert_almost_eq(full.power, _tuning.base_jump_impulse, 0.01, "a full press is the full jump")


func test_charge_scales_power_smoothly() -> void:
	var last: float = -1.0
	for step: int in range(6):
		var charge: float = float(step) / 5.0
		var outcome: JumpOutcome = JumpSolver.solve(_tuning, AT_SIX, Vector2.ZERO, 1, charge)
		assert_gt(outcome.power, last, "power rises at charge %.1f" % charge)
		last = outcome.power


func test_charge_changes_power_but_never_direction() -> void:
	# The clock decides where the jump goes; the press decides how hard. Keeping
	# them separate is what lets a player find one without the other.
	var soft: JumpOutcome = JumpSolver.solve(_tuning, AT_FOUR_THIRTY, Vector2.ZERO, 1, 0.1)
	var hard: JumpOutcome = JumpSolver.solve(_tuning, AT_FOUR_THIRTY, Vector2.ZERO, 1, 1.0)
	assert_almost_eq(soft.tilt_deg, hard.tilt_deg, 0.01, "same angle either way")
	assert_lt(soft.power, hard.power, "different strength")


func test_charge_is_clamped_to_a_full_press() -> void:
	var full: JumpOutcome = JumpSolver.solve(_tuning, AT_SIX, Vector2.ZERO, 1, 1.0)
	var overheld: JumpOutcome = JumpSolver.solve(_tuning, AT_SIX, Vector2.ZERO, 1, 9.0)
	assert_almost_eq(overheld.power, full.power, 0.01, "holding longer than max adds nothing")


func test_a_mistimed_flick_is_the_feeblest_thing_in_the_game() -> void:
	var worst: JumpOutcome = JumpSolver.solve(_tuning, AT_TWELVE, Vector2.ZERO, 1, 0.0)
	var best: JumpOutcome = JumpSolver.solve(_tuning, AT_FOUR_THIRTY, Vector2.ZERO, 1, 1.0)
	assert_lt(worst.power, best.power * 0.2, "wrong angle and no commitment gets you nothing")
