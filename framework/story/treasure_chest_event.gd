class_name TreasureChestEvent
extends StoryEvent

@export var item: ItemDefinition
@export_range(1, 99) var quantity: int = 1


func run(_trigger_id: StringName, story: StoryContext) -> void:
	if item == null:
		push_error("TreasureChestEvent has no ItemDefinition")
		return
	if story.is_source_entity_completed():
		return
	var result := story.give_item(item, quantity, RewardPolicy.Value.ALL_OR_NOTHING)
	if result.succeeded():
		story.complete_source_entity()
