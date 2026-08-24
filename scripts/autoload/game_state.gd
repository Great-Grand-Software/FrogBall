extends Node

## Process-wide state, and the only autoload.
##
## Kept deliberately small: anything that is really screen state belongs on the
## screen. All that outlives a run here is the furthest the player has ever got
## — distance is the only score this prototype has, and there is no meta layer
## on top of it.

## Emitted after [method submit_distance] raises the record.
signal best_distance_changed(metres: int)

var _best_metres: int = 0


## Furthest distance reached, in whole metres, across every run this session.
func best_distance() -> int:
	return _best_metres


## Offers a finished run's distance. Keeps it only if it beats the record, and
## reports whether it did, so the screen can react without comparing itself.
func submit_distance(metres: int) -> bool:
	if metres <= _best_metres:
		return false
	_best_metres = metres
	best_distance_changed.emit(_best_metres)
	return true


## Resets the record. Exists for tests and for a future "new game".
func reset() -> void:
	_best_metres = 0
	best_distance_changed.emit(_best_metres)
