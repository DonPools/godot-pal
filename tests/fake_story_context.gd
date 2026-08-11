class_name FakeStoryContext
extends StoryContext

var stage: StringName = &"not_started"
var shown_blocks: Array[StringName] = []
var flags: Dictionary[StringName, Variant] = {}
var source_completed: bool = false


func show_dialogue(
	_dialogue: DialogueDefinition,
	block_id: StringName = &"default"
) -> DialogueResult:
	shown_blocks.append(block_id)
	return DialogueResult.new()


func get_stage(_module: StoryModule) -> StringName:
	return stage


func set_stage(module: StoryModule, stage_id: StringName) -> void:
	if module.has_stage(stage_id):
		stage = stage_id


func is_flag_set(flag_id: StringName) -> bool:
	return bool(flags.get(flag_id, false))


func set_flag(flag_id: StringName, value: Variant = true) -> void:
	flags[flag_id] = value


func complete_source_entity() -> void:
	source_completed = true
