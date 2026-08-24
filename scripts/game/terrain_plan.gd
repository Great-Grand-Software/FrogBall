class_name TerrainPlan
extends RefCounted

## The climbing shaft, as data. No nodes, so it unit-tests without a scene.
##
## A run goes upward through a stack of horizontal ledges inside a walled
## column. Each ledge is a span; the emptiness between them is what forces a
## jump. Ledges are placed so the next one is always within reach both
## vertically and sideways — a generator that can emit an unreachable tier
## produces runs that end for reasons the player cannot see or avoid.
##
## Ledges live in a fixed-size ring buffer. That is the guardrail from CLAUDE.md
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

## Cap on ledges generated per advance_above() call, so the loop provably ends
## even if a caller asks for an absurd target.
const MAX_SPANS_PER_ADVANCE: int = MAX_SEGMENTS

var _tuning: LevelTuning
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _origin: Vector2 = Vector2.ZERO
var _x0: PackedFloat32Array = PackedFloat32Array()
var _x1: PackedFloat32Array = PackedFloat32Array()
var _y: PackedFloat32Array = PackedFloat32Array()
var _written: int = 0


func _init(tuning: LevelTuning, origin: Vector2 = Vector2.ZERO) -> void:
	_tuning = tuning if tuning != null else LevelTuning.new()
	_origin = origin
	_x0.resize(MAX_SEGMENTS)
	_x1.resize(MAX_SEGMENTS)
	_y.resize(MAX_SEGMENTS)
	reset(0)


## Clears the shaft and reseeds it. A seed of 0 picks a random one; any other
## value reproduces a climb exactly, which is what the tests rely on.
func reset(seed_value: int) -> void:
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	_written = 0
	# The floor: a solid slab across the shaft, so a run opens with a roll the
	# player can feel rather than a jump they have not learned yet.
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
	return Vector2(_x0[slot], _y[slot]) if slot >= 0 else Vector2.ZERO


## Right-hand end of ledge [param index].
func segment_end(index: int) -> Vector2:
	var slot: int = _slot(index)
	return Vector2(_x1[slot], _y[slot]) if slot >= 0 else Vector2.ZERO


## Height of the highest ledge built so far. Smaller y is higher up.
func frontier_y() -> float:
	return _y[_slot(segment_count() - 1)] if _written > 0 else _origin.y


## Builds upward until the shaft reaches [param target_y]. Bounded by
## MAX_SPANS_PER_ADVANCE, so it always terminates.
func advance_above(target_y: float) -> void:
	var spans: int = 0
	while frontier_y() > target_y and spans < MAX_SPANS_PER_ADVANCE:
		_generate_one()
		spans += 1


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


func _next_rise() -> float:
	return _rng.randf_range(
		minf(_tuning.rise_min, _tuning.rise_max), maxf(_tuning.rise_min, _tuning.rise_max)
	)


func _centre_of(index: int) -> float:
	if index < 0:
		return _origin.x
	return (segment_start(index).x + segment_end(index).x) * 0.5


func _push(left: float, right: float, height: float) -> void:
	var slot: int = _written % MAX_SEGMENTS
	_x0[slot] = left
	_x1[slot] = maxf(right, left + 1.0)
	_y[slot] = height
	_written += 1


## Ring-buffer slot for [param index], counting from the lowest live ledge.
func _slot(index: int) -> int:
	var count: int = segment_count()
	if index < 0 or index >= count:
		return -1
	return (_written - count + index) % MAX_SEGMENTS
