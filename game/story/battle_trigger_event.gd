@tool
class_name BattleTriggerEvent
extends StoryEvent

@export var encounter: BattleEncounter
@export var defeat_map: MapDefinition
@export var defeat_spawn_id: StringName


func can_run(_trigger_id: StringName, story: StoryContext) -> bool:
	return not story.is_source_entity_completed()


func run(_trigger_id: StringName, story: StoryContext) -> void:
	if encounter == null:
		push_error("BattleTriggerEvent requires a BattleEncounter")
		return
	var result := await story.start_battle(encounter)
	match result.outcome:
		BattleResult.Outcome.VICTORY:
			story.complete_source_entity()
		BattleResult.Outcome.DEFEAT:
			story.restore_party()
			if defeat_map != null:
				story.travel_to(defeat_map, defeat_spawn_id)
				return
