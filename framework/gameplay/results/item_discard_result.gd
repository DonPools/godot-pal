class_name ItemDiscardResult
extends RefCounted

enum Outcome {
	DISCARDED,
	INVALID_ITEM,
	INVALID_QUANTITY,
	NOT_DISCARDABLE,
	INSUFFICIENT_QUANTITY,
}

var outcome: Outcome = Outcome.INVALID_ITEM
var item_id: StringName
var quantity: int = 0


func succeeded() -> bool:
	return outcome == Outcome.DISCARDED
