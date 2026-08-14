class_name BattleResult
extends RefCounted

enum Outcome {
	VICTORY,
	ESCAPED,
	DEFEAT,
	CANCELLED,
}

var outcome: Outcome = Outcome.CANCELLED
var encounter_id: StringName
var rounds: int = 0
var money_reward: int = 0
var dropped_item_id: StringName
var dropped_quantity: int = 0


func is_victory() -> bool:
	return outcome == Outcome.VICTORY
