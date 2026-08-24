class_name FrogTuning
extends Resource

## Every dial that shapes how the ball rolls and how a kick resolves.
##
## None of these numbers are gospel. The prototype exists to find good values
## for them, so they live in a Resource — edit res://resources/frog_tuning.tres
## in the inspector and replay, without touching code or recompiling.
##
## The input is a DRAG, not a tap: direction aims, length powers, and the ball
## is thrown opposite the arrow. Kicks are legal anywhere — mid-air, off a wall
## — so the dials that decide whether this is a game rather than a flight
## simulator are the cooldown and the air budget, not the impulse.

# --- rolling ---------------------------------------------------------------

## Physical radius of the ball, in pixels. Now that aim comes from the thumb
## rather than from the body's rotation, this no longer gates whether the
## mechanic is usable — but it still sets how big a target the ball is, how
## wide a gap it fits through, and how fast it appears to spin.
@export_range(4.0, 256.0, 1.0, "or_greater") var roll_radius: float = 72.0

## Pick a fresh radius at random for every run, between the two values below.
## Radius is the hardest dial in the game to guess at, because it trades spin
## rate against readability and both only show up in play. Rolling a new one
## each run turns "what number should this be" into something you feel over a
## dozen runs instead of something you argue about. Turn it off and pin
## [member roll_radius] once the range has told you where to sit.
@export var randomize_radius: bool = true

## Smallest radius a random run may roll, px.
@export_range(4.0, 256.0, 1.0, "or_greater") var radius_min: float = 52.0

## Largest radius a random run may roll, px. A very large ball rolls over
## terrain that was meant to need a kick, and struggles to fit between tiers.
@export_range(4.0, 256.0, 1.0, "or_greater") var radius_max: float = 104.0

## Multiplier on rolling without slipping (angular = linear / radius * this).
## 1.0 is physically honest; higher just looks spinnier at the same speed.
@export_range(0.0, 4.0, 0.01, "or_greater") var rotation_to_velocity_ratio: float = 1.0

## Keep the spin locked to horizontal velocity while airborne. Purely cosmetic
## now: nothing reads the body's rotation any more.
@export var air_spin_follows_velocity: bool = true

## Which way the ball rolls itself: 1 for rightward, -1 for leftward. This is a
## property of the run, NOT of which way the ball happens to be moving. Tying it
## to travel direction instead makes a ball knocked backward drive itself
## further backward for ever — a dead run the player never chose. Only a wall
## may reverse it.
@export_range(-1, 1, 2) var drive_direction: int = 1

## Automatic forward acceleration while grounded, px/s^2. The ball rolls itself;
## the player steers with kicks rather than by driving it. Set to 0 for a pure
## gravity roller.
@export_range(0.0, 2000.0, 10.0, "or_greater") var grounded_drive_accel: float = 280.0

## Rolling resistance while grounded, px/s^2, always opposing motion.
@export_range(0.0, 2000.0, 10.0, "or_greater") var roll_resistance: float = 90.0

## Terminal roll speed along the ground, px/s.
##
## Kept low for the climb, and not for difficulty: horizontal velocity carries
## through a launch, so a fast ball crosses the whole shaft mid-air and hits the
## far wall instead of the tier it was aimed at. Roll speed and shaft width are
## coupled — widen one and this has to move too.
@export_range(100.0, 4000.0, 10.0, "or_greater") var max_roll_speed: float = 400.0

## How fast speed above [member max_roll_speed] bleeds off, px/s^2. A hard kick
## shoves the ball past the cap; decaying it keeps the cap from reading as a
## wall the player slams into.
@export_range(0.0, 4000.0, 10.0, "or_greater") var overspeed_decay: float = 900.0

## Downward acceleration, px/s^2.
@export_range(100.0, 8000.0, 10.0, "or_greater") var gravity: float = 2200.0

## Terminal fall speed, px/s.
@export_range(100.0, 8000.0, 10.0, "or_greater") var max_fall_speed: float = 2600.0

## Below this speed the ball keeps its old facing rather than flipping, px/s.
@export_range(0.0, 400.0, 1.0, "or_greater") var facing_flip_deadzone: float = 25.0

# --- the kick --------------------------------------------------------------
# Drag direction aims, drag length powers, and the ball is thrown OPPOSITE the
# arrow. Drag down, the arrow plants downward, the ball goes up.

## Impulse a full-length drag delivers, px/s.
@export_range(100.0, 4000.0, 10.0, "or_greater") var kick_impulse: float = 1250.0

## Drag length that counts as full power, in VIEWPORT pixels. Thumb travel
## should mean the same thing whatever the camera is doing, so this is measured
## on the screen and not in the world.
@export_range(20.0, 1000.0, 5.0, "or_greater") var max_drag_px: float = 220.0

## Drags shorter than this do nothing at all, in viewport pixels. Without a
## deadzone the ball leaps every time a thumb rests on the screen.
@export_range(0.0, 200.0, 1.0, "or_greater") var aim_deadzone_px: float = 18.0

## Power floor for the shortest drag that still counts. A nudge should be a
## nudge, but it has to visibly do something or the input reads as dropped.
@export_range(0.05, 1.0, 0.01) var min_kick_power: float = 0.35

## Cancel the part of the current velocity fighting the kick before applying it.
## Off, a kick taken while moving hard the other way is silently eaten.
@export var kick_cancels_opposing: bool = true

# --- what stops this being a flight simulator ------------------------------
# Kicks work in mid-air by design. These two dials are the entire difficulty
# budget: with a short cooldown and unlimited air kicks the ball simply flies,
# and no level can be a challenge. Tighten them from play.

## Minimum time between kicks, seconds.
@export_range(0.0, 2.0, 0.01, "or_greater") var kick_cooldown_sec: float = 0.22

## Kicks allowed before touching a surface again. -1 is unlimited, which is the
## most permissive reading of "kick in any direction, anywhere" and almost
## certainly too generous once anyone plays it.
@export_range(-1, 10, 1, "or_greater") var air_kicks_allowed: int = -1
