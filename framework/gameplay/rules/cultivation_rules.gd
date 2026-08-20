class_name CultivationRules
extends RefCounted


static func max_hp(
	definition: ActorDefinition,
	state: ActorState,
	database: ContentDatabase
) -> int:
	if definition == null or state == null:
		return 1
	var result := definition.base_max_hp
	var realm := database.realm(state.realm_id) if database != null else null
	if realm != null:
		result += realm.max_hp_bonus(state.realm_layer)
	var foundation := database.foundation(state.foundation_id) if database != null else null
	if foundation != null:
		result += foundation.max_hp_bonus
	result += _equipment_bonus(state, database, &"max_hp_bonus")
	return maxi(result, 1)


static func max_mp(
	definition: ActorDefinition,
	state: ActorState,
	database: ContentDatabase
) -> int:
	if definition == null or state == null:
		return 0
	var result := definition.base_max_mp
	var realm := database.realm(state.realm_id) if database != null else null
	if realm != null:
		result += realm.max_mp_bonus(state.realm_layer)
	var foundation := database.foundation(state.foundation_id) if database != null else null
	if foundation != null:
		result += foundation.max_mp_bonus
	result += _equipment_bonus(state, database, &"max_mp_bonus")
	return maxi(result, 0)


static func attack(
	definition: ActorDefinition,
	state: ActorState,
	database: ContentDatabase
) -> int:
	if definition == null or state == null:
		return 0
	var result := definition.base_attack
	var realm := database.realm(state.realm_id) if database != null else null
	if realm != null:
		result += realm.attack_bonus(state.realm_layer)
	var foundation := database.foundation(state.foundation_id) if database != null else null
	if foundation != null:
		result += foundation.attack_bonus
	result += _equipment_bonus(state, database, &"attack_bonus")
	return maxi(result, 0)


static func gain_cultivation(
	state: ActorState,
	amount: int,
	database: ContentDatabase
) -> CultivationResult:
	var result := CultivationResult.new()
	if state == null:
		return result
	var realm := database.realm(state.realm_id) if database != null else null
	if realm == null:
		result.outcome = CultivationResult.Outcome.REALM_NOT_FOUND
		return result
	result.previous_realm_id = state.realm_id
	result.new_realm_id = state.realm_id
	result.previous_layer = state.realm_layer
	result.cultivation_gained = maxi(amount, 0)
	state.cultivation_points += result.cultivation_gained
	while state.realm_layer < realm.max_layer:
		var required := realm.cultivation_cost_for_layer(state.realm_layer)
		if required < 0 or state.cultivation_points < required:
			break
		state.cultivation_points -= required
		state.realm_layer += 1
		result.layers_gained += 1
	if state.realm_layer == realm.max_layer and realm.breakthrough_cultivation_required > 0:
		state.cultivation_points = mini(
			state.cultivation_points,
			realm.breakthrough_cultivation_required
		)
	result.new_layer = state.realm_layer
	result.outcome = CultivationResult.Outcome.SUCCEEDED
	return result


static func breakthrough(
	state: ActorState,
	foundation: DaoFoundationDefinition,
	database: ContentDatabase
) -> CultivationResult:
	var result := check_breakthrough(state, foundation, database)
	if not result.succeeded():
		return result
	var realm := database.realm(state.realm_id)
	state.realm_id = realm.next_realm.id
	state.realm_layer = 1
	state.cultivation_points = 0
	state.foundation_id = foundation.id
	for skill: SkillDefinition in foundation.granted_skills:
		if skill != null and skill.id not in state.skill_ids:
			state.skill_ids.append(skill.id)
	result.new_realm_id = state.realm_id
	result.new_layer = state.realm_layer
	return result


static func check_breakthrough(
	state: ActorState,
	foundation: DaoFoundationDefinition,
	database: ContentDatabase
) -> CultivationResult:
	var result := CultivationResult.new()
	if state == null:
		return result
	var realm := database.realm(state.realm_id) if database != null else null
	if realm == null:
		result.outcome = CultivationResult.Outcome.REALM_NOT_FOUND
		return result
	result.previous_realm_id = state.realm_id
	result.previous_layer = state.realm_layer
	if state.realm_layer != realm.max_layer:
		result.outcome = CultivationResult.Outcome.NOT_AT_MAX_LAYER
		return result
	if state.cultivation_points < realm.breakthrough_cultivation_required:
		result.outcome = CultivationResult.Outcome.INSUFFICIENT_CULTIVATION
		return result
	if realm.next_realm == null:
		result.outcome = CultivationResult.Outcome.NO_NEXT_REALM
		return result
	if foundation == null:
		result.outcome = CultivationResult.Outcome.FOUNDATION_REQUIRED
		return result
	if (
		database == null
		or not database.has_foundation(foundation.id)
		or foundation.required_realm != realm.next_realm
	):
		result.outcome = CultivationResult.Outcome.FOUNDATION_INVALID
		return result
	result.outcome = CultivationResult.Outcome.SUCCEEDED
	return result


static func is_ready_for_breakthrough(
	state: ActorState,
	database: ContentDatabase
) -> bool:
	if state == null or database == null:
		return false
	var realm := database.realm(state.realm_id)
	return (
		realm != null
		and realm.next_realm != null
		and state.realm_layer == realm.max_layer
		and state.cultivation_points >= realm.breakthrough_cultivation_required
	)


static func _equipment_bonus(
	state: ActorState,
	database: ContentDatabase,
	property: StringName
) -> int:
	if database == null:
		return 0
	var result := 0
	for item_id: StringName in state.equipment.values():
		var equipment := database.item(item_id) as EquipmentDefinition
		if equipment != null:
			result += int(equipment.get(property))
	return result
