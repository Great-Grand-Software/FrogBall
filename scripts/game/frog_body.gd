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

## A contact counts as ground when its normal is this close to vertical.
## Filters out the side of a step riser, which is a wall, not a floor.
const GROUND_NORMAL_Y: float = -0.5

## Contacts to look at per frame. A heightfield surface never needs many.
const CONTACTS_REPORTED: int = 8

## Half-width of the drawn feet band, radians. Wide enough to read as "this end
## is the bottom" at a glance while the body is spinning.
const FEET_ARC_HALF_RAD: float = 0.62

@export var tuning: FrogTuning

## Which way the frog considers "forward". 1 is right, -1 is left.
var facing: int = 1

## True while touching something that reads as floor.
var grounded: bool = false

var _outcome: JumpOutcome = JumpOutcome.new()
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

	var circle := CircleShape2D.new()
	circle.radius = maxf(tuning.roll_radius, 1.0)
	_shape.shape = circle

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
	# Drawn here rather than as child sprites so the whole frog is one canvas
	# item and the face/feet axis rotates with the body for free.
	#
	# The feet are drawn as the single heaviest mark on the body, and the face
	# as something obviously different. Reading which way round the frog is IS
	# the game — if a player cannot tell the feet from the face at a glance
	# while it is spinning, there is nothing for them to time against.
	var radius: float = maxf(tuning.roll_radius, 1.0)
	var ink := Color(0.94, 0.94, 0.92)
	draw_circle(Vector2.ZERO, radius, Color(0.14, 0.17, 0.15))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, ink, 3.0)

	# Feet: a solid band across the bottom of the body. Local down is +y, which
	# is angle +PI/2 in Godot's 2D convention.
	var down_angle: float = PI * 0.5
	draw_arc(
		Vector2.ZERO,
		radius * 0.82,
		down_angle - FEET_ARC_HALF_RAD,
		down_angle + FEET_ARC_HALF_RAD,
		16,
		ink,
		radius * 0.3
	)
	for side: float in [-1.0, 1.0]:
		var toe: Vector2 = Vector2.DOWN.rotated(side * FEET_ARC_HALF_RAD) * radius * 0.82
		draw_circle(toe, radius * 0.17, ink)

	# Face: eyes on the opposite side, small and clearly not the feet.
	var brow: Vector2 = Vector2.UP * radius * 0.46
	draw_circle(brow + Vector2.LEFT * radius * 0.26, radius * 0.13, ink)
	draw_circle(brow + Vector2.RIGHT * radius * 0.26, radius * 0.13, ink)
	draw_arc(Vector2.UP * radius * 0.2, radius * 0.3, 0.35, PI - 0.35, 12, ink, 3.0)

	# One rim spoke, so spin rate stays readable even at full speed.
	draw_line(Vector2.RIGHT * radius * 0.55, Vector2.RIGHT * radius, ink, 3.0)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _teleport_pending:
		_teleport_pending = false
		state.transform = Transform2D(0.0, _teleport_to)
		state.linear_velocity = Vector2.ZERO
		state.angular_velocity = 0.0
		return

	var delta: float = state.step
	var velocity: Vector2 = state.linear_velocity
	var normal: Vector2 = _read_ground(state)

	if grounded:
		_coyote_timer = tuning.coyote_time_sec
		_air_jumps_used = 0
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	if grounded:
		velocity = _apply_rolling(velocity, normal, delta)
	velocity.y = minf(velocity.y, tuning.max_fall_speed)

	velocity = _apply_tap(state, velocity, delta)

	if absf(velocity.x) > tuning.facing_flip_deadzone:
		facing = 1 if velocity.x > 0.0 else -1

	if grounded or tuning.air_spin_follows_velocity:
		var radius: float = maxf(tuning.roll_radius, 1.0)
		state.angular_velocity = velocity.x / radius * tuning.rotation_to_velocity_ratio

	state.linear_velocity = velocity

	if grounded and not _was_grounded:
		landed.emit()
	_was_grounded = grounded


## Records a tap. The jump itself resolves on the next physics step, so the
## rotation it reads is the one physics is actually about to use.
func queue_tap() -> void:
	_tap_pending = true


## Drops the frog at [param point], stationary and upright. Applied on the next
## physics step, which is the only safe place to move a rigid body.
func reset_to(point: Vector2) -> void:
	_teleport_to = point
	_teleport_pending = true
	_coyote_timer = 0.0
	_buffer_timer = 0.0
	_air_jumps_used = 0
	_tap_pending = false
	_was_grounded = false
	grounded = false
	facing = 1


## Where the feet currently sit on the world clock, in degrees. Debug overlay
## reads this; nothing the player sees does.
func feet_phase_deg() -> float:
	return JumpSolver.feet_phase_deg(rotation, facing)


## Sets [member grounded] from this step's contacts and returns the floor
## normal, pointing up.
func _read_ground(state: PhysicsDirectBodyState2D) -> Vector2:
	grounded = false
	var normal := Vector2.UP
	for index: int in range(state.get_contact_count()):
		var candidate: Vector2 = state.get_contact_local_normal(index)
		# Reported normals can face either way depending on which body is
		# which, so flip to a consistent "up" before judging the angle.
		if candidate.y > 0.0:
			candidate = -candidate
		if candidate.y < GROUND_NORMAL_Y:
			grounded = true
			normal = candidate
			break
	return normal


## Automatic roll: a constant drive along the surface, rolling resistance
## against it, and a soft ceiling. None of this is steerable.
##
## The drive follows tuning.drive_direction, not [member facing]. A frog knocked
## backward is then decelerated and brought back by the same term that drives it
## normally, instead of accelerating away from the level for ever.
func _apply_rolling(velocity: Vector2, normal: Vector2, delta: float) -> Vector2:
	var drive: float = 1.0 if tuning.drive_direction >= 0 else -1.0
	var along_dir := Vector2(-normal.y, normal.x) * drive
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
		_outcome, tuning, state.transform.get_rotation(), velocity, facing
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
	jumped.emit(_outcome)
	return _outcome.velocity
