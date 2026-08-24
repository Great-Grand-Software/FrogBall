class_name TerrainPlan
extends RefCounted

## The level, as data. No nodes, so it unit-tests without a scene.
##
## Builds either kind of course, because the playtest wants both:
##
##  - CLIMB stacks ledges upward inside a walled column. The gap between tiers
##    is what forces a kick, and the walls keep the ball in frame.
##  - ROLL marches rightward over flats, ramps and gaps. The gaps force the
##    kick instead.
##
## Both share one representation — a span from one point to another — so the
## screen draws, collides and recycles them identically and neither mode gets
## its own copy of the pooling logic.
##
## Spans live in a fixed-size ring buffer. That is the guardrail from CLAUDE.md
## section 4 made structural rather than remembered: an endless climb cannot
## leak ledges when the oldest is overwritten by construction, and the node pool
## that renders them is sized from the same constant.

## Hard ceiling on live ledges. The collision pool is sized from this, so
## raising it raises the node count — see the 64-node ceiling.
##
## It must comfortably exceed the ledges visible at once PLUS the ledges
## generated ahead, or the ring recycles ground the frog is still standing on:
## the floor vanishes underneath it, every polygon is reassigned each frame, and
## the body freezes in place. A portrait frame shows roughly ten tiers, and
## generate_above adds about seven more.
const MAX_SEGMENTS: int = 26

## Cap on spans generated per advance call, so the loop provably ends even if a
## caller asks for an absurd target.
const MAX_SPANS_PER_ADVANCE: int = MAX_SEGMENTS

## Beyond this fraction of the drift limit, a roll course is steered back toward
## the spawn height.
const DRIFT_CORRECTION_THRESHOLD: float = 0.6

var _tuning: LevelTuning
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _origin: Vector2 = Vector2.ZERO
var _x0: PackedFloat32Array = PackedFloat32Array()
var _x1: PackedFloat32Array = PackedFloat32Array()
var _y0: PackedFloat32Array = PackedFloat32Array()
var _y1: PackedFloat32Array = PackedFloat32Array()
var _written: int = 0


func _init(tuning: LevelTuning, origin: Vector2 = Vector2.ZERO) -> void:
	_tuning = tuning if tuning != null else LevelTuning.new()
	_origin = origin
	_x0.resize(MAX_SEGMENTS)
	_x1.resize(MAX_SEGMENTS)
	_y0.resize(MAX_SEGMENTS)
	_y1.resize(MAX_SEGMENTS)
	reset(0)


## Clears the shaft and reseeds it. A seed of 0 picks a random one; any other
## value reproduces a climb exactly, which is what the tests rely on.
func reset(seed_value: int) -> void:
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	_written = 0
	if _tuning.mode == LevelTuning.Mode.ROLL:
		# A flat runway: the first thing a player meets should be a roll they
		# can feel, not a hole they fall down before learning the kick.
		_push(_origin.x, _origin.x + maxf(_tuning.roll_start_runway, 1.0), _origin.y)
		return
	# The floor: a solid slab across the shaft, same reasoning.
	var half: float = _tuning.shaft_width * 0.5
	var floor_half: float = half * clampf(_tuning.floor_width_ratio, 0.05, 1.0)
	_push(_origin.x - floor_half, _origin.x + floor_half, _origin.y)


## Where the frog starts: on top of the floor, in the middle of the shaft.
func start_point() -> Vector2:
	return _origin


func shaft_left() -> float:
	return _origin.x - _tuning.shaft_width * 0.5


func shaft_right() -> float:
	return _origin.x + _tuning.shaft_width * 0.5


## Live ledge count, oldest (lowest) first. Never exceeds MAX_SEGMENTS.
func segment_count() -> int:
	return mini(_written, MAX_SEGMENTS)


## Left-hand end of ledge [param index], 0 being the lowest still live.
func segment_start(index: int) -> Vector2:
	var slot: int = _slot(index)
	return Vector2(_x0[slot], _y0[slot]) if slot >= 0 else Vector2.ZERO


## Right-hand end of ledge [param index].
func segment_end(index: int) -> Vector2:
	var slot: int = _slot(index)
	return Vector2(_x1[slot], _y1[slot]) if slot >= 0 else Vector2.ZERO


## Height of the highest ledge built so far. Smaller y is higher up.
func frontier_y() -> float:
	return _y1[_slot(segment_count() - 1)] if _written > 0 else _origin.y


## True when this plan is building a vertical shaft rather than a roll course.
func climbing() -> bool:
	return _tuning.mode == LevelTuning.Mode.CLIMB


## Builds upward until the shaft reaches [param target_y]. Bounded by
## MAX_SPANS_PER_ADVANCE, so it always terminates. CLIMB only.
func advance_above(target_y: float) -> void:
	var spans: int = 0
	while frontier_y() > target_y and spans < MAX_SPANS_PER_ADVANCE:
		_generate_one()
		spans += 1


## Builds rightward until the course reaches [param target_x]. Bounded the same
## way. ROLL only.
func advance_beyond(target_x: float) -> void:
	var spans: int = 0
	while frontier_x() < target_x and spans < MAX_SPANS_PER_ADVANCE:
		_generate_roll_span()
		spans += 1


## Right-hand edge of the course built so far. ROLL only.
func frontier_x() -> float:
	return _x1[_slot(segment_count() - 1)] if _written > 0 else _origin.x


## Advances whichever axis this mode runs along, keeping [param here] covered.
func advance_for(here: Vector2) -> void:
	if climbing():
		advance_above(here.y - _tuning.generate_above)
	else:
		advance_beyond(here.x + _tuning.roll_generate_ahead)


## Lowest surface anywhere near [param x], used to trail the kill plane under a
## roll course instead of pinning it to a fixed height. ROLL only.
func lowest_surface_near(x: float, half_width: float) -> float:
	var lowest: float = -INF
	var anywhere: float = -INF
	for index: int in range(segment_count()):
		var a: Vector2 = segment_start(index)
		var b: Vector2 = segment_end(index)
		anywhere = maxf(anywhere, maxf(a.y, b.y))
		if b.x >= x - half_width and a.x <= x + half_width:
			lowest = maxf(lowest, maxf(a.y, b.y))
	if lowest > -INF:
		return lowest
	return anywhere if anywhere > -INF else _origin.y


## Lowest live ledge (largest y). The run ends when the frog falls well below
## this, since everything under it has already been recycled.
func lowest_surface_y() -> float:
	var lowest: float = -INF
	for index: int in range(segment_count()):
		lowest = maxf(lowest, segment_start(index).y)
	return lowest if lowest > -INF else _origin.y


# --- generation ------------------------------------------------------------


func _generate_one() -> void:
	var width: float = _rng.randf_range(_tuning.ledge_min_width, _tuning.ledge_max_width)
	var span: float = _tuning.shaft_width - width
	if span <= 0.0:
		# A ledge wider than the shaft can only span the whole thing.
		_push(shaft_left(), shaft_right(), frontier_y() - _next_rise())
		return

	var previous_centre: float = _centre_of(segment_count() - 1)
	var reach: float = _tuning.shaft_width * _tuning.max_lateral_step
	var low: float = shaft_left() + width * 0.5
	var high: float = shaft_right() - width * 0.5

	var centre: float
	if _rng.randf() < _tuning.alternate_chance:
		# Cross to the far side, so the climb zig-zags and the wall bounce and
		# the forward launch both stay useful.
		var far: float = high if previous_centre < _origin.x else low
		centre = clampf(far, previous_centre - reach, previous_centre + reach)
	else:
		centre = _rng.randf_range(previous_centre - reach, previous_centre + reach)
	centre = clampf(centre, low, high)

	var next_y: float = frontier_y() - _next_rise()
	_push(centre - width * 0.5, centre + width * 0.5, next_y)


## One span of roll course: an optional gap, then a flat or a ramp.
func _generate_roll_span() -> void:
	var gap: float = 0.0
	var step: float = 0.0
	if _rng.randf() < _tuning.roll_gap_chance:
		gap = _rng.randf_range(_tuning.roll_gap_min, _tuning.roll_gap_max)
		step = _rng.randf_range(-_tuning.roll_step_max, _tuning.roll_step_max)

	var length: float = _rng.randf_range(_tuning.roll_span_min, _tuning.roll_span_max)
	var drop: float = 0.0
	if _rng.randf() < _tuning.roll_ramp_chance:
		drop = length * tan(deg_to_rad(_rng.randf_range(0.0, _tuning.roll_slope_max)))
		drop *= _drift_sign()

	var limit: float = maxf(_tuning.roll_drift_limit, 1.0)
	var start_x: float = frontier_x() + gap
	var start_y: float = clampf(frontier_y() + step, _origin.y - limit, _origin.y + limit)
	var end_y: float = clampf(start_y + drop, _origin.y - limit, _origin.y + limit)
	_push(start_x, start_x + length, start_y, end_y)


## +1 to slope downward, -1 upward, biased back toward the spawn height once the
## surface has wandered too far. Keeps an endless run from drifting off screen.
func _drift_sign() -> float:
	var limit: float = maxf(_tuning.roll_drift_limit, 1.0)
	var drift: float = frontier_y() - _origin.y
	if drift > limit * DRIFT_CORRECTION_THRESHOLD:
		return -1.0
	if drift < -limit * DRIFT_CORRECTION_THRESHOLD:
		return 1.0
	return 1.0 if _rng.randf() < 0.5 else -1.0


func _next_rise() -> float:
	return _rng.randf_range(
		minf(_tuning.rise_min, _tuning.rise_max), maxf(_tuning.rise_min, _tuning.rise_max)
	)


func _centre_of(index: int) -> float:
	if index < 0:
		return _origin.x
	return (segment_start(index).x + segment_end(index).x) * 0.5


func _push(left: float, right: float, height: float, right_height: float = INF) -> void:
	var slot: int = _written % MAX_SEGMENTS
	_x0[slot] = left
	_x1[slot] = maxf(right, left + 1.0)
	_y0[slot] = height
	_y1[slot] = height if is_inf(right_height) else right_height
	_written += 1


## Ring-buffer slot for [param index], counting from the lowest live ledge.
func _slot(index: int) -> int:
	var count: int = segment_count()
	if index < 0 or index >= count:
		return -1
	return (_written - count + index) % MAX_SEGMENTS
