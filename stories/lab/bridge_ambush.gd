class_name BridgeAmbushStory
extends StoryModule

const CONFRONT_BANDIT := &"confront_bandit"

@export var encounter: BattleEncounter
@export var safe_map: MapDefinition
@export var safe_spawn_id: StringName = &"from_bridge"


func get_trigger_ids() -> Array[StringName]:
	return [CONFRONT_BANDIT]


func run(trigger_id: StringName, story: StoryContext) -> void:
	if trigger_id != CONFRONT_BANDIT or story.is_source_entity_completed():
		return
	var result := await story.start_battle(encounter)
	match result.outcome:
		BattleResult.Outcome.VICTORY:
			story.complete_source_entity()
			story.set_stage(self, &"completed")
		BattleResult.Outcome.ESCAPED:
			story.set_stage(self, &"escaped")
		BattleResult.Outcome.DEFEAT:
			story.restore_party()
			story.set_stage(self, &"defeated")
			story.travel_to(safe_map, safe_spawn_id)
			return
