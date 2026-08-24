extends SceneTree

## Headless tuning probe: plays the real scene under fixed policies and reports
## how HIGH each one climbs.
##
## Not part of the game and not part of CI. It exists because the questions this
## prototype has to answer — does timing read as skill, and how big should the
## frog be — are questions about gradients, and a gradient is easier to see in a
## table than in twenty minutes of playing.
##
## Run it with:
##   godot --headless --path . -s tools/tuning_probe.gd

const GAME_SCENE: String = "res://scenes/game.tscn"

## Fixed seeds, so a tuning change is the only thing that moves the numbers.
## The seed pins the course AND the frog's radius, so runs stay comparable.
const SEEDS: Array[int] = [11, 202, 3033, 40404, 555]

## Physics steps per run: thirty seconds at the default tick. Long enough for
## the climb to separate the policies, short enough that the whole sweep is
## worth running after a tuning change rather than being skipped.
const MAX_STEPS: int = 1800

## Steps a bot waits after jumping, so none of them hop continuously and all get
## the same chance to build speed between jumps.
const TAP_COOLDOWN_STEPS: int = 10

## Steps a bot holds the button before releasing. Comfortably a full press.
const HOLD_STEPS: int = 12

const POLICIES: Array[String] = ["never", "random", "neutral", "boost", "late"]

## Radii to sweep, px. Wide enough to bracket both failure modes: too small and
## the frog outspins the player, too large and it rolls over the level.
const SWEEP_RADII: Array[float] = [40.0, 52.0, 64.0, 76.0, 88.0, 104.0, 124.0]

## Steps before a bot is allowed its first press. Without this every bot spends
## its opening jump standing still on the spawn angle, then sits on cooldown
## through the first gap — which buries the difference between the policies.
const WARMUP_STEPS: int = 30

## Chance per step that the "random" bot presses. Roughly two presses a second.
const RANDOM_TAP_CHANCE: float = 0.03


func _initialize() -> void:
	await physics_frame
	await _report_policies()
	print("")
	await _report_radius_sweep()
	quit()


## Does timing beat not-timing? In a climber the shape differs from the roller:
## "neutral" (6 o'clock, straight up) is the honest climb jump, and "boost"
## (4:30) trades height for reach across the shaft. Both must beat "never" by a
## wide margin, and "late" must still be punished.
func _report_policies() -> void:
	print("== tap policy (radius randomised per seed) ==")
	print("policy   | median m | worst  | best   | note")
	print("---------|----------|--------|--------|-----")
	for policy: String in POLICIES:
		var runs: Array[float] = []
		for run_seed: int in SEEDS:
			var result: Dictionary = await _play(policy, run_seed, 0.0)
			runs.append(result["metres"])
		runs.sort()
		print("%-8s | %8.1f | %6.1f | %6.1f | %s" % [
			policy, runs[runs.size() / 2], runs[0], runs[-1], _note(policy)
		])


## Which frog is the right size? Same skilled policy at every radius, so the
## only variable is how fast the body spins for a given speed.
func _report_radius_sweep() -> void:
	print("== radius sweep (skilled play, radius pinned) ==")
	print("radius | median m | worst  | best")
	print("-------|----------|--------|------")
	for radius: float in SWEEP_RADII:
		var runs: Array[float] = []
		for run_seed: int in SEEDS:
			var result: Dictionary = await _play("boost", run_seed, radius)
			runs.append(result["metres"])
		runs.sort()
		print("%6.0f | %8.1f | %6.1f | %6.1f" % [
			radius, runs[runs.size() / 2], runs[0], runs[-1]
		])


func _note(policy: String) -> String:
	match policy:
		"never": return "baseline: no input at all"
		"random": return "mashing"
		"neutral": return "pressing at 6 o'clock — straight up, the climb jump"
		"boost": return "pressing near 4:30 — the forward launch"
		"late": return "pressing at the 3 o'clock edge — should be punished"
	return ""


## Plays one run. A [param pinned_radius] above zero disables the random roll,
## which is how the sweep isolates radius from everything else.
func _play(policy: String, run_seed: int, pinned_radius: float) -> Dictionary:
	var screen: Node2D = (load(GAME_SCENE) as PackedScene).instantiate()
	# Set up before add_child, because _ready() is what hands the tuning to the
	# frog. The resource is duplicated so one run cannot leak into the next.
	screen.frog_tuning = screen.frog_tuning.duplicate()
	screen.run_seed = run_seed
	if pinned_radius > 0.0:
		screen.frog_tuning.randomize_radius = false
		screen.frog_tuning.roll_radius = pinned_radius
	root.add_child(screen)
	screen.start_run()

	var frog: FrogBody = screen.get_node("%Frog")
	var origin: float = screen.terrain_plan().start_point().y
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	var highest: float = 0.0
	var cooldown: int = 0
	var holding: int = 0

	for step: int in range(MAX_STEPS):
		cooldown = maxi(cooldown - 1, 0)
		if step < WARMUP_STEPS:
			await physics_frame
			continue
		if holding > 0:
			holding -= 1
			if holding == 0:
				frog.release_tap()
		elif _wants_tap(policy, frog, rng, cooldown):
			frog.begin_tap()
			holding = HOLD_STEPS
			cooldown = TAP_COOLDOWN_STEPS + HOLD_STEPS
		await physics_frame
		highest = maxf(highest, origin - frog.global_position.y)
		if not screen.is_running():
			break

	var metres: float = highest / screen.pixels_per_metre
	screen.queue_free()
	return {"metres": metres}


## Where in the roll each bot decides to press. It presses on the angle it wants
## and holds for a fixed time, so the angle it releases on drifts a little —
## which is exactly what happens to a player who charges a jump.
func _wants_tap(policy: String, frog: FrogBody, rng: RandomNumberGenerator, cool: int) -> bool:
	if policy == "random":
		return rng.randf() < RANDOM_TAP_CHANCE
	if not frog.grounded or cool > 0:
		return false
	var phase: float = frog.feet_phase_deg()
	match policy:
		"neutral": return absf(phase) < 15.0
		"boost": return phase > 35.0 and phase < 60.0
		"late": return phase > 70.0
	return false
