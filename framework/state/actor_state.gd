class_name ActorState
extends RefCounted

var definition_id: StringName
var level: int = 1
var experience: int = 0
var hp: int = 1
var mp: int = 0
var equipment: Dictionary[StringName, StringName] = {}
var skill_ids: Array[StringName] = []


static func from_definition(definition: ActorDefinition) -> ActorState:
	var state := ActorState.new()
	state.definition_id = definition.id
	state.level = definition.initial_level
	state.hp = definition.base_max_hp
	state.mp = definition.base_max_mp
	for item: EquipmentDefinition in definition.initial_equipment:
		if item != null and not item.slot.is_empty():
			state.equipment[item.slot] = item.id
	for skill: SkillDefinition in definition.initial_skills:
		if skill != null:
			state.skill_ids.append(skill.id)
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


func add_experience(amount: int) -> void:
	experience = maxi(experience + amount, 0)


func to_dictionary() -> Dictionary:
	var raw_equipment: Dictionary = {}
	for slot: StringName in equipment:
		raw_equipment[String(slot)] = String(equipment[slot])
	return {
		"definition_id": String(definition_id),
		"level": level,
		"experience": experience,
		"hp": hp,
		"mp": mp,
		"equipment": raw_equipment,
		"skill_ids": _string_names(skill_ids),
	}


static func from_dictionary(data: Dictionary) -> ActorState:
	var raw_id: Variant = data.get("definition_id")
	var raw_equipment: Variant = data.get("equipment")
	var raw_skills: Variant = data.get("skill_ids")
	if not raw_id is String or String(raw_id).is_empty():
		return null
	if not raw_equipment is Dictionary or not raw_skills is Array:
		return null
	var state := ActorState.new()
	state.definition_id = StringName(raw_id)
	state.level = int(data.get("level", 1))
	state.experience = int(data.get("experience", 0))
	state.hp = int(data.get("hp", 0))
	state.mp = int(data.get("mp", 0))
	if state.level < 1 or state.experience < 0 or state.hp < 0 or state.mp < 0:
		return null
	for raw_slot: Variant in raw_equipment:
		if not raw_slot is String or not raw_equipment[raw_slot] is String:
			return null
		state.equipment[StringName(raw_slot)] = StringName(raw_equipment[raw_slot])
	for raw_skill: Variant in raw_skills:
		if not raw_skill is String:
			return null
		state.skill_ids.append(StringName(raw_skill))
	return state


static func _string_names(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value: StringName in values:
		result.append(String(value))
	return result
