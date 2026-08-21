class_name ActorState
extends RefCounted

const BATTLE_SKILL_SLOT_COUNT := 3

var definition_id: StringName
var realm_id: StringName
var realm_layer: int = 1
var cultivation_points: int = 0
var foundation_id: StringName
var hp: int = 1
var mp: int = 0
var equipment: Dictionary[StringName, StringName] = {}
var learned_skill_ids: Array[StringName] = []
var battle_skill_ids: Array[StringName] = [&"", &"", &""]
var battle_item_id: StringName


static func from_definition(definition: ActorDefinition) -> ActorState:
	var state := ActorState.new()
	state.definition_id = definition.id
	state.realm_id = definition.initial_realm.id if definition.initial_realm != null else &""
	state.realm_layer = definition.initial_realm_layer
	state.cultivation_points = definition.initial_cultivation_points
	state.foundation_id = (
		definition.initial_foundation.id
		if definition.initial_foundation != null
		else &""
	)
	state.hp = definition.base_max_hp
	state.mp = definition.base_max_mp
	for item: EquipmentDefinition in definition.initial_equipment:
		if item != null and not item.slot.is_empty():
			state.equipment[item.slot] = item.id
	for skill: SkillDefinition in definition.initial_skills:
		if skill == null or skill.id in state.learned_skill_ids:
			continue
		state.learned_skill_ids.append(skill.id)
		if skill.can_be_used_in_battle():
			var empty_slot := state.battle_skill_ids.find(&"")
			if empty_slot >= 0:
				state.battle_skill_ids[empty_slot] = skill.id
	return state


func heal(amount: int, maximum: int) -> int:
	var previous := hp
	hp = clampi(hp + maxi(amount, 0), 0, maxi(maximum, 1))
	return hp - previous


func restore_mp(amount: int, maximum: int) -> int:
	var previous := mp
	mp = clampi(mp + maxi(amount, 0), 0, maxi(maximum, 0))
	return mp - previous


func take_damage(amount: int) -> int:
	var previous := hp
	hp = maxi(hp - maxi(amount, 0), 0)
	return previous - hp


func spend_mp(amount: int) -> bool:
	if amount < 0 or mp < amount:
		return false
	mp -= amount
	return true


func to_dictionary() -> Dictionary:
	var raw_equipment: Dictionary = {}
	for slot: StringName in equipment:
		raw_equipment[String(slot)] = String(equipment[slot])
	return {
		"definition_id": String(definition_id),
		"realm_id": String(realm_id),
		"realm_layer": realm_layer,
		"cultivation_points": cultivation_points,
		"foundation_id": String(foundation_id),
		"hp": hp,
		"mp": mp,
		"equipment": raw_equipment,
		"learned_skill_ids": _string_names(learned_skill_ids),
		"battle_skill_ids": _string_names(battle_skill_ids),
		"battle_item_id": String(battle_item_id),
	}


static func from_dictionary(
	data: Dictionary,
	fallback_definition: ActorDefinition = null,
	database: ContentDatabase = null
) -> ActorState:
	var raw_id: Variant = data.get("definition_id")
	var raw_equipment: Variant = data.get("equipment")
	var legacy_skills := not data.has("learned_skill_ids")
	var raw_learned_skills: Variant = data.get(
		"learned_skill_ids",
		data.get("skill_ids", [])
	)
	var raw_battle_skills: Variant = data.get("battle_skill_ids")
	var raw_battle_item: Variant = data.get("battle_item_id", "")
	if not raw_id is String or String(raw_id).is_empty():
		return null
	if (
		not raw_equipment is Dictionary
		or not raw_learned_skills is Array
		or not raw_battle_item is String
		or (not legacy_skills and not raw_battle_skills is Array)
	):
		return null
	var state := ActorState.new()
	state.definition_id = StringName(raw_id)
	var fallback_realm := (
		fallback_definition.initial_realm
		if fallback_definition != null
		else null
	)
	state.realm_id = StringName(data.get(
		"realm_id",
		String(fallback_realm.id) if fallback_realm != null else ""
	))
	state.realm_layer = int(data.get(
		"realm_layer",
		data.get("level", fallback_definition.initial_realm_layer if fallback_definition != null else 1)
	))
	state.cultivation_points = int(data.get(
		"cultivation_points",
		data.get("experience", 0)
	))
	state.foundation_id = StringName(data.get(
		"foundation_id",
		String(fallback_definition.initial_foundation.id)
		if fallback_definition != null and fallback_definition.initial_foundation != null
		else ""
	))
	state.hp = int(data.get("hp", 0))
	state.mp = int(data.get("mp", 0))
	if (
		state.realm_id.is_empty()
		or state.realm_layer < 1
		or state.cultivation_points < 0
		or state.hp < 0
		or state.mp < 0
	):
		return null
	for raw_slot: Variant in raw_equipment:
		if not raw_slot is String or not raw_equipment[raw_slot] is String:
			return null
		state.equipment[StringName(raw_slot)] = StringName(raw_equipment[raw_slot])
	for raw_skill: Variant in raw_learned_skills:
		if not raw_skill is String:
			return null
		var skill_id := StringName(raw_skill)
		if legacy_skills and skill_id in state.learned_skill_ids:
			continue
		state.learned_skill_ids.append(skill_id)
	if legacy_skills:
		state.battle_skill_ids = _legacy_battle_skills(state.learned_skill_ids, database)
	else:
		if raw_battle_skills.size() != BATTLE_SKILL_SLOT_COUNT:
			return null
		state.battle_skill_ids.clear()
		for raw_skill: Variant in raw_battle_skills:
			if not raw_skill is String:
				return null
			state.battle_skill_ids.append(StringName(raw_skill))
	state.battle_item_id = StringName(raw_battle_item)
	return state


static func _string_names(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value: StringName in values:
		result.append(String(value))
	return result


static func _legacy_battle_skills(
	learned_skills: Array[StringName],
	database: ContentDatabase
) -> Array[StringName]:
	var result: Array[StringName] = [&"", &"", &""]
	var slot := 0
	for skill_id: StringName in learned_skills:
		var skill := database.skill(skill_id) if database != null else null
		if database != null and (skill == null or not skill.can_be_used_in_battle()):
			continue
		result[slot] = skill_id
		slot += 1
		if slot >= BATTLE_SKILL_SLOT_COUNT:
			break
	return result
