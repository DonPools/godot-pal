class_name MapGameScene3D
extends MapGameScene

const PROJECTILE_SCENE := preload(
	"res://framework/presentation/action_combat_3d/battle_projectile_3d.tscn"
)
const CAMERA_OFFSET := Vector3(10.0, 10.0, 10.0)
const POINTER_TARGET_MASK := 1 << 4
const WORLD_COLLISION_MASK := 1 << 1
const POINTER_RAY_DISTANCE := 180.0
const INTERACTION_DISTANCE := 2.1
const INTERACTION_STOPPING_DISTANCE := 1.45
const BASIC_ATTACK_DISTANCE := 1.65
const SOFT_TARGET_ACQUIRE_DISTANCE := 8.0
const SOFT_TARGET_RETAIN_DISTANCE := 10.0
const SOFT_TARGET_ACQUIRE_ANGLE_DEGREES := 50.0
const SOFT_TARGET_RETAIN_ANGLE_DEGREES := 65.0
const PLAYER_HIT_STOP_SECONDS := 0.065
const ENEMY_HIT_STOP_SECONDS := 0.045
const REDUCED_HIT_STOP_SCALE := 0.35

@export var hit_sound: AudioStream
@export var dodge_sound: AudioStream
@export var victory_sound: AudioStream
@export var escaped_sound: AudioStream
@export var defeat_sound: AudioStream
@export var charge_windup_sound: AudioStream
@export var pillar_stagger_sound: AudioStream
@export var move_cursor: Texture2D
@export var attack_cursor: Texture2D
@export var interact_cursor: Texture2D
@export var forbidden_cursor: Texture2D

@onready var world_root: Node3D = $WorldRoot
@onready var player_3d: PlayerCharacter3D = $WorldRoot/PlayerCharacter3D
@onready var enemy_root: Node3D = $WorldRoot/Enemies
@onready var encounter_sources: Node3D = $WorldRoot/EncounterSources
@onready var spawn_points_3d: Node3D = $WorldRoot/SpawnPoints
@onready var pointer_feedback: PointerFeedback3D = $WorldRoot/PointerFeedback3D
@onready var combat_feedback: CombatFeedback3D = $WorldRoot/CombatFeedback3D
@onready var camera_3d: Camera3D = $Camera3D
@onready var map_hud: MapHud3D = $HudLayer/MapHud
@onready var battle_hud: Control = $HudLayer/MapHud/BattlePanel
@onready var result_label: Label = $HudLayer/Result

var _active_source: EncounterSource3D
var _using_pointer_aim: bool = true
var _camera_focus := Vector3.ZERO
var _camera_initialized: bool = false
var _primary_pointer_pressed: bool = false
var _queued_primary_attack: bool = false
var _stand_ground_attack: bool = false
var _pointer_attack_point := Vector3.ZERO
var _pointer_enemy: EnemyActorView3D
var _pointer_interactable: StoryInteractable3D
var _pointer_interaction_running: bool = false
var _soft_target: EnemyActorView3D
var _hit_stop_remaining: float = 0.0
var _hit_stop_physics_states: Dictionary = {}
var _faded_camera_obstacles: Dictionary = {}


func enter(context: GameSceneContext, arguments: Variant) -> void:
	map_hud.configure(context.settings_service)
	combat_feedback.configure(context.settings_service)
	super.enter(context, arguments)
	player_3d.configure_input_tuning(context.settings_service.movement_deadzone)


func _ready() -> void:
	battle_started.connect(_on_battle_started_3d)
	battle_events_produced.connect(_on_battle_events_3d)
	battle_finished.connect(_on_battle_finished_3d)
	_register_custom_cursors()
	map_hud.set_input_device(false)
	result_label.visible = false


func _process(delta: float) -> void:
	if _hit_stop_remaining > 0.0:
		_hit_stop_remaining = maxf(_hit_stop_remaining - delta, 0.0)
		if _hit_stop_remaining <= 0.0:
			_restore_hit_stop_motion()
	else:
		super._process(delta)
	_update_camera(delta)
	_update_camera_occlusion()
	_update_aim(delta)
	_update_pointer_intent()
	_update_cursor_context()
	_refresh_battle_hud()
	_refresh_interaction_prompt()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_using_pointer_aim = true
		_soft_target = null
		map_hud.set_input_device(false)
	elif event is InputEventKey:
		map_hud.set_input_device(false)
	elif (
		event is InputEventJoypadMotion
		and absf(event.axis_value) > 0.25
		and event.axis in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]
	):
		_using_pointer_aim = false
		map_hud.set_input_device(true)
	elif event is InputEventJoypadButton:
		map_hud.set_input_device(true)


func _unhandled_input(event: InputEvent) -> void:
	if (
		not player_3d.control_enabled
		or scene_context == null
		or scene_context.story_director.is_busy()
	):
		return
	if event.is_action_pressed(&"combat_target_next") and battle_session != null:
		_using_pointer_aim = false
		_cycle_soft_target()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if not mouse_event.is_action(&"combat_attack"):
			return
		_primary_pointer_pressed = mouse_event.pressed
		if mouse_event.pressed:
			_handle_primary_pointer(mouse_event)
		elif not _queued_primary_attack:
			_clear_pointer_attack(false)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _primary_pointer_pressed:
		if _pointer_enemy == null and _pointer_interactable == null and not _stand_ground_attack:
			_begin_ground_navigation((event as InputEventMouseMotion).position)
			get_viewport().set_input_as_handled()


func exit_scene() -> void:
	_restore_hit_stop_motion()
	_restore_camera_obstacles()
	_soft_target = null
	_clear_pointer_intent()
	_clear_custom_cursors()
	super.exit_scene()


func pause_scene() -> void:
	_restore_hit_stop_motion()
	_restore_camera_obstacles()
	_soft_target = null
	_clear_pointer_intent()
	_clear_custom_cursors()
	super.pause_scene()


func resume_scene(result: Variant = null) -> void:
	super.resume_scene(result)
	_register_custom_cursors()


func _configure_characters() -> void:
	var leader := scene_context.game_run.party.leader()
	var actor_definition := (
		scene_context.content_database.actor(leader.definition_id)
		if leader != null
		else null
	)
	player_3d.configure(actor_definition)
	player_3d.bind_map(self, camera_3d)
	refresh_player_state()
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
	if not player_3d.pointer_intent_cancelled.is_connected(_clear_pointer_intent):
		player_3d.pointer_intent_cancelled.connect(_clear_pointer_intent)
	if not player_3d.navigation_failed.is_connected(_on_player_navigation_failed):
		player_3d.navigation_failed.connect(_on_player_navigation_failed)


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
	var returns_to_origin := battle_session.projectile_returns(action_instance_id)
	projectile.configure(
		self,
		actor_id,
		action_instance_id,
		direction,
		speed,
		actor_id != battle_session.player.id,
		(max_range / speed) * (2.0 if returns_to_origin else 1.0),
		returns_to_origin,
		battle_session.projectile_pierces(action_instance_id)
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


func show_area_skill_effect(
	position_3d: Vector3,
	radius: float,
	color: Color
) -> void:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.035
	mesh.material = material
	var effect := MeshInstance3D.new()
	effect.mesh = mesh
	world_root.add_child(effect)
	effect.global_position = position_3d + Vector3.UP * 0.06
	effect.scale = Vector3(0.15, 1.0, 0.15)
	var tween := effect.create_tween()
	tween.tween_property(effect, "scale", Vector3(radius, 1.0, radius), 0.22)
	tween.tween_interval(0.12)
	tween.tween_callback(effect.queue_free)


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
	_clear_pointer_intent()
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
		_show_battle_event_feedback(event)
		if (
			event.kind == BattleEvent.Kind.ACTION_REJECTED
			and battle_session != null
			and event.actor_id == battle_session.player.id
		):
			map_hud.show_rejection(event.rejection)
		player_3d.handle_battle_event(event)
		for enemy_view: EnemyActorView3D in enemy_views():
			enemy_view.handle_battle_event(event)


func _show_battle_event_feedback(event: BattleEvent) -> void:
	if battle_session == null:
		return
	match event.kind:
		BattleEvent.Kind.ACTION_ACTIVE:
			if event.actor_id == battle_session.player.id:
				var actor := battle_session.actor(event.actor_id)
				var empowered := (
					actor != null
					and actor.current_action != null
					and actor.current_action.intent.skill != null
				)
				combat_feedback.show_slash(
					player_3d.global_position + Vector3.UP * 0.92,
					player_3d.aim_direction(),
					empowered
				)
		BattleEvent.Kind.DODGE_STARTED:
			if event.actor_id == battle_session.player.id:
				var dodge_direction := player_3d.movement_direction()
				combat_feedback.show_dodge_afterimages(
					player_3d,
					dodge_direction
					if not dodge_direction.is_zero_approx()
					else player_3d.aim_direction()
				)
		BattleEvent.Kind.DAMAGE:
			var target := _actor_view_3d(event.target_id)
			if target == null:
				return
			var player_was_hit := event.target_id == battle_session.player.id
			combat_feedback.flash_actor(target, player_was_hit)
			combat_feedback.show_hit_spark(
				target.global_position + Vector3.UP * (1.0 if player_was_hit else 0.82),
				player_was_hit
			)
			_start_hit_stop(
				PLAYER_HIT_STOP_SECONDS if player_was_hit else ENEMY_HIT_STOP_SECONDS
			)


func _actor_view_3d(actor_id: StringName) -> Node3D:
	if battle_session != null and actor_id == battle_session.player.id:
		return player_3d
	for enemy_view: EnemyActorView3D in enemy_views():
		if enemy_view.actor_id == actor_id:
			return enemy_view
	return null


func _start_hit_stop(duration: float) -> void:
	var applied_duration := duration
	if (
		scene_context != null
		and scene_context.settings_service != null
		and scene_context.settings_service.reduce_combat_flashes
	):
		applied_duration *= REDUCED_HIT_STOP_SCALE
	_hit_stop_remaining = maxf(_hit_stop_remaining, applied_duration)
	if not _hit_stop_physics_states.is_empty():
		return
	for candidate: Node in get_tree().get_nodes_in_group(&"battle_motion_3d"):
		if not is_ancestor_of(candidate):
			continue
		_hit_stop_physics_states[candidate] = candidate.is_physics_processing()
		candidate.set_physics_process(false)


func _restore_hit_stop_motion() -> void:
	_hit_stop_remaining = 0.0
	for candidate: Node in _hit_stop_physics_states:
		if is_instance_valid(candidate):
			candidate.set_physics_process(bool(_hit_stop_physics_states[candidate]))
	_hit_stop_physics_states.clear()


func is_hit_stop_active() -> bool:
	return _hit_stop_remaining > 0.0


func _on_battle_finished_3d(result: BattleResult) -> void:
	_restore_hit_stop_motion()
	_clear_pointer_intent()
	map_hud.hide_battle()
	player_3d.set_aim_marker_visible(false)
	var summary: String = String(["胜利", "脱离", "战败", "中止"][result.outcome])
	if result.outcome == BattleResult.Outcome.VICTORY:
		if result.cultivation_reward > 0:
			summary += "　修为 +%d" % result.cultivation_reward
		if result.money_reward > 0:
			summary += "　灵钱 +%d" % result.money_reward
		if not result.dropped_items.is_empty():
			summary += "　获得战利品"
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
	await _run_interactable(interactable)


func _run_interactable(interactable: StoryInteractable3D) -> void:
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


func _update_camera(delta: float) -> void:
	if player_3d == null:
		return
	var desired := player_3d.global_position + player_3d.aim_direction() * 1.8
	if battle_session != null:
		var interest_target := _hud_target_view()
		if interest_target != null:
			var target_offset := interest_target.global_position - player_3d.global_position
			target_offset.y = 0.0
			if not target_offset.is_zero_approx():
				desired = player_3d.global_position + target_offset.normalized() * minf(
				target_offset.length() * 0.6,
				3.2
			)
	if not _camera_initialized or delta <= 0.0:
		_camera_focus = desired
		_camera_initialized = true
	else:
		_camera_focus = _camera_focus.lerp(desired, 1.0 - exp(-8.0 * delta))
	camera_3d.global_position = _camera_focus + CAMERA_OFFSET
	camera_3d.look_at(_camera_focus, Vector3.UP)


func _update_camera_occlusion() -> void:
	if player_3d == null or camera_3d == null:
		return
	var desired: Dictionary = {}
	var excluded: Array[RID] = [player_3d.hurtbox.get_rid()]
	var target := player_3d.global_position + Vector3.UP * 0.95
	for _hit_index: int in range(4):
		var query := PhysicsRayQueryParameters3D.create(
			camera_3d.global_position, target, WORLD_COLLISION_MASK
		)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.exclude = excluded
		var hit := camera_3d.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			break
		var collider := hit.get("collider") as CollisionObject3D
		if collider == null or not collider.is_in_group(&"camera_fade_obstacle"):
			break
		desired[collider] = true
		excluded.append(collider.get_rid())
	_apply_camera_obstacle_fade(desired)


func _apply_camera_obstacle_fade(desired: Dictionary) -> void:
	for obstacle: Node in _faded_camera_obstacles.keys():
		if desired.has(obstacle) and is_instance_valid(obstacle):
			continue
		if is_instance_valid(obstacle):
			for mesh: MeshInstance3D in _faded_camera_obstacles[obstacle]:
				if is_instance_valid(mesh):
					mesh.transparency = 0.0
		_faded_camera_obstacles.erase(obstacle)
	for obstacle: Node in desired:
		if _faded_camera_obstacles.has(obstacle):
			continue
		var meshes: Array[MeshInstance3D] = []
		_collect_mesh_instances(obstacle, meshes)
		for mesh: MeshInstance3D in meshes:
			mesh.transparency = 0.62
		_faded_camera_obstacles[obstacle] = meshes


func _restore_camera_obstacles() -> void:
	_apply_camera_obstacle_fade({})


func _collect_mesh_instances(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_mesh_instances(child, result)


func _update_aim(delta: float) -> void:
	if not player_3d.control_enabled:
		return
	var settings: SettingsService = (
		scene_context.settings_service if scene_context != null else null
	)
	var deadzone := settings.aim_deadzone if settings != null else 0.25
	var sensitivity := settings.aim_sensitivity if settings != null else 1.0
	var stick := Input.get_vector(
		&"aim_west", &"aim_east", &"aim_north", &"aim_south", deadzone
	)
	if stick.length() > deadzone:
		var right := camera_3d.global_basis.x
		right.y = 0.0
		var forward := -camera_3d.global_basis.z
		forward.y = 0.0
		_soft_target = null
		if _pointer_enemy == null:
			pointer_feedback.clear_target()
		player_3d.turn_aim_toward(
			right.normalized() * stick.x + forward.normalized() * -stick.y,
			1.0 - exp(-14.0 * sensitivity * maxf(delta, 0.0001))
		)
		return
	if _using_pointer_aim:
		_soft_target = null
		if _pointer_enemy == null:
			pointer_feedback.clear_target()
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
	if not target_direction.is_zero_approx():
		player_3d.turn_aim_toward(
			target_direction,
			1.0 - exp(-10.0 * sensitivity * maxf(delta, 0.0001))
		)
		if _soft_target != null:
			pointer_feedback.set_target(_soft_target, _target_ring_radius(_soft_target))
	elif not player_3d.movement_direction().is_zero_approx():
		player_3d.turn_aim_toward(
			player_3d.movement_direction(),
			1.0 - exp(-8.0 * sensitivity * maxf(delta, 0.0001))
		)
		pointer_feedback.clear_target()
	else:
		pointer_feedback.clear_target()


func _soft_target_direction() -> Vector3:
	if battle_session == null:
		_soft_target = null
		return Vector3.ZERO
	if _soft_target_is_valid(
		_soft_target,
		SOFT_TARGET_RETAIN_DISTANCE,
		SOFT_TARGET_RETAIN_ANGLE_DEGREES
	):
		return _soft_target.global_position - player_3d.global_position
	_soft_target = null
	var best_score := INF
	for enemy_view: EnemyActorView3D in enemy_views():
		if not _soft_target_is_valid(
			enemy_view,
			SOFT_TARGET_ACQUIRE_DISTANCE,
			SOFT_TARGET_ACQUIRE_ANGLE_DEGREES
		):
			continue
		var direction := enemy_view.global_position - player_3d.global_position
		direction.y = 0.0
		var angle := player_3d.aim_direction().angle_to(direction.normalized())
		var score := direction.length() + angle * 2.2
		if score < best_score:
			_soft_target = enemy_view
			best_score = score
	return (
		_soft_target.global_position - player_3d.global_position
		if _soft_target != null
		else Vector3.ZERO
	)


func _cycle_soft_target() -> void:
	var candidates: Array[EnemyActorView3D] = []
	for enemy_view: EnemyActorView3D in enemy_views():
		if _soft_target_is_visible(enemy_view, SOFT_TARGET_RETAIN_DISTANCE):
			candidates.append(enemy_view)
	if candidates.is_empty():
		_soft_target = null
		pointer_feedback.clear_target()
		map_hud.show_notice("附近没有可锁定目标")
		return
	candidates.sort_custom(func(left: EnemyActorView3D, right: EnemyActorView3D) -> bool:
		return camera_3d.unproject_position(left.global_position).x < camera_3d.unproject_position(
			right.global_position
		).x
	)
	var current_index := candidates.find(_soft_target)
	_soft_target = candidates[(current_index + 1) % candidates.size()]
	player_3d.set_aim_direction(_soft_target.global_position - player_3d.global_position)
	pointer_feedback.set_target(_soft_target, _target_ring_radius(_soft_target))
	map_hud.show_notice(
		"锁定：%s" % (
			_soft_target.definition.display_name
			if _soft_target.definition != null
			else "目标"
		)
	)


func _soft_target_is_valid(
	enemy: EnemyActorView3D,
	max_distance: float,
	max_angle_degrees: float
) -> bool:
	if not _soft_target_is_visible(enemy, max_distance):
		return false
	var direction := enemy.global_position - player_3d.global_position
	direction.y = 0.0
	return (
		not direction.is_zero_approx()
		and rad_to_deg(player_3d.aim_direction().angle_to(direction.normalized()))
		<= max_angle_degrees
	)


func _soft_target_is_visible(enemy: EnemyActorView3D, max_distance: float) -> bool:
	if enemy == null or not is_instance_valid(enemy) or enemy.is_defeated():
		return false
	var target_position := enemy.global_position + Vector3.UP * 0.85
	if player_3d.global_position.distance_to(enemy.global_position) > max_distance:
		return false
	if camera_3d.is_position_behind(target_position):
		return false
	var screen_position := camera_3d.unproject_position(target_position)
	if not get_viewport().get_visible_rect().has_point(screen_position):
		return false
	var query := PhysicsRayQueryParameters3D.create(
		camera_3d.global_position,
		target_position,
		POINTER_TARGET_MASK | WORLD_COLLISION_MASK
	)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [player_3d.hurtbox.get_rid()]
	var hit := camera_3d.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider := hit.get("collider") as Node
	return collider == enemy.hurtbox or (collider != null and enemy.is_ancestor_of(collider))


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
	for preferred: EnemyActorView3D in [_pointer_enemy, _soft_target]:
		if preferred != null and is_instance_valid(preferred) and not preferred.is_defeated():
			return preferred
	var only_living: EnemyActorView3D
	var living_count := 0
	for enemy_view: EnemyActorView3D in enemy_views():
		if enemy_view.is_defeated():
			continue
		living_count += 1
		only_living = enemy_view
		if (
			enemy_view.definition != null
			and enemy_view.definition.combat_style == EnemyDefinition.CombatStyle.CHARGER
		):
			return enemy_view
	return only_living if living_count == 1 else null


func _refresh_interaction_prompt() -> void:
	if (
		battle_session != null
		or not player_3d.interaction_enabled
		or scene_context == null
		or scene_context.story_director.is_busy()
	):
		map_hud.show_interaction("")
		return
	var interactable := _nearest_interactable_3d()
	map_hud.show_interaction(
		_interaction_text(interactable) if interactable != null else ""
	)


func _interaction_text(interactable: StoryInteractable3D) -> String:
	if not interactable.interaction_label.is_empty():
		return interactable.interaction_label
	if not interactable.portal_target_map_id.is_empty():
		var target_map := scene_context.content_database.map(
			interactable.portal_target_map_id
		)
		return "前往%s" % target_map.display_name if target_map != null else "前往别处"
	if not interactable.actor_definition_id.is_empty():
		return "交谈"
	return "互动"


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
	objective_label.text = "左键移动/互动 · WASD 可选 · M/Start 行囊"


func _handle_primary_pointer(event: InputEventMouseButton) -> void:
	var force_move := event.ctrl_pressed or Input.is_action_pressed(&"combat_force_move")
	var stand_ground := event.shift_pressed or Input.is_action_pressed(&"combat_stand_ground")
	if force_move:
		_begin_ground_navigation(event.position)
		return
	if battle_session != null:
		var enemy := _enemy_at_screen(event.position)
		if enemy != null:
			_begin_pointer_attack(enemy, stand_ground)
		elif stand_ground:
			_begin_stand_ground_attack(event.position)
		else:
			_begin_ground_navigation(event.position)
		return
	var interactable := _interactable_at_screen(event.position)
	if interactable != null:
		_begin_pointer_interaction(interactable)
	else:
		_begin_ground_navigation(event.position)


func _begin_ground_navigation(screen_position: Vector2) -> void:
	var ground_point: Variant = _screen_ground_point(screen_position)
	if ground_point == null:
		_show_navigation_failure(_screen_plane_fallback(screen_position))
		return
	_clear_pointer_intent(true, false)
	var destination := ground_point as Vector3
	var result := player_3d.navigate_to(destination)
	if _navigation_rejected(result):
		_show_navigation_failure(destination)
		return
	pointer_feedback.show_destination(
		player_3d.navigation_target_position()
		if result == PlayerCharacter3D.NavigationStartResult.STARTED
		else destination,
		PointerFeedback3D.DestinationKind.MOVE
	)


func _begin_pointer_interaction(interactable: StoryInteractable3D) -> void:
	_clear_pointer_intent(true, false)
	var result := player_3d.navigate_to(
		interactable.global_position,
		INTERACTION_STOPPING_DISTANCE
	)
	if _navigation_rejected(result):
		_show_navigation_failure(interactable.global_position)
		return
	_pointer_interactable = interactable
	pointer_feedback.show_destination(
		player_3d.navigation_target_position()
		if result == PlayerCharacter3D.NavigationStartResult.STARTED
		else interactable.global_position,
		PointerFeedback3D.DestinationKind.INTERACT
	)


func _begin_pointer_attack(enemy: EnemyActorView3D, stand_ground: bool) -> void:
	_clear_pointer_intent(true, false)
	_pointer_enemy = enemy
	_queued_primary_attack = true
	_stand_ground_attack = stand_ground
	_pointer_attack_point = enemy.global_position
	pointer_feedback.set_target(enemy, _target_ring_radius(enemy))


func _begin_stand_ground_attack(screen_position: Vector2) -> void:
	var ground_point: Variant = _screen_ground_point(screen_position)
	if ground_point == null:
		return
	_clear_pointer_intent(true, false)
	_pointer_attack_point = ground_point as Vector3
	_queued_primary_attack = true
	_stand_ground_attack = true
	player_3d.stop_navigation()
	pointer_feedback.show_destination(
		_pointer_attack_point,
		PointerFeedback3D.DestinationKind.MOVE
	)


func _update_pointer_intent() -> void:
	if (
		not player_3d.control_enabled
		or scene_context == null
		or scene_context.story_director.is_busy()
	):
		_clear_pointer_intent()
		return
	_update_pointer_interaction()
	_update_pointer_attack()


func _update_pointer_interaction() -> void:
	if _pointer_interactable == null or _pointer_interaction_running:
		return
	if not is_instance_valid(_pointer_interactable) or not _pointer_interactable.is_available():
		_clear_pointer_interaction()
		return
	if (
		player_3d.global_position.distance_to(_pointer_interactable.global_position)
		> INTERACTION_DISTANCE
	):
		var navigation_result := player_3d.navigate_to(
			_pointer_interactable.global_position,
			INTERACTION_STOPPING_DISTANCE
		)
		if _navigation_rejected(navigation_result):
			var failed_target := _pointer_interactable.global_position
			_clear_pointer_interaction()
			_show_navigation_failure(failed_target)
		return
	var interactable := _pointer_interactable
	_clear_pointer_interaction(false)
	_pointer_interaction_running = true
	_run_pointer_interaction(interactable)


func _run_pointer_interaction(interactable: StoryInteractable3D) -> void:
	await _run_interactable(interactable)
	if is_instance_valid(self):
		_pointer_interaction_running = false


func _update_pointer_attack() -> void:
	var has_attack_intent := (
		_queued_primary_attack
		or _pointer_enemy != null
		or _stand_ground_attack
	)
	if not has_attack_intent:
		return
	if not _queued_primary_attack and not _primary_pointer_pressed:
		_clear_pointer_attack(false)
		return
	if battle_session == null:
		_clear_pointer_attack()
		return
	var actor := battle_session.player
	var target_position := _pointer_attack_point
	var target_id: StringName
	if _pointer_enemy != null:
		if not is_instance_valid(_pointer_enemy) or _pointer_enemy.is_defeated():
			_clear_pointer_attack()
			return
			target_position = _pointer_enemy.global_position
			target_id = _pointer_enemy.actor_id
	var direction := target_position - player_3d.global_position
	direction.y = 0.0
	if direction.length_squared() > 0.001:
		player_3d.set_aim_direction(direction)
	var in_range := _stand_ground_attack or direction.length() <= BASIC_ATTACK_DISTANCE
	if not in_range:
		var navigation_result := player_3d.navigate_to(target_position, BASIC_ATTACK_DISTANCE)
		if _navigation_rejected(navigation_result):
			_clear_pointer_attack()
			_show_navigation_failure(target_position)
		return
	player_3d.stop_navigation()
	if not actor.can_act() or actor.cooldown_remaining(BattleSession.BASIC_ATTACK_ID) > 0.0:
		return
	var result := request_battle_action(
		BattleActionIntent.basic_attack(actor.id, target_id)
	)
	if result.accepted():
		_queued_primary_attack = false
		if not _primary_pointer_pressed:
			_clear_pointer_attack(false)


func _clear_pointer_intent(
	stop_navigation: bool = true,
	clear_primary_press: bool = true
) -> void:
	_clear_pointer_interaction(stop_navigation)
	_clear_pointer_attack(stop_navigation)
	if clear_primary_press:
		_primary_pointer_pressed = false
	if stop_navigation:
		player_3d.stop_navigation()


func _clear_pointer_interaction(stop_navigation: bool = true) -> void:
	_pointer_interactable = null
	if stop_navigation:
		player_3d.stop_navigation()


func _clear_pointer_attack(stop_navigation: bool = true) -> void:
	_pointer_enemy = null
	_queued_primary_attack = false
	_stand_ground_attack = false
	pointer_feedback.clear_target()
	if stop_navigation:
		player_3d.stop_navigation()


func _screen_ground_point(screen_position: Vector2) -> Variant:
	var hit := _pointer_ray(screen_position, WORLD_COLLISION_MASK, false, true)
	return hit.get("position") if not hit.is_empty() else null


func _enemy_at_screen(screen_position: Vector2) -> EnemyActorView3D:
	var collider := _pointer_collider(screen_position)
	if not collider is BattleHurtbox3D:
		return null
	var actor_id := (collider as BattleHurtbox3D).actor_id
	for enemy: EnemyActorView3D in enemy_views():
		if enemy.actor_id == actor_id and not enemy.is_defeated():
			return enemy
	return null


func _interactable_at_screen(screen_position: Vector2) -> StoryInteractable3D:
	var collider := _pointer_collider(screen_position)
	if collider is StoryInteractable3D:
		var direct := collider as StoryInteractable3D
		return direct if direct.is_available() else null
	if collider is Node:
		var nested := (collider as Node).find_child("Interactable", true, false)
		if nested is StoryInteractable3D and (nested as StoryInteractable3D).is_available():
			return nested as StoryInteractable3D
	return null


func _update_cursor_context() -> void:
	if not _using_pointer_aim or not player_3d.control_enabled:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return
	var pointer := get_viewport().get_mouse_position()
	if battle_session != null and _enemy_at_screen(pointer) != null:
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	elif battle_session == null and _interactable_at_screen(pointer) != null:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	elif _screen_ground_point(pointer) == null:
		Input.set_default_cursor_shape(Input.CURSOR_FORBIDDEN)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _pointer_collider(screen_position: Vector2) -> Object:
	var hit := _pointer_ray(
		screen_position,
		POINTER_TARGET_MASK | WORLD_COLLISION_MASK,
		true,
		true
	)
	return hit.get("collider") as Object if not hit.is_empty() else null


func _pointer_ray(
	screen_position: Vector2,
	collision_mask: int,
	collide_with_areas: bool,
	collide_with_bodies: bool
) -> Dictionary:
	var origin := camera_3d.project_ray_origin(screen_position)
	var direction := camera_3d.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction * POINTER_RAY_DISTANCE,
		collision_mask
	)
	query.collide_with_areas = collide_with_areas
	query.collide_with_bodies = collide_with_bodies
	query.exclude = [player_3d.hurtbox.get_rid()]
	return camera_3d.get_world_3d().direct_space_state.intersect_ray(query)


func _screen_plane_fallback(screen_position: Vector2) -> Vector3:
	var ray_origin := camera_3d.project_ray_origin(screen_position)
	var ray_direction := camera_3d.project_ray_normal(screen_position)
	if absf(ray_direction.y) <= 0.0001:
		return player_3d.global_position
	var distance := -ray_origin.y / ray_direction.y
	return (
		ray_origin + ray_direction * distance
		if distance > 0.0
		else player_3d.global_position
	)


func _navigation_rejected(result: PlayerCharacter3D.NavigationStartResult) -> bool:
	return result in [
		PlayerCharacter3D.NavigationStartResult.UNREACHABLE,
		PlayerCharacter3D.NavigationStartResult.NAVIGATION_UNAVAILABLE,
	]


func _show_navigation_failure(world_position: Vector3) -> void:
	pointer_feedback.show_destination(
		world_position,
		PointerFeedback3D.DestinationKind.UNREACHABLE
	)
	map_hud.show_notice("无法到达")


func _on_player_navigation_failed(
	target: Vector3,
	_reason: PlayerCharacter3D.NavigationFailure
) -> void:
	_clear_pointer_intent(false)
	_show_navigation_failure(target)


func _target_ring_radius(enemy: EnemyActorView3D) -> float:
	if enemy.definition != null and enemy.definition.combat_style == EnemyDefinition.CombatStyle.CHARGER:
		return 1.65
	return 1.0


func _register_custom_cursors() -> void:
	if move_cursor != null:
		Input.set_custom_mouse_cursor(move_cursor, Input.CURSOR_ARROW, Vector2(3, 3))
	if attack_cursor != null:
		Input.set_custom_mouse_cursor(attack_cursor, Input.CURSOR_CROSS, Vector2(3, 3))
	if interact_cursor != null:
		Input.set_custom_mouse_cursor(
			interact_cursor,
			Input.CURSOR_POINTING_HAND,
			Vector2(3, 3)
		)
	if forbidden_cursor != null:
		Input.set_custom_mouse_cursor(
			forbidden_cursor,
			Input.CURSOR_FORBIDDEN,
			Vector2(3, 3)
		)


func _clear_custom_cursors() -> void:
	for shape: Input.CursorShape in [
		Input.CURSOR_ARROW,
		Input.CURSOR_CROSS,
		Input.CURSOR_POINTING_HAND,
		Input.CURSOR_FORBIDDEN,
	]:
		Input.set_custom_mouse_cursor(null, shape)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
