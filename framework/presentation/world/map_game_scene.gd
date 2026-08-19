class_name MapGameScene
extends GameScene

signal battle_started(session: BattleSession)
signal battle_events_produced(events: Array[BattleEvent])
signal battle_finished(result: BattleResult)

@export var entry_trigger_id: StringName

@onready var map_name_label: Label = get_node_or_null(^"HudLayer/MapName") as Label
@onready var objective_label: Label = get_node_or_null(^"HudLayer/Objective") as Label

var map_id: StringName:
	get:
		return definition.id if definition != null else &""

var definition: MapDefinition
var story_module: StoryModule
var battle_session: BattleSession

var _exploration_control_enabled: bool = true
var _last_battle_result: BattleResult


func _process(delta: float) -> void:
	if battle_session != null:
		advance_battle(delta)


func enter(context: GameSceneContext, arguments: Variant) -> void:
	super.enter(context, arguments)
	var data: Dictionary = arguments if arguments is Dictionary else {}
	definition = data.get("definition") as MapDefinition
	story_module = data.get("story") as StoryModule
	if definition == null:
		push_error("MapGameScene.enter requires a MapDefinition")
		return
	_configure_characters()
	_configure_interactables()
	_place_player(StringName(data.get("spawn_id", definition.default_spawn_id)))
	context.audio_service.play_music(definition.music)
	if map_name_label != null:
		map_name_label.text = definition.display_name
	_refresh_objective()
	_connect_player_requests()
	call_deferred("_run_entry_binding")


func exit_scene() -> void:
	capture_location()
	_cancel_active_battle()
	super.exit_scene()


func pause_scene() -> void:
	capture_location()
	super.pause_scene()


func set_player_control_enabled(enabled: bool) -> void:
	_exploration_control_enabled = enabled
	if battle_session == null:
		_apply_player_control(enabled, enabled)


func has_active_battle() -> bool:
	return battle_session != null and not battle_session.finished


func start_battle(encounter: BattleEncounter) -> BattleResult:
	var session := begin_battle(encounter)
	if session == null:
		return BattleResult.new()
	if battle_session == null and _last_battle_result != null:
		return _last_battle_result
	var completed: Variant = await battle_finished
	if completed is BattleResult:
		return completed as BattleResult
	if completed is Array and completed.size() == 1 and completed[0] is BattleResult:
		return completed[0] as BattleResult
	return BattleResult.new()


func begin_battle(encounter: BattleEncounter) -> BattleSession:
	if encounter == null or scene_context == null:
		push_error("MapGameScene.begin_battle requires an encounter and scene context")
		return null
	if battle_session != null:
		push_error("MapGameScene allows only one active BattleSession")
		return null
	var session := BattleSession.create(
		encounter,
		scene_context.game_run,
		scene_context.content_database
	)
	if session.player == null or session.enemies.is_empty():
		push_error("MapGameScene could not create valid battle participants")
		return null
	battle_session = session
	_last_battle_result = null
	_apply_player_control(true, false)
	battle_started.emit(session)
	return session


func request_battle_action(intent: BattleActionIntent) -> BattleActionRequestResult:
	if battle_session == null:
		var rejected := BattleActionRequestResult.new()
		rejected.rejection = BattleActionRequestResult.Rejection.SESSION_FINISHED
		return rejected
	var result := battle_session.request_action(intent)
	_emit_battle_events(battle_session.drain_events())
	return result


func resolve_battle_hit(
	actor_id: StringName,
	action_instance_id: int,
	target_id: StringName
) -> Array[BattleEvent]:
	if battle_session == null:
		return []
	var events := battle_session.resolve_hit(actor_id, action_instance_id, target_id)
	_emit_battle_events(events)
	_complete_finished_battle()
	return events


func apply_battle_status(
	target_id: StringName,
	status: StatusDefinition
) -> Array[BattleEvent]:
	if battle_session == null:
		return []
	var events := battle_session.apply_status(target_id, status)
	_emit_battle_events(events)
	_complete_finished_battle()
	return events


func advance_battle(delta: float) -> Array[BattleEvent]:
	if battle_session == null:
		return []
	var events := battle_session.advance(delta)
	_emit_battle_events(events)
	_complete_finished_battle()
	return events


func escape_battle() -> BattleResult:
	if battle_session == null:
		return BattleResult.new()
	var result := battle_session.finish_escape()
	_emit_battle_events(battle_session.drain_events())
	_complete_finished_battle()
	return _last_battle_result if _last_battle_result != null else result


func complete_entity(_entity_id: StringName) -> void:
	push_error("MapGameScene.complete_entity must be implemented by the active map presentation")


func capture_location() -> void:
	pass


func _configure_characters() -> void:
	pass


func _configure_interactables() -> void:
	pass


func _place_player(_spawn_id: StringName) -> void:
	pass


func _connect_player_requests() -> void:
	pass


func _apply_player_control(_movement_enabled: bool, _can_interact: bool) -> void:
	pass


func _complete_finished_battle() -> void:
	if battle_session == null or not battle_session.finished:
		return
	var completed_session := battle_session
	var result := completed_session.commit_result()
	battle_session = null
	_last_battle_result = result
	_apply_player_control(
		_exploration_control_enabled,
		_exploration_control_enabled
	)
	battle_finished.emit(result)


func _cancel_active_battle() -> void:
	if battle_session == null:
		return
	var result := battle_session.finish_cancelled()
	battle_session = null
	_last_battle_result = result
	battle_finished.emit(result)


func _emit_battle_events(events: Array[BattleEvent]) -> void:
	if not events.is_empty():
		battle_events_produced.emit(events)


func _run_entry_binding() -> void:
	await get_tree().process_frame
	if entry_trigger_id.is_empty() or story_module == null:
		return
	var binding := StoryBinding.new()
	binding.event = story_module
	binding.trigger_id = entry_trigger_id
	await scene_context.story_director.run_binding(
		binding,
		StoryOrigin.create(map_id),
		self
	)
	_refresh_objective()


func _refresh_objective() -> void:
	if objective_label == null:
		return
	if story_module == null:
		objective_label.text = "WASD/摇杆移动 · 鼠标/右摇杆瞄准 · Enter/A 互动"
		return
	var stage := scene_context.game_run.story.get_stage(
		story_module.id,
		story_module.initial_stage
	)
	var objective := story_module.get_objective_text(stage, map_id)
	objective_label.text = (
		objective
		if not objective.is_empty()
		else "WASD/摇杆移动 · 鼠标/右摇杆瞄准 · Enter/A 互动"
	)
