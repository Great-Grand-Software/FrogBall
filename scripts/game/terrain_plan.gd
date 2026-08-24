class_name TerrainPlan
extends RefCounted

## The endless terrain, as data. No nodes, so it unit-tests without a scene.
##
## The surface is a heightfield of straight spans. A gap is simply the absence
## of a span between one segment's end and the next one's start, which is what
## makes a jump mandatory rather than optional.
##
## Segments live in a fixed-size ring buffer. That is the guardrail from
## CLAUDE.md section 4 made structural rather than remembered: an endless runner
## cannot leak segments if the oldest is overwritten by construction, and the
## node pool that renders it is sized from the same constant.

## The flavours of span the generator can emit.
enum Kind {FLAT, DOWNHILL, UPHILL, GAP_STEP, STAIRS}

## Hard ceiling on live segments. The collision-polygon pool is sized from this,
## so raising it raises the node count — see the 64-node ceiling.
const MAX_SEGMENTS: int = 20

## Cap on spans generated per advance_to() call, so the loop provably ends even
## if a caller asks for an absurd target.
const MAX_SPANS_PER_ADVANCE: int = MAX_SEGMENTS

## Beyond this fraction of the drift limit, steps are biased back toward centre.
const DRIFT_CORRECTION_THRESHOLD: float = 0.6

var _tuning: LevelTuning
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _start: Vector2 = Vector2.ZERO
var _x0: PackedFloat32Array = PackedFloat32Array()
var _y0: PackedFloat32Array = PackedFloat32Array()
var _x1: PackedFloat32Array = PackedFloat32Array()
var _y1: PackedFloat32Array = PackedFloat32Array()
var _written: int = 0
var _stairs_left: int = 0
var _stair_rise: float = 0.0
var _weights: PackedFloat32Array = PackedFloat32Array()


func _init(tuning: LevelTuning, start_point: Vector2 = Vector2.ZERO) -> void:
	_tuning = tuning if tuning != null else LevelTuning.new()
	_start = start_point
	_x0.resize(MAX_SEGMENTS)
	_y0.resize(MAX_SEGMENTS)
	_x1.resize(MAX_SEGMENTS)
	_y1.resize(MAX_SEGMENTS)
	_weights.resize(Kind.size())
	reset(0)


## Clears the terrain and reseeds it. A seed of 0 picks a random one, so runs
## differ; any other value reproduces a run exactly, which is what the tests use.
func reset(seed_value: int) -> void:
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	_written = 0
	_stairs_left = 0
	_stair_rise = 0.0
	# The opening runway is flat and unbroken: the first thing the player meets
	# should be a roll they can feel, not a hole they fall down. It also starts
	# BEHIND the spawn point, so a first tap that happens to launch backward
	# lands on ground instead of dropping the player off the back of the world.
	var behind: float = maxf(_tuning.start_runway_behind, 0.0)
	_push_at(
		_start.x - behind, _start.y, behind + maxf(_tuning.start_runway_length, 1.0), 0.0
	)


## Where the frog starts, on top of the opening runway.
func start_point() -> Vector2:
	return _start


## Live segment count, oldest first. Never exceeds MAX_SEGMENTS.
func segment_count() -> int:
	return mini(_written, MAX_SEGMENTS)


## Left-hand end of segment [param index], 0 being the oldest still live.
func segment_start(index: int) -> Vector2:
	var slot: int = _slot(index)
	return Vector2(_x0[slot], _y0[slot]) if slot >= 0 else Vector2.ZERO


## Right-hand end of segment [param index].
func segment_end(index: int) -> Vector2:
	var slot: int = _slot(index)
	return Vector2(_x1[slot], _y1[slot]) if slot >= 0 else Vector2.ZERO


## Right-hand edge of the terrain built so far.
func frontier_x() -> float:
	return _x1[_slot(segment_count() - 1)] if _written > 0 else _start.x


## Builds terrain until it reaches [param target_x]. Bounded by
## MAX_SPANS_PER_ADVANCE, so it always terminates.
func advance_to(target_x: float) -> void:
	var spans: int = 0
	while frontier_x() < target_x and spans < MAX_SPANS_PER_ADVANCE:
		_generate_one()
		spans += 1


## Lowest surface point (largest y) anywhere in [param from_x]..[param to_x],
## used to trail the kill plane below the terrain instead of pinning it to a
## fixed height. Falls back to the lowest live point when the span is over a gap.
func lowest_surface_y(from_x: float, to_x: float) -> float:
	var lowest: float = -INF
	var lowest_anywhere: float = -INF
	for index: int in range(segment_count()):
		var a: Vector2 = segment_start(index)
		var b: Vector2 = segment_end(index)
		lowest_anywhere = maxf(lowest_anywhere, maxf(a.y, b.y))
		if b.x >= from_x and a.x <= to_x:
			lowest = maxf(lowest, maxf(a.y, b.y))
	if lowest > -INF:
		return lowest
	return lowest_anywhere if lowest_anywhere > -INF else _start.y


# --- generation ------------------------------------------------------------


func _generate_one() -> void:
	if _stairs_left > 0:
		_stairs_left -= 1
		_push(
			_rng.randf_range(_tuning.stair_gap_min, _tuning.stair_gap_max),
			_stair_rise,
			_rng.randf_range(_tuning.stair_tread_min, _tuning.stair_tread_max),
			0.0
		)
		return

	var length: float = 0.0
	var slope: float = 0.0
	match _pick_kind():
		Kind.DOWNHILL:
			length = _rng.randf_range(_tuning.ramp_min_length, _tuning.ramp_max_length)
			slope = _rng.randf_range(
				_tuning.downhill_min_slope_deg, _tuning.downhill_max_slope_deg
			)
			_push(0.0, 0.0, length, length * tan(deg_to_rad(slope)))
		Kind.UPHILL:
			length = _rng.randf_range(_tuning.ramp_min_length, _tuning.ramp_max_length)
			slope = _rng.randf_range(
				_tuning.uphill_min_slope_deg, _tuning.uphill_max_slope_deg
			)
			_push(0.0, 0.0, length, -length * tan(deg_to_rad(slope)))
		Kind.GAP_STEP:
			_push(
				_rng.randf_range(_tuning.gap_min_width, _tuning.gap_max_width),
				_rng.randf_range(_tuning.step_min_rise, _tuning.step_max_rise) * _step_direction(),
				_rng.randf_range(_tuning.flat_min_length, _tuning.flat_max_length),
				0.0
			)
		Kind.STAIRS:
			# One tier now, the rest queued. The queue is capped by the tuning
			# range and by MAX_SEGMENTS, never by anything data-driven.
			var count: int = _rng.randi_range(
				maxi(_tuning.stair_min_count, 1), maxi(_tuning.stair_max_count, 1)
			)
			_stairs_left = mini(count, MAX_SEGMENTS) - 1
			_stair_rise = _rng.randf_range(_tuning.stair_rise_min, _tuning.stair_rise_max)
			_stair_rise *= _step_direction()
			_push(
				_rng.randf_range(_tuning.stair_gap_min, _tuning.stair_gap_max),
				_stair_rise,
				_rng.randf_range(_tuning.stair_tread_min, _tuning.stair_tread_max),
				0.0
			)
		_:
			_push(0.0, 0.0, _rng.randf_range(_tuning.flat_min_length, _tuning.flat_max_length), 0.0)


func _pick_kind() -> int:
	_weights[Kind.FLAT] = maxf(_tuning.weight_flat, 0.0)
	_weights[Kind.DOWNHILL] = maxf(_tuning.weight_downhill, 0.0)
	_weights[Kind.UPHILL] = maxf(_tuning.weight_uphill, 0.0)
	_weights[Kind.GAP_STEP] = maxf(_tuning.weight_gap_step, 0.0)
	_weights[Kind.STAIRS] = maxf(_tuning.weight_stairs, 0.0)
	var total: float = 0.0
	for weight: float in _weights:
		total += weight
	if total <= 0.0:
		return Kind.FLAT
	var roll: float = _rng.randf() * total
	for index: int in range(_weights.size()):
		roll -= _weights[index]
		if roll <= 0.0:
			return index
	return Kind.FLAT


## +1 to step up, -1 to step down. Random in the middle of the band, forced
## back toward the spawn height once the surface has drifted too far.
func _step_direction() -> float:
	var drift: float = _start.y - frontier_y()
	var limit: float = maxf(_tuning.vertical_drift_limit, 1.0)
	if drift > limit * DRIFT_CORRECTION_THRESHOLD:
		return -1.0
	if drift < -limit * DRIFT_CORRECTION_THRESHOLD:
		return 1.0
	return 1.0 if _rng.randf() < _tuning.step_up_chance else -1.0


func frontier_y() -> float:
	return _y1[_slot(segment_count() - 1)] if _written > 0 else _start.y


## Appends one span: a [param gap] of empty air, a vertical [param rise] at the
## far side of it, then a surface [param length] long that falls by [param drop].
func _push(gap: float, rise: float, length: float, drop: float) -> void:
	_push_at(frontier_x() + maxf(gap, 0.0), frontier_y() - rise, length, drop)


## Appends a span at an explicit start point. Only the opening runway needs
## this; everything after it grows from the frontier.
func _push_at(start_x: float, unclamped_y: float, length: float, drop: float) -> void:
	var limit: float = maxf(_tuning.vertical_drift_limit, 1.0)
	var start_y: float = clampf(unclamped_y, _start.y - limit, _start.y + limit)
	var end_y: float = clampf(start_y + drop, _start.y - limit, _start.y + limit)
	var slot: int = _written % MAX_SEGMENTS
	_x0[slot] = start_x
	_y0[slot] = start_y
	_x1[slot] = start_x + maxf(length, 1.0)
	_y1[slot] = end_y
	_written += 1


## Ring-buffer slot for [param index], counting from the oldest live segment.
func _slot(index: int) -> int:
	var count: int = segment_count()
	if index < 0 or index >= count:
		return -1
	return (_written - count + index) % MAX_SEGMENTS
