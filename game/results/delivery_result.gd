class_name DeliveryResult
extends RefCounted

enum Outcome {
	INVALID,
	INSUFFICIENT_ITEMS,
	COMPLETED,
}

var outcome: Outcome = Outcome.INVALID
var item_id: StringName
var quantity: int = 0
var money_delta: int = 0


func completed() -> bool:
	return outcome == Outcome.COMPLETED
