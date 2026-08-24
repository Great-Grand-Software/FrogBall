extends SceneTree

## Headless tuning probe: plays the real scene under fixed aim policies and
## reports how far each one gets.
##
## Not part of the game and not part of CI. It exists because the question the
## prototype has to answer — does deliberate input beat flailing? — is a
## question about a gradient, and a gradient is easier to see in a table than in
## twenty minutes of playing.
##
## Run it with:
##   godot --headless --path . -s tools/tuning_probe.gd

const GAME_SCENE: String = "res://scenes/game.tscn"

## Fixed seeds, so a tuning change is the only thing that moves the numbers.
const SEEDS: Array[int] = [11, 202, 3033, 40404, 555]

## Physics steps per run: thirty seconds at the default tick.
const MAX_STEPS: int = 1800

## Steps a bot waits between kicks, on top of the game's own cooldown.
const KICK_SPACING_STEPS: int = 6

## Steps before a bot takes its first kick.
const WARMUP_STEPS: int = 20

const POLICIES: Array[String] = ["never", "random", "always_up", "recover", "aimed"]


func _initialize() -> void:
	await physics_frame
	for mode: int in [LevelTuning.Mode.CLIMB, LevelTuning.Mode.ROLL]:
		await _report(mode)
		print("")
	quit()


func _report(mode: int) -> void:
	print("== %s ==" % ("CLIMB (score is height)" if mode == 0 else "ROLL (score is distance)"))
	print("policy    | median m | worst  | best   | note")
	print("----------|----------|--------|--------|-----")
	for policy: String in POLICIES:
		var runs: Array[float] = []
		for run_seed: int in SEEDS:
			runs.append(await _play(policy, run_seed, mode))
		runs.sort()
		print("%-9s | %8.1f | %6.1f | %6.1f | %s" % [
			policy, runs[runs.size() / 2], runs[0], runs[-1], _note(policy)
		])


func _note(policy: String) -> String:
	match policy:
		"never": return "no input at all"
		"random": return "flailing: full-power drags in random directions"
		"always_up": return "always drag down, i.e. always kick straight up"
		"recover": return "kick up only when falling — economical"
		"aimed": return "kick against whatever way it is drifting wrong"
	return ""


## Plays one run and returns the best score it reached, in metres.
func _play(policy: String, run_seed: int, mode: int) -> float:
	var screen: Node2D = (load(GAME_SCENE) as PackedScene).instantiate()
	# Duplicated so one run cannot leak tuning into the next, and set before
	# add_child because _ready() is what hands the tuning to the ball.
	screen.level_tuning = screen.level_tuning.duplicate()
	screen.level_tuning.mode = mode
	screen.run_seed = run_seed
	root.add_child(screen)
	screen.start_run()

	var frog: FrogBody = screen.get_node("%Frog")
	var origin: Vector2 = screen.terrain_plan().start_point()
	var climbing: bool = screen.terrain_plan().climbing()
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	var best: float = 0.0
	var spacing: int = 0

	for step: int in range(MAX_STEPS):
		spacing = maxi(spacing - 1, 0)
		if step > WARMUP_STEPS and spacing == 0 and frog.can_kick():
			var drag: Vector2 = _drag_for(policy, frog, rng, screen)
			if drag != Vector2.ZERO:
				frog.kick(drag)
				spacing = KICK_SPACING_STEPS
		await physics_frame
		var travelled: float = origin.y - frog.global_position.y if climbing \
			else frog.global_position.x - origin.x
		best = maxf(best, travelled)
		if not screen.is_running():
			break

	var metres: float = best / screen.pixels_per_metre
	screen.queue_free()
	return snappedf(metres, 0.1)


## What each bot drags, in viewport pixels. Remember the inversion: the drag
## direction is where the arrow points, and the ball goes the OTHER way.
func _drag_for(
	policy: String, frog: FrogBody, rng: RandomNumberGenerator, screen: Node2D
) -> Vector2:
	var full: float = screen.frog_tuning.max_drag_px
	var velocity: Vector2 = frog.linear_velocity
	var drag := Vector2.ZERO
	match policy:
		"random":
			drag = Vector2.RIGHT.rotated(rng.randf() * TAU) * full
		"always_up":
			drag = Vector2.DOWN * full
		"recover":
			# Only spend a kick when actually falling. Tests whether economy
			# beats spamming, which is what the cooldown is meant to reward.
			if velocity.y > 250.0:
				drag = Vector2.DOWN * full
		"aimed":
			# Push back against whatever is going wrong: up when falling,
			# sideways when about to leave the shaft.
			if velocity.y > 250.0:
				drag = Vector2.DOWN * full
			elif absf(velocity.x) > 260.0:
				drag = Vector2(signf(velocity.x), 0.0) * full
	return drag
