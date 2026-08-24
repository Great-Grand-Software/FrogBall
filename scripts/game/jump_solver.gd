class_name JumpSolver
extends RefCounted

## The clock-face jump: the one mechanic this prototype exists to test.
##
## Pure maths, no Node anywhere in it, so the feel can be unit-tested and
## iterated on without booting a scene.
##
## The clock is fixed to WORLD space, not to the frog:
## 12 o'clock is straight up, 3 is forward (the direction of travel), 6 is
## straight down (ground contact), 9 is backward. The feet marker rides around
## that clock as the body spins, at a rate tied to how fast the frog is rolling.
## Where the feet are at the instant of the tap is the entire input.
##
## The forward and backward halves are deliberately NOT mirror images. Forward
## of 6 the launch tilts and gains power. Backward of 6 the frog's existing
## momentum fights the tap and, past a threshold, wins outright — so a genuine
## reverse launch only happens to a frog that was barely moving.

## Half a turn, in degrees. Used to fold angles into [-180, 180).
const HALF_TURN_DEG: float = 180.0

## Slack on the window edge, degrees. The edge is inclusive, and without this a
## tap landing exactly on 3 o'clock is judged by float rounding — sometimes the
## strongest launch in the game, sometimes a whiff.
const WINDOW_EDGE_EPSILON_DEG: float = 0.001


## Where the feet sit on the world clock, in degrees: 0 at 6 o'clock, positive
## toward 3 o'clock (forward), negative toward 9 o'clock, +/-180 at 12 o'clock.
## [param facing] is 1 travelling right, -1 travelling left.
static func feet_phase_deg(body_rotation: float, facing: int) -> float:
	# The feet marker sits at the body's local "down", so at zero rotation it is
	# at 6 o'clock, touching the ground.
	var feet: Vector2 = Vector2.DOWN.rotated(body_rotation)
	var forward := Vector2(1.0 if facing >= 0 else -1.0, 0.0)
	return rad_to_deg(atan2(feet.dot(forward), feet.dot(Vector2.DOWN)))


## Turns a hold length, already normalised to 0..1, into a power multiplier
## running from [member FrogTuning.min_tap_power] at a flick to 1.0 at a full
## press. Separate from [method solve] so the frog can show a charge meter, and
## so the ramp can be tested on its own.
static func charge_multiplier(tuning: FrogTuning, charge: float) -> float:
	var shaped: float = pow(
		clampf(charge, 0.0, 1.0), maxf(tuning.charge_curve_exponent, 0.001)
	)
	return lerpf(clampf(tuning.min_tap_power, 0.0, 1.0), 1.0, shaped)


## Resolves a tap into a new velocity. Allocates one JumpOutcome; call
## [method solve_into] from anything running every frame.
##
## [param charge] is how long the player held the button, 0 for the shortest
## possible flick and 1 for a full press. It scales power only — where the jump
## goes is the clock's business, not the finger's.
static func solve(
	tuning: FrogTuning, body_rotation: float, velocity: Vector2, facing: int,
	charge: float = 1.0
) -> JumpOutcome:
	return solve_into(JumpOutcome.new(), tuning, body_rotation, velocity, facing, charge)


## As [method solve], but writes into [param out] and returns it, so a caller
## holding one instance never allocates.
static func solve_into(
	out: JumpOutcome, tuning: FrogTuning, body_rotation: float, velocity: Vector2,
	facing: int, charge: float = 1.0
) -> JumpOutcome:
	out.clear()
	var sign_facing: float = 1.0 if facing >= 0 else -1.0
	out.velocity = velocity
	out.phase_deg = feet_phase_deg(body_rotation, facing)
	out.charge = clampf(charge, 0.0, 1.0)
	var press: float = charge_multiplier(tuning, out.charge)

	var half_arc: float = maxf(tuning.window_arc_deg, 0.0) * 0.5
	var rel: float = _wrap_deg(out.phase_deg - tuning.window_centre_offset_deg)

	if absf(rel) > half_arc + WINDOW_EDGE_EPSILON_DEG:
		# Feet are up in the top half. This is a miss, and it has to feel like
		# one rather than like a second, cheaper way to jump.
		out.mistimed = true
		out.window_t = -1.0 if rel < 0.0 else 1.0
		if tuning.mistimed_tap == FrogTuning.MistimedTap.NO_OP:
			return out
		out.fired = true
		var whiff_full: float = tuning.base_jump_impulse * tuning.mistimed_jump_multiplier
		out.full_impulse = Vector2.UP * whiff_full
		out.power = whiff_full * press
		out.velocity = _apply_impulse(tuning, velocity, Vector2.UP * out.power)
		return out

	out.window_t = clampf(rel / half_arc, -1.0, 1.0) if half_arc > 0.001 else 0.0

	if out.window_t >= 0.0:
		# Forward half. The later the tap, the flatter and the stronger.
		var shaped: float = pow(out.window_t, maxf(tuning.forward_curve_exponent, 0.001))
		out.tilt_deg = shaped * tuning.forward_max_tilt_deg
		out.power = tuning.base_jump_impulse * lerpf(
			1.0, tuning.forward_boost_multiplier, shaped
		)
	else:
		# Backward half. Existing forward momentum blends against the backward
		# angle and, past backward_dominance_speed, cancels it entirely: the tap
		# collapses into a near-vertical hop instead of a reverse launch.
		var shaped: float = pow(-out.window_t, maxf(tuning.backward_curve_exponent, 0.001))
		var forward_speed: float = maxf(velocity.dot(Vector2(sign_facing, 0.0)), 0.0)
		var suppression: float = 0.0
		if tuning.backward_dominance_speed > 0.001:
			suppression = clampf(forward_speed / tuning.backward_dominance_speed, 0.0, 1.0)
			suppression = pow(suppression, maxf(tuning.backward_dominance_exponent, 0.001))
		out.backward_suppression = suppression

		var authority: float = 1.0 - suppression
		out.tilt_deg = -shaped * tuning.backward_max_tilt_deg * authority
		out.power = tuning.base_jump_impulse * lerpf(
			1.0, tuning.backward_boost_multiplier, shaped * authority
		)

	out.fired = true
	# Tilt is measured off straight up, rotated toward the direction of travel.
	var direction: Vector2 = Vector2.UP.rotated(deg_to_rad(out.tilt_deg * sign_facing))
	# out.power is the full-press strength up to here. Record the whole impulse
	# before scaling it down, so the frog can feed in the remainder while the
	# player keeps holding.
	out.full_impulse = direction * out.power
	out.power *= press
	out.velocity = _apply_impulse(tuning, velocity, direction * out.power)
	return out


static func _apply_impulse(tuning: FrogTuning, velocity: Vector2, impulse: Vector2) -> Vector2:
	var result := velocity
	if tuning.clear_vertical_on_jump:
		result.y = 0.0
	if not tuning.preserve_horizontal_on_jump:
		result.x = 0.0
	return result + impulse


## Folds an angle in degrees into [-180, 180).
static func _wrap_deg(degrees: float) -> float:
	return fposmod(degrees + HALF_TURN_DEG, 2.0 * HALF_TURN_DEG) - HALF_TURN_DEG
