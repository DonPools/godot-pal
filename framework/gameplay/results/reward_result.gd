class_name RewardResult
extends RefCounted

enum FailureReason {
	NONE,
	INVALID_QUANTITY,
	INVENTORY_FULL,
	INSUFFICIENT_QUANTITY,
}

var item_id: StringName
var requested_quantity: int = 0
var changed_quantity: int = 0
var rejected_quantity: int = 0
var failure_reason: FailureReason = FailureReason.NONE


func succeeded() -> bool:
	return changed_quantity > 0 and rejected_quantity == 0


func changed() -> bool:
	return changed_quantity > 0
