class_name SkillLearningResult
extends RefCounted

enum Outcome {
	LEARNED,
	ALREADY_LEARNED,
	INVALID_ACTOR,
	INVALID_SKILL,
}

var outcome: Outcome = Outcome.INVALID_SKILL
var skill_id: StringName
var auto_equipped: bool = false
var slot_index: int = -1


func succeeded() -> bool:
	return outcome == Outcome.LEARNED
