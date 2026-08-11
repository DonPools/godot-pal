class_name StoryContext
extends RefCounted

var source_entity_id: StringName:
	get:
		return _origin.source_entity_id if _origin != null else &""
var source_actor_id: StringName:
	get:
		return _origin.source_actor_id if _origin != null else &""

var _game_run: GameRun
var _dialogue_layer: DialogueLayer
var _map_scene: LabMapGameScene
var _origin: StoryOrigin
var _active: bool = false
var _pending_map: MapDefinition
var _pending_spawn_id: StringName


func initialize(
	game_run: GameRun,
	dialogue_layer: DialogueLayer,
	map_scene: LabMapGameScene,
	origin: StoryOrigin
) -> void:
	_game_run = game_run
	_dialogue_layer = dialogue_layer
	_map_scene = map_scene
	_origin = origin
	_active = true


func show_dialogue(
	dialogue: DialogueDefinition,
	block_id: StringName = &"default"
) -> DialogueResult:
	if not _require_active("show_dialogue"):
		return DialogueResult.new()
	return await _dialogue_layer.show_dialogue(dialogue, block_id)


func get_stage(module: StoryModule) -> StringName:
	if not _require_active("get_stage"):
		return &""
	return _game_run.story.get_stage(module.id, module.initial_stage)


func set_stage(module: StoryModule, stage_id: StringName) -> void:
	if not _require_active("set_stage"):
		return
	if not module.has_stage(stage_id):
		push_error("Story %s rejected unknown stage %s" % [module.id, stage_id])
		return
	_game_run.story.set_stage(module.id, stage_id)


func is_flag_set(flag_id: StringName) -> bool:
	return _require_active("is_flag_set") and _game_run.flags.is_set(flag_id)


func get_flag(flag_id: StringName, default_value: Variant = null) -> Variant:
	if not _require_active("get_flag"):
		return default_value
	return _game_run.flags.get_value(flag_id, default_value)


func set_flag(flag_id: StringName, value: Variant = true) -> void:
	if _require_active("set_flag"):
		_game_run.flags.set_value(flag_id, value)


func clear_flag(flag_id: StringName) -> void:
	if _require_active("clear_flag"):
		_game_run.flags.clear(flag_id)


func is_source_entity_completed() -> bool:
	if not _require_active("is_source_entity_completed") or source_entity_id.is_empty():
		return false
	return _game_run.world.is_completed(_origin.map_id, source_entity_id)


func complete_source_entity() -> void:
	if not _require_active("complete_source_entity"):
		return
	if source_entity_id.is_empty():
		push_error("complete_source_entity requires a persistent StoryOrigin")
		return
	_game_run.world.complete(_origin.map_id, source_entity_id)
	if _map_scene != null:
		_map_scene.complete_entity(source_entity_id)


func wait_seconds(seconds: float) -> void:
	if not _require_active("wait_seconds"):
		return
	await _map_scene.get_tree().create_timer(maxf(seconds, 0.0)).timeout


func travel_to(map: MapDefinition, spawn_id: StringName = &"") -> void:
	if not _require_active("travel_to"):
		return
	if map == null:
		push_error("travel_to requires a MapDefinition")
		return
	_pending_map = map
	_pending_spawn_id = spawn_id if not spawn_id.is_empty() else map.default_spawn_id
	_active = false


func pending_map() -> MapDefinition:
	return _pending_map


func pending_spawn_id() -> StringName:
	return _pending_spawn_id


func invalidate() -> void:
	_active = false
	_map_scene = null


func _require_active(operation: String) -> bool:
	if _active:
		return true
	push_error("StoryContext.%s called after the context became invalid" % operation)
	return false
