@tool
class_name GameRunContentValidator
extends RefCounted


static func validate(game_run: GameRun, database: ContentDatabase) -> PackedStringArray:
	var errors := PackedStringArray()
	if game_run == null:
		errors.append("GameRun is empty")
		return errors
	if not database.has_map(game_run.location.map_id):
		errors.append("GameRun references unknown map %s" % game_run.location.map_id)
	if game_run.party.members.is_empty():
		errors.append("GameRun party is empty")
	for actor_state: ActorState in game_run.party.members:
		var actor_definition := database.actor(actor_state.definition_id)
		if actor_definition == null:
			errors.append("GameRun references unknown actor %s" % actor_state.definition_id)
			continue
		var actor_realm := database.realm(actor_state.realm_id)
		if actor_realm == null:
			errors.append("ActorState %s references unknown realm %s" % [actor_state.definition_id, actor_state.realm_id])
		elif actor_state.realm_layer < 1 or actor_state.realm_layer > actor_realm.max_layer:
			errors.append("ActorState %s has invalid realm layer %d" % [actor_state.definition_id, actor_state.realm_layer])
		elif (
			actor_state.realm_layer == actor_realm.max_layer
			and actor_realm.breakthrough_cultivation_required > 0
			and actor_state.cultivation_points > actor_realm.breakthrough_cultivation_required
		):
			errors.append("ActorState %s exceeds breakthrough cultivation" % actor_state.definition_id)
		elif actor_state.realm_layer < actor_realm.max_layer and (
			actor_state.cultivation_points >= actor_realm.cultivation_cost_for_layer(actor_state.realm_layer)
		):
			errors.append("ActorState %s has uncommitted layer cultivation" % actor_state.definition_id)
		if not actor_state.foundation_id.is_empty():
			var actor_foundation := database.foundation(actor_state.foundation_id)
			if actor_foundation == null:
				errors.append("ActorState %s references unknown foundation %s" % [actor_state.definition_id, actor_state.foundation_id])
			elif actor_foundation.required_realm != actor_realm:
				errors.append("ActorState %s foundation does not match its realm" % actor_state.definition_id)
		var maximum_hp := CultivationRules.max_hp(actor_definition, actor_state, database)
		var maximum_mp := CultivationRules.max_mp(actor_definition, actor_state, database)
		if actor_state.hp > maximum_hp or actor_state.mp > maximum_mp:
			errors.append("ActorState %s exceeds its HP/MP limits" % actor_state.definition_id)
		for slot: StringName in actor_state.equipment:
			var equipment := database.item(actor_state.equipment[slot]) as EquipmentDefinition
			if (
				equipment == null
				or equipment.slot != slot
				or slot not in actor_definition.equipment_slots
			):
				errors.append(
					"ActorState %s has invalid equipment %s in slot %s"
					% [actor_state.definition_id, actor_state.equipment[slot], slot]
				)
		var learned_skills: Dictionary[StringName, bool] = {}
		for skill_id: StringName in actor_state.learned_skill_ids:
			if skill_id.is_empty() or learned_skills.has(skill_id):
				errors.append(
					"ActorState %s has an empty or repeated learned skill %s"
					% [actor_state.definition_id, skill_id]
				)
			elif not database.has_skill(skill_id):
				errors.append("ActorState %s references unknown skill %s" % [actor_state.definition_id, skill_id])
			learned_skills[skill_id] = true
		if actor_state.battle_skill_ids.size() != ActorState.BATTLE_SKILL_SLOT_COUNT:
			errors.append("ActorState %s must have exactly three battle skill slots" % actor_state.definition_id)
		else:
			var battle_skills: Dictionary[StringName, bool] = {}
			for skill_id: StringName in actor_state.battle_skill_ids:
				if skill_id.is_empty():
					continue
				var skill := database.skill(skill_id)
				if battle_skills.has(skill_id):
					errors.append("ActorState %s repeats battle skill %s" % [actor_state.definition_id, skill_id])
				elif not learned_skills.has(skill_id):
					errors.append("ActorState %s has unlearned battle skill %s" % [actor_state.definition_id, skill_id])
				elif skill == null or not skill.can_be_used_in_battle():
					errors.append("ActorState %s has invalid battle skill %s" % [actor_state.definition_id, skill_id])
				battle_skills[skill_id] = true
		if not actor_state.battle_item_id.is_empty():
			var battle_item := database.item(actor_state.battle_item_id)
			if battle_item == null or not battle_item.can_be_used_in_battle():
				errors.append(
					"ActorState %s has invalid battle item %s"
					% [actor_state.definition_id, actor_state.battle_item_id]
				)
	for item_id: StringName in game_run.inventory.item_ids():
		var definition := database.item(item_id)
		if definition == null:
			errors.append("InventoryState references unknown item %s" % item_id)
		elif game_run.inventory.quantity(item_id) > definition.max_stack:
			errors.append("InventoryState item %s exceeds max_stack" % item_id)
	if game_run.inventory.occupied_capacity() > game_run.inventory.max_distinct_items:
		errors.append("InventoryState exceeds max_distinct_items")
	return errors
