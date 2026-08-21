class_name SkillLearningTransaction
extends RefCounted


static func learn(
	actor_state: ActorState,
	skill: SkillDefinition,
	database: ContentDatabase
) -> SkillLearningResult:
	var result := SkillLearningResult.new()
	result.skill_id = skill.id if skill != null else &""
	if actor_state == null:
		result.outcome = SkillLearningResult.Outcome.INVALID_ACTOR
		return result
	if (
		skill == null
		or database == null
		or database.skill(skill.id) != skill
	):
		return result
	if skill.id in actor_state.learned_skill_ids:
		result.outcome = SkillLearningResult.Outcome.ALREADY_LEARNED
		return result
	actor_state.learned_skill_ids.append(skill.id)
	if skill.usable_in_battle:
		var empty_slot := actor_state.battle_skill_ids.find(&"")
		if empty_slot >= 0:
			actor_state.battle_skill_ids[empty_slot] = skill.id
			result.auto_equipped = true
			result.slot_index = empty_slot
	result.outcome = SkillLearningResult.Outcome.LEARNED
	return result
