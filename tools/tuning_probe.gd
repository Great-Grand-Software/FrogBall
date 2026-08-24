extends SceneTree

## Headless tuning probe: plays the real scene under fixed tap policies and
## reports how far each one gets.
##
## Not part of the game and not part of CI. It exists because the one question
## this prototype has to answer — does timing read as skill? — is a question
## about a gradient, and a gradient is easier to see in five numbers than in
## five minutes of playing. If "boost" stops beating "never" by a wide margin
## after a tuning change, the tuning change broke the game.
##
## Run it with:
##   godot --headless --path . -s tools/tuning_probe.gd

const GAME_SCENE: String = "res://scenes/game.tscn"

## Fixed seeds, so a tuning change is the only thing that moves the numbers.
const SEEDS: Array[int] = [11, 202, 3033, 40404, 555]

## Physics steps per run: sixty seconds at the default tick.
const MAX_STEPS: int = 3600

## Steps a bot waits after jumping, so none of them hop continuously and all of
## them get the same chance to build speed between jumps.
const TAP_COOLDOWN_STEPS: int = 40

const POLICIES: Array[String] = ["never", "random", "neutral", "boost", "late"]

## Chance per step that the "random" bot taps. Roughly two taps a second.
const RANDOM_TAP_CHANCE: float = 0.03


func _initialize() -> void:
	await physics_frame
	print("policy   | median m | worst  | best   | jumps | note")
	print("---------|----------|--------|--------|-------|-----")
	for policy: String in POLICIES:
		var runs: Array[float] = []
		var jumps: int = 0
		for run_seed: int in SEEDS:
			var result: Dictionary = await _play(policy, run_seed)
			runs.append(result["metres"])
			jumps += int(result["jumps"])
		runs.sort()
		print("%-8s | %8.1f | %6.1f | %6.1f | %5d | %s" % [
			policy, runs[runs.size() / 2], runs[0], runs[-1], jumps, _note(policy)
		])
	quit()


func _note(policy: String) -> String:
	match policy:
		"never": return "baseline: no input at all"
		"random": return "mashing"
		"neutral": return "tapping at 6 o'clock, untimed"
		"boost": return "tapping near 4:30 — should win by a lot"
		"late": return "tapping at the 3 o'clock edge — should be punished"
	return ""


func _play(policy: String, run_seed: int) -> Dictionary:
	var screen: Node2D = (load(GAME_SCENE) as PackedScene).instantiate()
	root.add_child(screen)
	screen.run_seed = run_seed
	screen.start_run()

	var frog: FrogBody = screen.get_node("%Frog")
	var origin: float = screen.terrain_plan().start_point().x
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	var furthest: float = 0.0
	var jumps: int = 0
	var cooldown: int = 0

	for step: int in range(MAX_STEPS):
		cooldown = maxi(cooldown - 1, 0)
		if _wants_tap(policy, frog, rng, cooldown):
			frog.queue_tap()
			cooldown = TAP_COOLDOWN_STEPS
			jumps += 1
		await physics_frame
		furthest = maxf(furthest, frog.global_position.x - origin)
		if not screen.is_running():
			break

	screen.queue_free()
	return {"metres": furthest / screen.pixels_per_metre, "jumps": jumps}


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
