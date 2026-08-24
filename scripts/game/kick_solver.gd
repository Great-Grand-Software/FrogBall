class_name KickSolver
extends RefCounted

## The kick: the one mechanic this prototype now tests.
##
## Pure maths, no Node anywhere in it, so the feel can be unit-tested and
## iterated on without booting a scene.
##
## The player drags a thumb. The arrow points the way the thumb went, and the
## ball is thrown the OPPOSITE way — drag down and the arrow plants downward,
## shoving the ball up. That inversion is the whole reason the arrow reads as a
## thing pushing off the world rather than an aiming reticle.
##
## Drag LENGTH is power, so a short flick is a nudge and a long pull is a
## launch. Drag DIRECTION is aim, and the two are independent.
##
## Nothing here knows about the ground. A kick is legal in mid-air, against a
## wall, or anywhere else; whether the ball is ALLOWED one right now is a
## question of cooldown and air budget, which lives on the body.


## Resolves a drag into a new velocity. Allocates one KickOutcome; call
## [method solve_into] from anything running every frame.
static func solve(tuning: FrogTuning, drag: Vector2, velocity: Vector2) -> KickOutcome:
	return solve_into(KickOutcome.new(), tuning, drag, velocity)


## As [method solve], but writes into [param out] and returns it, so a caller
## holding one instance never allocates.
##
## [param drag] is the thumb's travel in VIEWPORT pixels, not world pixels: how
## far a thumb moved should mean the same thing whatever the camera is doing.
static func solve_into(
	out: KickOutcome, tuning: FrogTuning, drag: Vector2, velocity: Vector2
) -> KickOutcome:
	out.clear()
	out.velocity = velocity

	var length: float = drag.length()
	if length < maxf(tuning.aim_deadzone_px, 0.0):
		# A tap, or a twitch. Firing on these would make the ball leap every
		# time the player rested a thumb on the screen.
		out.too_short = true
		return out

	out.aim = drag / length
	out.power = clampf(length / maxf(tuning.max_drag_px, 1.0), 0.0, 1.0)
	var strength: float = tuning.kick_impulse * lerpf(
		clampf(tuning.min_kick_power, 0.0, 1.0), 1.0, out.power
	)

	# Thrown against the arrow: drag down, go up.
	var direction: Vector2 = -out.aim
	out.impulse = direction * strength
	out.fired = true
	out.velocity = apply(tuning, velocity, direction, strength)
	return out


## Folds an impulse into an existing velocity.
##
## By default the component of the current velocity FIGHTING the kick is
## cancelled first. Without that, a kick taken while already moving hard the
## other way is silently eaten and reads as a dropped input — the single most
## common complaint about air control in games that add it late.
static func apply(
	tuning: FrogTuning, velocity: Vector2, direction: Vector2, strength: float
) -> Vector2:
	var result := velocity
	if tuning.kick_cancels_opposing:
		var against: float = result.dot(direction)
		if against < 0.0:
			result -= direction * against
	return result + direction * strength
