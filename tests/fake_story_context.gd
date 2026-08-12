class_name FakeStoryContext
extends StoryContext

var stage: StringName = &"not_started"
var shown_blocks: Array[StringName] = []
var flags: Dictionary[StringName, Variant] = {}
var source_completed: bool = false
var next_battle_result := BattleResult.new()
var party_restored: bool = false
var recorded_pending_map: MapDefinition
var recorded_pending_spawn_id: StringName


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


func is_source_entity_completed() -> bool:
	return source_completed


func start_battle(_encounter: BattleEncounter) -> BattleResult:
	return next_battle_result


func restore_party() -> void:
	party_restored = true


func travel_to(map: MapDefinition, spawn_id: StringName = &"") -> void:
	recorded_pending_map = map
	recorded_pending_spawn_id = spawn_id
