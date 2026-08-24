extends GutTest

## Tests for KickSolver, the whole input mechanic.
##
## The property worth pinning hardest is the INVERSION: the ball goes the
## opposite way to the drag. Get that backwards and the game is unplayable in a
## way no other test would catch, because every individual number still looks
## reasonable.

var _tuning: FrogTuning


func before_each() -> void:
	_tuning = FrogTuning.new()


func _full_drag(direction: Vector2) -> Vector2:
	return direction.normalized() * _tuning.max_drag_px


func test_dragging_down_throws_the_ball_up() -> void:
	# The headline behaviour, stated in the brief in exactly these words.
	var out: KickOutcome = KickSolver.solve(_tuning, _full_drag(Vector2.DOWN), Vector2.ZERO)
	assert_true(out.fired, "a full drag fires")
	assert_lt(out.velocity.y, 0.0, "down-drag sends it upward")
	assert_almost_eq(out.velocity.x, 0.0, 0.01, "and straight, with no sideways bias")


func test_the_arrow_points_the_way_the_thumb_went() -> void:
	var out: KickOutcome = KickSolver.solve(_tuning, _full_drag(Vector2.DOWN), Vector2.ZERO)
	assert_almost_eq(out.aim.y, 1.0, 0.01, "the arrow points down, where the thumb went")
	assert_lt(out.impulse.y, 0.0, "while the shove goes the other way")


func test_every_direction_kicks_the_opposite_way() -> void:
	for angle: float in [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]:
		var direction: Vector2 = Vector2.RIGHT.rotated(deg_to_rad(angle))
		var out: KickOutcome = KickSolver.solve(_tuning, _full_drag(direction), Vector2.ZERO)
		var got: Vector2 = out.velocity.normalized()
		assert_almost_eq(got.dot(-direction), 1.0, 0.01, "opposite at %.0f deg" % angle)


func test_longer_drags_kick_harder() -> void:
	var last: float = -1.0
	for fraction: float in [0.2, 0.4, 0.6, 0.8, 1.0]:
		var drag: Vector2 = Vector2.DOWN * (_tuning.max_drag_px * fraction)
		var out: KickOutcome = KickSolver.solve(_tuning, drag, Vector2.ZERO)
		assert_gt(out.impulse.length(), last, "power rises at %.0f%%" % (fraction * 100.0))
		last = out.impulse.length()


func test_power_is_clamped_at_a_full_pull() -> void:
	var full: KickOutcome = KickSolver.solve(_tuning, Vector2.DOWN * _tuning.max_drag_px, Vector2.ZERO)
	var over: KickOutcome = KickSolver.solve(_tuning, Vector2.DOWN * 9000.0, Vector2.ZERO)
	assert_almost_eq(over.impulse.length(), full.impulse.length(), 0.01, "no reward for a huge swipe")
	assert_almost_eq(over.power, 1.0, 0.001, "power saturates at 1")


func test_a_twitch_does_nothing() -> void:
	# Without a deadzone the ball leaps every time a thumb rests on the screen.
	var out: KickOutcome = KickSolver.solve(
		_tuning, Vector2.DOWN * (_tuning.aim_deadzone_px * 0.5), Vector2.ZERO
	)
	assert_false(out.fired, "inside the deadzone nothing fires")
	assert_true(out.too_short, "and it is reported as too short, not as a miss")
	assert_eq(out.velocity, Vector2.ZERO, "velocity untouched")


func test_the_shortest_real_drag_still_does_something() -> void:
	var drag: Vector2 = Vector2.DOWN * (_tuning.aim_deadzone_px + 1.0)
	var out: KickOutcome = KickSolver.solve(_tuning, drag, Vector2.ZERO)
	assert_true(out.fired, "just past the deadzone fires")
	assert_gt(out.impulse.length(), 0.0, "a dropped input would read as a bug")


func test_a_kick_beats_the_momentum_it_is_fighting() -> void:
	# A kick taken while moving hard the other way must not be silently eaten —
	# that is the classic complaint about air control bolted on late.
	var falling := Vector2(0.0, 1800.0)
	var out: KickOutcome = KickSolver.solve(_tuning, _full_drag(Vector2.DOWN), falling)
	assert_lt(out.velocity.y, 0.0, "a hard fall is reversed, not merely slowed")


func test_opposing_cancellation_can_be_turned_off() -> void:
	_tuning.kick_cancels_opposing = false
	var falling := Vector2(0.0, 1800.0)
	var out: KickOutcome = KickSolver.solve(_tuning, _full_drag(Vector2.DOWN), falling)
	assert_almost_eq(
		out.velocity.y, falling.y - _tuning.kick_impulse, 1.0, "pure addition when off"
	)


func test_a_kick_along_the_current_travel_adds_to_it() -> void:
	# Only the OPPOSING component is cancelled; a kick that agrees with the
	# ball's motion should still accelerate it.
	var rising := Vector2(0.0, -400.0)
	var out: KickOutcome = KickSolver.solve(_tuning, _full_drag(Vector2.DOWN), rising)
	assert_lt(out.velocity.y, rising.y, "faster than it already was")
