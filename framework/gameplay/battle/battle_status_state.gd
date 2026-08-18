class_name BattleStatusState
extends RefCounted

var definition_id: StringName
var remaining_seconds: float = 0.0
var tick_remaining_seconds: float = 0.0


static func from_definition(definition: StatusDefinition) -> BattleStatusState:
	var state := BattleStatusState.new()
	if definition == null:
		return state
	state.definition_id = definition.id
	state.remaining_seconds = definition.duration_seconds
	state.tick_remaining_seconds = definition.tick_interval_seconds
	return state
