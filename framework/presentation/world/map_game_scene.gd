class_name MapGameScene
extends GameScene

signal battle_started(session: BattleSession)
signal battle_events_produced(events: Array[BattleEvent])
signal battle_finished(result: BattleResult)

@export var entry_trigger_id: StringName
@export var interaction_sound: AudioStream
@export var portal_sound: AudioStream

@onready var ground_layer: TileMapLayer = get_node_or_null(^"GroundLayer") as TileMapLayer
@onready var detail_layer: TileMapLayer = get_node_or_null(^"DetailLayer") as TileMapLayer
@onready var y_sort_root: Node2D = get_node_or_null(^"YSortRoot") as Node2D
@onready var player: PlayerCharacter = (
	get_node_or_null(^"YSortRoot/PlayerCharacter") as PlayerCharacter
)
@onready var spawn_points: Node2D = get_node_or_null(^"SpawnPoints") as Node2D
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


func _apply_player_control(movement_enabled: bool, can_interact: bool) -> void:
	if player == null:
		return
	player.set_control_enabled(movement_enabled)
	player.set_interaction_enabled(can_interact)


func _connect_player_requests() -> void:
	if player != null and not player.interact_requested.is_connected(_on_player_interact):
		player.interact_requested.connect(_on_player_interact)


func complete_entity(entity_id: StringName) -> void:
	for interactable: Interactable in _map_interactables():
		if interactable.persistent_id == entity_id:
			interactable.apply_completed()


func capture_location() -> void:
	if scene_context == null or player == null or definition == null:
		return
	var location := scene_context.game_run.location
	location.map_id = definition.id
	location.spawn_id = &""
	location.position = Vector3(player.position.x, 0.0, player.position.y)
	location.direction = player.direction
	location.has_exact_position = true


func _configure_characters() -> void:
	var leader := scene_context.game_run.party.leader()
	var leader_definition := (
		scene_context.content_database.actor(leader.definition_id)
		if leader != null
		else null
	)
	player.configure(leader_definition)
	for child: Node in y_sort_root.get_children():
		if child is NpcCharacter:
			child.configure()
		elif child is WorldProp:
			child.configure(scene_context.game_run, map_id)


func _configure_interactables() -> void:
	for interactable: Interactable in _map_interactables():
		if not interactable.portal_target_map_id.is_empty():
			var destination := scene_context.content_database.map(
				interactable.portal_target_map_id
			)
			var portal := ScenePortalEvent.new()
			portal.target_map = destination
			portal.target_spawn_id = interactable.portal_target_spawn_id
			interactable.configure_story(portal)
		else:
			interactable.configure_story(story_module)
		if (
			not interactable.persistent_id.is_empty()
			and scene_context.game_run.world.is_completed(map_id, interactable.persistent_id)
		):
			interactable.apply_completed()


func _place_player(spawn_id: StringName) -> void:
	var location := scene_context.game_run.location
	if location.map_id == map_id and location.has_exact_position:
		player.position = Vector2(location.position.x, location.position.z)
		player.set_direction(location.direction)
		return
	var marker := spawn_points.get_node_or_null(NodePath(String(spawn_id))) as Node2D
	if marker == null and spawn_points.get_child_count() > 0:
		marker = spawn_points.get_child(0) as Node2D
	if marker == null:
		push_error("Map %s has no spawn point for %s" % [map_id, spawn_id])
		return
	player.position = marker.position
	player.set_direction(&"south")
	location.map_id = map_id
	location.spawn_id = spawn_id
	location.has_exact_position = false


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


func _on_player_interact() -> void:
	var interactable := _nearest_interactable()
	if interactable == null:
		return
	scene_context.audio_service.play_sound(
		portal_sound
		if not interactable.portal_target_map_id.is_empty()
		else interaction_sound
	)
	await scene_context.story_director.run_binding(
		interactable.binding,
		interactable.story_origin(map_id),
		self
	)
	if is_instance_valid(self):
		_refresh_world_props()
		_refresh_objective()


func _refresh_world_props() -> void:
	for child: Node in y_sort_root.get_children():
		if child is WorldProp:
			child.refresh()


func _nearest_interactable() -> Interactable:
	var nearest: Interactable
	var nearest_distance := 84.0
	for interactable: Interactable in _map_interactables():
		if not interactable.is_available():
			continue
		var distance := player.global_position.distance_to(interactable.global_position)
		if distance < nearest_distance:
			nearest = interactable
			nearest_distance = distance
	return nearest


func _map_interactables() -> Array[Interactable]:
	var result: Array[Interactable] = []
	for candidate: Node in get_tree().get_nodes_in_group(&"story_interactables"):
		if candidate is Interactable and is_ancestor_of(candidate):
			result.append(candidate)
	return result


func _refresh_objective() -> void:
	if objective_label == null:
		return
	if story_module == null:
		objective_label.text = "方向键/摇杆移动 · Enter/A 互动 · M/Start 菜单"
		return
	var stage := scene_context.game_run.story.get_stage(
		story_module.id,
		story_module.initial_stage
	)
	var objective := story_module.get_objective_text(stage, map_id)
	objective_label.text = (
		objective if not objective.is_empty() else "方向键移动 · Enter/Space 互动"
	)
