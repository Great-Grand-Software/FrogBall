class_name FrogBody
extends RigidBody2D

## The frog: a wheel with a face on one side and feet on the other.
##
## Rolling is automatic and momentum-driven. There is no steering input and no
## speed input — the only thing the player can do is tap, and the only thing a
## tap does is ask [JumpSolver] what the current rotation is worth.
##
## Spin is locked to horizontal velocity (rolling without slipping) rather than
## left to friction, because the whole mechanic depends on the feet marker and
## the velocity never disagreeing. Physics friction is zeroed for the same
## reason: it would fight the spin we impose.

## Emitted after a tap resolves, including a mistimed one, so the screen can
## react without polling. The outcome is reused — read it, do not store it.
signal jumped(outcome: JumpOutcome)

## Emitted on the frame the frog touches down after being airborne.
signal landed

## Emitted when the frog turns around against the side of the shaft.
signal bounced

## A contact counts as ground when its normal is this close to vertical.
## Filters out the side of a step riser, which is a wall, not a floor.
const GROUND_NORMAL_Y: float = -0.5

## A contact counts as wall when its normal is this close to horizontal. Set
## high on purpose: the corner of a ledge produces a diagonal normal, and
## treating those as walls flips the frog's drive while it is simply rolling.
const WALL_NORMAL_X: float = 0.9

## How long after a bounce the frog ignores further wall contacts, seconds.
## Without it a frog resting against a wall flips direction every frame.
const BOUNCE_COOLDOWN_SEC: float = 0.12

## Contacts to look at per frame. A heightfield surface never needs many.
const CONTACTS_REPORTED: int = 8

## Gap left between the frog and the surface when it is placed, px. Just enough
## that the physics step does not start by resolving an overlap.
const GROUND_CLEARANCE: float = 2.0

## Where the arrow sits at rest, as a fraction of the radius. 1.0 is the rim.
const ARROW_REST_RATIO: float = 0.96

## Where the arrow's tail starts, as a fraction of the radius.
const ARROW_TAIL_RATIO: float = 0.08

## Arrow head length, as a fraction of the radius.
const ARROW_HEAD_RATIO: float = 0.38

## Arrow shaft width, as a fraction of the radius.
const ARROW_WIDTH_RATIO: float = 0.1

@export var tuning: FrogTuning

## Which way the frog considers "forward". 1 is right, -1 is left.
var facing: int = 1

## True while touching something that reads as floor.
var grounded: bool = false

var _outcome: JumpOutcome = JumpOutcome.new()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _radius: float = 1.0
var _circle: CircleShape2D = CircleShape2D.new()
var _holding: bool = false
var _held_for: float = 0.0
var _thrusting: bool = false
var _arrow_push: float = 0.0
var _drive_dir: int = 1
var _bounce_cooldown: float = 0.0
var _head: PackedVector2Array = PackedVector2Array()
var _thrust_impulse: Vector2 = Vector2.ZERO
var _thrust_applied: float = 0.0
var _coyote_timer: float = 0.0
var _buffer_timer: float = 0.0
var _air_jumps_used: int = 0
var _tap_pending: bool = false
var _was_grounded: bool = false
var _teleport_pending: bool = false
var _teleport_to: Vector2 = Vector2.ZERO

@onready var _shape: CollisionShape2D = %Shape


func _ready() -> void:
	if tuning == null:
		tuning = FrogTuning.new()

	# Contacts are how we know we are on the ground; nothing else reports it.
	contact_monitor = true
	max_contacts_reported = CONTACTS_REPORTED
	can_sleep = false

	_rng.randomize()
	_head.resize(3)
	_drive_dir = 1 if tuning.drive_direction >= 0 else -1
	_shape.shape = _circle
	_apply_radius()

	# Zero friction and bounce: spin is imposed directly, so surface friction
	# would only fight it, and a bouncy frog makes landings unreadable.
	var material := PhysicsMaterial.new()
	material.friction = 0.0
	material.bounce = 0.0
	physics_material_override = material

	var default_gravity: float = ProjectSettings.get_setting(
		"physics/2d/default_gravity", 980.0
	)
	gravity_scale = tuning.gravity / maxf(default_gravity, 1.0)


func _draw() -> void:
	# A circle and one arrow, nothing else. The arrow lies along the body's local
	# "down", which is the axis the whole game is timed against: wherever the
	# arrow points is where the push will come from. Keeping the body featureless
	# means there is exactly one thing to read while it spins.
	var radius: float = _radius
	var ink := Color(0.94, 0.94, 0.92)
	draw_circle(Vector2.ZERO, radius, Color(0.14, 0.17, 0.15))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, ink, 3.0)
	_draw_arrow(radius, ink)


## The arrow, drawn along local down and extending past the rim as it fires.
##
## At rest it stops at the rim. On a jump it shoots out — planting itself into
## the ground and shoving the body off it — and stays out for as long as the
## player keeps holding, which is exactly as long as power is still feeding in.
## So the arrow is not decoration: its direction is the aim and its length is
## the commitment, the two halves of the only input in the game.
func _draw_arrow(radius: float, ink: Color) -> void:
	var reach: float = radius * (ARROW_REST_RATIO + _arrow_push * tuning.arrow_extend_ratio)
	var width: float = maxf(radius * ARROW_WIDTH_RATIO, 2.0)
	var head_length: float = radius * ARROW_HEAD_RATIO
	var head_half: float = radius * ARROW_HEAD_RATIO * 0.62

	# Local down is +y, and the body's own rotation carries the arrow round the
	# clock for free.
	var tip: Vector2 = Vector2.DOWN * reach
	var neck: Vector2 = Vector2.DOWN * maxf(reach - head_length, 0.0)
	draw_line(Vector2.DOWN * (radius * ARROW_TAIL_RATIO), neck, ink, width)

	# Head as a filled triangle, into a buffer allocated once, so an animating
	# arrow never allocates per frame.
	_head[0] = tip
	_head[1] = neck + Vector2.RIGHT * head_half
	_head[2] = neck + Vector2.LEFT * head_half
	draw_colored_polygon(_head, ink)


## Retracts the arrow after a jump.
##
## Held out at full reach for as long as thrust is still feeding in, so the
## arrow stays planted exactly while the press is still doing something, then
## springs back. Runs on the render clock rather than the physics one because
## it is purely cosmetic.
func _process(delta: float) -> void:
	if _thrusting:
		_arrow_push = 1.0
	elif _arrow_push > 0.0:
		_arrow_push = maxf(_arrow_push - delta / maxf(tuning.arrow_recoil_sec, 0.01), 0.0)
	else:
		return
	queue_redraw()


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _teleport_pending:
		_teleport_pending = false
		# Start on the clock angle from tuning, so the first tap of a run is a
		# good forward launch instead of whatever the frog happened to land on.
		state.transform = Transform2D(deg_to_rad(-tuning.start_phase_deg), _teleport_to)
		state.linear_velocity = Vector2.ZERO
		state.angular_velocity = 0.0
		return

	var delta: float = state.step
	var velocity: Vector2 = state.linear_velocity
	_bounce_cooldown = maxf(_bounce_cooldown - delta, 0.0)
	var normal: Vector2 = _read_ground(state)

	if grounded:
		_coyote_timer = tuning.coyote_time_sec
		_air_jumps_used = 0
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	if grounded:
		velocity = _apply_rolling(velocity, normal, delta)
	velocity.y = minf(velocity.y, tuning.max_fall_speed)

	if _holding:
		_held_for += delta
	velocity = _apply_tap(state, velocity, delta)
	velocity = _apply_thrust(velocity)

	if absf(velocity.x) > tuning.facing_flip_deadzone:
		facing = 1 if velocity.x > 0.0 else -1

	if grounded or tuning.air_spin_follows_velocity:
		state.angular_velocity = velocity.x / _radius * tuning.rotation_to_velocity_ratio

	state.linear_velocity = velocity

	if grounded and not _was_grounded:
		# Back on the ground: whatever was left of the press is spent.
		_thrusting = false
		landed.emit()
	_was_grounded = grounded


## The player pressed. The frog leaves the ground on THIS input, at the angle
## the clock is showing right now — no charge-up delay, because the whole game
## is aiming at a rotation you can see, and a jump that resolved on release
## would fire at an angle the frog had already spun past.
func begin_tap() -> void:
	_holding = true
	_held_for = 0.0
	_tap_pending = true


## The player let go. Cuts the thrust wherever it got to, which is what makes a
## flick a hop and a held press a full jump.
func release_tap() -> void:
	_holding = false
	_thrusting = false


## Seeds the radius roll. 0 keeps it genuinely random per run; any other value
## makes a pinned course give a pinned frog too, so a tuning comparison changes
## one thing at a time.
func set_run_seed(seed_value: int) -> void:
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value


## Fires a jump and holds it to full power, with no separate release. For tests
## and tools that only care about the jump, not about the press.
func queue_tap() -> void:
	_holding = true
	_held_for = 0.0
	_tap_pending = true


## How far the current press has charged, 0 to 1. Debug overlay reads this.
func charge() -> float:
	if not _holding:
		return 0.0
	return clampf(_held_for / maxf(tuning.max_hold_sec, 0.001), 0.0, 1.0)


## How far the arrow is currently shot out, 0 at rest and 1 fully planted.
## Exposed so the visual can be asserted, since a silent jump is a real defect.
func arrow_push() -> float:
	return _arrow_push


## Which way the self-drive currently points, 1 right and -1 left. Flipped only
## by the shaft walls. Exposed for diagnostics.
func drive_direction() -> int:
	return _drive_dir


## Radius this run rolled, px.
func radius() -> float:
	return _radius


## Drops the frog onto [param ground_point], a point on the terrain surface.
## Rolls a new radius first, then sits the body exactly on top of it. The move
## itself lands on the next physics step, the only safe place to shift a rigid
## body, but the radius applies immediately so callers can read it.
func reset_to(ground_point: Vector2) -> void:
	_apply_radius()
	_teleport_to = ground_point - Vector2(0.0, _radius + GROUND_CLEARANCE)
	_teleport_pending = true
	_holding = false
	_held_for = 0.0
	_thrusting = false
	_thrust_applied = 0.0
	_arrow_push = 0.0
	_coyote_timer = 0.0
	_buffer_timer = 0.0
	_air_jumps_used = 0
	_tap_pending = false
	_was_grounded = false
	grounded = false
	facing = 1
	_bounce_cooldown = 0.0
	_drive_dir = 1 if tuning.drive_direction >= 0 else -1


## Where the feet currently sit on the world clock, in degrees. Debug overlay
## reads this; nothing the player sees does.
func feet_phase_deg() -> float:
	return JumpSolver.feet_phase_deg(rotation, facing)


## Sets [member grounded] from this step's contacts and returns the floor
## normal, pointing up.
func _read_ground(state: PhysicsDirectBodyState2D) -> Vector2:
	grounded = false
	var normal := Vector2.UP
	var velocity_x: float = state.linear_velocity.x
	for index: int in range(state.get_contact_count()):
		var candidate: Vector2 = state.get_contact_local_normal(index)
		# Reported normals can face either way depending on which body is
		# which, so each case flips them to a known direction before judging.
		if absf(candidate.x) > WALL_NORMAL_X:
			_bounce_off_wall(candidate, velocity_x)
			continue
		var upward: Vector2 = -candidate if candidate.y > 0.0 else candidate
		if upward.y < GROUND_NORMAL_Y and not grounded:
			grounded = true
			normal = upward
	return normal


## Turns the frog around when it runs into the side of the shaft.
##
## Climbing needs the frog to stay inside a column narrow enough to see, so a
## wall reverses the self-drive rather than stopping it dead. The reversal is
## driven by the wall, never by the frog's own velocity — the same rule that
## keeps a mistimed hop from sending a run backwards for ever.
func _bounce_off_wall(contact_normal: Vector2, velocity_x: float) -> void:
	if _bounce_cooldown > 0.0 or absf(velocity_x) < 1.0:
		return
	# The useful normal is the one pointing away from the wall, which is the one
	# opposing the direction the frog was travelling when it hit.
	var away: Vector2 = contact_normal if contact_normal.x * velocity_x < 0.0 else -contact_normal
	var next_dir: int = 1 if away.x > 0.0 else -1
	if next_dir == _drive_dir:
		return
	_drive_dir = next_dir
	_bounce_cooldown = BOUNCE_COOLDOWN_SEC
	bounced.emit()


## Automatic roll: a constant drive along the surface, rolling resistance
## against it, and a soft ceiling. None of this is steerable.
##
## The drive follows tuning.drive_direction, not [member facing]. A frog knocked
## backward is then decelerated and brought back by the same term that drives it
## normally, instead of accelerating away from the level for ever.
func _apply_rolling(velocity: Vector2, normal: Vector2, delta: float) -> Vector2:
	var along_dir := Vector2(-normal.y, normal.x) * float(_drive_dir)
	var before: float = velocity.dot(along_dir)
	var along: float = before
	if absf(along) < tuning.max_roll_speed:
		along += tuning.grounded_drive_accel * delta
	along = move_toward(along, 0.0, tuning.roll_resistance * delta)
	if absf(along) > tuning.max_roll_speed:
		along = move_toward(
			along, signf(along) * tuning.max_roll_speed, tuning.overspeed_decay * delta
		)
	return velocity + along_dir * (along - before)


## Consumes a buffered tap if the frog is allowed to jump right now.
func _apply_tap(
	state: PhysicsDirectBodyState2D, velocity: Vector2, delta: float
) -> Vector2:
	if _tap_pending:
		_tap_pending = false
		_buffer_timer = maxf(tuning.jump_buffer_sec, delta)
	if _buffer_timer <= 0.0:
		return velocity

	_buffer_timer = maxf(_buffer_timer - delta, 0.0)
	var from_ground: bool = grounded or _coyote_timer > 0.0
	var from_air: bool = not from_ground and _air_jumps_used < tuning.air_jumps_allowed
	if not from_ground and not from_air:
		return velocity

	JumpSolver.solve_into(
		_outcome, tuning, state.transform.get_rotation(), velocity, facing, 0.0
	)
	# A swallowed no-op still spends the tap. Letting it sit in the buffer would
	# fire it a frame later, which reads as the game jumping on its own.
	_buffer_timer = 0.0
	if not _outcome.fired:
		jumped.emit(_outcome)
		return velocity

	if from_air:
		_air_jumps_used += 1
	_coyote_timer = 0.0
	# The solve above used the flick floor, so what just fired is the smallest
	# jump this angle can give. Keeping hold of the button feeds in the rest.
	_arrow_push = 1.0
	_thrust_impulse = _outcome.full_impulse
	_thrust_applied = JumpSolver.charge_multiplier(tuning, 0.0)
	_thrusting = _holding
	jumped.emit(_outcome)
	return _outcome.velocity


## Rolls this run's radius and resizes the body to match.
##
## Radius is randomised per run by default because it is the dial nobody can
## guess: it sets how fast the frog spins for a given speed, and therefore
## whether the jump window is tappable at all. Playing a spread of them is the
## fastest way to find out where it should sit.
func _apply_radius() -> void:
	if tuning.randomize_radius:
		var low: float = maxf(minf(tuning.radius_min, tuning.radius_max), 1.0)
		var high: float = maxf(tuning.radius_min, tuning.radius_max)
		_radius = _rng.randf_range(low, high)
	else:
		_radius = maxf(tuning.roll_radius, 1.0)
	_circle.radius = _radius
	queue_redraw()


## Feeds the rest of the jump in for as long as the button is held.
##
## The press already fired the jump at its weakest, in a direction fixed by the
## clock at that instant. This tops it up along that same direction, following
## the charge curve, until the player lets go or the hold maxes out. Direction
## never changes — the finger controls how hard, the clock controls where.
func _apply_thrust(velocity: Vector2) -> Vector2:
	if not _thrusting:
		return velocity
	var progress: float = clampf(_held_for / maxf(tuning.max_hold_sec, 0.001), 0.0, 1.0)
	var target: float = JumpSolver.charge_multiplier(tuning, progress)
	var owed: float = target - _thrust_applied
	if progress >= 1.0:
		_thrusting = false
	if owed <= 0.0:
		return velocity
	_thrust_applied = target
	return velocity + _thrust_impulse * owed
