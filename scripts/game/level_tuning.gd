class_name LevelTuning
extends Resource

## Shape of the endless terrain.
##
## The generation goal is a sequence that rewards chaining: roll down a slope to
## build speed, tap at the right rotation to launch up and over a ledge, land
## rolling, and immediately build into the next timed jump. Gaps and tiers are
## meant to need a jump — a walkable connection teaches the player nothing.

## Flat, safe runway ahead of the spawn point, px. Long enough that the first
## thing a player meets is a roll, not a hole.
@export_range(200.0, 4000.0, 10.0, "or_greater") var start_runway_length: float = 900.0

## Runway behind the spawn point, px. Cheap insurance: the first tap a player
## makes is usually mistimed, and a backward hop off the lip of the world is a
## death they cannot learn anything from.
@export_range(0.0, 2000.0, 10.0, "or_greater") var start_runway_behind: float = 420.0

## Keep terrain built this far ahead of the frog, px.
@export_range(500.0, 10000.0, 50.0, "or_greater") var generate_ahead: float = 3200.0

## How far the surface may wander above or below the spawn height, px. Keeps an
## endless run from drifting off into the sky or the basement.
@export_range(100.0, 4000.0, 10.0, "or_greater") var vertical_drift_limit: float = 1100.0

## Thickness of the ground slab drawn and collided below the surface line, px.
@export_range(20.0, 2000.0, 10.0, "or_greater") var ground_thickness: float = 480.0

# --- segment mix -----------------------------------------------------------
# Relative weights. Zero one out to remove that flavour entirely.

@export_range(0.0, 10.0, 0.1, "or_greater") var weight_flat: float = 1.0
@export_range(0.0, 10.0, 0.1, "or_greater") var weight_downhill: float = 2.0
@export_range(0.0, 10.0, 0.1, "or_greater") var weight_uphill: float = 1.2
@export_range(0.0, 10.0, 0.1, "or_greater") var weight_gap_step: float = 2.4
@export_range(0.0, 10.0, 0.1, "or_greater") var weight_stairs: float = 1.6

# --- segment sizing --------------------------------------------------------

@export_range(50.0, 3000.0, 10.0, "or_greater") var flat_min_length: float = 260.0
@export_range(50.0, 3000.0, 10.0, "or_greater") var flat_max_length: float = 620.0

@export_range(50.0, 3000.0, 10.0, "or_greater") var ramp_min_length: float = 320.0
@export_range(50.0, 3000.0, 10.0, "or_greater") var ramp_max_length: float = 780.0

@export_range(1.0, 60.0, 0.5, "or_greater") var downhill_min_slope_deg: float = 10.0
@export_range(1.0, 60.0, 0.5, "or_greater") var downhill_max_slope_deg: float = 32.0

@export_range(1.0, 60.0, 0.5, "or_greater") var uphill_min_slope_deg: float = 8.0
@export_range(1.0, 60.0, 0.5, "or_greater") var uphill_max_slope_deg: float = 24.0

## Gaps that must be cleared with a jump, px.
@export_range(50.0, 3000.0, 10.0, "or_greater") var gap_min_width: float = 240.0
@export_range(50.0, 3000.0, 10.0, "or_greater") var gap_max_width: float = 620.0

## Height change across a gap, px.
@export_range(0.0, 800.0, 5.0, "or_greater") var step_min_rise: float = 40.0
@export_range(0.0, 800.0, 5.0, "or_greater") var step_max_rise: float = 190.0

## Chance a gap steps up rather than down, before drift correction.
@export_range(0.0, 1.0, 0.01) var step_up_chance: float = 0.5

# --- laddered tiers --------------------------------------------------------

@export_range(2, 8, 1, "or_greater") var stair_min_count: int = 2
@export_range(2, 8, 1, "or_greater") var stair_max_count: int = 4
@export_range(40.0, 1200.0, 10.0, "or_greater") var stair_tread_min: float = 150.0
@export_range(40.0, 1200.0, 10.0, "or_greater") var stair_tread_max: float = 300.0
@export_range(0.0, 1200.0, 10.0, "or_greater") var stair_gap_min: float = 90.0
@export_range(0.0, 1200.0, 10.0, "or_greater") var stair_gap_max: float = 220.0
@export_range(10.0, 500.0, 5.0, "or_greater") var stair_rise_min: float = 55.0
@export_range(10.0, 500.0, 5.0, "or_greater") var stair_rise_max: float = 130.0
