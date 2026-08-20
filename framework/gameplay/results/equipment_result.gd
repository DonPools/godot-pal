class_name EquipmentResult
extends RefCounted

enum Outcome {
	EQUIPPED,
	INVALID_ACTOR,
	INVALID_EQUIPMENT,
	ITEM_UNAVAILABLE,
	INVENTORY_REJECTED,
	ALREADY_EQUIPPED,
}

var outcome: Outcome = Outcome.INVALID_EQUIPMENT
var slot: StringName
var equipped_item_id: StringName
var returned_item_id: StringName


func succeeded() -> bool:
	return outcome == Outcome.EQUIPPED
