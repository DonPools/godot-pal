class_name MapGameScene3D
extends MapGameScene

const PROJECTILE_SCENE := preload(
	"res://framework/presentation/action_combat_3d/battle_projectile_3d.tscn"
)
const CAMERA_OFFSET := Vector3(10.0, 10.0, 10.0)

@export var hit_sound: AudioStream
@export var dodge_sound: AudioStream
@export var victory_sound: AudioStream
@export var escaped_sound: AudioStream
@export var defeat_sound: AudioStream

@onready var world_root: Node3D = $WorldRoot
@onready var player_3d: PlayerCharacter3D = $WorldRoot/PlayerCharacter3D
@onready var enemy_root: Node3D = $WorldRoot/Enemies
@onready var encounter_sources: Node3D = $WorldRoot/EncounterSources
@onready var spawn_points_3d: Node3D = $WorldRoot/SpawnPoints
@onready var camera_3d: Camera3D = $Camera3D
@onready var battle_hud: Control = $HudLayer/BattleHud
@onready var hp_label: Label = $HudLayer/BattleHud/Panel/Margin/Rows/Hp
@onready var mp_label: Label = $HudLayer/BattleHud/Panel/Margin/Rows/Mp
@onready var skills_label: Label = $HudLayer/BattleHud/Panel/Margin/Rows/Skills
@onready var encounter_label: Label = $HudLayer/BattleHud/Panel/Margin/Rows/Encounter
@onready var result_label: Label = $HudLayer/Result

var _active_source: EncounterSource3D
var _using_pointer_aim: bool = true
var _camera_focus := Vector3.ZERO
var _camera_initialized: bool = false


func _ready() -> void:
	battle_started.connect(_on_battle_started_3d)
	battle_events_produced.connect(_on_battle_events_3d)
	battle_finished.connect(_on_battle_finished_3d)
	battle_hud.visible = false
	result_label.visible = false


func _process(delta: float) -> void:
	super._process(delta)
	_update_camera(delta)
	_update_aim()
	_refresh_battle_hud()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_using_pointer_aim = true
	elif (
		event is InputEventJoypadMotion
		and absf(event.axis_value) > 0.25
		and event.axis in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]
	):
		_using_pointer_aim = false


func _configure_characters() -> void:
	var leader := scene_context.game_run.party.leader()
	var actor_definition := (
		scene_context.content_database.actor(leader.definition_id)
		if leader != null
		else null
	)
	player_3d.configure(actor_definition)
	player_3d.bind_map(self, camera_3d)
	for view: WorldStateView3D in _world_state_views_3d():
		view.configure_world_state(scene_context.game_run, map_id)


func _configure_interactables() -> void:
	for interactable: StoryInteractable3D in _map_interactables_3d():
		if not interactable.portal_target_map_id.is_empty():
			var portal := ScenePortalEvent.new()
			portal.target_map = scene_context.content_database.map(
				interactable.portal_target_map_id
			)
			portal.target_spawn_id = interactable.portal_target_spawn_id
			interactable.configure_story(portal)
		else:
			interactable.configure_story(story_module)
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
	if battle_session == null:
		return
	var projectile := PROJECTILE_SCENE.instantiate() as BattleProjectile3D
	world_root.add_child(projectile)
	projectile.global_position = origin
	var actor := battle_session.actor(actor_id)
	var speed := speed_override
	var max_range := 9.0
	if actor != null and actor.current_action != null and actor.current_action.intent.skill != null:
		max_range = actor.current_action.intent.skill.max_range
	if speed <= 0.0:
		speed = 9.0
	projectile.configure(
		self,
		actor_id,
		action_instance_id,
		direction,
		speed,
		actor_id != battle_session.player.id,
		max_range / speed
	)


func show_damage_number(position_3d: Vector3, amount: int, enemy_damage: bool) -> void:
	var label := Label.new()
	label.text = str(amount)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.82, 0.32) if enemy_damage else Color(1.0, 0.35, 0.28)
	)
	label.position = camera_3d.unproject_position(position_3d) - Vector2(18.0, 12.0)
	$HudLayer.add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y - 24.0, 0.55)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.55)
	tween.tween_callback(label.queue_free)


func _on_battle_started_3d(session: BattleSession) -> void:
	if _active_source == null:
		return
	_active_source.begin_session(session)
	player_3d.bind_map(self, camera_3d)
	player_3d.hurtbox.configure(session.player.id)
	battle_hud.visible = true
	result_label.visible = false
	if session.encounter.battle_music != null:
		scene_context.audio_service.play_music(session.encounter.battle_music)


func _on_battle_events_3d(events: Array[BattleEvent]) -> void:
	for event: BattleEvent in events:
		_play_battle_event_sound(event)
		player_3d.handle_battle_event(event)
		for enemy_view: EnemyActorView3D in enemy_views():
			enemy_view.handle_battle_event(event)


func _on_battle_finished_3d(result: BattleResult) -> void:
	battle_hud.visible = false
	result_label.text = ["胜利", "脱离", "战败", "中止"][result.outcome]
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
			if battle_session != null and event.actor_id == battle_session.player.id:
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
	await scene_context.story_director.run_binding(
		interactable.binding,
		interactable.story_origin(map_id),
		self
	)
	if is_instance_valid(self):
		_refresh_world_state_views_3d()
		_refresh_objective()


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


func _update_camera(delta: float) -> void:
	if player_3d == null:
		return
	var desired := player_3d.global_position + player_3d.aim_direction() * 1.8
	if not _camera_initialized or delta <= 0.0:
		_camera_focus = desired
		_camera_initialized = true
	else:
		_camera_focus = _camera_focus.lerp(desired, 1.0 - exp(-8.0 * delta))
	camera_3d.global_position = _camera_focus + CAMERA_OFFSET
	camera_3d.look_at(_camera_focus, Vector3.UP)


func _update_aim() -> void:
	if not player_3d.control_enabled:
		return
	var stick := Input.get_vector(&"aim_west", &"aim_east", &"aim_north", &"aim_south")
	if stick.length() > 0.25:
		var right := camera_3d.global_basis.x
		right.y = 0.0
		var forward := -camera_3d.global_basis.z
		forward.y = 0.0
		player_3d.set_aim_direction(
			right.normalized() * stick.x + forward.normalized() * -stick.y
		)
		return
	if _using_pointer_aim:
		var ray_origin := camera_3d.project_ray_origin(get_viewport().get_mouse_position())
		var ray_direction := camera_3d.project_ray_normal(get_viewport().get_mouse_position())
		if absf(ray_direction.y) > 0.0001:
			var distance := -ray_origin.y / ray_direction.y
			if distance > 0.0:
				player_3d.set_aim_direction(
					ray_origin + ray_direction * distance - player_3d.global_position
				)
		return
	var target_direction := _soft_target_direction()
	player_3d.set_aim_direction(
		target_direction
		if not target_direction.is_zero_approx()
		else player_3d.movement_direction()
	)


func _soft_target_direction() -> Vector3:
	var nearest: EnemyActorView3D
	var nearest_distance := 8.0
	for enemy_view: EnemyActorView3D in enemy_views():
		if enemy_view.is_defeated():
			continue
		var direction := enemy_view.global_position - player_3d.global_position
		direction.y = 0.0
		var distance := direction.length()
		if distance < nearest_distance and distance > 0.001:
			nearest = enemy_view
			nearest_distance = distance
	return nearest.global_position - player_3d.global_position if nearest != null else Vector3.ZERO


func _refresh_battle_hud() -> void:
	if battle_session == null:
		return
	hp_label.text = "体力 %d / %d" % [battle_session.player.hp, battle_session.player.max_hp]
	mp_label.text = "真气 %d / %d" % [battle_session.player.mp, battle_session.player.max_mp]
	var actor_state := scene_context.game_run.party.leader()
	var skill_texts: PackedStringArray = []
	if actor_state != null:
		for skill_id: StringName in actor_state.skill_ids.slice(0, 2):
			var skill := scene_context.content_database.skill(skill_id)
			if skill != null:
				skill_texts.append(
					"%s %.1f" % [skill.display_name, battle_session.player.cooldown_remaining(skill.id)]
				)
	skills_label.text = "Q / E  %s" % "   ".join(skill_texts)
	var alive := 0
	for enemy: BattleActorState in battle_session.enemies:
		if enemy.is_alive():
			alive += 1
	encounter_label.text = "敌人 %d   Space/B 闪避   R 道具" % alive


func _refresh_objective() -> void:
	if objective_label == null or scene_context == null:
		return
	for child: Node in encounter_sources.get_children():
		if not child is EncounterSource3D:
			continue
		var source := child as EncounterSource3D
		if not source.event is StoryModule:
			continue
		var module := source.event as StoryModule
		var stage := scene_context.game_run.story.get_stage(module.id, module.initial_stage)
		var objective := module.get_objective_text(stage, map_id)
		if not objective.is_empty():
			objective_label.text = objective
			return
	objective_label.text = "WASD/摇杆移动 · 鼠标/右摇杆瞄准 · Enter/A 互动"
