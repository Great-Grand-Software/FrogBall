class_name JumpOutcome
extends RefCounted

## Everything one resolved tap produced.
##
## A plain object rather than a Dictionary so the fields are typed and the
## debug overlay can read them without string keys. The frog keeps one instance
## and rewrites it in place, so resolving a tap allocates nothing.

## False when the tap was swallowed whole — mistimed, under the no-op policy.
var fired: bool = false

## True when the feet were outside the window at the moment of the tap.
var mistimed: bool = false

## Velocity the body should adopt, px/s.
var velocity: Vector2 = Vector2.ZERO

## Where the feet sat on the world clock, degrees. 0 is 6 o'clock, +90 is 3
## o'clock (forward), -90 is 9 o'clock (backward), +/-180 is 12 o'clock.
var phase_deg: float = 0.0

## Position within the window: -1 trailing edge, 0 centre, +1 leading edge.
var window_t: float = 0.0

## Launch tilt off vertical, signed toward the direction of travel, degrees.
var tilt_deg: float = 0.0

## Impulse magnitude actually applied, px/s.
var power: float = 0.0

## How much forward momentum ate a backward-angled tap, 0 to 1.
var backward_suppression: float = 0.0


## Puts every field back to its default. Called before each solve so a reused
## instance can never leak a value from the previous tap.
func clear() -> void:
	fired = false
	mistimed = false
	velocity = Vector2.ZERO
	phase_deg = 0.0
	window_t = 0.0
	tilt_deg = 0.0
	power = 0.0
	backward_suppression = 0.0
