class_name SkillLoadoutTransaction
extends RefCounted


static func assign(
	actor_state: ActorState,
	skill: SkillDefinition,
	slot_index: int,
	database: ContentDatabase
) -> SkillLoadoutResult:
	var result := SkillLoadoutResult.new()
	result.skill_id = skill.id if skill != null else &""
	result.slot_index = slot_index
	if actor_state == null:
		result.outcome = SkillLoadoutResult.Outcome.INVALID_ACTOR
		return result
	if slot_index < 0 or slot_index >= ActorState.BATTLE_SKILL_SLOT_COUNT:
		result.outcome = SkillLoadoutResult.Outcome.SLOT_OUT_OF_RANGE
		return result
	if (
		skill == null
		or database == null
		or database.skill(skill.id) != skill
	):
		return result
	if skill.id not in actor_state.learned_skill_ids:
		result.outcome = SkillLoadoutResult.Outcome.SKILL_NOT_LEARNED
		return result
	if not skill.usable_in_battle:
		result.outcome = SkillLoadoutResult.Outcome.SKILL_NOT_USABLE_IN_BATTLE
		return result
	var previous_slot := actor_state.battle_skill_ids.find(skill.id)
	result.previous_slot_index = previous_slot
	result.displaced_skill_id = actor_state.battle_skill_ids[slot_index]
	if previous_slot == slot_index:
		result.outcome = SkillLoadoutResult.Outcome.UNCHANGED
		return result
	if previous_slot >= 0:
		actor_state.battle_skill_ids[previous_slot] = &""
	actor_state.battle_skill_ids[slot_index] = skill.id
	result.outcome = SkillLoadoutResult.Outcome.ASSIGNED
	return result


static func clear(actor_state: ActorState, slot_index: int) -> SkillLoadoutResult:
	var result := SkillLoadoutResult.new()
	result.slot_index = slot_index
	if actor_state == null:
		result.outcome = SkillLoadoutResult.Outcome.INVALID_ACTOR
		return result
	if slot_index < 0 or slot_index >= ActorState.BATTLE_SKILL_SLOT_COUNT:
		result.outcome = SkillLoadoutResult.Outcome.SLOT_OUT_OF_RANGE
		return result
	result.skill_id = actor_state.battle_skill_ids[slot_index]
	if result.skill_id.is_empty():
		result.outcome = SkillLoadoutResult.Outcome.UNCHANGED
		return result
	actor_state.battle_skill_ids[slot_index] = &""
	result.outcome = SkillLoadoutResult.Outcome.CLEARED
	return result
