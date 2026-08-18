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
var duration_msec: int = 0
var defeated_enemy_ids: Array[StringName] = []
var experience_reward: int = 0
var money_reward: int = 0
var dropped_item_id: StringName
var dropped_quantity: int = 0
var dropped_items: Dictionary[StringName, int] = {}
var rejected_dropped_items: Dictionary[StringName, int] = {}
var state_changes: Dictionary[StringName, Dictionary] = {}
var committed: bool = false


func is_victory() -> bool:
	return outcome == Outcome.VICTORY
