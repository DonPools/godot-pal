class_name ItemUseResult
extends RefCounted

enum Outcome {
	NOT_USABLE,
	NO_ITEM,
	NO_EFFECT,
	USED,
}

var outcome: Outcome = Outcome.NOT_USABLE
var item_id: StringName
var changed_amount: int = 0


func used() -> bool:
	return outcome == Outcome.USED
