class_name ShopEvent
extends StoryEvent

@export var shop: ShopDefinition


func run(_trigger_id: StringName, story: StoryContext) -> void:
	if shop == null:
		push_error("ShopEvent has no ShopDefinition")
		return
	await story.open_shop(shop)
