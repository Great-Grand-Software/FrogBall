extends GutTest

## Tests for the GameState autoload.

func before_each() -> void:
	GameState.reset()


func after_all() -> void:
	GameState.reset()


func test_starts_at_zero() -> void:
	assert_eq(GameState.best_distance(), 0, "a fresh state has no record")


func test_a_longer_run_sets_the_record() -> void:
	assert_true(GameState.submit_distance(42), "42 m beats nothing")
	assert_eq(GameState.best_distance(), 42, "and is kept")


func test_a_shorter_run_does_not_lower_the_record() -> void:
	GameState.submit_distance(42)
	assert_false(GameState.submit_distance(10), "10 m does not beat 42")
	assert_eq(GameState.best_distance(), 42, "the record survives a bad run")


func test_beating_the_record_emits_the_signal() -> void:
	watch_signals(GameState)
	GameState.submit_distance(7)
	assert_signal_emitted_with_parameters(GameState, "best_distance_changed", [7])
