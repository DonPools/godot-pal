@tool
class_name NorthSlopePackStory
extends StoryModule

const CONFRONT := &"confront_pack"
const SUPPLY_GRANTED := &"flag.story.roadside.north_slope_pack.supply_granted"

@export var encounter: BattleEncounter
@export var supply_item: ItemDefinition
@export var defeat_map: MapDefinition
@export var defeat_spawn_id: StringName = &"default"


func get_trigger_ids() -> Array[StringName]:
	return [CONFRONT]


func can_run(trigger_id: StringName, story: StoryContext) -> bool:
	return trigger_id == CONFRONT and not story.is_source_entity_completed()


func get_objective_text(stage_id: StringName, map_id: StringName) -> String:
	if map_id != &"map.roadside.north_slope_pack":
		return ""
	if stage_id == &"cleared":
		return "兽径已经安静 · 沿南边旧路返回"
	return "穿过兽径 · 留意前摇并拉开投石手的射线"


func run(trigger_id: StringName, story: StoryContext) -> void:
	if trigger_id != CONFRONT or encounter == null:
		return
	await story.show_dialogue(dialogue, &"approach")
	if supply_item != null and not story.is_flag_set(SUPPLY_GRANTED):
		var supply := story.give_item(supply_item, 2, RewardPolicy.Value.ALL_OR_NOTHING)
		if supply.succeeded():
			story.set_flag(SUPPLY_GRANTED)
			await story.show_dialogue(dialogue, &"supply")
		else:
			await story.show_dialogue(dialogue, &"pack_full")
	var result := await story.start_battle(encounter)
	match result.outcome:
		BattleResult.Outcome.VICTORY:
			story.complete_source_entity()
			story.set_stage(self, &"cleared")
			await story.show_dialogue(dialogue, &"victory")
		BattleResult.Outcome.ESCAPED:
			await story.show_dialogue(dialogue, &"escaped")
		BattleResult.Outcome.DEFEAT:
			story.restore_party()
			if defeat_map != null:
				story.travel_to(defeat_map, defeat_spawn_id)
				return

