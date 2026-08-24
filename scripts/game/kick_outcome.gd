class_name KickOutcome
extends RefCounted

## Everything one resolved kick produced.
##
## A plain object rather than a Dictionary so the fields are typed and the
## debug overlay can read them without string keys. The ball keeps one instance
## and rewrites it in place, so resolving a kick allocates nothing.

## False when the drag was too short to count — see FrogTuning.aim_deadzone_px.
var fired: bool = false

## True when the drag was inside the deadzone, i.e. a tap rather than a drag.
var too_short: bool = false

## Where the arrow points: the direction the thumb dragged, normalised. The ball
## is thrown the OTHER way, as if the arrow planted and shoved.
var aim: Vector2 = Vector2.ZERO

## Drag length as a fraction of max_drag_px, 0 to 1.
var power: float = 0.0

## The impulse applied, px/s. Opposite [member aim].
var impulse: Vector2 = Vector2.ZERO

## Velocity the body should adopt, px/s.
var velocity: Vector2 = Vector2.ZERO

## True when this kick was taken in mid-air rather than off a surface.
var airborne: bool = false


## Puts every field back to its default, so a reused instance can never leak a
## value from the previous kick.
func clear() -> void:
	fired = false
	too_short = false
	aim = Vector2.ZERO
	power = 0.0
	impulse = Vector2.ZERO
	velocity = Vector2.ZERO
	airborne = false
