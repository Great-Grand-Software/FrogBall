extends Node2D

## The run: one frog climbing a walled shaft, and a camera rising with it.
##
## Deliberately silent. There is no tutorial, no hint, no prompt and no arrow
## pointing anywhere — the prototype's whole question is whether the roll-timing
## jump reads as skill with nothing explained, and any hint on screen would
## answer that question for the player. The height readout is a score, not a
## hint, and it is the only text a run shows.
##
## Ledge collision is a fixed pool reused in place and the visuals are one
## _draw() over the same data, so nothing here grows with how high the player
## gets — which is the property an endless climb most needs.

## Collision polygons in the pool, one per live ledge. This is the shaft's
## entire contribution to the node count.
const TERRAIN_POLYGONS: int = TerrainPlan.MAX_SEGMENTS

## Points in a ledge quad. Named so the buffer size is not a loose 4.
const QUAD_POINTS: int = 4

## How far either side of the ball a roll course looks for ground when placing
## the kill plane, px. CLIMB does not need it — everything below the lowest live
## ledge has already been recycled.
const KILL_SCAN_HALF_WIDTH: float = 900.0

## Debug overlay refresh period, seconds. Slower than a frame on purpose: the
## overlay builds a string, and nothing running every frame should allocate.
const DEBUG_REFRESH_SEC: float = 0.1

@export var frog_tuning: FrogTuning
@export var level_tuning: LevelTuning

## Course seed. 0 rolls a fresh one per run; anything else pins the shaft AND
## the frog's radius, which is what the integration tests rely on.
@export var run_seed: int = 0

## How far below the lowest standing ledge the frog may fall before the run
## ends, px. Everything under that has already been recycled, so there is
## nothing left to land on.
@export_range(100.0, 4000.0, 10.0, "or_greater") var fall_tolerance: float = 700.0

## Pause between death and the automatic restart, seconds.
@export_range(0.1, 3.0, 0.05, "or_greater") var restart_delay_sec: float = 0.7

## Speed below which the frog counts as stalled, px/s.
@export_range(0.0, 400.0, 1.0, "or_greater") var stuck_speed: float = 22.0

## How long it may stay stalled before the run is abandoned, seconds. A frog
## wedged in a corner is not a fail state the player can read, so end it.
@export_range(0.0, 20.0, 0.5, "or_greater") var stuck_timeout_sec: float = 4.0

## Pixels per displayed metre of height.
@export_range(1.0, 500.0, 1.0, "or_greater") var pixels_per_metre: float = 64.0

@export_range(0.1, 4.0, 0.05, "or_greater") var camera_zoom: float = 1.0

## How far above the frog the camera leads, px. Generous, because in a climber
## the thing you need to see is the ledge you are aiming at, not the one you
## just left.
@export_range(0.0, 1200.0, 10.0, "or_greater") var camera_look_ahead: float = 190.0

## Vertical catch-up rate, higher is snappier.
@export_range(0.5, 30.0, 0.5, "or_greater") var camera_follow_speed: float = 5.0

## Start with the tuning overlay up. Off by default, and it must stay off for a
## real playtest: an overlay that draws the window is an explanation.
@export var debug_overlay: bool = false

var _plan: TerrainPlan
var _plan_tuning: LevelTuning
var _quad: PackedVector2Array = PackedVector2Array()
var _polygons: Array[CollisionPolygon2D] = []
var _run_active: bool = false
var _synced_frontier: float = INF
var _shown_metres: int = -1
var _run_metres: int = 0
var _best_axis: float = 0.0
var _synced_frontier_x: float = INF
var _stuck_for: float = 0.0
var _debug_elapsed: float = 0.0
var _aim_active: bool = false
var _aim_origin: Vector2 = Vector2.ZERO

@onready var _frog: FrogBody = %Frog
@onready var _terrain: StaticBody2D = %Terrain
@onready var _left_wall: CollisionShape2D = %LeftWall
@onready var _right_wall: CollisionShape2D = %RightWall
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
	_plan_tuning = level_tuning
	_build_polygon_pool()
	_build_walls()
	var walled: bool = level_tuning.mode == LevelTuning.Mode.CLIMB
	_left_wall.disabled = not walled
	_right_wall.disabled = not walled

	_camera.zoom = Vector2(camera_zoom, camera_zoom)
	_debug_label.visible = debug_overlay
	_frog.kicked.connect(_on_frog_kicked)

	GameState.best_distance_changed.connect(_on_game_state_best_distance_changed)
	start_run()


## Terrain data behind the run. Exposed so tests can drive generation hard
## without waiting for a frog to climb there.
func terrain_plan() -> TerrainPlan:
	return _plan


## True while a run is in play, false between death and the restart.
func is_running() -> bool:
	return _run_active


## Rebuilds the collision pool and the drawing from the current plan. Cheap,
## and idempotent — it touches the same fixed set of nodes every time.
func refresh_terrain() -> void:
	var live: int = _plan.segment_count()
	var depth: float = maxf(level_tuning.ledge_thickness, 1.0)
	for index: int in range(TERRAIN_POLYGONS):
		var polygon: CollisionPolygon2D = _polygons[index]
		if index >= live:
			polygon.disabled = true
			continue
		var left: Vector2 = _plan.segment_start(index)
		var right: Vector2 = _plan.segment_end(index)
		_quad[0] = left
		_quad[1] = right
		_quad[2] = right + Vector2(0.0, depth)
		_quad[3] = left + Vector2(0.0, depth)
		polygon.polygon = _quad
		polygon.disabled = false
	_synced_frontier = _plan.frontier_y()
	_synced_frontier_x = _plan.frontier_x()
	queue_redraw()


## Starts a fresh run: new shaft, frog back on the floor, height back to zero.
func start_run() -> void:
	# Rebuilt when the tuning instance has been swapped — the plan captures its
	# tuning, so changing mode on the screen alone would silently do nothing.
	if _plan == null or _plan_tuning != level_tuning:
		_plan = TerrainPlan.new(level_tuning, Vector2.ZERO)
		_plan_tuning = level_tuning
	_plan.reset(run_seed if run_seed != 0 else level_tuning.seed_value)
	_plan.advance_for(_plan.start_point())
	_plan.advance_for(_plan.start_point())
	refresh_terrain()

	var spawn: Vector2 = _plan.start_point()
	# Before the first physics frame the wall shapes still sit at the origin —
	# which is exactly where the frog spawns — so place them now or the run
	# starts with the frog wedged inside both of them.
	_track_walls(spawn)
	_frog.set_run_seed(run_seed)
	_frog.reset_to(spawn)
	_camera.global_position = Vector2(spawn.x, spawn.y - camera_look_ahead)

	_best_axis = spawn.y if _plan.climbing() else spawn.x
	_run_metres = 0
	_stuck_for = 0.0
	_run_active = true
	_refresh_height(0)


func _draw() -> void:
	# One pass over the same data the collision pool uses. Prefer this over a
	# visual node per ledge — see CLAUDE.md section 4.
	var ink := Color(0.94, 0.94, 0.92)
	var fill := Color(0.16, 0.18, 0.17)
	var depth: float = maxf(level_tuning.ledge_thickness, 1.0)
	for index: int in range(_plan.segment_count()):
		var left: Vector2 = _plan.segment_start(index)
		var right: Vector2 = _plan.segment_end(index)
		_quad[0] = left
		_quad[1] = right
		_quad[2] = right + Vector2(0.0, depth)
		_quad[3] = left + Vector2(0.0, depth)
		draw_colored_polygon(_quad, fill)
		draw_line(left, right, ink, 4.0)

	# The walls, drawn across whatever slice of the shaft is near the frog.
	if not _plan.climbing():
		return
	var span: float = level_tuning.wall_span * 0.5
	var centre_y: float = _frog.global_position.y
	for edge: float in [_plan.shaft_left(), _plan.shaft_right()]:
		draw_line(
			Vector2(edge, centre_y - span), Vector2(edge, centre_y + span), ink, 3.0
		)


func _physics_process(delta: float) -> void:
	if not _run_active:
		return

	var here: Vector2 = _frog.global_position
	_plan.advance_for(here)
	if not is_equal_approx(_plan.frontier_y(), _synced_frontier) \
			or not is_equal_approx(_plan.frontier_x(), _synced_frontier_x):
		refresh_terrain()
	if _plan.climbing():
		_track_walls(here)

	if here.y > _fall_floor(here) + _fall_limit():
		_end_run()
		return

	if stuck_timeout_sec > 0.0 and _frog.linear_velocity.length() < stuck_speed:
		_stuck_for += delta
		if _stuck_for >= stuck_timeout_sec:
			_end_run()
			return
	else:
		_stuck_for = 0.0

	_advance_score(here)


## Where the ground under the ball currently is, for the kill plane to trail.
func _fall_floor(here: Vector2) -> float:
	if _plan.climbing():
		return _plan.lowest_surface_y()
	return _plan.lowest_surface_near(here.x, KILL_SCAN_HALF_WIDTH)


func _fall_limit() -> float:
	return fall_tolerance if _plan.climbing() else level_tuning.roll_fall_tolerance


## Height climbed, or distance covered, depending on the mode. Either way it
## only ever goes up: a run is scored on its best, not its current position.
func _advance_score(here: Vector2) -> void:
	var travelled: float = 0.0
	if _plan.climbing():
		_best_axis = minf(_best_axis, here.y)
		travelled = _plan.start_point().y - _best_axis
	else:
		_best_axis = maxf(_best_axis, here.x)
		travelled = _best_axis - _plan.start_point().x
	_run_metres = maxi(_run_metres, int(maxf(travelled, 0.0) / maxf(pixels_per_metre, 1.0)))
	_refresh_height(_run_metres)


func _process(delta: float) -> void:
	_track_camera(delta)
	if debug_overlay:
		_debug_elapsed += delta
		if _debug_elapsed >= DEBUG_REFRESH_SEC:
			_debug_elapsed = 0.0
			_refresh_debug()


func _unhandled_input(event: InputEvent) -> void:
	# One thumb, dragged. Press starts an aim, motion aims it, release kicks.
	#
	# Drag is measured in VIEWPORT pixels from where the press began, not in
	# world space: how far a thumb travelled should mean the same thing whatever
	# the camera is doing.
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.index != 0:
			return
		get_viewport().set_input_as_handled()
		_aim_event(touch.pressed, touch.position)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index != 0:
			return
		get_viewport().set_input_as_handled()
		_aim_moved(drag.position)
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		get_viewport().set_input_as_handled()
		_aim_event(mouse.pressed, mouse.position)
	elif event is InputEventMouseMotion and _aim_active:
		_aim_moved((event as InputEventMouseMotion).position)


func _aim_event(pressed: bool, position: Vector2) -> void:
	if not _run_active:
		return
	if pressed:
		_aim_active = true
		_aim_origin = position
		_frog.begin_aim()
	elif _aim_active:
		_aim_active = false
		_frog.update_aim(position - _aim_origin)
		_frog.release_aim()


func _aim_moved(position: Vector2) -> void:
	if not _aim_active or not _run_active:
		return
	_frog.update_aim(position - _aim_origin)


func _build_polygon_pool() -> void:
	# Created once, bounded by a named constant, and owned by this screen for
	# the life of the scene. Nothing is spawned per ledge at run time.
	for index: int in range(TERRAIN_POLYGONS):
		var polygon := CollisionPolygon2D.new()
		polygon.name = "Ledge%02d" % index
		polygon.disabled = true
		_terrain.add_child(polygon)
		_polygons.append(polygon)


func _build_walls() -> void:
	# Two shapes, repositioned as the frog climbs rather than extended, so an
	# endless run cannot grow them.
	var thickness: float = maxf(level_tuning.wall_thickness, 1.0)
	for shape_node: CollisionShape2D in [_left_wall, _right_wall]:
		var box := RectangleShape2D.new()
		box.size = Vector2(thickness, maxf(level_tuning.wall_span, 1.0))
		shape_node.shape = box


func _track_walls(here: Vector2) -> void:
	var half: float = maxf(level_tuning.wall_thickness, 1.0) * 0.5
	_left_wall.global_position = Vector2(_plan.shaft_left() - half, here.y)
	_right_wall.global_position = Vector2(_plan.shaft_right() + half, here.y)


func _track_camera(delta: float) -> void:
	var here: Vector2 = _camera.global_position
	var weight: float = 1.0 - exp(-camera_follow_speed * delta)
	if _plan.climbing():
		# Pinned horizontally: the column is narrow enough to see whole, and a
		# camera sliding sideways would make a vertical kick read as a diagonal.
		here.x = _plan.start_point().x
		here.y = lerpf(here.y, _frog.global_position.y - camera_look_ahead, weight)
	else:
		here.x = lerpf(here.x, _frog.global_position.x + camera_look_ahead, weight)
		here.y = lerpf(here.y, _frog.global_position.y, weight * 0.6)
	_camera.global_position = here


func _refresh_height(metres: int) -> void:
	# Guarded because building the string every frame would allocate every
	# frame, and the number only changes a few times a second.
	if metres == _shown_metres:
		return
	_shown_metres = metres
	_distance_label.text = "%d M    BEST %d M" % [metres, GameState.best_distance()]


func _refresh_debug() -> void:
	# Radius is in here because it is randomised per run: when a run feels good
	# or awful, the first thing you want to know is which frog you were riding.
	_debug_label.text = "r %.0f   aim %.0f%%   air kicks %d   %s%s" % [
		_frog.radius(),
		_frog.aim_power() * 100.0,
		_frog.air_kicks_used(),
		"ground" if _frog.grounded else "air",
		"" if _frog.can_kick() else "  (cooling)",
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


func _on_frog_kicked(outcome: KickOutcome) -> void:
	# Nothing on screen reacts to a kick on purpose. The arc itself is the only
	# feedback. This hook exists for the debug overlay.
	if debug_overlay:
		_debug_elapsed = DEBUG_REFRESH_SEC
		if not outcome.fired:
			_debug_label.text = "drag too short"


func _on_game_state_best_distance_changed(_metres: int) -> void:
	_shown_metres = -1
	_refresh_height(_run_metres)
