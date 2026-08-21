class_name MapGameScene3D
extends MapGameScene

const PLAYER_HIT_STOP_SECONDS := MapBattlePresentation3D.PLAYER_HIT_STOP_SECONDS
const ENEMY_HIT_STOP_SECONDS := MapBattlePresentation3D.ENEMY_HIT_STOP_SECONDS
const REDUCED_HIT_STOP_SCALE := MapBattlePresentation3D.REDUCED_HIT_STOP_SCALE

@export var hit_sound: AudioStream
@export var dodge_sound: AudioStream
@export var victory_sound: AudioStream
@export var escaped_sound: AudioStream
@export var defeat_sound: AudioStream
@export var charge_windup_sound: AudioStream
@export var pillar_stagger_sound: AudioStream

@onready var world_root: Node3D = $WorldRoot
@onready var player_3d: PlayerCharacter3D = $WorldRoot/PlayerCharacter3D
@onready var enemy_root: Node3D = $WorldRoot/Enemies
@onready var encounter_sources: Node3D = $WorldRoot/EncounterSources
@onready var spawn_points_3d: Node3D = $WorldRoot/SpawnPoints
@onready var pointer_feedback: PointerFeedback3D = $WorldRoot/PointerFeedback3D
@onready var combat_feedback: CombatFeedback3D = $WorldRoot/CombatFeedback3D
@onready var camera_3d: MapCameraRig3D = $Camera3D
@onready var pointer_controller: MapPointerController3D = $PointerController
@onready var map_hud: MapHud3D = $HudLayer/MapHud
@onready var battle_hud: Control = $HudLayer/MapHud/BattlePanel
@onready var result_label: Label = $HudLayer/Result

var _active_source: EncounterSource3D
var _battle_presentation := MapBattlePresentation3D.new()
var _suppressed_destination_labels: Array[DestinationLabel3D] = []


func enter(context: GameSceneContext, arguments: Variant) -> void:
	map_hud.configure(context.settings_service)
	combat_feedback.configure(context.settings_service)
	_battle_presentation.configure(self, context.settings_service)
	super.enter(context, arguments)
	pointer_controller.configure(
		self,
		player_3d,
		camera_3d,
		pointer_feedback,
		map_hud,
		context.settings_service
	)
	player_3d.configure_input_tuning(context.settings_service.movement_deadzone)


func _ready() -> void:
	battle_started.connect(_on_battle_started_3d)
	battle_events_produced.connect(_on_battle_events_3d)
	battle_finished.connect(_on_battle_finished_3d)
	map_hud.set_input_device(false)
	result_label.visible = false


func _process(delta: float) -> void:
	if not _battle_presentation.advance_hit_stop(delta):
		super._process(delta)
	pointer_controller.update_pointer_state(delta)
	_refresh_battle_hud()
	_refresh_interaction_prompt()


func _input(event: InputEvent) -> void:
	pointer_controller.handle_input(event)


func _unhandled_input(event: InputEvent) -> void:
	pointer_controller.handle_unhandled_input(event)


func exit_scene() -> void:
	restore_hit_stop_motion()
	camera_3d.restore_obstacles()
	pointer_controller.reset_pointer_state()
	pointer_controller.clear_custom_cursors()
	_set_destination_labels_suppressed(false)
	super.exit_scene()


func pause_scene() -> void:
	restore_hit_stop_motion()
	camera_3d.restore_obstacles()
	pointer_controller.reset_pointer_state()
	pointer_controller.clear_custom_cursors()
	_set_destination_labels_suppressed(false)
	super.pause_scene()


func resume_scene(result: Variant = null) -> void:
	super.resume_scene(result)
	pointer_controller.register_custom_cursors()


func _configure_characters() -> void:
	var leader := scene_context.game_run.party.leader()
	var actor_definition := (
		scene_context.content_database.actor(leader.definition_id)
		if leader != null
		else null
	)
	player_3d.configure(actor_definition)
	player_3d.bind_map(self, camera_3d)
	camera_3d.configure(player_3d, _camera_interest_target)
	refresh_player_state()
	for view: WorldStateView3D in _world_state_views_3d():
		view.configure_world_state(scene_context.game_run, map_id)


func _configure_interactables() -> void:
	for interactable: StoryInteractable3D in _map_interactables_3d():
		if not interactable.portal_target_map_id.is_empty():
			interactable.configure_portal(MapDestination.create(
				interactable.portal_target_map_id,
				interactable.portal_target_spawn_id
			))
		if (
			not interactable.persistent_id.is_empty()
			and scene_context.game_run.world.is_completed(map_id, interactable.persistent_id)
		):
			interactable.apply_completed()
	for child: Node in encounter_sources.get_children():
		if child is EncounterSource3D:
			var source := child as EncounterSource3D
			source.prepare(self, enemy_root, player_3d)
			source.encounter_alerted.connect(run_encounter_source)
			source.enemy_returned_home.connect(request_escape_if_source_returned)
			for enemy_view: EnemyActorView3D in source.enemy_views:
				enemy_view.projectile_requested.connect(spawn_battle_projectile)
				enemy_view.damage_number_requested.connect(show_damage_number)


func _connect_player_requests() -> void:
	if not player_3d.interact_requested.is_connected(_on_player_interact_3d):
		player_3d.interact_requested.connect(_on_player_interact_3d)
	if not player_3d.projectile_requested.is_connected(spawn_battle_projectile):
		player_3d.projectile_requested.connect(spawn_battle_projectile)
	if not player_3d.damage_number_requested.is_connected(show_damage_number):
		player_3d.damage_number_requested.connect(show_damage_number)
	if not player_3d.action_rejected.is_connected(show_action_rejection):
		player_3d.action_rejected.connect(show_action_rejection)
	if not player_3d.area_skill_effect_requested.is_connected(show_area_skill_effect):
		player_3d.area_skill_effect_requested.connect(show_area_skill_effect)
	if not player_3d.pointer_intent_cancelled.is_connected(
		pointer_controller.cancel_pointer_intent
	):
		player_3d.pointer_intent_cancelled.connect(
			pointer_controller.cancel_pointer_intent
		)
	if not player_3d.navigation_failed.is_connected(
		pointer_controller.handle_navigation_failure
	):
		player_3d.navigation_failed.connect(pointer_controller.handle_navigation_failure)


func _place_player(spawn_id: StringName) -> void:
	var location := scene_context.game_run.location
	if location.map_id == map_id and location.has_exact_position:
		player_3d.position = location.position
		player_3d.set_direction(location.direction)
		return
	var marker := spawn_points_3d.get_node_or_null(NodePath(String(spawn_id))) as Node3D
	if marker == null and spawn_points_3d.get_child_count() > 0:
		marker = spawn_points_3d.get_child(0) as Node3D
	if marker == null:
		push_error("3D map %s has no spawn point for %s" % [map_id, spawn_id])
		return
	player_3d.position = marker.position
	player_3d.set_direction(&"north")
	location.map_id = map_id
	location.spawn_id = spawn_id
	location.has_exact_position = false


func capture_location() -> void:
	if scene_context == null or player_3d == null or definition == null:
		return
	var location := scene_context.game_run.location
	location.map_id = definition.id
	location.spawn_id = &""
	location.position = player_3d.position
	location.direction = player_3d.direction
	location.has_exact_position = true


func _apply_player_control(movement_enabled: bool, can_interact: bool) -> void:
	if player_3d == null:
		return
	player_3d.set_control_enabled(movement_enabled)
	player_3d.set_interaction_enabled(can_interact)


func complete_entity(entity_id: StringName) -> void:
	for child: Node in encounter_sources.get_children():
		if child is EncounterSource3D and (child as EncounterSource3D).persistent_id == entity_id:
			(child as EncounterSource3D).apply_completed()
	for interactable: StoryInteractable3D in _map_interactables_3d():
		if interactable.persistent_id == entity_id:
			interactable.apply_completed()
	_refresh_world_state_views_3d()


func run_encounter_source(source: EncounterSource3D) -> void:
	if (
		source == null
		or source.triggering
		or battle_session != null
		or scene_context.story_director.is_busy()
	):
		return
	source.triggering = true
	_active_source = source
	await scene_context.story_director.run_binding(
		source.binding,
		source.story_origin(map_id),
		self
	)
	if not is_instance_valid(self):
		return
	if source.process_mode != Node.PROCESS_MODE_DISABLED and battle_session == null:
		source.triggering = false
	if _active_source == source and battle_session == null:
		_active_source = null
	_refresh_objective()


func begin_encounter_source_battle(source: EncounterSource3D) -> BattleSession:
	if source == null or source.encounter == null or battle_session != null:
		return null
	_active_source = source
	source.triggering = true
	return begin_battle(source.encounter)


func request_escape_if_source_returned(source: EncounterSource3D) -> void:
	if source == _active_source and battle_session != null and source.all_living_enemies_home():
		escape_battle()


func enemy_views() -> Array[EnemyActorView3D]:
	var result: Array[EnemyActorView3D] = []
	for child: Node in enemy_root.get_children():
		if child is EnemyActorView3D:
			result.append(child as EnemyActorView3D)
	return result


func spawn_battle_projectile(
	actor_id: StringName,
	action_instance_id: int,
	origin: Vector3,
	direction: Vector3,
	speed_override: float = 0.0
) -> void:
	_battle_presentation.spawn_projectile(
		actor_id,
		action_instance_id,
		origin,
		direction,
		speed_override
	)


func show_damage_number(position_3d: Vector3, amount: int, enemy_damage: bool) -> void:
	_battle_presentation.show_damage_number(position_3d, amount, enemy_damage)


func show_area_skill_effect(
	position_3d: Vector3,
	radius: float,
	color: Color
) -> void:
	_battle_presentation.show_area_skill_effect(position_3d, radius, color)


func refresh_player_state() -> void:
	if scene_context == null or player_3d == null:
		return
	var leader := scene_context.game_run.party.leader()
	var foundation := (
		scene_context.content_database.foundation(leader.foundation_id)
		if leader != null
		else null
	)
	player_3d.set_cultivation_aura(
		foundation.aura_color if foundation != null else Color.WHITE,
		foundation != null
	)


func _on_battle_started_3d(session: BattleSession) -> void:
	if _active_source == null:
		return
	_active_source.begin_session(session)
	pointer_controller.cancel_pointer_intent()
	player_3d.bind_map(self, camera_3d)
	player_3d.hurtbox.configure(session.player.id)
	map_hud.show_battle()
	player_3d.set_aim_marker_visible(true)
	_refresh_battle_hud()
	result_label.visible = false
	if session.encounter.battle_music != null:
		scene_context.audio_service.play_music(session.encounter.battle_music)


func _on_battle_events_3d(events: Array[BattleEvent]) -> void:
	for event: BattleEvent in events:
		_play_battle_event_sound(event)
		_battle_presentation.show_event_feedback(event)
		if (
			event.kind == BattleEvent.Kind.ACTION_REJECTED
			and battle_session != null
			and event.actor_id == battle_session.player.id
		):
			map_hud.show_rejection(event.rejection)
		player_3d.handle_battle_event(event)
		for enemy_view: EnemyActorView3D in enemy_views():
			enemy_view.handle_battle_event(event)


func start_hit_stop(duration: float) -> void:
	_battle_presentation.start_hit_stop(duration)


func restore_hit_stop_motion() -> void:
	_battle_presentation.restore_hit_stop_motion()


func is_hit_stop_active() -> bool:
	return _battle_presentation.is_hit_stop_active()


func hit_stop_remaining_seconds() -> float:
	return _battle_presentation.hit_stop_remaining_seconds()


func paused_battle_motion_count() -> int:
	return _battle_presentation.paused_battle_motion_count()


func _on_battle_finished_3d(result: BattleResult) -> void:
	restore_hit_stop_motion()
	pointer_controller.cancel_pointer_intent()
	map_hud.hide_battle()
	player_3d.set_aim_marker_visible(false)
	var summary_keys := [
		"UI_HUD_RESULT_VICTORY",
		"UI_HUD_RESULT_ESCAPED",
		"UI_HUD_RESULT_DEFEAT",
		"UI_HUD_RESULT_CANCELLED",
	]
	var summary: String = tr(summary_keys[result.outcome])
	if result.outcome == BattleResult.Outcome.VICTORY:
		if result.cultivation_reward > 0:
			summary += tr("UI_HUD_REWARD_CULTIVATION") % result.cultivation_reward
		if result.money_reward > 0:
			summary += tr("UI_HUD_REWARD_MONEY") % result.money_reward
		if not result.dropped_items.is_empty():
			summary += tr("UI_HUD_REWARD_ITEMS")
	result_label.text = summary
	result_label.visible = true
	var tween := create_tween()
	tween.tween_interval(1.2)
	tween.tween_callback(func() -> void: result_label.visible = false)
	if result.outcome == BattleResult.Outcome.ESCAPED and _active_source != null:
		_active_source.reset_after_escape()
	if definition != null:
		scene_context.audio_service.play_music(definition.music)


func _play_battle_event_sound(event: BattleEvent) -> void:
	var sound: AudioStream
	match event.kind:
		BattleEvent.Kind.ACTION_STARTED:
			if event.action_id == BattleSession.CHARGE_ID:
				sound = charge_windup_sound
			elif battle_session != null and event.actor_id == battle_session.player.id:
				var actor := battle_session.actor(event.actor_id)
				if (
					actor != null
					and actor.current_action != null
					and actor.current_action.intent.skill != null
				):
					sound = actor.current_action.intent.skill.sound
		BattleEvent.Kind.DODGE_STARTED:
			sound = dodge_sound
		BattleEvent.Kind.DAMAGE, BattleEvent.Kind.STATUS_TICK:
			sound = hit_sound
		BattleEvent.Kind.PILLAR_CONSUMED:
			sound = pillar_stagger_sound
		BattleEvent.Kind.OUTCOME:
			match BattleResult.Outcome.values()[event.amount]:
				BattleResult.Outcome.VICTORY:
					sound = victory_sound
				BattleResult.Outcome.ESCAPED:
					sound = escaped_sound
				BattleResult.Outcome.DEFEAT:
					sound = defeat_sound
	if sound != null:
		scene_context.audio_service.play_sound(sound)


func _on_player_interact_3d() -> void:
	var interactable := _nearest_interactable_3d()
	if interactable == null:
		return
	await run_interactable(interactable)


func run_interactable(interactable: StoryInteractable3D) -> void:
	await scene_context.story_director.run_binding(
		interactable.binding,
		interactable.story_origin(map_id),
		self
	)
	if is_instance_valid(self):
		_refresh_world_state_views_3d()
		_refresh_objective()


func show_action_rejection(rejection: BattleActionRequestResult.Rejection) -> void:
	map_hud.show_rejection(rejection)


func _nearest_interactable_3d() -> StoryInteractable3D:
	var nearest: StoryInteractable3D
	var nearest_distance := 2.2
	for interactable: StoryInteractable3D in _map_interactables_3d():
		if not interactable.is_available():
			continue
		var distance := player_3d.global_position.distance_to(interactable.global_position)
		if distance < nearest_distance:
			nearest = interactable
			nearest_distance = distance
	return nearest


func _map_interactables_3d() -> Array[StoryInteractable3D]:
	var result: Array[StoryInteractable3D] = []
	for candidate: Node in get_tree().get_nodes_in_group(&"story_interactables_3d"):
		if candidate is StoryInteractable3D and is_ancestor_of(candidate):
			result.append(candidate as StoryInteractable3D)
	return result


func _world_state_views_3d() -> Array[WorldStateView3D]:
	var result: Array[WorldStateView3D] = []
	_collect_world_state_views_3d(world_root, result)
	return result


func _collect_world_state_views_3d(
	node: Node,
	result: Array[WorldStateView3D]
) -> void:
	for child: Node in node.get_children():
		if child is WorldStateView3D:
			result.append(child as WorldStateView3D)
		_collect_world_state_views_3d(child, result)


func _refresh_world_state_views_3d() -> void:
	for view: WorldStateView3D in _world_state_views_3d():
		view.refresh_world_state()


func _camera_interest_target() -> Node3D:
	return _hud_target_view() if battle_session != null else null


func _refresh_battle_hud() -> void:
	if battle_session == null:
		return
	var actor_state := scene_context.game_run.party.leader()
	var target_view := _hud_target_view()
	map_hud.refresh_battle(
		battle_session,
		actor_state,
		scene_context.content_database,
		battle_session.actor(target_view.actor_id) if target_view != null else null,
		target_view.definition if target_view != null else null
	)


func _hud_target_view() -> EnemyActorView3D:
	return pointer_controller.preferred_hud_target()


func _refresh_interaction_prompt() -> void:
	if (
		battle_session != null
		or not player_3d.interaction_enabled
		or scene_context == null
		or scene_context.story_director.is_busy()
	):
		map_hud.show_interaction("")
		_set_destination_labels_suppressed(false)
		return
	var interactable := _nearest_interactable_3d()
	map_hud.show_interaction(
		_interaction_text(interactable) if interactable != null else ""
	)
	_set_destination_labels_suppressed(interactable != null)


func _set_destination_labels_suppressed(suppressed: bool) -> void:
	if not suppressed:
		for label: DestinationLabel3D in _suppressed_destination_labels:
			if is_instance_valid(label):
				label.set_context_suppressed(false)
		_suppressed_destination_labels.clear()
		return
	if not _suppressed_destination_labels.is_empty():
		return
	for child: Node in world_root.find_children("*", "", true, false):
		if child is DestinationLabel3D:
			var label := child as DestinationLabel3D
			label.set_context_suppressed(true)
			_suppressed_destination_labels.append(label)


func _interaction_text(interactable: StoryInteractable3D) -> String:
	if not interactable.interaction_label.is_empty():
		return interactable.interaction_label
	if not interactable.portal_target_map_id.is_empty():
		var target_map := scene_context.content_database.map(
			interactable.portal_target_map_id
		)
		return (
			tr("UI_HUD_TRAVEL_FORMAT") % target_map.display_name
			if target_map != null
			else tr("UI_HUD_TRAVEL_OTHER")
		)
	if not interactable.actor_definition_id.is_empty():
		return tr("UI_HUD_TALK")
	return tr("UI_HUD_INTERACT")


func _refresh_objective() -> void:
	if map_hud == null or scene_context == null:
		return
	var objective := ""
	if story_module != null:
		var stage := scene_context.game_run.story.get_stage(
			story_module.id,
			story_module.initial_stage
		)
		objective = story_module.get_objective_text(stage, map_id)
	map_hud.show_objective(objective)
