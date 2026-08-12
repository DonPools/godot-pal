@tool
class_name StoryModule
extends StoryEvent

@export var id: StringName
@export var initial_stage: StringName = &"not_started"
@export var valid_stages: Array[StringName] = []
@export var dialogue: DialogueDefinition


func has_stage(stage_id: StringName) -> bool:
	return stage_id in valid_stages


func get_objective_text(_stage_id: StringName, _map_id: StringName) -> String:
	return ""
