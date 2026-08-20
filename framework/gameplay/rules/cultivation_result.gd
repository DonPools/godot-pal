class_name CultivationResult
extends RefCounted

enum Outcome {
	SUCCEEDED,
	INVALID_ACTOR,
	REALM_NOT_FOUND,
	NOT_AT_MAX_LAYER,
	INSUFFICIENT_CULTIVATION,
	NO_NEXT_REALM,
	FOUNDATION_REQUIRED,
	FOUNDATION_INVALID,
	CATALYST_REQUIRED,
}

var outcome: Outcome = Outcome.INVALID_ACTOR
var previous_realm_id: StringName
var new_realm_id: StringName
var previous_layer: int = 0
var new_layer: int = 0
var cultivation_gained: int = 0
var layers_gained: int = 0


func succeeded() -> bool:
	return outcome == Outcome.SUCCEEDED
