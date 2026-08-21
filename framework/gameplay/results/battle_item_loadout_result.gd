class_name BattleItemLoadoutResult
extends RefCounted

enum Outcome {
	ASSIGNED,
	CLEARED,
	UNCHANGED,
	INVALID_ACTOR,
	INVALID_ITEM,
	ITEM_UNAVAILABLE,
	ITEM_NOT_USABLE_IN_BATTLE,
}

var outcome: Outcome = Outcome.INVALID_ITEM
var item_id: StringName
var previous_item_id: StringName


func succeeded() -> bool:
	return outcome in [Outcome.ASSIGNED, Outcome.CLEARED]
