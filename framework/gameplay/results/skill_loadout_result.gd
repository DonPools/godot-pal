class_name SkillLoadoutResult
extends RefCounted

enum Outcome {
	ASSIGNED,
	CLEARED,
	UNCHANGED,
	INVALID_ACTOR,
	INVALID_SKILL,
	SKILL_NOT_LEARNED,
	SKILL_NOT_USABLE_IN_BATTLE,
	SLOT_OUT_OF_RANGE,
}

var outcome: Outcome = Outcome.INVALID_SKILL
var skill_id: StringName
var slot_index: int = -1
var previous_slot_index: int = -1
var displaced_skill_id: StringName


func succeeded() -> bool:
	return outcome in [Outcome.ASSIGNED, Outcome.CLEARED]
