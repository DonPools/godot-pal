class_name BattleActionIntent
extends RefCounted

enum Kind {
	BASIC_ATTACK,
	SKILL,
	ITEM,
	DODGE,
	CHARGE,
}

var kind: Kind = Kind.BASIC_ATTACK
var actor_id: StringName
var target_id: StringName
var skill: SkillDefinition
var item: ItemDefinition


static func basic_attack(actor: StringName, target: StringName = &"") -> BattleActionIntent:
	var intent := BattleActionIntent.new()
	intent.kind = Kind.BASIC_ATTACK
	intent.actor_id = actor
	intent.target_id = target
	return intent


static func use_skill(
	actor: StringName,
	definition: SkillDefinition,
	target: StringName = &""
) -> BattleActionIntent:
	var intent := BattleActionIntent.new()
	intent.kind = Kind.SKILL
	intent.actor_id = actor
	intent.target_id = target
	intent.skill = definition
	return intent


static func use_item(
	actor: StringName,
	definition: ItemDefinition,
	target: StringName = &""
) -> BattleActionIntent:
	var intent := BattleActionIntent.new()
	intent.kind = Kind.ITEM
	intent.actor_id = actor
	intent.target_id = target
	intent.item = definition
	return intent


static func dodge(actor: StringName) -> BattleActionIntent:
	var intent := BattleActionIntent.new()
	intent.kind = Kind.DODGE
	intent.actor_id = actor
	return intent


static func charge(actor: StringName, target: StringName = &"") -> BattleActionIntent:
	var intent := BattleActionIntent.new()
	intent.kind = Kind.CHARGE
	intent.actor_id = actor
	intent.target_id = target
	return intent
