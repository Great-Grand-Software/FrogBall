extends Node2D

## The run: one frog, an endless heightfield, and a camera chasing both.
##
## Deliberately silent. There is no tutorial, no hint, no prompt and no arrow —
## the prototype's whole question is whether the roll-timing jump reads as skill
## with nothing explained, and any hint on screen would answer that question for
## the player instead of letting them find it. The distance readout is a score,
## not a hint, and it is the only text the run shows.
##
## Terrain collision is a fixed pool of polygons reused in place; terrain
## visuals are one _draw() over the same data. Nothing here grows with how long
## the player survives, which is the property an endless mode most needs.

## Collision polygons in the pool. One per live terrain segment, so this is the
## terrain's entire contribution to the node count.
const TERRAIN_POLYGONS: int = TerrainPlan.MAX_SEGMENTS

## Points in a terrain quad. Named so the buffer size is not a loose 4.
const QUAD_POINTS: int = 4

## How far either side of the frog the kill plane looks for ground, px.
const KILL_SCAN_HALF_WIDTH: float = 900.0

## Debug overlay refresh period, seconds. Slower than a frame on purpose: the
## overlay builds a string, and nothing that runs every frame should allocate.
const DEBUG_REFRESH_SEC: float = 0.1

@export var frog_tuning: FrogTuning
@export var level_tuning: LevelTuning

## Terrain seed. 0 picks a fresh one per run, which is what shipping wants. Any
## other value replays the same course every time, which is what tuning the jump
## against a known ramp wants, and what the tests need to not be flaky.
@export var run_seed: int = 0

## How far below the lowest nearby ground the frog may fall before the run ends,
## px. The plane trails the terrain rather than sitting at a fixed height, so a
## level that descends does not kill the player for descending with it.
@export_range(100.0, 4000.0, 10.0, "or_greater") var kill_plane_margin: float = 900.0

## Pause between death and the automatic restart, seconds.
@export_range(0.1, 3.0, 0.05, "or_greater") var restart_delay_sec: float = 0.7

## Speed below which the frog counts as stalled, px/s.
@export_range(0.0, 400.0, 1.0, "or_greater") var stuck_speed: float = 22.0

## How long it may stay stalled before the run is abandoned, seconds. A frog
## wedged in a corner is not a fail state the player can read, so end it.
@export_range(0.0, 20.0, 0.5, "or_greater") var stuck_timeout_sec: float = 3.5

## Pixels per displayed metre.
@export_range(1.0, 500.0, 1.0, "or_greater") var pixels_per_metre: float = 64.0

@export_range(0.1, 4.0, 0.05, "or_greater") var camera_zoom: float = 0.85

## How far ahead the camera leads at full roll speed, px.
@export_range(0.0, 1200.0, 10.0, "or_greater") var camera_look_ahead: float = 260.0

@export_range(0.5, 30.0, 0.5, "or_greater") var camera_follow_speed: float = 6.0

## Vertical catch-up. Slower than horizontal, or every jump swims.
@export_range(0.5, 30.0, 0.5, "or_greater") var camera_vertical_follow_speed: float = 3.0

@export_range(-600.0, 600.0, 10.0) var camera_vertical_offset: float = -60.0

## Start with the tuning overlay up. Off by default, and it must stay off for a
## real playtest: an overlay that draws the window is an explanation.
@export var debug_overlay: bool = false

var _plan: TerrainPlan
var _quad: PackedVector2Array = PackedVector2Array()
var _polygons: Array[CollisionPolygon2D] = []
var _run_active: bool = false
var _synced_frontier: float = -INF
var _shown_metres: int = -1
var _run_metres: int = 0
var _stuck_for: float = 0.0
var _debug_elapsed: float = 0.0

@onready var _frog: FrogBody = %Frog
@onready var _terrain: StaticBody2D = %Terrain
@onready var _camera: Camera2D = %Camera
@onready var _distance_label: Label = %Distance
@onready var _debug_label: Label = %Debug
@onready var _fade: ColorRect = %Fade


func _ready() -> void:
	if frog_tuning == null:
		frog_tuning = FrogTuning.new()
	if level_tuning == null:
		level_tuning = LevelTuning.new()

	_frog.tuning = frog_tuning
	_quad.resize(QUAD_POINTS)
	_plan = TerrainPlan.new(level_tuning, Vector2.ZERO)
	_build_polygon_pool()

	_camera.zoom = Vector2(camera_zoom, camera_zoom)
	_debug_label.visible = debug_overlay
	_frog.jumped.connect(_on_frog_jumped)

	GameState.best_distance_changed.connect(_on_game_state_best_distance_changed)
	start_run()


## Terrain data behind the run. Exposed so tests can drive generation hard
## without waiting for a frog to roll there.
func terrain_plan() -> TerrainPlan:
	return _plan


## False once the frog has died and before the next run begins.
func is_running() -> bool:
	return _run_active


## Rebuilds the collision pool and the drawing from the current plan. Cheap, and
## idempotent — it touches the same fixed set of nodes every time.
func refresh_terrain() -> void:
	var live: int = _plan.segment_count()
	for index: int in range(TERRAIN_POLYGONS):
		var polygon: CollisionPolygon2D = _polygons[index]
		if index >= live:
			polygon.disabled = true
			continue
		var top_left: Vector2 = _plan.segment_start(index)
		var top_right: Vector2 = _plan.segment_end(index)
		var depth: float = maxf(level_tuning.ground_thickness, 1.0)
		_quad[0] = top_left
		_quad[1] = top_right
		_quad[2] = top_right + Vector2(0.0, depth)
		_quad[3] = top_left + Vector2(0.0, depth)
		polygon.polygon = _quad
		polygon.disabled = false
	_synced_frontier = _plan.frontier_x()
	queue_redraw()


## Starts a fresh run: new terrain, frog back on the opening runway, distance
## back to zero.
func start_run() -> void:
	_plan.reset(run_seed)
	_plan.advance_to(_plan.start_point().x + level_tuning.generate_ahead)
	refresh_terrain()

	# The frog rolls its own radius, so it places itself on the surface point
	# rather than the screen guessing how tall it is this run.
	var spawn: Vector2 = _plan.start_point()
	_frog.set_run_seed(run_seed)
	_frog.reset_to(spawn)
	_camera.global_position = spawn + Vector2(0.0, camera_vertical_offset - _frog.radius())

	_run_metres = 0
	_stuck_for = 0.0
	_run_active = true
	_refresh_distance(0)


func _draw() -> void:
	# One pass over the same data the collision pool uses. Prefer this over a
	# visual node per segment — see CLAUDE.md section 4.
	var ink := Color(0.92, 0.92, 0.90)
	var fill := Color(0.16, 0.18, 0.17)
	var depth: float = maxf(level_tuning.ground_thickness, 1.0)
	for index: int in range(_plan.segment_count()):
		var top_left: Vector2 = _plan.segment_start(index)
		var top_right: Vector2 = _plan.segment_end(index)
		_quad[0] = top_left
		_quad[1] = top_right
		_quad[2] = top_right + Vector2(0.0, depth)
		_quad[3] = top_left + Vector2(0.0, depth)
		draw_colored_polygon(_quad, fill)
		draw_line(top_left, top_right, ink, 4.0)


func _physics_process(delta: float) -> void:
	if not _run_active:
		return

	var here: Vector2 = _frog.global_position
	_plan.advance_to(here.x + level_tuning.generate_ahead)
	if not is_equal_approx(_plan.frontier_x(), _synced_frontier):
		refresh_terrain()

	var floor_y: float = _plan.lowest_surface_y(
		here.x - KILL_SCAN_HALF_WIDTH, here.x + KILL_SCAN_HALF_WIDTH
	)
	if here.y > floor_y + kill_plane_margin:
		_end_run()
		return

	if stuck_timeout_sec > 0.0 and _frog.linear_velocity.length() < stuck_speed:
		_stuck_for += delta
		if _stuck_for >= stuck_timeout_sec:
			_end_run()
			return
	else:
		_stuck_for = 0.0

	var travelled: float = here.x - _plan.start_point().x
	_run_metres = maxi(_run_metres, int(maxf(travelled, 0.0) / maxf(pixels_per_metre, 1.0)))
	_refresh_distance(_run_metres)


func _process(delta: float) -> void:
	_track_camera(delta)
	if debug_overlay:
		_debug_elapsed += delta
		if _debug_elapsed >= DEBUG_REFRESH_SEC:
			_debug_elapsed = 0.0
			_refresh_debug()


func _unhandled_input(event: InputEvent) -> void:
	# One button is the entire input surface: a single touch, a single left
	# click, or space, which is a desktop convenience and never required.
	#
	# Press and release are BOTH meaningful. Pressing starts a charge; releasing
	# fires the jump, reading how long it was held for power and the clock angle
	# at that instant for direction. A flick is a hop, a full press is a launch.
	var pressed: bool = false
	var is_tap: bool = false
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		is_tap = touch.index == 0
		pressed = touch.pressed
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		is_tap = mouse.button_index == MOUSE_BUTTON_LEFT
		pressed = mouse.pressed
	elif event is InputEventKey:
		var key := event as InputEventKey
		is_tap = key.keycode == KEY_SPACE and not key.echo
		pressed = key.pressed
	if not is_tap:
		return
	get_viewport().set_input_as_handled()
	if not _run_active:
		return
	if pressed:
		_frog.begin_tap()
	else:
		_frog.release_tap()


func _build_polygon_pool() -> void:
	# Created once, bounded by a named constant, and owned by this screen for
	# the life of the scene. Nothing is spawned per segment at run time.
	for index: int in range(TERRAIN_POLYGONS):
		var polygon := CollisionPolygon2D.new()
		polygon.name = "Segment%02d" % index
		polygon.disabled = true
		_terrain.add_child(polygon)
		_polygons.append(polygon)


func _track_camera(delta: float) -> void:
	var lead: float = clampf(
		_frog.linear_velocity.x / maxf(frog_tuning.max_roll_speed, 1.0), -1.0, 1.0
	)
	var target: Vector2 = _frog.global_position
	target.x += lead * camera_look_ahead
	target.y += camera_vertical_offset

	# Exponential smoothing, so the follow feels the same at any frame rate.
	var here: Vector2 = _camera.global_position
	here.x = lerpf(here.x, target.x, 1.0 - exp(-camera_follow_speed * delta))
	here.y = lerpf(here.y, target.y, 1.0 - exp(-camera_vertical_follow_speed * delta))
	_camera.global_position = here


func _refresh_distance(metres: int) -> void:
	# Guarded because building the string every frame would allocate every
	# frame, and the number only changes a few times a second.
	if metres == _shown_metres:
		return
	_shown_metres = metres
	_distance_label.text = "%d M    BEST %d M" % [metres, GameState.best_distance()]


func _refresh_debug() -> void:
	# Radius is in here because it is randomised per run: when a run feels good
	# or awful, the first thing you want to know is which frog you were riding.
	_debug_label.text = "r %.0f   feet %+.0f deg   charge %.0f%%   speed %.0f   %s" % [
		_frog.radius(),
		_frog.feet_phase_deg(),
		_frog.charge() * 100.0,
		_frog.linear_velocity.length(),
		"ground" if _frog.grounded else "air",
	]


func _end_run() -> void:
	if not _run_active:
		return
	_run_active = false
	GameState.submit_distance(_run_metres)

	# A finite Tween rather than a countdown in _process: it cannot outlive its
	# own exit condition, and it frees itself.
	var half: float = maxf(restart_delay_sec, 0.1) * 0.5
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, half)
	tween.tween_callback(start_run)
	tween.tween_property(_fade, "color:a", 0.0, half)


func _on_frog_jumped(outcome: JumpOutcome) -> void:
	# Nothing on screen reacts to a jump on purpose — no flash, no readout, no
	# "nice timing". The arc itself is the only feedback the player gets, which
	# is the thing being tested. The hook exists for the debug overlay and for
	# whatever juice survives the playtest.
	if debug_overlay:
		_debug_elapsed = DEBUG_REFRESH_SEC
		if not outcome.fired:
			_debug_label.text = "whiffed at %+.0f deg" % outcome.phase_deg


func _on_game_state_best_distance_changed(_metres: int) -> void:
	_shown_metres = -1
	_refresh_distance(_run_metres)
