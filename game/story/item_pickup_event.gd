class_name ItemPickupEvent
extends StoryEvent

@export var item: ItemDefinition
@export_range(1, 99) var quantity: int = 1
@export var reward_policy: RewardPolicy.Value = RewardPolicy.Value.ALL_OR_NOTHING


func run(_trigger_id: StringName, story: StoryContext) -> void:
	if item == null:
		push_error("ItemPickupEvent has no ItemDefinition")
		return
	if reward_policy == RewardPolicy.Value.ALLOW_PARTIAL:
		push_error("ItemPickupEvent ALLOW_PARTIAL requires persistent remaining quantity support")
		return
	if story.is_source_entity_completed():
		return
	var result := story.give_item(item, quantity, reward_policy)
	if result.succeeded():
		story.complete_source_entity()
