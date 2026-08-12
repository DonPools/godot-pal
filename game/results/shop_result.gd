class_name ShopResult
extends RefCounted

enum Outcome {
	CANCELLED,
	PURCHASED,
	INSUFFICIENT_FUNDS,
	INVENTORY_FULL,
}

var outcome: Outcome = Outcome.CANCELLED
var item_id: StringName
var quantity: int = 0
var money_delta: int = 0


func purchased() -> bool:
	return outcome == Outcome.PURCHASED
