class_name LevelTuning
extends Resource

## Shape of the level, in either mode.
##
## The run goes UP. Ledges are stacked in a narrow column with walls down both
## sides, and the only way to the next tier is a well-timed jump — a ledge you
## could walk onto teaches the player nothing.
##
## The vertical gap between tiers is the dial that decides whether the game is
## possible at all: it has to sit under the height a full press can clear, or
## the run dead-ends at the first ledge the frog cannot reach.

## Which kind of level to build.
##
## Both exist because they ask different things of the kick. CLIMB is about
## height and vertical aim in a confined column; ROLL is about carrying speed
## across gaps. The playtest wants both, so neither was deleted when the other
## was built.
enum Mode {
	CLIMB,  ## Up a walled shaft. Score is height.
	ROLL,   ## Rightward across gaps and ramps. Score is distance.
}

@export var mode: Mode = Mode.CLIMB

## 0 means "pick a fresh seed per run".
@export var seed_value: int = 0

## Inside width of the shaft, px. Narrow enough that both walls are on screen in
## a portrait frame, so the player can always see where the bounce will send it.
@export_range(200.0, 2000.0, 10.0, "or_greater") var shaft_width: float = 660.0

## Thickness of the drawn and collided side walls, px.
@export_range(10.0, 400.0, 5.0, "or_greater") var wall_thickness: float = 60.0

## Height of the wall colliders kept around the frog, px. They are repositioned
## rather than extended, so an endless climb cannot grow the scene.
@export_range(1000.0, 20000.0, 100.0, "or_greater") var wall_span: float = 4000.0

## Width of the solid floor the run starts on, as a fraction of the shaft.
@export_range(0.2, 1.0, 0.05) var floor_width_ratio: float = 1.0

## Keep ledges generated this far above the frog, px.
##
## Bounded from above by the ring buffer: this plus the on-screen height must
## stay inside MAX_SEGMENTS worth of rises, or the oldest ledge is recycled
## while the frog is still standing on it.
@export_range(200.0, 8000.0, 50.0, "or_greater") var generate_above: float = 900.0

## Thickness of a ledge, px. Also how far its collision extends downward.
@export_range(10.0, 300.0, 5.0, "or_greater") var ledge_thickness: float = 34.0

# --- the climb -------------------------------------------------------------

## Vertical rise between one ledge and the next, px.
##
## Squeezed between two hard limits, and getting either wrong breaks the game
## outright rather than making it feel bad:
##
##  - It MUST exceed the ball's DIAMETER **plus ledge_thickness**, not just its
##    radius. The gap a ball has to pass through is the rise minus the slab
##    hanging below the ledge above it. Get this wrong and the ball scrapes the
##    tier above and never gets airborne — which presents as jumps that barely
##    leave the ground, not as anything to do with size. With radius_max 104 and
##    a 34px slab that is 208 + 34 = 242px before any margin at all.
##  - It MUST stay under the apex of a full-power jump, or the tier simply
##    cannot be reached and the run dead-ends for reasons the player cannot see.
##
## So rises and base_jump_impulse move together. Change one, check the other.
@export_range(30.0, 800.0, 5.0, "or_greater") var rise_min: float = 300.0
@export_range(30.0, 800.0, 5.0, "or_greater") var rise_max: float = 345.0

## Ledge width, px.
##
## Bounded from ABOVE, which is the counter-intuitive part. A ledge sitting
## directly over the ball is a ceiling: a straight-up jump slams into its
## underside and the climb stops. The shaft has to keep a corridor at least a
## ball wide open beside every tier, so ledge width plus the ball's diameter has
## to stay inside the shaft. Widening these to make landing easier makes the
## climb IMPOSSIBLE instead — measured, not guessed.
@export_range(60.0, 1600.0, 10.0, "or_greater") var ledge_min_width: float = 220.0
@export_range(60.0, 1600.0, 10.0, "or_greater") var ledge_max_width: float = 330.0

## How far across the shaft consecutive ledges are allowed to jump, as a
## fraction of the shaft width.
##
## Squeezed from both sides. Too small and consecutive tiers stack into a
## ceiling the ball cannot rise past; too large and the sideways reach exceeds
## what a jump actually drifts (roll speed times flight time), which the player
## cannot make up because there is no steering. It wants to sit just past
## half a ledge plus a ball radius.
@export_range(0.05, 1.0, 0.05) var max_lateral_step: float = 0.42

## Chance a ledge is placed on the opposite side of the shaft from the last one,
## rather than near it. Alternating is what makes the climb a zig-zag instead of
## a straight ladder.
@export_range(0.0, 1.0, 0.05) var alternate_chance: float = 0.85

# --- ROLL mode -------------------------------------------------------------
# Only read when mode is ROLL. The ball runs rightward over flats, ramps and
# gaps; the kick is what clears the gaps and rescues a bad landing.

## Flat, safe runway ahead of the spawn point, px.
@export_range(200.0, 4000.0, 10.0, "or_greater") var roll_start_runway: float = 900.0

## Keep terrain built this far ahead of the ball, px.
@export_range(500.0, 10000.0, 50.0, "or_greater") var roll_generate_ahead: float = 2200.0

## How far the surface may wander above or below the spawn height, px.
@export_range(100.0, 4000.0, 10.0, "or_greater") var roll_drift_limit: float = 900.0

## Length of a flat or ramped span, px.
@export_range(50.0, 3000.0, 10.0, "or_greater") var roll_span_min: float = 300.0
@export_range(50.0, 3000.0, 10.0, "or_greater") var roll_span_max: float = 640.0

## Slope of a ramp, degrees. Positive is downhill, and the sign is chosen per
## span to keep the surface inside the drift limit.
@export_range(0.0, 50.0, 0.5, "or_greater") var roll_slope_max: float = 24.0

## Chance a span is a ramp rather than a flat.
@export_range(0.0, 1.0, 0.05) var roll_ramp_chance: float = 0.45

## Gap width that must be cleared, px. Bounded above by what a kick can carry
## the ball across from a standing roll — a gap wider than that is a dead end.
@export_range(50.0, 2000.0, 10.0, "or_greater") var roll_gap_min: float = 180.0
@export_range(50.0, 2000.0, 10.0, "or_greater") var roll_gap_max: float = 420.0

## Chance a span is preceded by a gap.
@export_range(0.0, 1.0, 0.05) var roll_gap_chance: float = 0.55

## Height change across a gap, px.
@export_range(0.0, 600.0, 5.0, "or_greater") var roll_step_max: float = 150.0

## How far below the surface the run ends, px.
@export_range(100.0, 4000.0, 10.0, "or_greater") var roll_fall_tolerance: float = 800.0
