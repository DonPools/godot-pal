class_name ScenePortalEvent
extends StoryEvent

var target_map: MapDefinition
var target_spawn_id: StringName


func run(_trigger_id: StringName, story: StoryContext) -> void:
	if target_map == null:
		push_error("ScenePortalEvent has no target map")
		return
	story.travel_to(target_map, target_spawn_id)
