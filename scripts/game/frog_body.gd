class_name FrogBody
extends RigidBody2D

## The ball: a wheel that rolls on its own, and gets kicked wherever you drag.
##
## Rolling is automatic and momentum-driven. Steering comes entirely from kicks:
## the player drags a thumb, the arrow swings to point that way, and releasing
## throws the ball in the OPPOSITE direction — drag down, the arrow plants
## downward, the ball goes up.
##
## A kick is legal anywhere: grounded, mid-air, scraping a wall. Nothing in the
## kick path asks about the ground. What limits it is the cooldown and the
## air-kick budget, and those two dials are the whole difficulty of the game.

## Emitted after a kick resolves, so the screen can react without polling. The
## outcome is reused — read it, do not store it.
signal kicked(outcome: KickOutcome)

## Emitted on the frame the ball touches down after being airborne.
signal landed

## Emitted when the ball turns around against the side of the shaft.
signal bounced

## A contact counts as ground when its normal is this close to vertical.
const GROUND_NORMAL_Y: float = -0.5

## A contact counts as wall when its normal is this close to horizontal. Set
## high on purpose: the corner of a ledge produces a diagonal normal, and
## treating those as walls flips the ball's drive while it is simply rolling.
const WALL_NORMAL_X: float = 0.9

## How long after a bounce the ball ignores further wall contacts, seconds.
## Without it a ball resting against a wall flips direction every frame.
const BOUNCE_COOLDOWN_SEC: float = 0.12

## Contacts to look at per frame. A heightfield surface never needs many.
const CONTACTS_REPORTED: int = 8

## Gap left between the ball and the surface when it is placed, px.
const GROUND_CLEARANCE: float = 2.0

## Where the arrow sits at rest, as a fraction of the radius. 1.0 is the rim.
const ARROW_REST_RATIO: float = 0.96

## Where the arrow's tail starts, as a fraction of the radius.
const ARROW_TAIL_RATIO: float = 0.08

## Arrow head length, as a fraction of the radius.
const ARROW_HEAD_RATIO: float = 0.38

## Arrow shaft width, as a fraction of the radius.
const ARROW_WIDTH_RATIO: float = 0.1

## How far the arrow extends past the rim at full aim, as a fraction of radius.
const ARROW_AIM_REACH: float = 0.85

@export var tuning: FrogTuning

## Which way the ball considers "forward". 1 is right, -1 is left. Cosmetic.
var facing: int = 1

## True while touching something that reads as floor.
var grounded: bool = false

var _outcome: KickOutcome = KickOutcome.new()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _radius: float = 1.0
var _circle: CircleShape2D = CircleShape2D.new()
var _head: PackedVector2Array = PackedVector2Array()
var _drive_dir: int = 1
var _bounce_cooldown: float = 0.0
var _was_grounded: bool = false
var _teleport_pending: bool = false
var _teleport_to: Vector2 = Vector2.ZERO
var _aiming: bool = false
var _drag: Vector2 = Vector2.ZERO
var _aim_dir: Vector2 = Vector2.UP
var _aim_power: float = 0.0
var _kick_cooldown: float = 0.0
var _air_kicks_used: int = 0
var _kick_pending: bool = false
var _arrow_push: float = 0.0

@onready var _shape: CollisionShape2D = %Shape


func _ready() -> void:
	if tuning == null:
		tuning = FrogTuning.new()

	contact_monitor = true
	max_contacts_reported = CONTACTS_REPORTED
	can_sleep = false

	_rng.randomize()
	_head.resize(3)
	_drive_dir = 1 if tuning.drive_direction >= 0 else -1
	_shape.shape = _circle
	_apply_radius()

	# Zero friction and bounce: spin is imposed directly, so surface friction
	# would only fight it, and a bouncy ball makes landings unreadable.
	var material := PhysicsMaterial.new()
	material.friction = 0.0
	material.bounce = 0.0
	physics_material_override = material

	var default_gravity: float = ProjectSettings.get_setting(
		"physics/2d/default_gravity", 980.0
	)
	gravity_scale = tuning.gravity / maxf(default_gravity, 1.0)


func _draw() -> void:
	# A circle and one arrow, nothing else. The arrow is the entire interface:
	# it shows where the next kick will push FROM, which is the only thing the
	# player needs to read.
	var ink := Color(0.94, 0.94, 0.92)
	draw_circle(Vector2.ZERO, _radius, Color(0.14, 0.17, 0.15))
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 48, ink, 3.0)
	_draw_arrow(_radius, ink)


## The arrow, pointing wherever the thumb last dragged.
##
## Drawn in world-space terms and counter-rotated into the body's local frame,
## because the ball spins and the aim does not. While aiming it stretches with
## the pull, so the player can see both the direction and the strength of the
## kick before committing; on release it shoots out and springs back.
func _draw_arrow(radius: float, ink: Color) -> void:
	var stretch: float = maxf(_aim_power if _aiming else 0.0, _arrow_push)
	var reach: float = radius * (ARROW_REST_RATIO + stretch * ARROW_AIM_REACH)
	var width: float = maxf(radius * ARROW_WIDTH_RATIO, 2.0)
	var head_length: float = radius * ARROW_HEAD_RATIO
	var head_half: float = radius * ARROW_HEAD_RATIO * 0.62

	# The body's own rotation must be cancelled out: the aim is a world
	# direction, and _draw works in the body's spinning local space.
	var local: Vector2 = _aim_dir.rotated(-rotation)
	var tip: Vector2 = local * reach
	var neck: Vector2 = local * maxf(reach - head_length, 0.0)
	var side := Vector2(-local.y, local.x)
	draw_line(local * (radius * ARROW_TAIL_RATIO), neck, ink, width)

	_head[0] = tip
	_head[1] = neck + side * head_half
	_head[2] = neck - side * head_half
	draw_colored_polygon(_head, ink)


func _process(delta: float) -> void:
	if _arrow_push <= 0.0:
		return
	_arrow_push = maxf(_arrow_push - delta / maxf(tuning.kick_cooldown_sec, 0.05), 0.0)
	queue_redraw()


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _teleport_pending:
		_teleport_pending = false
		state.transform = Transform2D(0.0, _teleport_to)
		state.linear_velocity = Vector2.ZERO
		state.angular_velocity = 0.0
		return

	var delta: float = state.step
	var velocity: Vector2 = state.linear_velocity
	_bounce_cooldown = maxf(_bounce_cooldown - delta, 0.0)
	_kick_cooldown = maxf(_kick_cooldown - delta, 0.0)
	var normal: Vector2 = _read_ground(state)

	if grounded:
		velocity = _apply_rolling(velocity, normal, delta)
	velocity.y = minf(velocity.y, tuning.max_fall_speed)
	velocity = _apply_kick(velocity)

	if absf(velocity.x) > tuning.facing_flip_deadzone:
		facing = 1 if velocity.x > 0.0 else -1

	if grounded or tuning.air_spin_follows_velocity:
		state.angular_velocity = velocity.x / _radius * tuning.rotation_to_velocity_ratio

	state.linear_velocity = velocity

	if grounded and not _was_grounded:
		_air_kicks_used = 0
		landed.emit()
	_was_grounded = grounded


## The player put a thumb down. Starts an aim; nothing fires yet.
func begin_aim() -> void:
	_aiming = true
	_drag = Vector2.ZERO
	_aim_power = 0.0
	queue_redraw()


## The thumb moved. [param drag] is total travel from where the press started,
## in VIEWPORT pixels — thumb distance should mean the same thing whatever the
## camera is doing. The arrow follows immediately, so the aim is visible before
## the player commits to it.
func update_aim(drag: Vector2) -> void:
	if not _aiming:
		return
	_drag = drag
	var length: float = drag.length()
	if length > 0.001:
		_aim_dir = drag / length
	_aim_power = clampf(length / maxf(tuning.max_drag_px, 1.0), 0.0, 1.0)
	queue_redraw()


## The thumb lifted. Resolves the kick on the next physics step, so the velocity
## it modifies is the one physics is actually about to use.
func release_aim() -> void:
	if not _aiming:
		return
	_aiming = false
	_kick_pending = true


## Abandons an aim without kicking.
func cancel_aim() -> void:
	_aiming = false
	_drag = Vector2.ZERO
	_aim_power = 0.0
	_kick_pending = false
	queue_redraw()


## Fires a kick directly, bypassing the drag. For tests and tools.
func kick(drag: Vector2) -> void:
	_drag = drag
	var length: float = drag.length()
	if length > 0.001:
		_aim_dir = drag / length
	_aim_power = clampf(length / maxf(tuning.max_drag_px, 1.0), 0.0, 1.0)
	_aiming = false
	_kick_pending = true


## True while the player is holding and aiming.
func aiming() -> bool:
	return _aiming


## Current drag as a fraction of a full-power pull, 0 to 1.
func aim_power() -> float:
	return _aim_power


## Where the arrow points, in world space. The ball is thrown the other way.
func aim_direction() -> Vector2:
	return _aim_dir


## Whether a kick would be allowed right now. False during the cooldown, or
## once the air budget is spent.
func can_kick() -> bool:
	if _kick_cooldown > 0.0:
		return false
	if grounded or tuning.air_kicks_allowed < 0:
		return true
	return _air_kicks_used < tuning.air_kicks_allowed


## Air kicks spent since the ball last touched down.
func air_kicks_used() -> int:
	return _air_kicks_used


## How far the arrow is currently shot out, 0 to 1. Debug overlay reads this.
func arrow_push() -> float:
	return _arrow_push


## Which way the self-drive currently points, 1 right and -1 left.
func drive_direction() -> int:
	return _drive_dir


## Radius this run rolled, px.
func radius() -> float:
	return _radius


## Seeds the radius roll. 0 keeps it genuinely random per run; any other value
## makes a pinned course give a pinned ball too, so a tuning comparison changes
## one thing at a time.
func set_run_seed(seed_value: int) -> void:
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value


## Drops the ball onto [param ground_point], a point on the terrain surface.
## Rolls a new radius first, then sits the body exactly on top of it. The move
## lands on the next physics step, the only safe place to shift a rigid body,
## but the radius applies immediately so callers can read it.
func reset_to(ground_point: Vector2) -> void:
	_apply_radius()
	_teleport_to = ground_point - Vector2(0.0, _radius + GROUND_CLEARANCE)
	_teleport_pending = true
	cancel_aim()
	_aim_dir = Vector2.UP
	_arrow_push = 0.0
	_kick_cooldown = 0.0
	_air_kicks_used = 0
	_bounce_cooldown = 0.0
	_was_grounded = false
	grounded = false
	facing = 1
	_drive_dir = 1 if tuning.drive_direction >= 0 else -1


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


## Turns the ball around when it runs into the side of the shaft.
##
## The reversal is driven by the wall, never by the ball's own velocity — the
## rule that keeps a mistimed kick from sending a run backwards for ever.
func _bounce_off_wall(contact_normal: Vector2, velocity_x: float) -> void:
	if _bounce_cooldown > 0.0 or absf(velocity_x) < 1.0:
		return
	var away: Vector2 = contact_normal if contact_normal.x * velocity_x < 0.0 else -contact_normal
	var next_dir: int = 1 if away.x > 0.0 else -1
	if next_dir == _drive_dir:
		return
	_drive_dir = next_dir
	_bounce_cooldown = BOUNCE_COOLDOWN_SEC
	bounced.emit()


## Automatic roll: a constant drive along the surface, rolling resistance
## against it, and a soft ceiling.
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


## Resolves a pending kick, if one is due and allowed.
##
## Deliberately knows nothing about the ground: a kick off a wall, out of a
## fall, or at the top of an arc is the same operation. What limits it is the
## cooldown and the air budget, checked here and nowhere else.
func _apply_kick(velocity: Vector2) -> Vector2:
	if not _kick_pending:
		return velocity
	_kick_pending = false
	if not can_kick():
		return velocity

	KickSolver.solve_into(_outcome, tuning, _drag, velocity)
	_outcome.airborne = not grounded
	if not _outcome.fired:
		# Too short to count. Still reported, so the screen can tell a deadzone
		# twitch apart from a kick that never happened.
		kicked.emit(_outcome)
		return velocity

	_kick_cooldown = tuning.kick_cooldown_sec
	if not grounded:
		_air_kicks_used += 1
	_arrow_push = 1.0
	_aim_dir = _outcome.aim
	kicked.emit(_outcome)
	return _outcome.velocity


## Rolls this run's radius and resizes the body to match.
func _apply_radius() -> void:
	if tuning.randomize_radius:
		var low: float = maxf(minf(tuning.radius_min, tuning.radius_max), 1.0)
		var high: float = maxf(tuning.radius_min, tuning.radius_max)
		_radius = _rng.randf_range(low, high)
	else:
		_radius = maxf(tuning.roll_radius, 1.0)
	_circle.radius = _radius
	queue_redraw()
