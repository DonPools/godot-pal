class_name ScenePortalEvent
extends StoryEvent

@export var destination: MapDestination


func run(_trigger_id: StringName, story: StoryContext) -> void:
	if destination == null:
		push_error("ScenePortalEvent has no MapDestination")
		return
	story.travel_to(destination)
