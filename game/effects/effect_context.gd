class_name EffectContext
extends RefCounted

var source_id: StringName
var target: ActorState
var target_definition: ActorDefinition


static func create(
	source: StringName,
	actor_state: ActorState,
	actor_definition: ActorDefinition
) -> EffectContext:
	var context := EffectContext.new()
	context.source_id = source
	context.target = actor_state
	context.target_definition = actor_definition
	return context
