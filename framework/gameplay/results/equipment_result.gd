class_name EquipmentResult
extends RefCounted

enum Outcome {
	EQUIPPED,
	UNEQUIPPED,
	INVALID_ACTOR,
	INVALID_EQUIPMENT,
	ITEM_UNAVAILABLE,
	INVENTORY_REJECTED,
	ALREADY_EQUIPPED,
	SLOT_EMPTY,
	SLOT_NOT_ALLOWED,
}

var outcome: Outcome = Outcome.INVALID_EQUIPMENT
var slot: StringName
var equipped_item_id: StringName
var returned_item_id: StringName


func succeeded() -> bool:
	return outcome in [Outcome.EQUIPPED, Outcome.UNEQUIPPED]
