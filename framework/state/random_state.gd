class_name RandomState
extends RefCounted

const DEFAULT_SEED := 20_260_814

var seed: int = DEFAULT_SEED
var draw_count: int = 0
var _state: int = 0


func _init() -> void:
	initialize(DEFAULT_SEED)


func initialize(seed_value: int) -> void:
	seed = seed_value
	draw_count = 0
	var generator := RandomNumberGenerator.new()
	generator.seed = seed
	_state = generator.state


func roll_percent(chance: int) -> bool:
	if chance <= 0:
		return false
	if chance >= 100:
		return true
	var generator := RandomNumberGenerator.new()
	generator.state = _state
	var result := generator.randi_range(1, 100) <= chance
	_state = generator.state
	draw_count += 1
	return result


func to_dictionary() -> Dictionary:
	# Store 64-bit RNG values as strings so JSON cannot round them through a float.
	return {
		"seed": str(seed),
		"state": str(_state),
		"draw_count": draw_count,
	}


func restore(data: Dictionary) -> bool:
	var raw_seed: Variant = data.get("seed")
	var raw_state: Variant = data.get("state")
	var restored_draw_count := int(data.get("draw_count", -1))
	if (
		not _is_stored_int(raw_seed)
		or not _is_stored_int(raw_state)
		or restored_draw_count < 0
	):
		return false
	seed = int(raw_seed)
	_state = int(raw_state)
	draw_count = restored_draw_count
	return true


func _is_stored_int(value: Variant) -> bool:
	return value is int or (value is String and String(value).is_valid_int())
