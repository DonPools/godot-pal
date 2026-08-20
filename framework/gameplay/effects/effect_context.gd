class_name EffectContext
extends RefCounted

var source_id: StringName
var target: ActorState
var target_definition: ActorDefinition
var target_max_hp: int = -1
var target_max_mp: int = -1
var battle_target: BattleActorState


static func create(
	source: StringName,
	actor_state: ActorState,
	actor_definition: ActorDefinition,
	maximum_hp: int = -1,
	maximum_mp: int = -1
) -> EffectContext:
	var context := EffectContext.new()
	context.source_id = source
	context.target = actor_state
	context.target_definition = actor_definition
	context.target_max_hp = maximum_hp
	context.target_max_mp = maximum_mp
	return context


static func create_for_battle(
	source: StringName,
	actor_state: BattleActorState
) -> EffectContext:
	var context := EffectContext.new()
	context.source_id = source
	context.battle_target = actor_state
	return context
