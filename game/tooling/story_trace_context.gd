class_name StoryTraceContext
extends StoryContext

var stage: StringName
var flags: Dictionary[StringName, Variant] = {}
var source_completed: bool = false
var battle_outcome: BattleResult.Outcome = BattleResult.Outcome.VICTORY
var trace: Array[Dictionary] = []
var pending_map_id: StringName
var recorded_spawn_id: StringName


func show_dialogue(dialogue: DialogueDefinition, block_id: StringName = &"default") -> DialogueResult:
	trace.append({"operation": "show_dialogue", "dialogue_id": String(dialogue.id), "block_id": String(block_id)})
	return DialogueResult.new()


func get_stage(module: StoryModule) -> StringName:
	return stage if not stage.is_empty() else module.initial_stage


func set_stage(_module: StoryModule, stage_id: StringName) -> void:
	stage = stage_id
	trace.append({"operation": "set_stage", "stage_id": String(stage_id)})


func is_flag_set(flag_id: StringName) -> bool:
	return bool(flags.get(flag_id, false))


func set_flag(flag_id: StringName, value: Variant = true) -> void:
	flags[flag_id] = value
	trace.append({"operation": "set_flag", "flag_id": String(flag_id), "value": value})


func is_source_entity_completed() -> bool:
	return source_completed


func complete_source_entity() -> void:
	source_completed = true
	trace.append({"operation": "complete_source_entity"})


func start_battle(encounter: BattleEncounter) -> BattleResult:
	trace.append({"operation": "start_battle", "encounter_id": String(encounter.id)})
	var result := BattleResult.new()
	result.outcome = battle_outcome
	return result


func restore_party() -> void:
	trace.append({"operation": "restore_party"})


func travel_to(map: MapDefinition, spawn_id: StringName = &"") -> void:
	pending_map_id = map.id
	recorded_spawn_id = spawn_id
	trace.append({"operation": "travel_to", "map_id": String(map.id), "spawn_id": String(spawn_id)})
