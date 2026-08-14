@tool
class_name StoryEvent
extends Resource


func get_trigger_ids() -> Array[StringName]:
	return [&"default"]


func can_run(_trigger_id: StringName, _story: StoryContext) -> bool:
	return true


func run(_trigger_id: StringName, _story: StoryContext) -> void:
	push_error("StoryEvent.run() must be implemented")
