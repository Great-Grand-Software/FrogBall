class_name FrogTuning
extends Resource

## Every dial that shapes how the frog rolls and how a tap resolves.
##
## None of these numbers are gospel. The prototype exists to find good values
## for them, so they live in a Resource — edit res://resources/frog_tuning.tres
## in the inspector and replay, without touching code or recompiling.
##
## The defaults are the reference points from the design brief: a 180 degree
## window across the bottom half, and a linear curve that puts a 45 degree
## launch at the halfway mark between 6 and 3 o'clock.

## What a tap does when the feet are outside the window, up in the top half.
## Either way it must read as a miss, never as a second way to play.
enum MistimedTap {
	NO_OP,      ## Swallowed. Nothing happens.
	WEAK_JUMP,  ## A feeble straight-up hop, so the miss is legible.
}

# --- rolling ---------------------------------------------------------------

## Physical radius of the frog, in pixels. This is the single most important
## dial in the file and it is not a cosmetic one: rolling without slipping ties
## spin to speed, so a small frog spins fast, and a frog spinning three times a
## second has a sweet spot that passes in less than one physics frame. At 72 the
## feet take about three quarters of a second to come round at cruise, which is
## a rhythm a player can actually read and tap against.
@export_range(4.0, 256.0, 1.0, "or_greater") var roll_radius: float = 72.0

## Pick a fresh radius at random for every run, between the two values below.
## Radius is the hardest dial in the game to guess at, because it trades spin
## rate against readability and both only show up in play. Rolling a new one
## each run turns "what number should this be" into something you feel over a
## dozen runs instead of something you argue about. Turn it off and pin
## [member roll_radius] once the range has told you where to sit.
@export var randomize_radius: bool = true

## Smallest radius a random run may roll, px. Below roughly 48 the frog spins
## faster than a player can read, and the jump window stops being tappable.
@export_range(4.0, 256.0, 1.0, "or_greater") var radius_min: float = 52.0

## Largest radius a random run may roll, px. A very large frog rolls over
## terrain that was meant to need a jump.
@export_range(4.0, 256.0, 1.0, "or_greater") var radius_max: float = 104.0

## Where the feet sit on the clock at the start of a run, in degrees, using the
## same convention as everything else: 0 is 6 o'clock, +90 is 3 o'clock. 45 puts
## the frog on 4:30 standing still, so the player's very first tap — before they
## know there is a window at all — is a good forward launch rather than a coin
## flip. First impressions are the one thing a no-tutorial prototype cannot
## afford to leave to chance.
@export_range(-90.0, 90.0, 1.0) var start_phase_deg: float = 45.0

## Multiplier on rolling without slipping (angular = linear / radius * this).
## 1.0 is physically honest; higher just looks spinnier at the same speed.
@export_range(0.0, 4.0, 0.01, "or_greater") var rotation_to_velocity_ratio: float = 1.0

## Keep the spin locked to horizontal velocity while airborne. Off means the
## frog holds whatever spin it left the ground with.
@export var air_spin_follows_velocity: bool = true

## Which way the frog rolls itself: 1 for rightward, -1 for leftward. This is a
## property of the run, NOT of which way the frog happens to be moving. Tying it
## to travel direction instead makes a frog that gets knocked backward drive
## itself further backward for ever, which is a dead run the player cannot
## recover from and never chose. The clock's "forward" still follows actual
## travel — only the self-drive is fixed.
@export_range(-1, 1, 2) var drive_direction: int = 1

## Automatic forward acceleration while grounded, px/s^2. This is the "the frog
## rolls itself" term and is NOT steerable — there is no input for it. Set it to
## 0 for a pure gravity roller, which then needs levels that always trend down.
@export_range(0.0, 2000.0, 10.0, "or_greater") var grounded_drive_accel: float = 380.0

## Rolling resistance while grounded, px/s^2, always opposing motion.
@export_range(0.0, 2000.0, 10.0, "or_greater") var roll_resistance: float = 90.0

## Terminal roll speed along the ground, px/s. Capped as much for readability
## as for difficulty — past this the spin outruns the player's timing.
@export_range(100.0, 4000.0, 10.0, "or_greater") var max_roll_speed: float = 950.0

## How fast speed above [member max_roll_speed] bleeds off, px/s^2. A very late
## jump can shove the frog past the cap; decaying it keeps the cap from reading
## as a wall the player slams into.
@export_range(0.0, 4000.0, 10.0, "or_greater") var overspeed_decay: float = 900.0

## Downward acceleration, px/s^2.
@export_range(100.0, 8000.0, 10.0, "or_greater") var gravity: float = 2200.0

## Terminal fall speed, px/s.
@export_range(100.0, 8000.0, 10.0, "or_greater") var max_fall_speed: float = 2600.0

## Below this speed the frog keeps its old facing rather than flipping, px/s.
@export_range(0.0, 400.0, 1.0, "or_greater") var facing_flip_deadzone: float = 25.0

# --- the jump window -------------------------------------------------------

## Total arc of the valid window, degrees, centred on 6 o'clock plus the offset
## below. 180 is the whole bottom half: 9 o'clock through 6 through 3.
@export_range(10.0, 360.0, 1.0) var window_arc_deg: float = 180.0

## Shifts the window off bottom-dead-centre. Positive rotates it toward 3.
@export_range(-90.0, 90.0, 1.0) var window_centre_offset_deg: float = 0.0

## Straight-up impulse for a perfectly neutral 6 o'clock tap, px/s, at full
## charge. A shorter press scales this down — see [member min_tap_power].
@export_range(100.0, 3000.0, 10.0, "or_greater") var base_jump_impulse: float = 900.0

# --- how long you hold ------------------------------------------------------
# The clock decides WHERE the jump goes. The press decides HOW HARD. They are
# deliberately separate: one is timing, the other is pressure, and a player can
# find one without the other.

## Hold time that counts as a full press, seconds. Anything longer adds nothing.
##
## Keep this SHORT. The remainder of the jump is fed in over this window, and a
## low forward arc can land before a slow ramp finishes — which silently eats
## most of the boost and flattens the whole skill gradient.
@export_range(0.05, 1.5, 0.01, "or_greater") var max_hold_sec: float = 0.15

## Power multiplier for the shortest possible tap. This is the floor of the
## charge ramp: a flick of the finger should be a hop, not a launch, but it must
## still visibly do something or the input reads as dropped.
@export_range(0.05, 1.0, 0.01) var min_tap_power: float = 0.55

## Shape of the charge ramp. 1.0 is linear. Above 1 makes a nearly-full press
## necessary for a full jump; below 1 makes most presses feel strong.
@export_range(0.2, 4.0, 0.05, "or_greater") var charge_curve_exponent: float = 1.0

# --- the forward half: 6 o'clock toward 3 ----------------------------------

## Launch tilt off vertical at the leading edge of the window. At the default 90
## with a linear curve, the halfway point lands on a 45 degree arc, as briefed.
## Note that 90 makes the very edge a flat horizontal shove with no lift, so
## over-timing costs you height — deliberate, but the first thing to try
## lowering (70-80) if the edge plays as a free speed exploit.
@export_range(0.0, 90.0, 1.0) var forward_max_tilt_deg: float = 90.0

## Shape of the forward half. 1.0 is linear. Above 1 pushes the payoff toward
## the 3 o'clock edge, making the boost tighter to hit and more of a reward.
@export_range(0.2, 4.0, 0.05, "or_greater") var forward_curve_exponent: float = 1.0

## Impulse multiplier at the leading edge. This is what makes a late tap a
## boosted launch rather than merely a carried one.
@export_range(1.0, 4.0, 0.05, "or_greater") var forward_boost_multiplier: float = 1.7

# --- the backward half: 6 o'clock toward 9 ---------------------------------

## Launch tilt off vertical at the trailing edge, before momentum eats it.
@export_range(0.0, 90.0, 1.0) var backward_max_tilt_deg: float = 90.0

## Shape of the backward half. 1.0 is linear.
@export_range(0.2, 4.0, 0.05, "or_greater") var backward_curve_exponent: float = 1.0

## Impulse multiplier at the trailing edge, before momentum eats it.
@export_range(0.5, 4.0, 0.05, "or_greater") var backward_boost_multiplier: float = 1.0

## Forward speed at which existing momentum COMPLETELY suppresses the backward
## tilt, collapsing a late tap into a near-vertical hop, px/s. Below it the
## backward launch bleeds back in. This is the dial that stops "tap near 9
## o'clock" from becoming a reliable reverse button.
@export_range(0.0, 2000.0, 10.0, "or_greater") var backward_dominance_speed: float = 420.0

## Shape of that suppression ramp. Above 1 keeps some backward launch until
## fairly fast; below 1 kills it the moment the frog is moving at all.
@export_range(0.2, 4.0, 0.05, "or_greater") var backward_dominance_exponent: float = 1.0

# --- tap policy ------------------------------------------------------------

## Carry existing horizontal velocity through the jump.
@export var preserve_horizontal_on_jump: bool = true

## Zero vertical velocity before applying the impulse.
@export var clear_vertical_on_jump: bool = true

## What a tap in the top half does.
@export var mistimed_tap: MistimedTap = MistimedTap.WEAK_JUMP

## Impulse multiplier for a mistimed tap, when it is not a no-op.
@export_range(0.0, 1.0, 0.01) var mistimed_jump_multiplier: float = 0.3

## Grace after leaving the ground during which a tap still counts, seconds.
@export_range(0.0, 0.5, 0.01, "or_greater") var coyote_time_sec: float = 0.1

## How long an early tap is remembered while falling, seconds.
@export_range(0.0, 0.5, 0.01, "or_greater") var jump_buffer_sec: float = 0.1

## Extra jumps before touching down again. 0 keeps the frog honest.
@export_range(0, 3, 1, "or_greater") var air_jumps_allowed: int = 0
