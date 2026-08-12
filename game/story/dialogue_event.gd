@tool
class_name DialogueEvent
extends StoryEvent

@export var dialogue: DialogueDefinition
@export var block_id: StringName = &"default"


func run(_trigger_id: StringName, story: StoryContext) -> void:
	if dialogue == null or dialogue.block(block_id) == null:
		push_error("DialogueEvent requires a valid dialogue block")
		return
	await story.show_dialogue(dialogue, block_id)
